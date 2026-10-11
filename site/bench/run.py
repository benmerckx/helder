#!/usr/bin/env python3
"""Benchmark the pinned reference compiler against the translated compiler
(haxe.Main) built for several targets (see site/bench/build.sh) and run on the
reference's Eval (from source, or from an Eval HXB archive).

Each run compiles a workload to HXB with -D disable-parallelism. Every
runner's archive is checked against the reference output (same member set,
identical uncompressed .hxb payloads) before its timing counts.

Per run, wall time, CPU time (user + system of the child and its reaped
descendants, from wait4) and peak RSS are recorded; the report gives the
minimum and median over N runs.

Usage: HAXE_REFERENCE=haxe/haxe python3 site/bench/run.py [-n RUNS] [--runs RUNNER=N ...]
           [-w WORKLOAD ...] [--json FILE] [runner ...]

--json merges the results into FILE (entries are keyed by workload and runner,
so separate invocations, e.g. a slow runner with -n 1, can fill one file).
"""
import argparse, datetime, json, os, pathlib, platform, re, resource, shutil, statistics, subprocess, sys, tempfile, time, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
BIN = ROOT / "bin/bench"
STD = ROOT / "haxe/std"
# The port as an Eval HXB archive, for the eval-hxb runner (built on demand).
EVAL_HXB = BIN / "haxe-in-haxe.eval.hxb"
# Eval's default call stack depth (1000) is too small for the port's typer
# recursion; the self-compile, whose macros the port interprets in turn, needs
# more than 10000 frames.
EVAL_STACK = ["-D", "eval-call-stack-depth=1000000"]
NODE_WASM = os.environ.get("NODE_WASM", "node")

WORKLOADS = {
    # name: (cwd, arguments)
    "hello": (ROOT / "site/bench/workloads", ["-cp", ".", "--main", "Hello"]),
    "trycatch": (ROOT, ["-cp", "test", "--main", "unit.moduleload.TryCatch"]),
    # Many std modules as bare roots.
    "stdlib": (ROOT, """haxe.Json haxe.Serializer haxe.Unserializer haxe.crypto.Sha256 haxe.crypto.Md5
        haxe.crypto.Base64 haxe.io.BytesBuffer haxe.zip.Reader haxe.zip.Writer haxe.ds.BalancedTree
        haxe.ds.GenericStack haxe.ds.ListSort haxe.xml.Parser haxe.xml.Printer haxe.Template
        haxe.format.JsonParser haxe.io.Path haxe.Int64Helper haxe.CallStack DateTools EReg StringTools
        Lambda haxe.ds.Vector haxe.EnumFlags haxe.http.HttpBase haxe.crypto.Hmac haxe.crypto.Crc32
        haxe.zip.Huffman haxe.zip.InflateImpl haxe.io.Float32Array haxe.ds.HashMap""".split()),
    # The port's own source (~52k lines, 382 modules); runs std macros.
    "self": (ROOT, ["-cp", "src", "-main", "haxe.Main"]),
}


def runners(reference):
    return {
        "reference": [reference],
        # The port on the reference's Eval: typed from source on every run, or
        # loaded from its Eval HXB archive (AGENTS.md: Eval-HXB host execution).
        "eval-source": [reference] + EVAL_STACK + ["-cp", str(ROOT / "src"), "--run", "haxe.Main"],
        "eval-hxb": [reference] + EVAL_STACK + ["--hxb-lib", str(EVAL_HXB), "--run", "haxe.Main"],
        "hl": ["hl", str(BIN / "hih.hl")],
        "cpp": [str(BIN / "cpp/Main")],
        "hlc": [str(BIN / "hih-hlc")],
        "jvm": ["java", "-Xss512m", "-XX:+UnlockDiagnosticVMOptions", "-XX:-BytecodeVerificationRemote", "-XX:-BytecodeVerificationLocal", "-jar", str(BIN / "hih.jar")],
        "js": ["node", "--stack-size=65500", str(BIN / "hih.js")],
        "go": [str(BIN / "hih-go")],
        # hxc/ (hxc target): sh hxc/build.sh port; hih is the tcc build, hih_o2 gcc -O2
        "hxc": [str(ROOT / "bin/hxc/hih/hih")],
        "hxc-o2": [str(ROOT / "bin/hxc/hih/hih_o2")],
        "hxc-clang": [str(ROOT / "bin/hxc/hih/hih_clang")],  # CC="clang -O2" BIN=hih_clang sh hxc/build.sh port
        # Cosmopolitan builds (cosmocc -O2), fat x86-64 + aarch64 and x86-64 only
        "hxc-cosmo": ["sh", str(ROOT / "bin/hxc/hih/hih.com")],  # APE: started by the shell without binfmt_misc
        "hxc-cosmo-x86": ["sh", str(ROOT / "bin/hxc/hih/hih_x86.com")],
        # hxc's C compiled by Emscripten (wasm64, wasm exceptions) for Node with
        # direct file system access (sh site/bench/build.sh wasm); the site's build uses MEMFS.
        # memory64 needs Node 24 (NODE_WASM, e.g. emsdk's node)
        "wasm": [NODE_WASM, "--stack-size=65500", str(BIN / "wasm/hih.js")],
    }


def payloads(path):
    with zipfile.ZipFile(path) as z:
        return {n: z.read(n) for n in z.namelist() if n.endswith(".hxb")}


def unlimited_stack():
    # Eval runners: the port's deep recursion also needs native stack (ulimit -s)
    hard = resource.getrlimit(resource.RLIMIT_STACK)[1]
    resource.setrlimit(resource.RLIMIT_STACK, (hard, hard))


def run_measured(cmd, cwd, env, log, deep=False):
    """Runs cmd; returns (exit code, wall s, cpu s, peak RSS KB) of the child
    and the descendants it waited for (wait4 rusage)."""
    start = time.perf_counter()
    p = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, preexec_fn=unlimited_stack if deep else None)
    _, status, ru = os.wait4(p.pid, 0)
    elapsed = time.perf_counter() - start
    p.returncode = os.waitstatus_to_exitcode(status)
    return p.returncode, elapsed, ru.ru_utime + ru.ru_stime, ru.ru_maxrss


def first_line(cmd):
    try:
        out = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30).stdout
        # (the JVM first reports JAVA_TOOL_OPTIONS)
        lines = [l.strip() for l in out.splitlines() if l.strip() and not l.startswith("Picked up")]
        return lines[0] if lines else None
    except Exception:
        return None


def metadata(reference, names):
    cpu = None
    try:
        m = re.search(r"^model name\s*:\s*(.*)$", pathlib.Path("/proc/cpuinfo").read_text(), re.M)
        cpu = m.group(1).strip() if m else None
    except OSError:
        pass
    try:
        commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, stdout=subprocess.PIPE, text=True).stdout.strip()
    except OSError:
        commit = None
    mem = None
    try:
        m = re.search(r"^MemTotal:\s*(\d+)", pathlib.Path("/proc/meminfo").read_text(), re.M)
        mem = round(int(m.group(1)) / 1048576, 1) if m else None
    except OSError:
        pass
    versions = {"reference": first_line([reference, "-version"])}
    if "wasm" in names:
        versions["node_wasm"] = first_line([NODE_WASM, "--version"])
    probes = {
        "node": ["node", "--version"], "java": ["java", "-version"], "hl": ["hl", "--version"],
        "gcc": ["gcc", "--version"], "tcc": ["tcc", "-v"], "cosmocc": ["cosmocc", "--version"],
        "emcc": ["emcc", "--version"],
    }
    for k, cmd in probes.items():
        if shutil.which(cmd[0]):
            versions[k] = first_line(cmd)
    return {
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        "commit": commit, "cpu": cpu, "cores": os.cpu_count(), "memory_gb": mem,
        "os": platform.platform(), "python": platform.python_version(), "versions": versions,
    }


def build_eval_hxb(reference, env):
    BIN.mkdir(parents=True, exist_ok=True)
    cmd = [reference, "-cp", str(ROOT / "src"), "-main", "haxe.Main", "--interp", "--no-output", "--hxb", str(EVAL_HXB)]
    with open(BIN / "build-eval-hxb.log", "w") as log:
        code, wall, cpu, rss = run_measured(cmd, ROOT, env, log)
    if code != 0 or "eval/haxe/Main.hxb" not in zipfile.ZipFile(EVAL_HXB).namelist():
        raise SystemExit("Building the port as Eval HXB failed; see " + str(BIN / "build-eval-hxb.log"))
    print(f"built {EVAL_HXB.relative_to(ROOT)} in {wall:.2f}s (cpu {cpu:.2f}s)", flush=True)
    return {"wall": round(wall, 3), "cpu": round(cpu, 3), "size": EVAL_HXB.stat().st_size}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, default=3)
    ap.add_argument("--runs", action="append", default=[], metavar="RUNNER=N", help="run count for one runner (e.g. eval-source=1)")
    ap.add_argument("-w", "--workload", action="append")
    ap.add_argument("--json", metavar="FILE", help="merge machine-readable results into FILE")
    ap.add_argument("runners", nargs="*")
    opts = ap.parse_args()
    runs_for = {k: int(v) for k, v in (r.split("=", 1) for r in opts.runs)}
    reference = os.environ.get("HAXE_REFERENCE", str(ROOT / "haxe/haxe"))
    reference = str(pathlib.Path(reference).resolve())
    table = runners(reference)
    names = opts.runners or list(table)
    # The reference output is what every other runner is checked against.
    names = ["reference"] + [n for n in names if n != "reference"]
    env = dict(os.environ, HAXE_STD_PATH=str(STD), HAXE_IN_HAXE_STD_PATH=str(STD))
    meta = metadata(reference, names)
    if "eval-hxb" in names:
        meta["eval_hxb_build"] = build_eval_hxb(reference, env)
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="hih-bench-"))
    results = {}
    try:
        for wname in opts.workload or list(WORKLOADS):
            cwd, args = WORKLOADS[wname]
            expected = None
            for rname in names:
                times, cpus, rsss = [], [], []
                status = "ok"
                for i in range(runs_for.get(rname, opts.n)):
                    out = tmp / f"{wname}-{rname}-{i}.hxb"
                    cmd = table[rname] + args + ["-D", "disable-parallelism", "--interp", "--no-output", "--hxb", str(out)]
                    with open(tmp / "log.txt", "w") as log:
                        code, elapsed, cpu, rss = run_measured(cmd, cwd, env, log, deep=rname.startswith("eval-"))
                    if code != 0 or not out.exists():
                        status = f"exit {code}: " + (tmp / "log.txt").read_text()[-300:].strip().replace("\n", " | ")
                        break
                    got = payloads(out)
                    if expected is None:
                        expected = got
                    elif got != expected:
                        bad = sum(1 for k in set(got) | set(expected) if got.get(k) != expected.get(k))
                        status = f"output differs from reference ({bad} members)"
                        break
                    times.append(elapsed)
                    cpus.append(cpu)
                    rsss.append(rss)
                    out.unlink()
                results[(wname, rname)] = (times, cpus, rsss, status)
                med = f"{statistics.median(times):8.2f}s" if times and status == "ok" else "       -"
                extra = f"  cpu min {min(cpus):.2f}s  rss {max(rsss) / 1024:.0f} MB" if times and status == "ok" else ""
                print(f"{wname:8} {rname:10} {med}  {status if status != 'ok' else 'runs: ' + ' '.join(f'{t:.2f}' for t in times)}{extra}", flush=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if opts.json:
        write_json(pathlib.Path(opts.json), meta, results, table)


def write_json(path, meta, results, table):
    data = {"meta": {}, "runners": {}, "results": []}
    if path.exists():
        data = json.loads(path.read_text())
    versions = dict(data["meta"].get("versions", {}), **meta["versions"])
    data["meta"].update(meta, versions=versions)
    # Command lines without the machine-specific prefix of this checkout.
    rel = lambda a: os.path.relpath(a, ROOT) if os.path.isabs(a) and a.startswith(str(ROOT)) else a
    for rname in {r for _, r in results}:
        data["runners"][rname] = " ".join(rel(a) for a in table[rname])
    # An existing successful entry with more runs is kept (e.g. the reference
    # rerun only to check a slow runner's output with -n 1).
    better = lambda e: e["status"] == "ok" and results[(e["workload"], e["runner"])][3] == "ok" and e["runs"] > len(results[(e["workload"], e["runner"])][0])
    keep = [e for e in data["results"] if (e["workload"], e["runner"]) not in results or better(e)]
    kept = {(e["workload"], e["runner"]) for e in keep}
    for (wname, rname), (times, cpus, rsss, status) in results.items():
        if (wname, rname) in kept:
            continue
        ok = status == "ok" and bool(times)
        keep.append({
            "workload": wname, "runner": rname, "status": status, "runs": len(times),
            # the reference defines the expected output; the others were compared with it
            "verified": ok and rname != "reference",
            "wall_min": round(min(times), 3) if ok else None,
            "wall_median": round(statistics.median(times), 3) if ok else None,
            "cpu_min": round(min(cpus), 3) if ok else None,
            "cpu_median": round(statistics.median(cpus), 3) if ok else None,
            "maxrss_mb": round(max(rsss) / 1024, 1) if ok else None,
            "date": meta["date"],
        })
    order = list(WORKLOADS)
    data["results"] = sorted(keep, key=lambda e: (order.index(e["workload"]) if e["workload"] in order else 99, e["workload"], e["runner"]))
    path.write_text(json.dumps(data, indent=1) + "\n")
    print(f"wrote {path}", flush=True)


if __name__ == "__main__":
    main()
