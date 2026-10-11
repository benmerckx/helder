#!/usr/bin/env python3
"""EXPERIMENTAL: the HaxeBenchmarks cases (github.com/HaxeBenchmarks/benchmark-runner)
on hxc and the fast Haxe targets, with build times.

    python3 site/bench/haxebench.py [-n RUNS] [-t hxc,cpp,...] [-c alloc,nbody,...] [--json out.json]

The runner is cloned into bin/haxebench/runner (its cases; not its lix-based
driver). Targets:
  hxc       the hxc dev tool (bin/hxc-dev/tool, see hxc/tools/dev-tool.sh):
            source -> C chunks -> $HXC_BENCH_CC (default clang -O2), objects reused
  hxc-tcc   the same C with tcc (build speed)
  cpp       hxcpp (haxelib), g++ -O2 as configured by hxcpp
  hlc       HL/C: gcc -O2 against the installed libhl; headers from $HL_SRC
            (default bin/haxebench/hlsrc/src, `git archive` of the libhl commit)
  hl        HashLink JIT
  jvm       --jvm, java -jar
  js        --js, node
Build time is wall time of every step (typing + codegen + C/C++ compile).
Run time is the minimum wall time of RUNS runs. Builds that fail are reported, not fatal.
"""
import argparse, json, os, resource, shutil, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HB = ROOT / "bin/haxebench"
RUNNER = HB / "runner"
HAXE = os.environ.get("HAXE", str(ROOT / "haxe/haxe"))
STD = ROOT / "haxe/std"
TOOL = ROOT / "bin/hxc-dev/tool"
HL_SRC = Path(os.environ.get("HL_SRC", HB / "hlsrc/src"))

# git clones into bin/haxebench/libs: (dir, url, revision)
LIBS = [
    ("crypto", "https://github.com/HaxeFoundation/crypto.git", "HEAD"),
    ("formatter", "https://github.com/HaxeCheckstyle/haxe-formatter.git", "v1.9.1"),
    ("tokentree", "https://github.com/HaxeCheckstyle/tokentree.git", "v1.0.23"),
    ("haxeparser", "https://github.com/Simn/haxeparser.git", "e5746bfc55c09a3694db42738ff575b91441971a"),
    ("hxparse", "https://github.com/Simn/hxparse.git", "876070ec62a4869de60081f87763e23457a3bda8"),
    ("json2object", "https://github.com/elnabo/json2object.git", "a75859de1e966c09e73591b6c9186086c143fe60"),
    ("hxargs", "https://github.com/simn/hxargs.git", "1d8ec84f641833edd6f0cb2e4290b7524fd27219"),
    ("hxjsonast", "https://github.com/nadako/hxjsonast.git", "1.1.0"),
]
FORMATTER_CPS = ["formatter/src", "tokentree/src", "haxeparser/src", "hxparse/src", "json2object/src", "hxargs", "hxjsonast/src"]

# name: (case dir, main class, extra class paths, defines)
CASES = {
    "alloc": ("alloc", "BMAllocCode", [], []),
    "bcrypt": ("bcrypt", "BMBCryptCode", [str(HB / "libs/crypto/src")], []),  # github.com/HaxeFoundation/crypto
    "binarytrees": ("binarytrees", "BMBinaryTreesCode", [], []),
    "json": ("json", "BMJsonCode", [], []),
    "mandelbrot": ("mandelbrot", "BMMandelbrotCode", [], []),
    "mandelbrot_anon": ("mandelbrot_anon_objects", "BMMandelbrotCode", ["../mandelbrot"], ["anon_objects"]),
    "nbody": ("nbody", "BMNBodyCode", [], []),
    "sha256": ("sha256", "BMSHA256Code", [], []),
    "sha512": ("sha512", "BMSHA512Code", [str(HB / "libs/crypto/src")], []),
    # haxe-formatter 1.9.1 formatting its own src/ (60 times), libraries as the runner pins them
    "formatter_noio": ("formatter_noio", "BMFormatterNoIOCode", [str(HB / "libs" / d) for d in FORMATTER_CPS], [d.split("/")[0] for d in FORMATTER_CPS]),
}
TARGETS = ["hxc", "hxc-tcc", "cpp", "hlc", "hl", "jvm", "js"]


def stack(limit):
    # the hxc tool recurses deeply (unlimited stack); the benchmarks run with
    # the usual 8 MB (hxcpp crashes with an unlimited stack)
    return lambda: resource.setrlimit(resource.RLIMIT_STACK, (limit, resource.RLIM_INFINITY))


def sh(cmd, cwd, log, env=None):
    t = time.perf_counter()
    r = subprocess.run(cmd, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, env=env, preexec_fn=stack(resource.RLIM_INFINITY))
    return r.returncode, time.perf_counter() - t


def build(target, case, out):
    """Returns (run command, build seconds) or raises with the log."""
    d, main, cps, defs = CASES[case]
    cwd = RUNNER / "cases" / d
    args = ["-cp", "."] + sum([["-cp", c] for c in cps], []) + ["-main", main] + sum([["-D", x] for x in defs], [])
    out.mkdir(parents=True, exist_ok=True)
    log = open(out / "build.log", "w")
    env = dict(os.environ, HAXE_STD_PATH=str(STD))
    steps = []
    if target in ("hxc", "hxc-tcc"):
        c = out / "prog"
        steps.append(([str(TOOL), str(c)] + args + ["-cp", str(ROOT / "bin/hxc/std"), "--custom-target", "hxc"], env))
        cc = os.environ.get("HXC_BENCH_CC", "clang -O2") if target == "hxc" else "tcc"
        ids = "-DHXC_CONST_IDS" if target == "hxc" else ""
        ccenv = dict(env, CC=cc, CFLAGS=f"-w -fno-strict-aliasing -DHXC_NO_SSL -DHXC_NO_UV {ids}", RT_DIR=str(ROOT / "hxc/rt"))
        steps.append((["sh", str(ROOT / "hxc/tools/cc-chunks.sh"), str(c) + "_hxc", str(out / "bin")], ccenv))
        run = [str(out / "bin")]
    elif target == "cpp":
        steps.append(([HAXE] + args + ["--cpp", str(out / "cpp"), "-D", "HXCPP_M64"], env))
        run = [str(out / "cpp" / main)]
    elif target == "hlc":
        # no-compilation: Haxe would run `haxelib run hashlink build`
        steps.append(([HAXE] + args + ["--hl", str(out / "c/main.c"), "-D", "no-compilation"], env))
        steps.append((["gcc", "-O2", "-std=c11", "-w", "-o", str(out / "bin"), "-I", str(HL_SRC), "-I", str(out / "c"), str(out / "c/main.c"), "-L/usr/local/lib", "-lhl", "-lm", "-Wl,-rpath,/usr/local/lib"], env))
        run = [str(out / "bin")]
    elif target == "hl":
        steps.append(([HAXE] + args + ["--hl", str(out / "main.hl")], env))
        run = ["hl", str(out / "main.hl")]
    elif target == "jvm":
        steps.append(([HAXE] + args + ["--jvm", str(out / "main.jar")], env))
        run = ["java", "-jar", str(out / "main.jar")]
    elif target == "js":
        steps.append(([HAXE] + args + ["-lib", "hxnodejs", "--js", str(out / "main.js")], env))
        run = ["node", str(out / "main.js")]
    total = 0.0
    for cmd, e in steps:
        log.write("$ " + " ".join(cmd) + "\n")
        log.flush()
        code, t = sh(cmd, cwd, log, e)
        total += t
        if code != 0:
            log.close()
            raise RuntimeError((out / "build.log").read_text()[-1500:])
    log.close()
    return run, total


def run_case(cmd, case, runs, out):
    # the cases read ../data/... : run from a directory inside the case
    cwd = RUNNER / "cases" / CASES[case][0] / "out"
    cwd.mkdir(exist_ok=True)
    best = None
    for _ in range(runs):
        with open(out / "run.log", "w") as log:
            t = time.perf_counter()
            p = subprocess.Popen(cmd, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, preexec_fn=stack(8 << 20))
            _, status, ru = os.wait4(p.pid, 0)
            t = time.perf_counter() - t
        code = os.waitstatus_to_exitcode(status)
        if code != 0:
            raise RuntimeError("exit %d: %s" % (code, (out / "run.log").read_text()[-800:]))
        best = t if best is None else min(best, t)
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, default=3)
    ap.add_argument("-t", default=",".join(TARGETS))
    ap.add_argument("-c", default=",".join(CASES))
    ap.add_argument("--json")
    ap.add_argument("--clean", action="store_true", help="remove previous build outputs (hxc reuses objects otherwise)")
    a = ap.parse_args()
    if not RUNNER.exists():
        subprocess.check_call(["git", "clone", "-q", "https://github.com/HaxeBenchmarks/benchmark-runner.git", str(RUNNER)])
    for d, url, rev in LIBS:
        if not (HB / "libs" / d).exists():
            subprocess.check_call(["git", "clone", "-q", url, str(HB / "libs" / d)])
            subprocess.check_call(["git", "-C", str(HB / "libs" / d), "checkout", "-q", rev])
    data = RUNNER / "cases/formatter_noio/data"
    if not data.exists():
        shutil.copytree(HB / "libs/formatter/src", data)
    results = {}
    if a.json and os.path.exists(a.json):
        results = json.load(open(a.json))
    for case in a.c.split(","):
        for target in a.t.split(","):
            out = HB / "out" / case / target
            if a.clean and out.exists():
                shutil.rmtree(out)
            key = f"{case}/{target}"
            try:
                cmd, bt = build(target, case, out)
                rt = run_case(cmd, case, a.n, out)
                results[key] = {"build": round(bt, 2), "run": round(rt, 3)}
                print(f"{case:16} {target:8} build {bt:6.2f}s  run {rt:7.3f}s", flush=True)
            except Exception as e:
                results[key] = {"error": str(e)[-300:]}
                print(f"{case:16} {target:8} FAILED: {str(e).strip().splitlines()[-1] if str(e).strip() else e}", flush=True)
            if a.json:
                json.dump(results, open(a.json, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
