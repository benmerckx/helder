#!/usr/bin/env python3
"""Compile-time benchmark of the target generators: the reference compiler and the
port compile the same projects to every target; outputs must be identical.

    python3 site/bench/targets.py [-n RUNS] [-p formatter,self] [-t js,lua,...] [--port CMD] [--json out.json]

Projects:
  formatter  haxe-formatter 1.9.1 with its six libraries (bin/haxebench/libs, see
             site/bench/haxebench.py), the HaxeBenchmarks formatter_noio case
  self       the port's own source (src/, haxe.Main), about 1,000 modules; for JS, the
             hxc tool (the port and the C backend, backend.Main, over hxnodejs)
Each run is a fresh process with -D disable-parallelism; both compilers run in the
same directory (some outputs embed it). CPU is user + system time of the process
(os.wait4), best of RUNS; peak RSS is the largest of the runs. The output is
compared after the last run: files and directories byte for byte, JARs and HXB
archives member by member (ZIP containers are not compared).
"""
import argparse, json, os, platform, resource, shutil, subprocess, sys, time, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIBS = ROOT / "bin/haxebench/libs"
REF = os.environ.get("HAXE_REFERENCE", str(ROOT / "haxe/haxe"))
STD = ROOT / "haxe/std"
WORK = ROOT / "bin/bench-targets"

FMT_CPS = ["formatter/src", "tokentree/src", "haxeparser/src", "hxparse/src", "json2object/src", "hxargs", "hxjsonast/src"]
PROJECTS = {
    "formatter": (["-cp", str(ROOT / "bin/haxebench/runner/cases/formatter_noio"), "-main", "BMFormatterNoIOCode"]
                  + sum([["-cp", str(LIBS / d)] for d in FMT_CPS], []) + sum([["-D", d.split("/")[0]] for d in FMT_CPS], [])),
    "self": ["-cp", str(ROOT / "src"), "-main", "haxe.Main"],
}
# target: (args, output kind:path, extra args per project)
TARGETS = {
    "hxb": (["--interp", "--no-output", "--hxb", "out/out.zip"], "zip:out/out.zip"),
    "js": (["--js", "out/main.js"], "file:out/main.js"),
    "lua": (["--lua", "out/main.lua"], "file:out/main.lua"),
    "python": (["--python", "out/main.py"], "file:out/main.py"),
    "php": (["--php", "out/php"], "dir:out/php"),
    "neko": (["--neko", "out/main.n"], "file:out/main.n"),
    "hl": (["--hl", "out/main.hl"], "file:out/main.hl"),
    "hlc": (["--hl", "out/hlc/main.c", "-D", "no-compilation"], "dir:out/hlc"),
    "cpp": (["--cpp", "out/cpp", "-D", "no-compilation"], "dir:out/cpp"),
    "jvm": (["--jvm", "out/main.jar"], "zip:out/main.jar"),
    "swf": (["--swf", "out/main.swf"], "file:out/main.swf"),
}
EXTRA = {("formatter", "js"): ["-lib", "hxnodejs"]}
# the port's JS build is the hxc tool (bin/hxc/wbk.js): the port and the C backend over hxnodejs
PROJECT_FOR = {("self", "js"): ["-cp", str(ROOT / "src"), "-cp", str(ROOT / "hxc/src"), "-main", "backend.Main", "-lib", "hxnodejs", "-cp", str(ROOT / "hxc/js"), "-w", "-WDeprecated"]}


def run_once(cmd, cwd, log):
    env = dict(os.environ, HAXE_STD_PATH=str(STD), HAXE_IN_HAXE_STD_PATH=str(STD))
    t = time.perf_counter()
    unlimited = lambda: resource.setrlimit(resource.RLIMIT_STACK, (resource.RLIM_INFINITY, resource.RLIM_INFINITY))
    p = subprocess.Popen(cmd, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, env=env, preexec_fn=unlimited)
    _, status, ru = os.wait4(p.pid, 0)
    wall = time.perf_counter() - t
    return os.waitstatus_to_exitcode(status), wall, ru.ru_utime + ru.ru_stime, ru.ru_maxrss / 1024


def snapshot(kind, cwd):
    """The output as {member: bytes}."""
    k, path = kind.split(":", 1)
    p = cwd / path
    if k == "file":
        return {"": p.read_bytes()} if p.exists() else None
    if k == "dir":
        if not p.exists():
            return None
        return {str(f.relative_to(p)): f.read_bytes() for f in sorted(p.rglob("*")) if f.is_file()}
    if not p.exists():
        return None
    with zipfile.ZipFile(p) as z:
        return {n: z.read(n) for n in sorted(z.namelist()) if not n.endswith("/")}


def bench(compiler, project, target, runs):
    args, kind = TARGETS[target]
    cwd = WORK / "cwd"
    best = None
    for i in range(runs):
        if cwd.exists():
            shutil.rmtree(cwd)
        (cwd / "out").mkdir(parents=True)
        with open(WORK / "log.txt", "w") as log:
            code, wall, cpu, rss = run_once(compiler + PROJECT_FOR.get((project, target), PROJECTS[project]) + EXTRA.get((project, target), []) + args + ["-D", "disable-parallelism"], cwd, log)
        if code != 0:
            tail = (WORK / "log.txt").read_text(errors="replace").strip().splitlines()[-3:]
            return {"status": "exit %d: %s" % (code, " | ".join(tail))}, None
        if best is None:
            best = {"cpu": cpu, "wall": wall, "rss_mb": rss}
        else:
            best = {"cpu": min(best["cpu"], cpu), "wall": min(best["wall"], wall), "rss_mb": max(best["rss_mb"], rss)}
    out = snapshot(kind, cwd)
    best.update(status="ok", members=len(out or {}), bytes=sum(len(v) for v in (out or {}).values()))
    return best, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, default=3)
    ap.add_argument("-p", default=",".join(PROJECTS))
    ap.add_argument("-t", default=",".join(TARGETS))
    ap.add_argument("--port", default=os.environ.get("HAXE_IN_HAXE_PORT", str(ROOT / "bin/hxc/hih/hih_clang")))
    ap.add_argument("--json")
    ap.add_argument("--merge", action="store_true", help="replace only the measured project/target entries of an existing --json file")
    a = ap.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    results = []
    if a.merge and a.json and os.path.exists(a.json):
        keep = set((p, t) for p in a.p.split(",") for t in a.t.split(","))
        results = [r for r in json.load(open(a.json))["results"] if (r["project"], r["target"]) not in keep]
    for project in a.p.split(","):
        for target in a.t.split(","):
            ref, ref_out = bench([REF], project, target, a.n)
            if ref["status"] != "ok":
                print(f"{project:10} {target:7} reference fails: {ref['status'][-120:]}", flush=True)
                results.append({"project": project, "target": target, "reference": ref, "port": None, "identical": None})
                continue
            port, port_out = bench(a.port.split(), project, target, a.n)
            same = port["status"] == "ok" and ref_out == port_out
            diff = ""
            if port["status"] == "ok" and not same:
                names = sorted(set(ref_out) | set(port_out))
                bad = [n for n in names if ref_out.get(n) != port_out.get(n)]
                diff = f" ({len(bad)} of {len(names)} differ: {', '.join(bad[:3])})"
            results.append({"project": project, "target": target, "reference": ref, "port": port, "identical": same})
            if port["status"] == "ok":
                print(f"{project:10} {target:7} ref {ref['cpu']:6.2f}s {ref['rss_mb']:5.0f} MB  port {port['cpu']:6.2f}s {port['rss_mb']:5.0f} MB  "
                      f"{port['cpu'] / ref['cpu']:.2f}x  {'identical' if same else 'DIFFERENT' + diff}", flush=True)
            else:
                print(f"{project:10} {target:7} port fails: {port['status'][-120:]}", flush=True)
            if a.json:
                write(a.json, results, a)
    if a.json:
        write(a.json, results, a)


def write(path, results, a):
    def version(cmd):
        try:
            return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30).stdout.strip().splitlines()[0]
        except Exception:
            return None
    cpu = None
    try:
        for l in open("/proc/cpuinfo"):
            if l.startswith("model name"):
                cpu = l.split(":", 1)[1].strip()
                break
    except OSError:
        pass
    meta = {
        "date": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "commit": subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"], stdout=subprocess.PIPE, text=True).stdout.strip(),
        "cpu": cpu, "cores": os.cpu_count(), "runs": a.n, "port": a.port, "reference": version([REF, "--version"]),
        "platform": platform.platform(),
    }
    json.dump({"meta": meta, "results": results}, open(path, "w"), indent=1)


if __name__ == "__main__":
    main()
