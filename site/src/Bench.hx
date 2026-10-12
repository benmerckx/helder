// Benchmarks section: renders bench.json (site/bench/results.json, written by
// site/bench/run.py --json and copied by site/build.sh).
import Js.el;
import haxe.DynamicAccess;
import js.Browser.document;
import js.html.Element;
import js.html.TableCellElement;

class Bench {
	static final RUNNERS = [
		["reference", "OCaml reference"],
		["eval-source", "Eval, from source"],
		["eval-hxb", "Eval, from HXB"],
		["hl", "HashLink JIT"],
		["hlc", "HL/C"],
		["js", "JS (Node)"],
		["jvm", "JVM"],
		["cpp", "C++ (hxcpp)"],
		["hxc", "hxc, tcc"],
		["hxc-o2", "hxc, gcc -O2"],
		["hxc-clang", "hxc, clang -O2"],
		["hxc-cosmo", "hxc, cosmocc"],
		["wasm", "hxc, wasm (Node)"],
	];
	static final WORKLOADS:Array<Array<String>> = [
		["self", "The port's own source: 52k lines in 382 modules, with std macros run by the Eval interpreter."],
		["stdlib", "32 standard library modules (JSON, XML, zip, crypto, data structures) as roots."],
		["hello", "Hello world: mostly start-up time and the core standard library."],
	];

	static var root:Element;

	static function main() {
		root = document.getElementById("bench-results");
		if (root == null) return;
		js.Browser.window.fetch("bench.json").then((r) -> r.ok ? r.json() : null).then((d) -> {
			if (Js.truthy(d)) render(d);
		}).catchError((_) -> {});
	}

	static function secs(s:Null<Float>):String {
		return s == null ? "–" : s < 10 ? Js.fixed(s, 2) + " s" : s < 100 ? Js.fixed(s, 1) + " s" : Math.round(s) + " s";
	}

	static function ratio(r:Float):String {
		return r < 10 ? Js.fixed(r, 2) + "×" : r < 100 ? Js.fixed(r, 1) + "×" : Math.round(r) + "×";
	}

	static function mb(m:Null<Float>):String {
		return m == null ? "–" : m >= 1024 ? Js.fixed(m / 1024, 1) + " GB" : Math.round(m) + " MB";
	}

	static function table(rows:Array<Dynamic>, ref:Dynamic):Element {
		final t = el("table", "bench");
		t.innerHTML = "<thead><tr><th>Runner</th><th class=\"num\">CPU</th><th class=\"barcol\">CPU vs. reference <span class=\"muted\">(log scale)</span></th><th class=\"num wall\">Wall</th><th class=\"num\">Peak RSS</th><th class=\"out\">Output</th></tr></thead>";
		final body = el("tbody");
		final ok = rows.filter((r) -> r.cpu_min != null);
		final rs:Array<Float> = ok.map((r) -> r.cpu_min / ref.cpu_min);
		final lo = Math.log(Js.min(0.5, rs)), hi = Math.log(Js.max(2, rs));
		final pos = (r:Float) -> 100 * (Math.log(r) - lo) / (hi - lo);
		for (r in rows) {
			final tr = el("tr", r.runner == "reference" ? "ref" : "");
			final name = el("td", "runner", r.label);
			// on narrow screens the Output column is hidden: a check mark marks verified runs
			if (Js.truthy(r.verified)) name.append(el("span", "chk", " ✓"));
			if (r.runs > 1 || r.runs == 1) name.title = '${Js.str(r.runs)} run${r.runs > 1 ? "s" : ""}';
			tr.append(name);
			if (r.cpu_min == null) {
				// "exit 1: <log tail with | for newlines>": the last log line is the error
				final status:String = r.status;
				final last = Js.or(status.split(" | ").map((s) -> ((s : Dynamic).trim() : String)).filter((s) -> s != "").pop(), status);
				final td:TableCellElement = cast el("td", "fail", StringTools.startsWith(status, "exit") ? "failed: " + ~/^exit \d+: /.replace(last, "").substring(0, 120) : status);
				if (Js.truthy(r.note)) td.textContent += ". " + Js.str(r.note);
				td.colSpan = 5;
				tr.append(td);
				body.append(tr);
				continue;
			}
			final x:Float = r.cpu_min / ref.cpu_min;
			tr.append(el("td", "num", secs(r.cpu_min) + (r.runs == 1 ? "¹" : "")));
			final bar = el("td", "barcol");
			final track = el("div", "track");
			final fill = el("div", "fill" + (r.runner == "reference" ? " base" : x < 0.995 ? " fast" : ""));
			fill.style.width = Math.max(1.5, pos(x)) + "%";
			final mark = el("div", "mark");
			mark.style.left = pos(1) + "%";
			track.append(fill, mark, el("span", "lbl", ratio(x)));
			bar.append(track);
			tr.append(bar);
			tr.append(el("td", "num wall", secs(r.wall_min)));
			tr.append(el("td", "num", mb(r.maxrss_mb)));
			tr.append(el("td", "out " + (Js.truthy(r.verified) ? "ok" : "muted"), r.runner == "reference" ? "baseline" : Js.truthy(r.verified) ? "identical" : "–"));
			body.append(tr);
		}
		t.append(body);
		return t;
	}

	static function render(data:Dynamic) {
		final byWorkload:DynamicAccess<DynamicAccess<Dynamic>> = {};
		for (r in (data.results : Array<Dynamic>)) {
			if (!byWorkload.exists(r.workload)) byWorkload[r.workload] = {};
			byWorkload[r.workload][r.runner] = r;
		}
		final names = WORKLOADS.filter((w) -> Js.truthy(byWorkload[w[0]]) && Js.truthy(byWorkload[w[0]]["reference"]));
		if (names.length == 0) return;
		root.textContent = "";
		final tabs = el("div", "tabs");
		tabs.setAttribute("role", "tablist");
		final panes:Array<Element> = [];
		for (i in 0...names.length) {
			final w = names[i][0];
			final b = el("button", "", w);
			b.setAttribute("role", "tab");
			b.setAttribute("aria-selected", i == 0 ? "true" : "false");
			b.onclick = () -> {
				for (k in 0...tabs.children.length) tabs.children[k].setAttribute("aria-selected", tabs.children[k] == b ? "true" : "false");
				for (j in 0...panes.length) panes[j].hidden = j != i;
			};
			tabs.append(b);
			final pane = el("div", "pane");
			pane.hidden = i != 0;
			final rows:Array<Dynamic> = [];
			final notes:DynamicAccess<Dynamic> = Js.or(data.notes, {});
			for (runner in RUNNERS) {
				final id = runner[0], label = runner[1];
				if (Js.truthy(byWorkload[w][id])) rows.push(js.lib.Object.assign({label: label, note: notes[w + "/" + id]}, byWorkload[w][id]));
			}
			final ref:Dynamic = byWorkload[w]["reference"];
			pane.append(el("p", "note", names[i][1] + ' Reference: ${secs(ref.cpu_min)} CPU, ${mb(ref.maxrss_mb)}.'));
			final scroll = el("div", "scroll");
			scroll.append(table(rows, ref));
			pane.append(scroll);
			pane.append(el("p", "note", "Identical (✓): every .hxb member byte-identical to the reference's. The dashed line marks the reference." + (rows.filter((r) -> r.runs == 1).length > 0 ? " ¹ Single run (slow runner)." : "")));
			panes.push(pane);
		}
		root.append(tabs);
		for (p in panes) root.append(p);
		final m:Dynamic = Js.or(data.meta, {}), v:DynamicAccess<String> = Js.or(m.versions, {});
		final facts = document.getElementById("bench-machine");
		if (facts != null) {
			final parts:Array<String> = [];
			if (Js.truthy(m.cpu)) parts.push('${Js.str(m.cpu)}, ${Js.str(m.cores)} cores${Js.truthy(m.memory_gb) ? ', ${Math.round(m.memory_gb)} GB' : ""}');
			if (Js.truthy(m.date)) parts.push('measured ${(m.date : String).substring(0, 10)}');
			if (Js.truthy(m.commit)) parts.push('commit ${Js.str(m.commit)}');
			final tools = [
				["reference", "Haxe"], ["node", "Node"], ["node_wasm", "Node (wasm)"], ["hl", "HashLink"], ["java", ""], ["gcc", ""], ["tcc", ""], ["cosmocc", ""], ["emcc", ""]
			].filter((t) -> Js.truthy(v[t[0]])).map((t) -> (t[1] != "" ? t[1] + " " : "")
				+ ~/ \d{4}-\d\d-\d\d$/.replace(~/"/g.replace(~/ version /.replace(~/\s*\([^)]*\)/g.replace(v[t[0]], ""), " "), ""), ""));
			facts.textContent = parts.join("; ") + (tools.length > 0 ? ". Tools: " + tools.join(", ") + "." : ".");
		}
	}
}
