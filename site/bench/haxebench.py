#!/usr/bin/env python3
"""The HaxeBenchmarks cases (github.com/HaxeBenchmarks/benchmark-runner) built
by hxmc, natively and as WebAssembly: run times, build times and sizes. The
website's Benchmarks section shows the results (site/src/Tables.hx).

    python3 site/bench/haxebench.py [-n RUNS] [-t hxmc,...] [-c alloc,nbody,...] [--json out.json] [--check] [--rm]

The runner is cloned into bin/haxebench/runner (its cases; not its lix-based
driver), the libraries the cases use into bin/haxebench/libs. Targets:
  hxmc      the hxmc tool ($HXMC_TOOL, default bin/hxmc/hxmc) from source with
            hxmc's std (bin/hxmc/std): a static linux-x86_64 executable
  hxmc-wasm-node, hxmc-wasm-wasmtime
            the same with -D hxmc.target=wasm32-wasi: one WebAssembly module,
            run by node (hxmc/tools/wasi.mjs, --experimental-wasm-exnref
            --no-turbo-fast-api-calls) or by wasmtime (-W exceptions=y)
Build time is the wall time of hxmc's cold build (its object cache removed).
Run time is the minimum wall time of RUNS runs (engine start-up and the
compilation of the module included). Size is the artifact's, and gzip -9 of it.
Builds that fail are reported, not fatal.

--check also builds and runs, once per target, the programs of
site/bench/haxebench-check (Check<Case>: the case's computation with its
results printed; the cases themselves print nothing) and stores their output,
so that the targets can be compared.
"""
import argparse, datetime, gzip, json, os, platform, re, resource, shutil, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HB = ROOT / "bin/haxebench"
RUNNER = HB / "runner"
STD = ROOT / "haxe/std"
HXMC = Path(os.environ.get("HXMC_TOOL", ROOT / "bin/hxmc/hxmc"))
HXMC_STD = os.environ.get("HXMC_STD", str(ROOT / "bin/hxmc/std"))
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
TARGETS = ["hxmc", "hxmc-wasm-node", "hxmc-wasm-wasmtime"]


def stack(limit):
    return lambda: resource.setrlimit(resource.RLIMIT_STACK, (limit, resource.RLIM_INFINITY))


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
    wasm = target != "hxmc"
    art = out / ("bin.wasm" if wasm else "bin")
    shutil.rmtree(str(art) + ".hxmc", ignore_errors=True)  # cold build: no object cache
    cmd = [str(HXMC), str(art)] + args + ["-cp", HXMC_STD, "--custom-target", "hxmc"] + (["-D", "hxmc.target=wasm32-wasi"] if wasm else [])
    if target == "hxmc-wasm-node":
        run = ["node", "--experimental-wasm-exnref", "--no-turbo-fast-api-calls", "--stack-size=65500", "--no-warnings", str(ROOT / "hxmc/tools/wasi.mjs"), str(art)]
    elif target == "hxmc-wasm-wasmtime":
        # PWD: the runtime resolves relative paths against it (the whole file system is
        # preopened); resolved: wasmtime refuses symbolic links to absolute paths
        run = ["wasmtime", "run", "-W", "exceptions=y", "-W", "max-wasm-stack=67108864", "--dir", "/", "--env", "PWD=" + str((cwd / "out").resolve()), str(art)]
    else:
        run = [str(art)]
    with open(out / "build.log", "w") as log:
        log.write("$ " + " ".join(cmd) + "\n")
        log.flush()
        t = time.perf_counter()
        r = subprocess.run(cmd, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, env=dict(os.environ, HAXE_STD_PATH=str(STD)), preexec_fn=stack(resource.RLIM_INFINITY))
        t = time.perf_counter() - t
    if r.returncode != 0:
        raise RuntimeError((out / "build.log").read_text()[-1500:])
    return run, t, art


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
    return best, (out / "run.log").read_text(errors="replace")


def first_line(cmd):
    try:
        out = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30).stdout
        return out.strip().splitlines()[0]
    except Exception:
        return None


def meta():
    cpu = None
    try:
        m = re.search(r"^model name\s*:\s*(.*)$", Path("/proc/cpuinfo").read_text(), re.M)
        cpu = m.group(1).strip() if m else None
    except OSError:
        pass
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, stdout=subprocess.PIPE, text=True).stdout.strip()
    return {
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        "commit": commit, "cpu": cpu, "cores": os.cpu_count(), "os": platform.platform(),
        "versions": {"node": first_line(["node", "--version"]), "wasmtime": first_line(["wasmtime", "--version"])},
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, default=3)
    ap.add_argument("-t", default=",".join(TARGETS))
    ap.add_argument("-c", default=",".join(CASES))
    ap.add_argument("--json")
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
    doc = {"meta": {}, "results": {}}
    if a.json and os.path.exists(a.json):
        doc = json.load(open(a.json))
    doc["meta"] = meta()
    results = doc["results"]
    for case in a.c.split(","):
        for target in a.t.split(","):
            out = HB / "out" / case / target
            shutil.rmtree(out, ignore_errors=True)
            key = f"{case}/{target}"
            r = {}
            try:
                cmd, bt, art = build(target, case, out)
                b = art.read_bytes()
                r.update(build=round(bt, 2), size=len(b), gzip=len(gzip.compress(b, 9)))
                rt, output = run_case(cmd, case, a.n, out)
                r.update(run=round(rt, 3), runs=a.n)
                print(f"{case:16} {target:18} build {bt:6.2f}s  run {rt:7.3f}s  size {len(b) / 1024:8.0f} KB  gzip {r['gzip'] / 1024:7.0f} KB", flush=True)
            except Exception as e:
                r["error"] = str(e)[-600:]
                print(f"{case:16} {target:18} FAILED: {str(e).strip().splitlines()[-1] if str(e).strip() else e}", flush=True)
            if a.check:
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
                json.dump(doc, open(a.json, "w"), indent=1, sort_keys=True)
    if a.check:
        # the check programs print the same on every target
        for case in a.c.split(","):
            outs = {t: results.get(f"{case}/{t}", {}).get("check") for t in a.t.split(",")}
            same = len(set(outs.values())) == 1 and None not in outs.values()
            print(f"check {case:16} {'identical' if same else 'DIFFERS'} on {', '.join(outs)}", flush=True)


if __name__ == "__main__":
    main()
