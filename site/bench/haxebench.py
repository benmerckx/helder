#!/usr/bin/env python3
"""EXPERIMENTAL: the HaxeBenchmarks cases (github.com/HaxeBenchmarks/benchmark-runner)
on hxc, hxmc and the fast Haxe targets, with build times and output sizes.

    python3 site/bench/haxebench.py [-n RUNS] [-t hxc,cpp,...] [-c alloc,nbody,...] [--json out.json] [--check] [--clean]

The runner is cloned into bin/haxebench/runner (its cases; not its lix-based
driver). Targets:
  hxc       the hxc dev tool (bin/hxc-dev/tool, see `make dev-tool`):
            source -> C chunks -> $HXC_BENCH_CC (default clang -O2), objects reused
  hxc-tcc   the same C with tcc (build speed)
  hxmc      the hxmc tool ($HXMC_TOOL, default bin/hxmc/hxmc, hxmc/README.md
            "Building") from source with hxmc's std (bin/hxmc/std): a static
            linux-x86_64 executable, cold build (its object cache removed)
  hxmc-wasm-node, hxmc-wasm-wasmtime
            the same with -D hxmc.target=wasm32-wasi: one WebAssembly module,
            run by node (hxmc/tools/wasi.mjs, --experimental-wasm-exnref
            --no-turbo-fast-api-calls) or by wasmtime (-W exceptions=y)
  cpp       hxcpp (haxelib), g++ -O2 as configured by hxcpp
  hlc       HL/C: gcc -O2 against the installed libhl; headers from $HL_SRC
            (default bin/haxebench/hlsrc/src, `git archive` of the libhl commit)
  hl        HashLink JIT
  jvm       --jvm, java -jar
  js        --js, node
Build time is wall time of every step (typing + codegen + C/C++ compile).
Run time is the minimum wall time of RUNS runs. Size is the artifact (stripped
copy for native executables of C compilers; gzip -9 size too).
Builds that fail are reported, not fatal.

--check also builds and runs, once per target, the programs of
site/bench/haxebench-check (Check<Case>: the case's computation with its
results printed; the cases themselves print nothing) and stores their output,
so that targets can be compared.
"""
import argparse, gzip, hashlib, json, os, resource, shutil, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HB = ROOT / "bin/haxebench"
RUNNER = HB / "runner"
HAXE = os.environ.get("HAXE", str(ROOT / "haxe/haxe"))
STD = ROOT / "haxe/std"
TOOL = ROOT / "bin/hxc-dev/tool"
HXMC = Path(os.environ.get("HXMC_TOOL", ROOT / "bin/hxmc/hxmc"))
HXMC_STD = os.environ.get("HXMC_STD", str(ROOT / "bin/hxmc/std"))
HL_SRC = Path(os.environ.get("HL_SRC", HB / "hlsrc/src"))
CHECK = ROOT / "site/bench/haxebench-check"

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

# name: (case dir, main class, extra class paths, defines, check program)
CASES = {
    "alloc": ("alloc", "BMAllocCode", [], [], "CheckAlloc"),
    "bcrypt": ("bcrypt", "BMBCryptCode", [str(HB / "libs/crypto/src")], [], "CheckBcrypt"),  # github.com/HaxeFoundation/crypto
    "binarytrees": ("binarytrees", "BMBinaryTreesCode", [], [], "CheckBinarytrees"),
    "json": ("json", "BMJsonCode", [], [], "CheckJson"),
    "mandelbrot": ("mandelbrot", "BMMandelbrotCode", [], [], "CheckMandelbrot"),
    "mandelbrot_anon": ("mandelbrot_anon_objects", "BMMandelbrotCode", ["../mandelbrot"], ["anon_objects"], "CheckMandelbrot"),
    "nbody": ("nbody", "BMNBodyCode", [], [], "CheckNbody"),
    "sha256": ("sha256", "BMSHA256Code", [], [], "CheckSha256"),
    "sha512": ("sha512", "BMSHA512Code", [str(HB / "libs/crypto/src")], [], "CheckSha512"),
    # haxe-formatter 1.9.1 formatting its own src/ (60 times), libraries as the runner pins them
    "formatter_noio": ("formatter_noio", "BMFormatterNoIOCode", [str(HB / "libs" / d) for d in FORMATTER_CPS], [d.split("/")[0] for d in FORMATTER_CPS], "CheckFormatter"),
}
TARGETS = ["hxc", "hxc-tcc", "hxmc", "hxmc-wasm-node", "hxmc-wasm-wasmtime", "cpp", "hlc", "hl", "jvm", "js"]
# what the artifact needs at run time
NEEDS = {
    "hxc": "glibc, libm (dynamic)",
    "hxc-tcc": "glibc, libm (dynamic)",
    "hxmc": "nothing (static)",
    "hxmc-wasm-node": "WASI runtime (node 22 + wasi.mjs)",
    "hxmc-wasm-wasmtime": "WASI runtime (wasmtime, exceptions)",
    "cpp": "glibc, libstdc++ (dynamic)",
    "hlc": "libhl.so, glibc (dynamic)",
    "hl": "HashLink VM (hl) + libhl",
    "jvm": "JRE",
    "js": "node (hxnodejs)",
}


def stack(limit):
    # the hxc tool recurses deeply (unlimited stack); the benchmarks run with
    # the usual 8 MB (hxcpp crashes with an unlimited stack)
    return lambda: resource.setrlimit(resource.RLIMIT_STACK, (limit, resource.RLIM_INFINITY))


def sh(cmd, cwd, log, env=None):
    t = time.perf_counter()
    r = subprocess.run(cmd, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, env=env, preexec_fn=stack(resource.RLIM_INFINITY))
    return r.returncode, time.perf_counter() - t


def build(target, case, out, main=None):
    """Returns (run command, build seconds, artifact) or raises with the log.
    main: another main class (a check program of CHECK)."""
    d, cmain, cps, defs, _ = CASES[case]
    main = main or cmain
    cwd = RUNNER / "cases" / d
    if main != cmain:
        cps = cps + [str(CHECK)]
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
        ccenv = dict(env, CC=cc, CFLAGS=f"-w -fno-strict-aliasing -DHXC_NO_SSL -DHXC_NO_UV {ids}", RT_DIR=str(ROOT / "hxc/rt"), HXC_CCACHE="0")
        steps.append((["sh", str(ROOT / "hxc/tools/cc-chunks.sh"), str(c) + "_hxc", str(out / "bin")], ccenv))
        run = [str(out / "bin")]
        art = out / "bin"
    elif target == "hxmc" or target.startswith("hxmc-wasm"):
        wasm = target != "hxmc"
        art = out / ("bin.wasm" if wasm else "bin")
        shutil.rmtree(str(art) + ".hxmc", ignore_errors=True)  # cold build: no object cache
        tgt = ["-D", "hxmc.target=wasm32-wasi"] if wasm else []
        steps.append(([str(HXMC), str(art)] + args + ["-cp", HXMC_STD, "--custom-target", "hxmc"] + tgt, env))
        if target == "hxmc-wasm-node":
            run = ["node", "--experimental-wasm-exnref", "--no-turbo-fast-api-calls", "--stack-size=65500", "--no-warnings", str(ROOT / "hxmc/tools/wasi.mjs"), str(art)]
        elif target == "hxmc-wasm-wasmtime":
            # PWD: the runtime resolves relative paths against it (the whole file system is
            # preopened); resolved: wasmtime refuses symbolic links to absolute paths
            run = ["wasmtime", "run", "-W", "exceptions=y", "-W", "max-wasm-stack=67108864", "--dir", "/", "--env", "PWD=" + str((cwd / "out").resolve()), str(art)]
        else:
            run = [str(art)]
    elif target == "cpp":
        steps.append(([HAXE] + args + ["--cpp", str(out / "cpp"), "-D", "HXCPP_M64"], env))
        run = [str(out / "cpp" / main)]
        art = out / "cpp" / main
    elif target == "hlc":
        # no-compilation: Haxe would run `haxelib run hashlink build`
        steps.append(([HAXE] + args + ["--hl", str(out / "c/main.c"), "-D", "no-compilation"], env))
        steps.append((["gcc", "-O2", "-std=c11", "-w", "-o", str(out / "bin"), "-I", str(HL_SRC), "-I", str(out / "c"), str(out / "c/main.c"), "-L/usr/local/lib", "-lhl", "-lm", "-Wl,-rpath,/usr/local/lib"], env))
        run = [str(out / "bin")]
        art = out / "bin"
    elif target == "hl":
        steps.append(([HAXE] + args + ["--hl", str(out / "main.hl")], env))
        run = ["hl", str(out / "main.hl")]
        art = out / "main.hl"
    elif target == "jvm":
        steps.append(([HAXE] + args + ["--jvm", str(out / "main.jar")], env))
        run = ["java", "-jar", str(out / "main.jar")]
        art = out / "main.jar"
    elif target == "js":
        steps.append(([HAXE] + args + ["-lib", "hxnodejs", "--js", str(out / "main.js")], env))
        run = ["node", str(out / "main.js")]
        art = out / "main.js"
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
    return run, total, art


def sizes(target, art):
    """(size, stripped size or None, gzip -9 size) in bytes"""
    data = art.read_bytes()
    stripped = None
    if target in ("hxc", "hxc-tcc", "cpp", "hlc"):
        s = art.with_name(art.name + ".stripped")
        shutil.copyfile(art, s)
        subprocess.run(["strip", str(s)], check=True)
        stripped = s.stat().st_size
        data = s.read_bytes()
        s.unlink()
    return len(art.read_bytes()), stripped, len(gzip.compress(data, 9))


def run_case(cmd, case, runs, out):
    """(best seconds, output) — the cases read ../data/... : run from a directory inside the case"""
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
            raise RuntimeError("exit %d: %s" % (code, (out / "run.log").read_text(errors="replace")[-800:]))
        best = t if best is None else min(best, t)
    output = (out / "run.log").read_text(errors="replace")
    # the JVM announces $JAVA_TOOL_OPTIONS on stderr
    return best, "".join(l for l in output.splitlines(True) if not l.startswith("Picked up JAVA_TOOL_OPTIONS"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, default=3)
    ap.add_argument("-t", default=",".join(TARGETS))
    ap.add_argument("-c", default=",".join(CASES))
    ap.add_argument("--json")
    ap.add_argument("--clean", action="store_true", help="remove previous build outputs (hxc reuses objects otherwise)")
    ap.add_argument("--check", action="store_true", help="also build and run the check program of each case (site/bench/haxebench-check)")
    ap.add_argument("--rm", action="store_true", help="remove each build output after measuring it (disk space)")
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
            r = results.get(key, {})
            for k in ("error", "build", "run", "runs", "size", "stripped", "gzip", "output"):
                r.pop(k, None)
            r["needs"] = NEEDS[target]
            try:
                cmd, bt, art = build(target, case, out)
                size, stripped, gz = sizes(target, art)
                r.update(build=round(bt, 2), size=size, gzip=gz)
                if stripped is not None:
                    r["stripped"] = stripped
                rt, output = run_case(cmd, case, a.n, out)
                r.update(run=round(rt, 3), runs=a.n, output=output)
                print(f"{case:16} {target:18} build {bt:6.2f}s  run {rt:7.3f}s  size {(stripped or size) / 1024:8.0f} KB  gzip {gz / 1024:7.0f} KB", flush=True)
            except Exception as e:
                r["error"] = str(e)[-600:]
                print(f"{case:16} {target:18} FAILED: {str(e).strip().splitlines()[-1] if str(e).strip() else e}", flush=True)
            if a.check:
                r.pop("check", None)
                r.pop("check_error", None)
                cout = HB / "out" / case / (target + "-check")
                shutil.rmtree(cout, ignore_errors=True)
                try:
                    cmd, _, _ = build(target, case, cout, CASES[case][4])
                    _, output = run_case(cmd, case, 1, cout)
                    r["check"] = output
                except Exception as e:
                    r["check_error"] = str(e)[-600:]
                    print(f"{case:16} {target:18} check FAILED: {str(e).strip().splitlines()[-1] if str(e).strip() else e}", flush=True)
                if a.rm:
                    shutil.rmtree(cout, ignore_errors=True)
            if a.rm:
                shutil.rmtree(out, ignore_errors=True)
            results[key] = r
            if a.json:
                json.dump(results, open(a.json, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
