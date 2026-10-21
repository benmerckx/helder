import js.Browser.document;
import js.Browser.window;
import js.html.Element;

// The forge: the loader over the stage while the compiler works. Its rings
// fill with what actually happens: the downloads (fetch), the sources the
// compiler reads (parse · type), the objects it writes (emit), the link;
// its ticker shows the files as they go, each one a spark and a nudge of
// the sky's warp.
class Forge {
	static final ORDER = ["fetch", "parse", "emit", "link"];

	public var reads(default, null) = 0;

	final el:Element;
	final sky:Sky;
	var writes = 0;
	var expect = 500;
	var phase:Null<String>;

	public function new(sky:Sky) {
		el = document.getElementById("forge");
		this.sky = sky;
	}

	inline function byId(id:String)
		return document.getElementById(id);

	public function show(label:String, ?expect:Int) {
		el.hidden = false;
		reads = writes = 0;
		this.expect = expect == null || expect == 0 ? 500 : expect;
		phase = null;
		byId("ticker").innerHTML = "";
		for (s in ORDER) ring(s, 0);
		set("fetch", label);
		byId("forge-count").textContent = "…";
		sky.hold(0.35);
	}

	public function hide() {
		el.hidden = true;
		sky.hold(0);
	}

	public function ring(name:String, f:Float) {
		var c:Dynamic = byId("ring-" + name);
		var len = 2 * Math.PI * (c.r.baseVal.value : Float);
		c.style.strokeDasharray = '${Math.max(0, Math.min(1, f)) * len} $len';
	}

	public function set(p:String, ?label:String) {
		if (phase != p) {
			var i = ORDER.indexOf(p);
			for (li in el.querySelectorAll(".phases li")) {
				var e:Element = cast li;
				var j = ORDER.indexOf(e.dataset.phase);
				e.classList.toggle("on", j == i);
				e.classList.toggle("done", j < i);
			}
			for (s in ORDER.slice(0, i)) ring(s, 1);
			phase = p;
		}
		if (label != null) byId("forge-phase").textContent = label;
	}

	public function count(text:String)
		byId("forge-count").textContent = text;

	public function progress(what:String, loaded:Int, total:Int) {
		ring("fetch", total > 0 ? loaded / total : 0);
		count(Std.string(Math.round(loaded / 104857.6) / 10));
		set("fetch", 'MB · $what');
	}

	static final SHORT = ~/^\/lib\/(src\/packages\/|std\/|hxmc-std\/)?|^\/work\/out\/[^\/]+\/[^\/]+\//;

	public function files(list:Array<Array<Dynamic>>) {
		var t = byId("ticker");
		for (f in list) {
			var path:String = f[0], writing:Bool = f[1];
			if (writing) writes++ else reads++;
			if (!writing && phase == "fetch") set("parse", "parsing · typing");
			if (writing && StringTools.endsWith(path, ".o") && phase != "emit") set("emit", "emitting machine code");
		}
		for (f in list.slice(-3)) {
			var d = document.createDivElement();
			d.textContent = (f[1] ? "→ " : "") + SHORT.replace(f[0], "");
			if (f[1]) d.className = "w";
			t.append(d);
		}
		while (t.children.length > 5) t.firstElementChild.remove();
		count(Std.string(phase == "emit" ? writes : reads));
		ring("parse", reads / expect);
		if (phase == "emit") ring("emit", Math.min(0.95, writes / Math.max(20, expect / 12)));
		sky.kick(0.02 * list.length);
		if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) sparks(Std.int(Math.min(4, list.length)));
	}

	public function done(seconds:Float) {
		set("link", "linked");
		ring("emit", 1);
		ring("link", 1);
		count('${Math.round(seconds * 10) / 10}s');
	}

	function sparks(n:Int) {
		var box = el.getBoundingClientRect();
		var color = window.getComputedStyle(byId("world")).getPropertyValue("--c1");
		if (color == "") color = "#22d3ee";
		for (_ in 0...n) {
			var s = document.createElement("i");
			s.className = "spark";
			var a = Math.random() * Math.PI * 2, r = Math.max(box.width, box.height) * 0.55;
			s.style.setProperty("--x", '${Math.cos(a) * r}px');
			s.style.setProperty("--y", '${Math.sin(a) * r}px');
			s.style.background = color;
			s.style.boxShadow = '0 0 8px $color';
			el.append(s);
			haxe.Timer.delay(() -> s.remove(), 750);
		}
	}
}
