import Compiler;
import js.Browser.document;
import js.Browser.window;
import js.html.Element;

private typedef Planet = {e:Example, el:Element, ring:Int, i:Int, n:Int};

// The universe: a planet per example on its package's orbit around the
// compiler (the core), the orbits turning, slowing to a stop under the
// pointer; on narrow screens a trail of planets to scroll, by package.
class Universe {
	public static final PACKAGES = [
		"gfx" => "a portable GPU API, shaders in Haxe",
		"physics" => "a small rigid-body core",
		"3d" => "glTF scenes, PBR, animation",
		"ui" => "a UI toolkit drawn on the GPU",
		"theme" => "shadcn/ui looks for ui",
		"os" => "windows, input, audio",
	];
	// the orbits, inner to outer
	public static final RINGS = ["os", "theme", "physics", "3d", "ui", "gfx"];
	public static final COLORS = ["gfx" => "#22d3ee", "physics" => "#fb923c", "3d" => "#a78bfa", "ui" => "#4ade80", "theme" => "#f472b6", "os" => "#facc15"];

	public var onEnter:Example->Void = _ -> {};
	public var onHover:Void->Void = () -> {};
	public var layout(default, null) = "orbit";

	final examples:Array<Example>;
	final sky:Sky;
	final planets = new Map<String, Planet>();
	final reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
	var spin = 0.0;
	var spinSpeed = 1.0;
	var hovered:Null<Example>;

	public function new(examples:Array<Example>, sky:Sky) {
		this.examples = examples;
		this.sky = sky;
		var sys = document.getElementById("system");
		var rings = RINGS.copy();
		rings.reverse();
		for (pkg in rings) {
			var list = examples.filter(e -> e.pkg == pkg);
			if (list.length == 0) continue;
			var head = document.createDivElement();
			head.className = 'system-head pkg-$pkg';
			head.innerHTML = '<h3>$pkg</h3><p>${PACKAGES[pkg]}</p>';
			sys.append(head);
			for (i in 0...list.length) {
				var e = list[i];
				var b = document.createButtonElement();
				b.type = "button";
				b.className = 'planet pkg-${e.pkg}';
				b.dataset.id = e.id;
				b.setAttribute("aria-label", '${e.title}: ${e.summary}');
				var size = 46 + Math.min(30, (e.summary.length % 7) * 4 + (e.pkg == "ui" || e.pkg == "3d" ? 10 : 0));
				b.style.setProperty("--size", '${size}px');
				if (e.pkg == "3d" || e.id == "gfx-instances" || e.id == "physics-walker") b.style.setProperty("--ring", "1");
				b.innerHTML = '<span class="orb"></span><span class="text"><span class="name"></span><span class="meta"></span></span>';
				b.querySelector(".name").textContent = e.title;
				b.querySelector(".meta").textContent = e.summary;
				if (Store.progress.visited.contains(e.id)) b.classList.add("visited");
				b.onclick = () -> onEnter(e);
				b.addEventListener("pointerenter", () -> hover(e, b));
				b.addEventListener("pointerleave", () -> hover(null, null));
				b.addEventListener("focus", () -> hover(e, b));
				b.addEventListener("blur", () -> hover(null, null));
				sys.append(b);
				planets.set(e.id, {e: e, el: b, ring: RINGS.indexOf(pkg), i: i, n: list.length});
			}
		}
		var card = document.createDivElement();
		card.className = "card";
		card.id = "card";
		sys.append(card);
		hud();
		relayout();
		window.addEventListener("resize", relayout);
		window.requestAnimationFrame(place);
	}

	public function visited(id:String)
		planets[id]?.el.classList.add("visited");

	public function focus(id:String)
		if (planets.exists(id)) (cast planets[id].el).focus({preventScroll: true});

	public function hud() {
		var v = Store.progress.visited.filter(id -> Lambda.exists(examples, e -> e.id == id)).length;
		var n = Store.progress.native.length;
		document.getElementById("progress-hud").innerHTML = 'worlds <b>$v/${examples.length}</b>${n > 0 ? ' · native <b>$n</b>' : ""}';
	}

	function hover(e:Null<Example>, el:Null<Element>) {
		hovered = e;
		var card = document.getElementById("card");
		if (e == null || layout != "orbit") {
			card.classList.remove("on");
			return;
		}
		card.innerHTML = '<h3></h3><p></p><div class="go">${Store.progress.visited.contains(e.id) ? "visited · enter again" : "enter world"} ▸</div>';
		card.querySelector("h3").textContent = e.title;
		card.querySelector("p").textContent = e.summary;
		var r = el.getBoundingClientRect();
		var x = Math.min(window.innerWidth - card.offsetWidth - 12, Math.max(12, r.left + r.width / 2 - 150));
		var below = r.bottom + 10 + card.offsetHeight < window.innerHeight;
		card.style.left = '${x}px';
		card.style.top = '${below ? r.bottom + 10 : r.top - card.offsetHeight - 10}px';
		card.classList.add("on");
		onHover();
	}

	function relayout() {
		var narrow = window.innerWidth < 760 || window.innerHeight < 560;
		layout = narrow ? "trail" : "orbit";
		document.getElementById("universe").classList.toggle("trail", narrow);
		var core = document.getElementById("core"), sys = document.getElementById("system");
		if (narrow) {
			sky.orbits = [];
			for (p in planets) {
				p.el.style.removeProperty("transform");
				p.el.style.removeProperty("z-index");
				p.el.style.removeProperty("filter");
			}
			core.style.removeProperty("left");
			core.style.removeProperty("top");
			sys.before(core);
		} else sys.after(core);
	}

	// the orbits: ellipses around the core, each package's planets spread on its own
	function place(_:Float) {
		window.requestAnimationFrame(place);
		if (document.getElementById("universe").hidden || layout != "orbit") return;
		var w = window.innerWidth, h = window.innerHeight;
		var cx = w * (w > 1100 ? 0.58 : 0.5), cy = h * (w > 1100 ? 0.52 : 0.6);
		var maxRx = Math.min(w * (w > 1100 ? 0.4 : 0.46), h);
		var minRx = 110;
		spinSpeed += ((hovered != null ? 0 : 1) - spinSpeed) * 0.08;
		if (!reduced.matches) spin += 0.0009 * spinSpeed;
		var orbits = [];
		for (p in planets) {
			var k = p.ring / (RINGS.length - 1);
			var rx = minRx + (maxRx - minRx) * k, ry = rx * 0.42;
			var dir = p.ring % 2 == 1 ? 1 : -1;
			var a = spin * dir * (1.4 - k * 0.6) + p.i / p.n * Math.PI * 2 + p.ring * 0.9;
			var depth = Math.sin(a);
			var x = cx + rx * Math.cos(a), y = cy + ry * depth;
			var s = 0.72 + 0.38 * (depth + 1) / 2;
			p.el.style.transform = 'translate(${x}px, ${y}px) translate(-50%, -30%) scale($s)';
			p.el.style.zIndex = depth > 0 ? "3" : "1";
			p.el.style.filter = depth < -0.3 ? 'brightness(${0.55 + 0.45 * (1 + depth)})' : "";
			if (p.i == 0) orbits.push({cx: cx, cy: cy, rx: rx, ry: ry, color: COLORS[p.e.pkg]});
		}
		sky.orbits = orbits;
		var core = document.getElementById("core");
		core.style.left = '${cx}px';
		core.style.top = '${cy}px';
	}
}
