import Ui.el;
import Ui.fixed;
import haxe.DynamicAccess;
import js.Browser.document;
import js.Browser.window;
import js.html.Element;
import js.html.MouseEvent;

// The Programs part of the Benchmarks section: the HaxeBenchmarks cases on
// hxmc and the other targets (hxmc/test/Bench.hx, .github/workflows/bench.yml).
// bench/history.json (every run: per case and target the median, min, max and
// peak RSS) and bench/latest.json (the newest CI run in full) come from the
// bench-data branch, copied by `make site BENCH_DATA=<dir>`. The latest run as
// a table (time, relative to hxmc, peak RSS, size) and below it the compile
// time of every case and target (the Haxe compiler, and the C/C++ compiler for
// C++ and HL/C), the history as one line chart per case (inline SVG, one line
// per target; hidden for now: SHOW_HISTORY).
typedef HistoryRun = {
	file:String,
	date:String,
	commit:String,
	source:String,
	?machine:String,
	?runs:Int,
	?stat:String,
	?note:String,
	?run_url:String,
	results:DynamicAccess<DynamicAccess<Array<Null<Float>>>>,
}

// (schema 2: each run's per case and target array holds `fields`: median, min,
// max, rss_mb, build_s, haxe_s, cc_s; schema 1 the first four)
typedef History = {
	?schema:Int,
	?fields:Array<String>,
	targets:Array<String>,
	runs:Array<HistoryRun>,
}

typedef LatestEntry = {
	?median:Float,
	?min:Float,
	?max:Float,
	?times:Array<Float>,
	?cpu:Float,
	?rss_mb:Float,
	?build_s:Float,
	?haxe_s:Float,
	?cc_s:Float,
	?size:Float,
	?gzip:Float,
	?check:String,
	?error:String,
}

typedef Latest = {
	date:String,
	short:String,
	runs:Int,
	?run_url:String,
	?machine:{?cpu:String, ?cores:Int, ?memory_gb:Float, ?runner:String},
	?versions:DynamicAccess<String>,
	targets:Array<String>,
	cases:Array<String>,
	results:DynamicAccess<DynamicAccess<LatestEntry>>,
	?checks:DynamicAccess<{?output:String, differ:Array<String>}>,
}

class BenchCharts {
	// the targets in their color order (style.css: --s1 ... --s7)
	static final TARGETS = [
		["hxmc", "hxmc, x86-64"], ["hxmc-wasm", "hxmc, wasm (Node)"], ["cpp", "C++ (hxcpp)"], ["jvm", "JVM"], ["js", "JS (Node)"], ["hlc", "HL/C"],
		["hl", "HashLink JIT"],
	];
	static final CASES = [
		["alloc", "allocation"], ["bcrypt", "bcrypt"], ["binarytrees", "binary trees"], ["json", "JSON"], ["mandelbrot", "Mandelbrot"],
		["mandelbrot_anon", "Mandelbrot, anonymous objects"], ["nbody", "n-body"], ["sha256", "SHA-256"], ["sha512", "SHA-512"],
		["formatter_noio", "haxe-formatter"],
	];
	static final METRICS = [
		["time", "Time"], ["rel", "vs. hxmc"], ["rss", "Peak RSS"], ["size", "Size (gzip)"],
	];
	// the "Over time" charts (index.html's #programs-over-time): off for now, the
	// code kept; a page URL with ?bench-history shows them anyway
	static final SHOW_HISTORY = false;

	static var hidden = new Map<String, Bool>();
	static var relative = false;
	static var redraw:Array<() -> Void> = [];

	public static function load() {
		final root = document.getElementById("programs-results");
		if (root == null) return;
		final get = (f:String) -> (cast window.fetch(Version.url(f)).then((r) -> r.ok ? r.json() : null).catchError((_) -> null) : js.lib.Promise<Dynamic>);
		get("bench/latest.json").then((latest:Null<Latest>) -> {
			if (latest != null) renderLatest(root, latest)
			else root.innerHTML = "<p class=\"note\">No benchmark results in this build of the site (<code>make site BENCH_DATA=&lt;a checkout of the bench-data branch&gt;</code>).</p>";
			final wrap = document.getElementById("programs-over-time");
			final hist = document.getElementById("programs-history");
			final showHistory = SHOW_HISTORY || new js.html.URLSearchParams(window.location.search).has("bench-history");
			if (wrap != null && showHistory) wrap.hidden = false;
			if (hist != null && showHistory) get("bench/history.json").then((h:Null<History>) -> if (h != null && h.runs.length > 0) renderHistory(hist, h) else hist.textContent = "");
		});
	}

	static function label(id:String, list:Array<Array<String>>):String {
		for (t in list) if (t[0] == id) return t[1];
		return id;
	}

	static function color(id:String):String {
		for (i => t in TARGETS) if (t[0] == id) return 'var(--s${i + 1})';
		return "var(--muted)";
	}

	static function secs(s:Float):String {
		return s < 0.1 ? fixed(s * 1000, 0) + " ms" : s < 10 ? fixed(s, 2) + " s" : fixed(s, 1) + " s";
	}

	static function bytes(b:Float):String {
		return b >= 1 << 20 ? fixed(b / (1 << 20), 1) + " MB" : Math.max(1, Math.round(b / 1024)) + " KB";
	}

	static function ratio(r:Float):String {
		return (r < 10 ? fixed(r, 2) : fixed(r, 1)) + "×";
	}

	static function geomean(xs:Array<Float>):Float {
		var s = 0.0;
		for (x in xs) s += Math.log(x);
		return Math.exp(s / xs.length);
	}

	// ---- the latest run

	static function renderLatest(root:Element, d:Latest) {
		root.textContent = "";
		final targets = [for (t in TARGETS) if (d.targets.indexOf(t[0]) >= 0) t[0]];
		final cases = [for (c in CASES) if (d.results.exists(c[0])) c[0]];
		final bar = el("div", "tabs");
		bar.setAttribute("role", "tablist");
		final scroll = el("div", "scroll");
		final legendNote = el("p", "note");
		root.append(bar, scroll, legendNote);
		final show = (metric:String) -> {
			for (i => m in METRICS) bar.children[i].setAttribute("aria-selected", m[0] == metric ? "true" : "false");
			scroll.textContent = "";
			scroll.append(latestTable(d, targets, cases, metric));
			legendNote.textContent = switch metric {
				case "time": 'Wall time of the whole process, median of ${d.runs} runs (hover a cell for the spread and CPU time); bold: the fastest. ⚠ the case\'s check output differs from the other targets\', ✗ failed.';
				case "rel": "Median time relative to hxmc's x86-64 executable (below 1×: faster than hxmc). The last row is the geometric mean over the cases.";
				case "rss": "Peak resident set size of the process (getrusage), median of the runs: the JVM, Node and the HashLink VM included.";
				case "size": "The artifact, gzip -9: the static executable (hxmc), the module (wasm), stripped executables (C++, HL/C; dynamically linked to libstdc++ or libhl), the jar, the script, the bytecode.";
				case _: "";
			};
		};
		for (m in METRICS) {
			final b = el("button", "", m[1]);
			b.setAttribute("role", "tab");
			b.onclick = () -> show(m[0]);
			bar.append(b);
		}
		show("time");
		final compile = document.getElementById("programs-compile");
		if (compile != null) renderCompile(compile, d, targets, cases);
		final facts = document.getElementById("programs-machine");
		if (facts != null) {
			final parts = [];
			final m = d.machine;
			if (m != null && m.cpu != null) parts.push('${m.cpu}, ${m.cores} cores${m.memory_gb != null ? ', ${Math.round(m.memory_gb)} GB' : ""}${m.runner != null ? " (GitHub Actions, " + StringTools.trim(m.runner) + ")" : ""}');
			parts.push('measured ${d.date.substring(0, 10)} at commit ${d.short}');
			final v = d.versions;
			if (v != null) {
				final tools = [for (k in ["node", "java", "gcc", "hashlink", "hxcpp", "hxnodejs", "hxjava"]) if (v[k] != null) (StringTools.startsWith(v[k].toLowerCase(), k) ? "" : k + " ") + v[k]];
				parts.push(tools.join(", "));
			}
			facts.textContent = parts.join("; ") + ".";
			if (d.run_url != null) {
				final a:js.html.AnchorElement = cast el("a", "", "Run log");
				a.href = d.run_url;
				facts.append(document.createTextNode(" "), a, document.createTextNode("."));
			}
		}
		final noise = document.getElementById("programs-noise");
		if (noise != null) {
			final spreads = [];
			for (c in cases) for (t in targets) {
				final r = d.results[c][t];
				if (r != null && r.median != null && r.max != null && r.min != null && r.median > 0) spreads.push((r.max - r.min) / r.median);
			}
			spreads.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
			if (spreads.length > 0) {
				final med = spreads[spreads.length >> 1], p90 = spreads[Std.int(spreads.length * 0.9)];
				noise.textContent = 'Noise: a shared cloud machine. In this run the spread of a target\'s ${d.runs} runs (max − min over the median) is ${fixed(med * 100, 1)}% typically, ${fixed(p90 * 100, 1)}% at the 90th percentile; nightlies also land on different machines of the same type, so read changes of a few percent between points as noise and the relative view as the more stable one.';
			}
		}
	}

	static function latestTable(d:Latest, targets:Array<String>, cases:Array<String>, metric:String):Element {
		final t = el("table", "bench matrix");
		final head = el("tr");
		head.append(el("th", "", "Case"));
		for (x in targets) {
			final th = el("th", "num");
			final sw = el("span", "swatch");
			sw.style.background = color(x);
			th.append(sw, document.createTextNode(label(x, TARGETS)));
			head.append(th);
		}
		final thead = el("thead");
		thead.append(head);
		t.append(thead);
		final body = el("tbody");
		final rels = [for (x in targets) x => []];
		for (c in cases) {
			final row = d.results[c];
			final tr = el("tr");
			tr.append(el("td", "runner", label(c, CASES)));
			final base = row["hxmc"] != null ? row["hxmc"].median : null;
			final value = (r:LatestEntry) -> r == null || r.error != null ? null : switch metric {
				case "time": r.median;
				case "rel": base == null || r.median == null ? null : r.median / base;
				case "rss": r.rss_mb;
				case "size": r.gzip;
				case _: r.build_s;
			};
			var best = Math.POSITIVE_INFINITY;
			for (x in targets) {
				final v = value(row[x]);
				if (v != null && v < best) best = v;
			}
			for (x in targets) {
				final r = row[x];
				final v = value(r);
				final td = el("td", "num");
				if (r == null) td.textContent = "–";
				else if (r.error != null) {
					td.textContent = "✗";
					td.className = "num fail";
					td.title = r.error.substring(0, 400);
				} else if (v == null) td.textContent = "–";
				else {
					td.textContent = switch metric {
						case "time": secs(v);
						case "rel": ratio(v);
						case "rss": v < 10 ? fixed(v, 1) + " MB" : Math.round(v) + " MB";
						case "size": bytes(v);
						case _: secs(v);
					};
					if (metric == "rel") rels[x].push(v);
					if (v == best && metric != "rel") td.classList.add("best");
					if (metric == "rel" && x != "hxmc" && v < 0.995) td.classList.add("best");
					if (r.median != null) td.title = 'median ${secs(r.median)} (min ${secs(r.min)}, max ${secs(r.max)}, ${r.times != null ? r.times.length : d.runs} runs); CPU ${r.cpu != null ? secs(r.cpu) : "–"}; peak RSS ${r.rss_mb} MB';
				}
				if (r != null && r.check == "differs") {
					td.append(el("span", "warnmark", " ⚠"));
					td.title = "check output differs from the other targets'. " + td.title;
				}
				tr.append(td);
			}
			body.append(tr);
		}
		if (metric == "rel") {
			final tr = el("tr", "ref");
			tr.append(el("td", "runner", "geometric mean"));
			for (x in targets) tr.append(el("td", "num", rels[x].length == cases.length ? ratio(geomean(rels[x])) : "–"));
			body.append(tr);
		}
		t.append(body);
		return t;
	}

	// ---- compile time

	static function renderCompile(root:Element, d:Latest, targets:Array<String>, cases:Array<String>) {
		root.textContent = "";
		if (!Lambda.exists(cases, (c) -> Lambda.exists(targets, (x) -> d.results[c][x] != null && d.results[c][x].build_s != null))) return;
		final split = Lambda.exists(cases, (c) -> Lambda.exists(targets, (x) -> d.results[c][x] != null && d.results[c][x].haxe_s != null));
		root.append(el("h4", "", "Compile time"));
		final t = el("table", "bench matrix compile");
		final head = el("tr");
		head.append(el("th", "", "Case"));
		for (x in targets) {
			final th = el("th", "num");
			final sw = el("span", "swatch");
			sw.style.background = color(x);
			th.append(sw, document.createTextNode(label(x, TARGETS)));
			head.append(th);
		}
		final thead = el("thead");
		thead.append(head);
		t.append(thead);
		final body = el("tbody");
		final sums = [for (x in targets) x => 0.0], counts = [for (x in targets) x => 0];
		for (c in cases) {
			final row = d.results[c];
			final tr = el("tr");
			tr.append(el("td", "runner", label(c, CASES)));
			var best = Math.POSITIVE_INFINITY;
			for (x in targets) {
				final r = row[x];
				if (r != null && r.build_s != null && r.build_s < best) best = r.build_s;
			}
			for (x in targets) {
				final r = row[x];
				final td = el("td", "num");
				if (r == null || r.build_s == null) {
					td.textContent = r != null && r.error != null ? "✗" : "–";
					if (r != null && r.error != null) {
						td.className = "num fail";
						td.title = r.error.substring(0, 400);
					}
				} else {
					td.append(el("span", "total", secs(r.build_s)));
					sums[x] += r.build_s;
					counts[x]++;
					if (r.build_s == best) td.classList.add("best");
					if (r.cc_s != null && r.haxe_s != null) {
						td.append(el("span", "parts", fixed(r.haxe_s, 2) + " + " + fixed(r.cc_s, 2)));
						td.title = 'Haxe ${secs(r.haxe_s)}, ${x == "cpp" ? "C++ (hxcpp, g++)" : "C (gcc)"} ${secs(r.cc_s)}';
					} else if (r.haxe_s != null) td.title = x == "hxmc" || x == "hxmc-wasm" ? 'hxmc ${secs(r.haxe_s)}: typing, code generation and link' : 'Haxe ${secs(r.haxe_s)}';
				}
				tr.append(td);
			}
			body.append(tr);
		}
		final tr = el("tr", "ref");
		tr.append(el("td", "runner", "total"));
		for (x in targets) tr.append(el("td", "num", counts[x] == cases.length ? secs(sums[x]) : "–"));
		body.append(tr);
		t.append(body);
		final scroll = el("div", "scroll");
		scroll.append(t);
		root.append(scroll);
		root.append(el("p", "note",
			"Wall time of a cold build of each case (a fresh output directory). hxmc: the tool's whole build, from the Haxe sources to the executable or module (typing, code generation, link; its typed runtime cached per tool, as in every build). JVM, JS, HashLink: the port's run (typing and the generator, which writes the jar, the script or the bytecode). C++ and HL/C: the port writing the C++ or C sources "
			+ (split ? "+ the C/C++ compiler (the second number: hxcpp with g++, its runtime compiled once beforehand; gcc -O3 against libhl), " : "and the C/C++ compiler (hxcpp with g++, its runtime compiled once beforehand; gcc -O3 against libhl), ")
			+ "the total on top. Bold: the fastest; the last row sums the cases."));
	}

	// ---- the history

	static function renderHistory(root:Element, h:History) {
		root.textContent = "";
		final targets = [for (t in TARGETS) if (h.targets.indexOf(t[0]) >= 0) t[0]];
		final controls = el("div", "chartbar");
		final legend = el("div", "legend");
		for (x in targets) {
			final b = el("button", "series");
			b.setAttribute("aria-pressed", "true");
			final sw = el("span", "swatch");
			sw.style.background = color(x);
			b.append(sw, document.createTextNode(label(x, TARGETS)));
			b.onclick = () -> {
				hidden[x] = !hidden[x];
				b.setAttribute("aria-pressed", hidden[x] ? "false" : "true");
				for (f in redraw) f();
			};
			legend.append(b);
		}
		final scale = el("div", "tabs");
		for (m in [["abs", "Seconds"], ["rel", "vs. hxmc"]]) {
			final b = el("button", "", m[1]);
			b.setAttribute("aria-selected", (m[0] == "rel") == relative ? "true" : "false");
			b.onclick = () -> {
				relative = m[0] == "rel";
				for (i in 0...scale.children.length) scale.children[i].setAttribute("aria-selected", i == (relative ? 1 : 0) ? "true" : "false");
				for (f in redraw) f();
			};
			scale.append(b);
		}
		controls.append(legend, scale);
		final grid = el("div", "charts");
		root.append(controls, grid);
		redraw = [];
		for (c in CASES) {
			if (!Lambda.exists(h.runs, (r) -> r.results.exists(c[0]))) continue;
			final fig = el("figure", "chart");
			final cap = el("figcaption", "", c[1]);
			final box = el("div", "plot");
			fig.append(cap, box);
			grid.append(fig);
			final draw = () -> drawChart(box, h, c[0], targets);
			redraw.push(draw);
			draw();
		}
		final imported = Lambda.count(h.runs, (r) -> r.source == "imported");
		final p = el("p", "note",
			'${h.runs.length} runs. Each point is the median of the runs of one benchmark run (hover a chart for the values). Click a target to hide it; the scale follows the visible ones.'
			+ (imported > 0 ? ' The shaded points (${imported}) are earlier measurements imported from the repository\'s history: a development VM instead of the CI runner, the best instead of the median of the runs, HashLink 2.0 from master, built by the reference compiler; compare them by shape and through the relative view only.' : ""));
		root.append(p);
	}

	static function drawChart(box:Element, h:History, c:String, targets:Array<String>) {
		final runs = [for (r in h.runs) if (r.results.exists(c)) r];
		final shown = [for (x in targets) if (!hidden[x]) x];
		final W = 340.0, H = 190.0, L = 40.0, R = 8.0, T = 10.0, B = 24.0;
		final value = (r:HistoryRun, x:String) -> {
			final e = r.results[c][x];
			if (e == null || e[0] == null) return null;
			if (!relative) return e[0];
			final b = r.results[c]["hxmc"];
			return b == null || b[0] == null ? null : e[0] / b[0];
		};
		var hi = relative ? 1.0 : 0.0;
		for (r in runs) for (x in shown) {
			final v = value(r, x);
			if (v != null && v > hi) hi = v;
		}
		if (hi <= 0) hi = 1;
		final step = niceStep(hi / 4);
		hi = Math.ceil(hi / step) * step;
		final n = runs.length;
		final xAt = (i:Int) -> n == 1 ? L + (W - L - R) / 2 : L + i * (W - L - R) / (n - 1);
		final yAt = (v:Float) -> T + (H - T - B) * (1 - v / hi);
		final s = new StringBuf();
		s.add('<svg viewBox="0 0 $W $H" role="img" aria-label="${label(c, CASES)}: ${relative ? "time relative to hxmc" : "seconds"} per run">');
		// imported runs: shaded
		var lastImported = -1;
		for (i => r in runs) if (r.source == "imported") lastImported = i;
		if (lastImported >= 0) {
			final x1 = n == 1 ? W - R : (xAt(lastImported) + (lastImported + 1 < n ? xAt(lastImported + 1) : xAt(lastImported))) / 2;
			s.add('<rect class="imported" x="$L" y="$T" width="${x1 - L}" height="${H - T - B}"/>');
		}
		var v = 0.0;
		while (v <= hi + step / 2) {
			final y = yAt(v);
			s.add('<line class="grid" x1="$L" x2="${W - R}" y1="$y" y2="$y"/>');
			s.add('<text class="tick" x="${L - 4}" y="${y + 3.5}" text-anchor="end">${relative ? fixed(v, step < 1 ? 1 : 0) + "×" : tick(v, step)}</text>');
			v += step;
		}
		if (relative) s.add('<line class="unit" x1="$L" x2="${W - R}" y1="${yAt(1)}" y2="${yAt(1)}"/>');
		s.add('<text class="tick" x="$L" y="${H - 6}">${runs[0].date.substring(0, 10)}</text>');
		if (n > 1) s.add('<text class="tick" x="${W - R}" y="${H - 6}" text-anchor="end">${runs[n - 1].date.substring(0, 10)}</text>');
		for (x in shown) {
			final pts = [];
			var path = new StringBuf(), pen = false;
			for (i => r in runs) {
				final v = value(r, x);
				if (v == null) {
					pen = false;
					continue;
				}
				path.add((pen ? "L" : "M") + fixed(xAt(i), 1) + " " + fixed(yAt(v), 1));
				pen = true;
				pts.push('<circle cx="${fixed(xAt(i), 1)}" cy="${fixed(yAt(v), 1)}" r="${n > 40 ? 1.5 : 2.5}"/>');
			}
			s.add('<g class="series" style="--c:${color(x)}"><path d="${path.toString()}"/>${pts.join("")}</g>');
		}
		s.add('<line class="cross" x1="0" x2="0" y1="$T" y2="${H - B}" visibility="hidden"/>');
		s.add('<rect class="hit" x="0" y="0" width="$W" height="$H"/></svg>');
		box.innerHTML = s.toString() + '<div class="tip" hidden></div>';
		final svg = box.firstElementChild;
		final cross = svg.querySelector(".cross");
		final tip = box.querySelector(".tip");
		final move = (e:MouseEvent) -> {
			final rect = svg.getBoundingClientRect();
			final px = (e.clientX - rect.left) * W / rect.width;
			var best = 0;
			for (i in 0...n) if (Math.abs(xAt(i) - px) < Math.abs(xAt(best) - px)) best = i;
			final r = runs[best];
			cross.setAttribute("x1", "" + xAt(best));
			cross.setAttribute("x2", "" + xAt(best));
			cross.setAttribute("visibility", "visible");
			final rows = [for (x in shown) {x: x, v: value(r, x)}].filter((o) -> o.v != null);
			rows.sort((a, b) -> a.v < b.v ? -1 : a.v > b.v ? 1 : 0);
			final head = '<b>${r.date.substring(0, 10)}</b> · <code>${r.commit}</code>' + (r.source == "imported" ? " · imported (dev VM, best of " + r.runs + ")" : r.source == "ci" ? "" : " · " + r.source);
			tip.innerHTML = head + rows.map((o) -> '<div><span class="swatch" style="background:${color(o.x)}"></span>${label(o.x, TARGETS)}<span class="v">${relative ? ratio(o.v) : secs(o.v)}</span></div>').join("");
			tip.hidden = false;
			final left = xAt(best) / W * rect.width;
			tip.style.left = (left > rect.width / 2 ? left - tip.offsetWidth - 10 : left + 10) + "px";
		};
		svg.addEventListener("pointermove", move);
		svg.addEventListener("pointerdown", move);
		svg.addEventListener("pointerleave", (_) -> {
			tip.hidden = true;
			cross.setAttribute("visibility", "hidden");
		});
	}

	static function niceStep(raw:Float):Float {
		final p = Math.pow(10, Math.floor(Math.log(raw) / Math.log(10)));
		final f = raw / p;
		return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * p;
	}

	static function tick(v:Float, step:Float):String {
		return v == 0 ? "0" : step < 0.1 ? fixed(v, 2) : step < 1 ? fixed(v, 1) : fixed(v, 0) + "";
	}
}
