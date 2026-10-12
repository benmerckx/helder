// Target generators section: renders targets.json (site/bench/targets-results.json,
// written by site/bench/targets.py --json and copied by site/build.sh).
import Js.el;
import haxe.DynamicAccess;
import js.Browser.document;
import js.html.Element;
import js.html.TableCellElement;

class Targets {
	static final TARGETS:Array<Array<String>> = [
		["hxb", "HXB"], ["js", "JavaScript"], ["lua", "Lua"], ["python", "Python"], ["php", "PHP"], ["neko", "Neko"],
		["hl", "HashLink"], ["hlc", "HL/C (sources)"], ["cpp", "C++ (sources)"], ["jvm", "JVM"], ["swf", "Flash (SWF)"],
	];
	static final PROJECTS:Array<Array<String>> = [
		["formatter", "haxe-formatter 1.9.1 with its six libraries (tokentree, haxeparser, hxparse, json2object, hxargs, hxjsonast): the HaxeBenchmarks formatter case."],
		["self", "The port's own source, about 1,000 modules including the C backend's runtime bindings. Targets without threads or a file system reject it, in both compilers."],
	];

	static var root:Element;

	static function main() {
		root = document.getElementById("targets-results");
		if (root == null) return;
		js.Browser.window.fetch("targets.json").then((r) -> r.ok ? r.json() : null).then((d) -> {
			if (Js.truthy(d)) render(d);
		}).catchError((_) -> {});
	}

	static function targetName(target:String):String {
		for (t in TARGETS) if (t[0] == target) return t[1];
		return target;
	}

	static function targetIndex(target:String):Int {
		for (i in 0...TARGETS.length) if (TARGETS[i][0] == target) return i;
		return -1;
	}

	static function secs(s:Float):String {
		return s < 10 ? Js.fixed(s, 2) + " s" : Js.fixed(s, 1) + " s";
	}

	static function ratio(r:Float):String {
		return Js.fixed(r, 2) + "×";
	}

	static function mb(m:Float):String {
		return Math.round(m) + " MB";
	}

	static function size(b:Float):String {
		return b >= 1 << 20 ? Js.fixed(b / (1 << 20), 1) + " MB" : Math.max(1, Math.round(b / 1024)) + " KB";
	}

	static function table(rows:Array<Dynamic>):Element {
		final t = el("table", "bench");
		t.innerHTML = "<thead><tr><th>Target</th><th class=\"num\">Reference</th><th class=\"num\">Port</th><th class=\"barcol\">Port CPU vs. reference <span class=\"muted\">(log scale)</span></th><th class=\"num wall\">Peak RSS</th><th class=\"out\">Output</th></tr></thead>";
		final body = el("tbody");
		final ok = rows.filter((r) -> Js.truthy(r.port) && r.port.status == "ok");
		final rs:Array<Float> = ok.map((r) -> r.port.cpu / r.reference.cpu);
		final lo = Math.log(Js.min(0.5, rs)), hi = Math.log(Js.max(2, rs));
		final pos = (x:Float) -> 100 * (Math.log(x) - lo) / (hi - lo);
		for (r in rows) {
			final tr = el("tr");
			final name = el("td", "runner", targetName(r.target));
			if (Js.truthy(r.identical)) name.append(el("span", "chk", " ✓"));
			tr.append(name);
			if (r.reference.status != "ok") {
				final status:String = r.reference.status;
				final last = Js.or(status.split(" | ").map((s) -> ((s : Dynamic).trim() : String)).filter((s) -> s != "").pop(), "");
				final td:TableCellElement = cast el("td", "fail muted", "the reference compiler rejects this project: " + ~/^exit \d+: /.replace(last, "").substring(0, 110));
				td.colSpan = 5;
				tr.append(td);
				body.append(tr);
				continue;
			}
			tr.append(el("td", "num", secs(r.reference.cpu)));
			if (!Js.truthy(r.port) || r.port.status != "ok") {
				final td:TableCellElement = cast el("td", "fail", "port failed: " + (Js.truthy(r.port) ? (r.port.status : String).substring(0, 110) : "not run"));
				td.colSpan = 4;
				tr.append(td);
				body.append(tr);
				continue;
			}
			tr.append(el("td", "num", secs(r.port.cpu)));
			final x:Float = r.port.cpu / r.reference.cpu;
			final bar = el("td", "barcol");
			final track = el("div", "track");
			final fill = el("div", "fill" + (x < 0.995 ? " fast" : ""));
			fill.style.width = Math.max(1.5, pos(x)) + "%";
			final mark = el("div", "mark");
			mark.style.left = pos(1) + "%";
			track.append(fill, mark, el("span", "lbl", ratio(x)));
			bar.append(track);
			tr.append(bar);
			tr.append(el("td", "num wall", mb(r.port.rss_mb) + " / " + mb(r.reference.rss_mb)));
			final out = el("td", "out " + (Js.truthy(r.identical) ? "ok" : "fail"), Js.truthy(r.identical)
				? 'identical, ${r.port.members > 1 ? Js.str(r.port.members) + " files, " : ""}${size(r.port.bytes)}'
				: "different");
			tr.append(out);
			body.append(tr);
		}
		t.append(body);
		return t;
	}

	static function render(data:Dynamic) {
		final byProject:DynamicAccess<Array<Dynamic>> = {};
		for (r in (data.results : Array<Dynamic>)) {
			if (!Js.truthy(byProject[r.project])) byProject[r.project] = [];
			byProject[r.project].push(r);
		}
		for (p in byProject.keys()) byProject[p].sort((a, b) -> targetIndex(a.target) - targetIndex(b.target));
		final names = PROJECTS.filter((p) -> Js.truthy(byProject[p[0]]));
		if (names.length == 0) return;
		root.textContent = "";
		final tabs = el("div", "tabs");
		tabs.setAttribute("role", "tablist");
		final panes:Array<Element> = [];
		for (i in 0...names.length) {
			final p = names[i][0];
			final b = el("button", "", p);
			b.setAttribute("role", "tab");
			b.setAttribute("aria-selected", i == 0 ? "true" : "false");
			b.onclick = () -> {
				for (k in 0...tabs.children.length) tabs.children[k].setAttribute("aria-selected", tabs.children[k] == b ? "true" : "false");
				for (j in 0...panes.length) panes[j].hidden = j != i;
			};
			tabs.append(b);
			final pane = el("div", "pane");
			pane.hidden = i != 0;
			final rows = byProject[p];
			final ok = rows.filter((r) -> Js.truthy(r.port) && r.port.status == "ok");
			var ref = 0.0, port = 0.0;
			for (r in ok) ref = ref + r.reference.cpu;
			for (r in ok) port = port + r.port.cpu;
			final same = ok.filter((r) -> Js.truthy(r.identical)).length;
			pane.append(el("p", "note", names[i][1] + (ok.length > 0 ? ' Over the ${ok.length} targets: ${secs(port)} of CPU for the port, ${secs(ref)} for the reference (${ratio(port / ref)}); ${same} of ${ok.length} outputs identical.' : "")));
			final scroll = el("div", "scroll");
			scroll.append(table(rows));
			pane.append(scroll);
			pane.append(el("p", "note", "CPU: minimum of the runs. Peak RSS: port / reference. The dashed line marks the reference; green bars are faster than it."));
			panes.push(pane);
		}
		root.append(tabs);
		for (q in panes) root.append(q);
		final m:Dynamic = Js.or(data.meta, {});
		final facts = document.getElementById("targets-machine");
		if (facts != null) {
			final parts:Array<String> = [];
			if (Js.truthy(m.cpu)) parts.push('${Js.str(m.cpu)}, ${Js.str(m.cores)} cores');
			if (Js.truthy(m.date)) parts.push('measured ${(m.date : String).substring(0, 10)}');
			if (Js.truthy(m.commit)) parts.push('commit ${Js.str(m.commit)}');
			if (Js.truthy(m.reference)) parts.push('reference: ${Js.str(m.reference)}');
			facts.textContent = parts.join("; ") + ".";
		}
	}
}
