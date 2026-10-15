# Benchmarks

How the numbers on the website were measured, and how to reproduce them.
Every timing of the port counts only if its output matches the reference
compiler's: same HXB members with byte-identical payloads, or identical
output files. All numbers are from one 4-core Xeon VM shared with other
jobs (a few percent of noise between runs; the VM's speed also varies from
day to day, so compare columns of one run, not runs of different days).
Earlier measurements (the port built for HashLink, HL/C, JS, JVM, C++ and by
hxc, the C backend this repository had until 2026-10-15) are in the Git
history of this file.

## The port (`run.py`, the Benchmarks section)

```sh
make reference port
python3 site/bench/run.py -n 3 --build --json site/bench/results.json
```

The reference compiler and the port built by hxmc compile three workloads to
HXB with `-D disable-parallelism` (`hello`, 32 std modules as roots, the
port's own source): `hxmc` is `bin/port/haxe` (x86-64, static), `hxmc-wasm-*`
the port as a wasm32-wasi module (`bin/bench/haxe.wasm`, built by run.py)
under node 22 (`hxmc/tools/wasi.mjs`) and wasmtime 38. CPU is user + system
time of the process, best of 3; node's includes its compiler threads.
`--build` times hxmc's cold builds of the port (object cache removed, best of
3) and records the sizes.

2026-10-15, at the commit the site names (`results.json`):

| workload | reference | hxmc x86-64 | wasm, node | wasm, wasmtime |
| --- | ---: | ---: | ---: | ---: |
| hello | 0.14 s, 46 MB | 0.11 s, 36 MB | 0.59 s wall (1.61 s CPU), 299 MB | 0.45 s, 645 MB |
| stdlib | 0.22 s, 60 MB | 0.22 s, 45 MB | 0.84 s wall (2.30 s CPU), 334 MB | 0.67 s, 201 MB |
| self | 9.08 s, 1.44 GB | 8.88 s, 0.88 GB | 17.0 s wall (19.6 s CPU), 2.0 GB | 17.3 s, 1.9 GB |

Builds by hxmc, cold: the x86-64 executable in 17.2 s wall (23.2 s CPU),
20.3 MB (5.9 MB gzipped); the WebAssembly module in 15.9 s wall, 16.3 MB
(3.1 MB gzipped). (The VM ran slow that day: the reference's self-compile,
6.0 s on 2026-10-09, took 9.1 s.) The playground's module (`make wasm`,
without the target generators) is 10.8 MB, 2.1 MB gzipped.

## Programs (`haxebench.py`, the Programs table)

```sh
python3 site/bench/haxebench.py -n 3 --check --rm --json site/bench/haxebench.json
```

The [HaxeBenchmarks](https://github.com/HaxeBenchmarks/benchmark-runner)
cases (cloned into `bin/haxebench`, with the libraries they use at pinned
revisions) built by hxmc from source: `hxmc`, a static linux-x86_64
executable; `hxmc-wasm-node` and `hxmc-wasm-wasmtime`, one wasm32-wasi
module run by node (`--experimental-wasm-exnref --no-turbo-fast-api-calls`)
or wasmtime (`-W exceptions=y`). Run time is the best wall time of 3 runs
(engine start-up and the module's compilation included); build time is
hxmc's cold build; sizes are the artifact and its gzip -9. `--check` builds
each case's check program (`haxebench-check/`: the case's computation with
its results printed) on every target: the outputs are identical on all
three.

2026-10-15 (`haxebench.json`): run time in seconds, size in KB.

| case | x86-64 | wasm, node | wasm, wasmtime | size x86-64 / wasm | build x86-64 / wasm |
| --- | ---: | ---: | ---: | ---: | ---: |
| alloc | 1.59 | 2.09 | 2.00 | 100 / 79 | 0.30 / 0.42 |
| bcrypt | 3.01 | 3.35 | 4.43 | 340 / 317 | 0.34 / 0.44 |
| binarytrees | 0.72 | 1.26 | 1.07 | 96 / 75 | 0.32 / 0.43 |
| json | 0.53 | 0.78 | 0.81 | 169 / 149 | 0.39 / 0.45 |
| mandelbrot | 0.78 | 1.02 | 1.28 | 101 / 80 | 0.29 / 0.46 |
| mandelbrot_anon | 1.29 | 2.50 | 1.91 | 113 / 83 | 0.30 / 0.44 |
| nbody | 0.81 | 1.20 | 0.98 | 100 / 79 | 0.42 / 0.43 |
| sha256 | 0.18 | 0.36 | 0.33 | 314 / 287 | 0.36 / 0.40 |
| sha512 | 0.027 | 0.146 | 0.094 | 326 / 295 | 0.41 / 0.49 |
| formatter_noio | 6.48 | 8.10 | 8.61 | 1347 / 1121 | 1.43 / 1.37 |

## Target generators (`targets.py`, the Target generators section)

```sh
python3 site/bench/targets.py -n 3 --json site/bench/targets-results.json
```

Both compilers (the reference and `bin/port/haxe`) build haxe-formatter
(with its libraries, from `haxebench.py`'s checkout) and the port's own
source for every target, in the same directory, with `-D
disable-parallelism`; CPU is user + system time, best of 3, and every output
file is compared. C++ and HL/C stop at the generated sources. For JS, the
port's own source is the hxmc tool as the bootstrap builds it.

## The formatter

`formatter.sh` formats the port's sources with haxe-formatter built by hxmc
(`hxformat.json`); `--check` lists the files that would change.
