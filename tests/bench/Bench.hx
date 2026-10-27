import haxe.Timer;
import haxe.io.Bytes;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.physics.*;
import helder.scene.Camera;
import helder.scene.World;
import helder.scene.Node as SceneNode;
import helder.scene.math.*;
import helder.text.*;
import helder.ui.*;
import helder.ui.draw.DrawText;

// The engine's workloads timed, with the collector's counters (GcStats):
// text (shaping and layout, the atlas cold and warm), ui (a tree of 10k
// nodes laid out, laid out again after a change, hit tests and pointer
// moves), scene (world matrices of 10k and 100k nodes, a frame's culling
// and draw list) and physics (stacks, chains, a pile, jointed links,
// characters walking). Each workload runs once to warm up, then RUNS
// times, each run timed alone. One line per workload:
//
//   bench <name> <runs> <median ms> <p99 ms> <max ms> <bytes/run> <GCs> <majors> <longest GC ms in a run|-> <check>
//
//   Bench <DejaVuSans.ttf> [workload ...]     (bun run test bench: natively and as wasm32-wasi)
//   Bench <DejaVuSans.ttf> list               (their names)
//   Bench <DejaVuSans.ttf> steady             (physics' worlds in steady state: GC bytes a step)
class Bench {
	static var font:FontFile;
	static var fontBytes:Bytes;

	static function main() {
		var args = Sys.args();
		fontBytes = sys.io.File.getBytes(args.shift());
		font = FontFile.parse(fontBytes);
		var all:Array<Workload> = [
			// text
			{name: "text.layout.latin", runs: 200, run: () -> layoutAll(LATIN)},
			{name: "text.layout.mixed", runs: 200, run: () -> layoutAll(MIXED)},
			{name: "text.atlas.cold", runs: 60, run: atlasCold},
			{name: "text.atlas.warm", runs: 400, setup: atlasWarmSetup, run: atlasWarm},
			// ui
			{name: "ui.layout.10k", runs: 60, setup: uiSetup, run: uiFull},
			{name: "ui.relayout", runs: 300, setup: uiSetup, run: uiChange},
			{name: "ui.hit", runs: 300, setup: uiSetup, run: uiHit},
			// scene
			{name: "scene.world.10k", runs: 200, setup: () -> sceneSetup(100, 100), run: sceneWorld},
			{name: "scene.world.100k", runs: 40, setup: () -> sceneSetup(1000, 100), run: sceneWorld},
			{name: "scene.cull.10k", runs: 200, setup: () -> sceneSetup(100, 100), run: sceneCull},
			// physics
			{name: "physics.stacks", runs: 60, before: stacksSetup, run: () -> steps(30)},
			{name: "physics.chains", runs: 60, before: chainsSetup, run: () -> steps(30)},
			{name: "physics.pile", runs: 40, before: pileSetup, run: () -> steps(30)},
			{name: "physics.joints", runs: 60, before: jointsSetup, run: () -> steps(30)},
			{name: "physics.walkers", runs: 60, before: walkersSetup, run: () -> steps(30)},
		];
		if (args[0] == "list") {
			for (w in all)
				Sys.println(w.name);
			return;
		}
		GcStats.enable();
		if (args[0] == "steady") {
			for (w in all)
				if (StringTools.startsWith(w.name, "physics.")) steady(w);
			return;
		}
		for (w in all)
			if (args.length == 0 || args.contains(w.name)) measure(w);
		GcStats.disable();
	}

	// --- the harness

	static var check = 0.0;

	static function measure(w:Workload) {
		if (w.setup != null) w.setup();
		if (w.before != null) w.before();
		w.run();
		var times = [], bytes = 0.0, gcs = 0, majors = 0, longest = 0.0;
		for (_ in 0...w.runs) {
			if (w.before != null) w.before();
			var b0 = GcStats.bytes(), c0 = GcStats.collections(), m0 = GcStats.majors(), s0 = GcStats.seconds();
			var t0 = Timer.stamp();
			w.run();
			var t = Timer.stamp() - t0;
			var s = GcStats.seconds() - s0;
			bytes += GcStats.bytes() - b0;
			gcs += GcStats.collections() - c0;
			majors += GcStats.majors() - m0;
			if (s > longest) longest = s;
			times.push(t * 1000);
		}
		times.sort(Reflect.compare);
		inline function at(q:Float)
			return times[Std.int(Math.min(times.length - 1, Math.ceil(q * times.length) - 1))];
		var cols = [
			"bench", w.name, Std.string(w.runs), fixed(at(0.5), 3), fixed(at(0.99), 3), fixed(times[times.length - 1], 3), Std.string(Math.round(bytes / w.runs)),
			Std.string(gcs), Std.string(majors), GcStats.TIMED ? fixed(longest * 1000, 3) : "-", Std.string(Math.round(check))
		];
		Sys.println(cols.join(" "));
		check = 0;
	}

	// (a world's bytes a step once it has run 300 steps: each run above
	// starts from a new one, whose buffers grow)
	static function steady(w:Workload) {
		w.before();
		for (_ in 0...300)
			step();
		var b0 = GcStats.bytes(), c0 = GcStats.collections();
		for (_ in 0...300)
			step();
		Sys.println('steady ${w.name} ${Math.round((GcStats.bytes() - b0) / 300)} B/step, ${GcStats.collections() - c0} GCs in 300 steps');
	}

	static function fixed(v:Float, digits:Int):String {
		var m = Math.pow(10, digits);
		return Std.string(Math.round(v * m) / m);
	}

	// --- text: paragraphs of DejaVu Sans at 16 px, 480 px wide

	static final LATIN = [
		"The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs; how vexingly quick daft zebras jump! "
		+ "Sphinx of black quartz, judge my vow. The five boxing wizards jump quickly, and a wizard's job is to vex chumps quickly in fog.",
		"Typography is the art and technique of arranging type to make written language legible, readable and appealing when displayed. "
		+ "The arrangement of type involves selecting typefaces, point sizes, line lengths, line spacing, and letter spacing (tracking), "
		+ "and adjusting the space between pairs of letters (kerning): AV, Wa, To, Ty, fi, fl, ffi.",
		"Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. "
		+ "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. 0123456789",
		"Café, naïve, résumé, façade, coöperate, Übermaß, smørrebrød, Ångström, crème brûlée, jalapeño, piñata — “quoted” ‘text’ … ¡olé!",
	];

	static final MIXED = [
		"English and Ελληνικά: Η γρήγορη καφέ αλεπού πηδάει πάνω από τον τεμπέλη σκύλο. Русский: Съешь же ещё этих мягких французских булок.",
		"Arabic in a Latin line: مرحبا بالعالم، هذا نص عربي للتجربة with numbers 2026 and العربية then Latin again at the end of it.",
		"עברית: שלום עולם, זהו טקסט לבדיקה — mixed with English words and (brackets) and עוד קצת עברית בסוף השורה.",
		"Combining marks: é à ö ñ ç û; Vietnamese: Tiếng Việt có dấu; and ligatures fi fl ffi ffl in office.",
	];

	static function layoutAll(texts:Array<String>) {
		var set = new FontSet(font, [], 16);
		for (t in texts) {
			var l = new TextLayout(t, set, 1.25, 480);
			check += l.lines.length + l.width;
		}
	}

	// every glyph of the paragraphs at three sizes and each quarter-pixel
	// offset into a new atlas (cold), or into one that has them (warm: a frame's lookups)
	static final SIZES = [12.0, 16.0, 24.0];
	static var glyphIds:Array<Int>;
	static var warmAtlas:GlyphAtlas;

	static function glyphsOf():Array<Int> {
		if (glyphIds != null) return glyphIds;
		var set = new FontSet(font, [], 16), seen = new Map<Int, Bool>();
		glyphIds = [];
		for (t in LATIN.concat(MIXED))
			for (l in new TextLayout(t, set, 1.25, 480).lines)
				for (g in l.glyphs)
					if (!seen.exists(g.id)) {
						seen.set(g.id, true);
						glyphIds.push(g.id);
					}
		return glyphIds;
	}

	static function atlasCold() {
		var ids = glyphsOf(), atlas = new GlyphAtlas(1024, 1024);
		for (size in SIZES)
			for (id in ids)
				for (sub in 0...GlyphAtlas.SUBPIXELS)
					check += atlas.get(font, id, size, sub).w;
	}

	static function atlasWarmSetup() {
		warmAtlas = new GlyphAtlas(1024, 1024);
		atlasCold();
		glyphsOf();
		for (size in SIZES)
			for (id in glyphIds)
				for (sub in 0...GlyphAtlas.SUBPIXELS)
					warmAtlas.get(font, id, size, sub);
	}

	// (a frame drawing 3000 glyphs: runs of 50 in one size)
	static function atlasWarm() {
		var ids = glyphIds, n = ids.length;
		for (k in 0...3000) {
			var size = SIZES[Std.int(k / 50) % SIZES.length];
			check += warmAtlas.get(font, ids[(k * 7) % n], size, k & 3).x;
		}
	}

	// --- ui: 100 sections (rows that wrap) of 10 cards (a title, a row of
	// six boxes that grow, a paragraph, a button): 10,101 nodes, 2,000 texts

	static var ui:Ui;
	static var changed:Node;
	static var wide = false;

	static function uiSetup() {
		var fonts = new SystemFonts();
		fonts.add(fontBytes);
		ui = new Ui(new DrawText(fonts), 1200, 800);
		ui.root.style.fontFamily = "DejaVu Sans";
		ui.root.style.fontSize = 13;
		var page = new Node("page");
		page.style.overflow = Scroll;
		page.style.grow = 1;
		page.style.minHeight = 0;
		page.style.padding = 12;
		page.style.rowGap = 12;
		ui.root.append(page);
		for (s in 0...100) {
			var section = new Node("section");
			section.style.direction = Row;
			section.style.wrap = true;
			section.style.columnGap = 8;
			section.style.rowGap = 8;
			page.append(section);
			for (c in 0...10) {
				var card = new Node("card");
				card.style.grow = 1;
				card.style.basis = 200;
				card.style.padding = 8;
				card.style.rowGap = 6;
				card.style.borderWidth = 1;
				section.append(card);
				card.append(new TextNode('Card ${s * 10 + c}'));
				var row = new Node("row");
				row.style.direction = Row;
				row.style.columnGap = 4;
				card.append(row);
				for (b in 0...6) {
					var box = new Node("box");
					box.style.grow = b % 3;
					box.style.width = 10 + b * 3;
					box.style.height = 12 + (b & 1) * 6;
					row.append(box);
				}
				card.append(new TextNode(LATIN[(s + c) % LATIN.length].substr(0, 60 + (c * 13) % 90)));
				var button = new Node("button");
				button.style.alignSelf = End;
				button.style.width = 60;
				button.style.height = 20;
				button.focusable = true;
				button.onClick = e -> check++;
				card.append(button);
			}
		}
		changed = page.children[50].children[5].children[1].children[0];
		ui.update();
	}

	// (the window's width changed: every box and text again)
	static function uiFull() {
		wide = !wide;
		ui.resize(wide ? 1180 : 1200, 800);
		ui.update();
		check += ui.root.children[0].contentHeight;
	}

	// (one box's width changed)
	static function uiChange() {
		wide = !wide;
		changed.style.width = wide ? 30 : 10;
		ui.update();
		check += changed.width;
	}

	// (1000 hit tests over the window, then 100 pointer moves)
	static function uiHit() {
		for (k in 0...1000) {
			var n = ui.root.hitTest((k * 37) % 1200, (k * 53) % 800);
			if (n != null) check++;
		}
		for (k in 0...100)
			ui.pointerMove((k * 97) % 1200, (k * 31) % 800);
	}

	// --- scene: tops under the root, each with a chain and a fan below it;
	// each frame the tops move, then every node's world matrix is asked for

	static var world:World;
	static var tops:Array<SceneNode>;
	static var nodes:Array<SceneNode>;
	static var bounds:Aabb;
	static var viewProj:Mat4;
	static var frame = 0;
	static final drawList:Array<Int> = [];

	static function sceneSetup(n:Int, each:Int) {
		if (world != null) world.dispose();
		world = new World("bench");
		tops = [];
		nodes = [];
		for (t in 0...n) {
			var top = world.node("top");
			top.position = new Vec3((t % 32) * 3 - 48, 0, -Std.int(t / 32) * 3);
			tops.push(top);
			nodes.push(top);
			var parent = top;
			for (k in 1...each) {
				// (half a chain, half a fan off its end)
				var c = world.node("n", parent);
				c.position = new Vec3(0.1, 0.2, 0);
				c.rotation = Quat.axisAngle(new Vec3(0, 1, 0), 0.05 * k);
				if (k < each / 2) parent = c;
				nodes.push(c);
			}
		}
		bounds = new Aabb(new Vec3(-0.5, -0.5, -0.5), new Vec3(0.5, 0.5, 0.5));
		var eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(1.0, 0.1, 200));
		eye.position = new Vec3(0, 20, 30);
		eye.lookAt(new Vec3(0, 0, -20));
		viewProj = camera.viewProjection(16 / 9);
	}

	static function sceneWorld() {
		frame++;
		for (t in tops)
			t.rotation = Quat.axisAngle(new Vec3(0, 1, 0), frame * 0.01);
		for (n in nodes)
			check += n.worldMatrix().c3.x;
	}

	// (the renderer's extract: each node's box in clip space against the
	// frustum, a draw for each one inside, the list sorted by key)
	static function sceneCull() {
		sceneWorld();
		drawList.resize(0);
		for (k in 0...nodes.length) {
			var mvp = viewProj * nodes[k].worldMatrix();
			if (visible(mvp, bounds)) drawList.push(k);
		}
		check += drawList.length;
	}

	static function visible(mvp:Mat4, b:Aabb):Bool {
		var o0 = 0, o1 = 0, o2 = 0, o3 = 0, o4 = 0, o5 = 0;
		for (k in 0...8) {
			var c = mvp * new Vec4((k & 1) == 0 ? b.min.x : b.max.x, (k & 2) == 0 ? b.min.y : b.max.y, (k & 4) == 0 ? b.min.z : b.max.z, 1);
			if (c.x < -c.w) o0++;
			if (c.x > c.w) o1++;
			if (c.y < -c.w) o2++;
			if (c.y > c.w) o3++;
			if (c.z < 0) o4++;
			if (c.z > c.w) o5++;
		}
		return o0 < 8 && o1 < 8 && o2 < 8 && o3 < 8 && o4 < 8 && o5 < 8;
	}

	// --- physics: 10 stacks of 20 crates on a floor (201 bodies); 20
	// chains of 15 balls on distance joints (301 bodies); a pile of 294
	// balls, crates and capsules in a pen of planes (settled 45 steps
	// first); 16 chains of 12 links on ball joints, each hung from a hinge,
	// swinging down onto the floor (192 bodies); 16 characters walking
	// circles among 64 crates and 4 steps, jumping now and then. 30 steps a
	// run, from the start each run

	static var physics:PhysicsWorld;
	static var walkers:Array<Character> = [];
	static var tick = 0;

	static function physicsWorld() {
		physics = new PhysicsWorld();
		physics.add(new Body(Plane(new Vec3(0, 1, 0), 0), new Vec3(0, 0, 0), 0));
		walkers = [];
		tick = 0;
	}

	static function stacksSetup() {
		physicsWorld();
		for (s in 0...10)
			for (k in 0...20)
				physics.add(new Body(Box(new Vec3(0.3, 0.3, 0.3)), new Vec3((s % 5) * 1.5 + 0.02 * k, 0.3 + 0.61 * k, Std.int(s / 5) * 1.5)));
	}

	static function chainsSetup() {
		physicsWorld();
		for (c in 0...20) {
			var x = (c % 10) * 0.8 - 4, z = Std.int(c / 10) * 0.8, prev:Null<Body> = null;
			for (k in 0...15) {
				var b = physics.add(new Body(Sphere(0.12), new Vec3(x + 0.05 * k, 5 - k * 0.3, z), 0.5));
				physics.join(prev == null ? Joint.distanceOf(b, new Vec3(0, 0, 0), null, new Vec3(x, 5.3, z)) : Joint.distanceOf(b, new Vec3(0, 0, 0), prev,
					new Vec3(0, 0, 0)));
				prev = b;
			}
		}
	}

	static function pileSetup() {
		physicsWorld();
		for (n in [new Vec3(1, 0, 0), new Vec3(-1, 0, 0), new Vec3(0, 0, 1), new Vec3(0, 0, -1)])
			physics.add(new Body(Plane(n, -1.8), new Vec3(0, 0, 0), 0));
		for (l in 0...6)
			for (k in 0...49) {
				var p = new Vec3((k % 7) * 0.5 - 1.5 + 0.03 * l, 0.3 + 0.55 * l, Std.int(k / 7) * 0.5 - 1.5 - 0.02 * l);
				var b = physics.add(new Body(switch (k + l) % 3 {
					case 0: Sphere(0.2);
					case 1: Box(new Vec3(0.2, 0.15, 0.18));
					case _: Capsule(0.12, 0.12);
				}, p));
				b.orientation = Quat.axisAngle(new Vec3(1, 0.3 * l, 0.1 * k), 0.2 * k);
			}
		for (_ in 0...45)
			physics.step(1 / 60);
	}

	static function jointsSetup() {
		physicsWorld();
		for (c in 0...16) {
			var x0 = (c % 4) * 1.2 - 1.8, z = Std.int(c / 4) * 1.2 - 1.8, prev:Null<Body> = null;
			for (k in 0...12) {
				var b = physics.add(new Body(Box(new Vec3(0.1, 0.06, 0.08)), new Vec3(x0 + 0.13 + 0.26 * k, 2.2, z), 0.4));
				physics.join(prev == null ? Joint.hinge(b, new Vec3(-0.13, 0, 0), new Vec3(0, 0, 1), null, new Vec3(x0, 2.2, z),
					new Vec3(0, 0, 1)) : Joint.ball(b, new Vec3(-0.13, 0, 0), prev, new Vec3(0.13, 0, 0)));
				prev = b;
			}
		}
	}

	static function walkersSetup() {
		physicsWorld();
		for (b in [[4, 0.5, -3, 2, 0.5, 1.5], [1.6, 0.15, -3, 0.4, 0.15, 1], [-4, 0.25, 3, 1, 0.25, 1], [0, 0.4, 5, 1.5, 0.4, 0.5]])
			physics.add(new Body(Box(new Vec3(b[3], b[4], b[5])), new Vec3(b[0], b[1], b[2]), 0));
		for (k in 0...64) {
			var b = physics.add(new Body(Box(new Vec3(0.3, 0.3, 0.3)), new Vec3((k % 8) * 1.1 - 4, 0.3 + 0.6 * Std.int(k / 32), Std.int(k / 8 % 4) * 1.6 - 2.5), 8));
			b.friction = 0.6;
		}
		for (k in 0...16)
			walkers.push(new Character(physics, new Vec3((k % 4) * 2.2 - 3.3 + 0.5, 0.95, Std.int(k / 4) * 2.2 - 3.3 + 0.8)));
		for (_ in 0...10)
			step();
	}

	static function step() {
		tick++;
		for (k in 0...walkers.length) {
			var a = tick * 0.02 + k;
			walkers[k].update(1 / 60, new Vec3(Math.cos(a), 0, Math.sin(a)), (tick + k * 7) % 90 == 0);
		}
		physics.step(1 / 60);
	}

	static function steps(n:Int) {
		for (_ in 0...n)
			step();
		check += physics.contacts;
	}
}

typedef Workload = {
	name:String,
	runs:Int,
	run:() -> Void,
	// (once, before warming up; before each run, untimed)
	?setup:() -> Void,
	?before:() -> Void,
}
