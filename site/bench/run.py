#!/usr/bin/env python3
"""Benchmark the pinned reference compiler against the port built by hxmc:
natively (bin/port/haxe, `make port`) and as a wasm32-wasi module run by node
and by wasmtime (bin/bench/haxe.wasm, built here). The website's Benchmarks
section shows the results (site/src/Tables.hx).

Each run compiles a workload to HXB with -D disable-parallelism. Every
runner's archive is checked against the reference output (same member set,
identical uncompressed .hxb payloads) before its timing counts.

Per run, wall time, CPU time (user + system of the child and its reaped
descendants, from wait4) and peak RSS are recorded; the report gives the
minimum and median over N runs. --build also times hxmc's cold builds of the
port (native and wasm, best of N) and records the sizes of what they write.

Usage: HAXE_REFERENCE=haxe/haxe python3 site/bench/run.py [-n RUNS] [--build]
           [-w WORKLOAD ...] [--json FILE] [runner ...]

--json merges the results into FILE (entries are keyed by workload and runner,
so separate invocations can fill one file).
"""
import argparse, datetime, gzip, json, os, pathlib, platform, re, resource, shutil, statistics, subprocess, sys, tempfile, time, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
BIN = ROOT / "bin/bench"
STD = ROOT / "haxe/std"
HXMC = ROOT / "bin/hxmc/hxmc"
PORT = ROOT / "bin/port/haxe"
WASM = BIN / "haxe.wasm"
# node 22: exception handling with exnref is behind a flag; no fast API calls
# for WASI's fd_write (hxmc/tools/run.py)
NODE = ["node", "--experimental-wasm-exnref", "--no-turbo-fast-api-calls", "--no-warnings", "--stack-size=8000", str(ROOT / "hxmc/tools/wasi.mjs")]
WASMTIME = ["wasmtime", "run", "-W", "exceptions=y", "-W", "max-wasm-stack=67108864", "--dir", "/", "--env", "HAXE_STD_PATH", "--env", "PWD"]

WORKLOADS = {
    # name: (cwd, arguments)
    "hello": (ROOT / "site/bench/workloads", ["-cp", ".", "--main", "Hello"]),
    # Many std modules as bare roots.
    "stdlib": (ROOT, """haxe.Json haxe.Serializer haxe.Unserializer haxe.crypto.Sha256 haxe.crypto.Md5
        haxe.crypto.Base64 haxe.io.BytesBuffer haxe.zip.Reader haxe.zip.Writer haxe.ds.BalancedTree
        haxe.ds.GenericStack haxe.ds.ListSort haxe.xml.Parser haxe.xml.Printer haxe.Template
        haxe.format.JsonParser haxe.io.Path haxe.Int64Helper haxe.CallStack DateTools EReg StringTools
        Lambda haxe.ds.Vector haxe.EnumFlags haxe.http.HttpBase haxe.crypto.Hmac haxe.crypto.Crc32
        haxe.zip.Huffman haxe.zip.InflateImpl haxe.io.Float32Array haxe.ds.HashMap""".split()),
    # The port's own source (~52k lines, 400 modules); runs std macros.
    "self": (ROOT, ["-cp", "src", "-main", "haxe.Main"]),
}


def runners(reference):
    return {
        "reference": [reference],
        "hxmc": [str(PORT)],
        "hxmc-wasm-node": NODE + [str(WASM)],
        "hxmc-wasm-wasmtime": WASMTIME + [str(WASM)],
    }


def payloads(path):
    with zipfile.ZipFile(path) as z:
        return {n: z.read(n) for n in z.namelist() if n.endswith(".hxb")}


def unlimited_stack():
    hard = resource.getrlimit(resource.RLIMIT_STACK)[1]
    resource.setrlimit(resource.RLIMIT_STACK, (hard, hard))


def run_measured(cmd, cwd, env, log):
    """Runs cmd; returns (exit code, wall s, cpu s, peak RSS KB) of the child
    and the descendants it waited for (wait4 rusage)."""
    start = time.perf_counter()
    p = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, preexec_fn=unlimited_stack)
    _, status, ru = os.wait4(p.pid, 0)
    elapsed = time.perf_counter() - start
    p.returncode = os.waitstatus_to_exitcode(status)
    return p.returncode, elapsed, ru.ru_utime + ru.ru_stime, ru.ru_maxrss


def first_line(cmd):
    try:
        out = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30).stdout
        lines = [l.strip() for l in out.splitlines() if l.strip()]
        return lines[0] if lines else None
    except Exception:
        return None


def metadata(reference):
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
    versions = {"reference": first_line([reference, "-version"]), "node": first_line(["node", "--version"])}
    if shutil.which("wasmtime"):
        versions["wasmtime"] = first_line(["wasmtime", "--version"])
    return {
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        "commit": commit, "cpu": cpu, "cores": os.cpu_count(), "memory_gb": mem,
        "os": platform.platform(), "python": platform.python_version(), "versions": versions,
    }


def build(out, extra, env, n):
    """hxmc's cold build of the port to out (its object cache removed first),
    best of n: wall and CPU seconds, the output's size and gzipped size"""
    walls, cpus = [], []
    for _ in range(n):
        shutil.rmtree(str(out) + ".hxmc", ignore_errors=True)
        cmd = [str(HXMC), str(out), "-cp", "src", "-main", "haxe.Main", "-D", "disable-parallelism",
               "-cp", str(ROOT / "bin/hxmc/std"), "--custom-target", "hxmc"] + extra
        with open(BIN / "build.log", "w") as log:
            code, wall, cpu, _ = run_measured(cmd, ROOT, env, log)
        if code != 0:
            raise SystemExit(f"hxmc failed to build {out}; see {BIN / 'build.log'}")
        walls.append(wall)
        cpus.append(cpu)
    b = pathlib.Path(out).read_bytes()
    return {"wall": round(min(walls), 2), "cpu": round(min(cpus), 2), "size": len(b), "gzip": len(gzip.compress(b, 9))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, default=3)
    ap.add_argument("--build", action="store_true", help="time hxmc's cold builds of the port (native and wasm)")
    ap.add_argument("-w", "--workload", action="append")
    ap.add_argument("--json", metavar="FILE", help="merge machine-readable results into FILE")
    ap.add_argument("runners", nargs="*")
    opts = ap.parse_args()
    reference = os.environ.get("HAXE_REFERENCE", str(ROOT / "haxe/haxe"))
    reference = str(pathlib.Path(reference).resolve())
    table = runners(reference)
    names = opts.runners or list(table)
    # The reference output is what every other runner is checked against.
    names = ["reference"] + [n for n in names if n != "reference"]
    env = dict(os.environ, HAXE_STD_PATH=str(STD))
    meta = metadata(reference)
    BIN.mkdir(parents=True, exist_ok=True)
    builds = {}
    if opts.build:
        builds["native"] = build(PORT, [], env, opts.n)
        print(f"build native {builds['native']}", flush=True)
        builds["wasm"] = build(WASM, ["-D", "hxmc.target=wasm32-wasi"], env, opts.n)
        print(f"build wasm {builds['wasm']}", flush=True)
    elif any(n.startswith("hxmc-wasm") for n in names) and not WASM.exists():
        build(WASM, ["-D", "hxmc.target=wasm32-wasi"], env, 1)
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="hih-bench-"))
    results = {}
    try:
        for wname in opts.workload or list(WORKLOADS):
            cwd, args = WORKLOADS[wname]
            expected = None
            for rname in names:
                times, cpus, rsss = [], [], []
                status = "ok"
                for i in range(opts.n):
                    out = tmp / f"{wname}-{rname}-{i}.hxb"
                    cmd = table[rname] + args + ["-D", "disable-parallelism", "--interp", "--no-output", "--hxb", str(out)]
                    with open(tmp / "log.txt", "w") as log:
                        code, elapsed, cpu, rss = run_measured(cmd, cwd, dict(env, PWD=str(cwd)), log)
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
                print(f"{wname:8} {rname:18} {med}  {status if status != 'ok' else 'runs: ' + ' '.join(f'{t:.2f}' for t in times)}{extra}", flush=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if opts.json:
        write_json(pathlib.Path(opts.json), meta, results, table, builds)


def write_json(path, meta, results, table, builds):
    data = {"meta": {}, "runners": {}, "results": [], "builds": {}}
    if path.exists():
        data = json.loads(path.read_text())
    data.setdefault("builds", {}).update(builds)
    versions = dict(data["meta"].get("versions", {}), **meta["versions"])
    data["meta"].update(meta, versions=versions)
    # Command lines without the machine-specific prefix of this checkout.
    rel = lambda a: os.path.relpath(a, ROOT) if os.path.isabs(a) and a.startswith(str(ROOT)) else a
    for rname in {r for _, r in results}:
        data["runners"][rname] = " ".join(rel(a) for a in table[rname])
    keep = [e for e in data["results"] if (e["workload"], e["runner"]) not in results]
    for (wname, rname), (times, cpus, rsss, status) in results.items():
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
