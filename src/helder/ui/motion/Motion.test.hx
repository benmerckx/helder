package helder.ui.motion;

import helder.test.Test;
import helder.ui.*;

// Motion as property tracks (helder.ui.motion): the spring's closed form
// against the equation it solves in each regime, position and velocity
// kept exactly through a retarget, tweens and decay; layout moving edge by
// edge (a stationary edge still, children riding their parent, lead and
// trail, riding the trailing edge), presence (nothing on the first frame,
// entering, leaving drawn until it settles, revived from where it is),
// colours through premultiplied OKLab and a text colour leading its
// background, matched elements flying, reduced motion, instant subtrees.
function tests() {
	describe("Track", () -> {
		test("a spring's closed form against its equation, every regime", () -> {
			for (bounce in [0.0, 0.3, 0.6, -0.5]) {
				var c = Curve.spring(0.4, bounce), k = Math.pow(c.omega(), 2), d = 2 * c.zeta() * c.omega();
				var tr = new Track(0);
				tr.animate(0, 100, c, 250);
				// (the same spring stepped by RK4 in 0.1 ms steps)
				var x = 0.0, v = 250.0, h = 1e-4, t = 0.0, worst = 0.0, worstV = 0.0;
				inline function acc(x:Float, v:Float):Float
					return -k * (x - 100) - d * v;
				for (sample in [0.02, 0.05, 0.1, 0.2, 0.35, 0.6]) {
					while (t < sample - 1e-9) {
						var a1 = acc(x, v), b1 = v;
						var a2 = acc(x + b1 * h / 2, v + a1 * h / 2), b2 = v + a1 * h / 2;
						var a3 = acc(x + b2 * h / 2, v + a2 * h / 2), b3 = v + a2 * h / 2;
						var a4 = acc(x + b3 * h, v + a3 * h), b4 = v + a3 * h;
						x += h / 6 * (b1 + 2 * b2 + 2 * b3 + b4);
						v += h / 6 * (a1 + 2 * a2 + 2 * a3 + a4);
						t += h;
					}
					tr.sample(sample);
					worst = Math.max(worst, Math.abs(tr.value - x));
					worstV = Math.max(worstV, Math.abs(tr.velocity - v));
				}
				assert(worst < 1e-6, 'bounce $bounce: position within 1e-6 of the integrated spring (off by $worst)');
				assert(worstV < 1e-4, 'bounce $bounce: velocity within 1e-4 (off by $worstV)');
				tr.sample(30);
				equals(tr.value, 100.0, 'bounce $bounce: settled on its target');
				equals(tr.moving(), false, 'bounce $bounce: at rest');
			}
		});
		test("retargeting keeps position and velocity exactly", () -> {
			for (c in [Curve.spring(0.3), Curve.spring(0.3, 0.4), Curve.spring(0.5, -0.3), Curve.tween(0.4)]) {
				var tr = new Track(0);
				tr.animate(0, 100, c);
				var t = 0.0;
				for (k in 0...12) {
					t += 0.037;
					tr.sample(t);
					var x = tr.value, v = tr.velocity;
					tr.animate(t, k % 2 == 0 ? -40 + k * 13 : 200 - k * 7, c);
					tr.sample(t);
					assert(Math.abs(tr.value - x) < 1e-9, '$c: the position kept at a retarget (${tr.value} for $x)');
					assert(Math.abs(tr.velocity - v) < 1e-6 * Math.max(1, Math.abs(v)), '$c: the velocity kept at a retarget (${tr.velocity} for $v)');
					// (and moving on from there: the next millisecond as its velocity says)
					tr.sample(t + 1e-4);
					assert(Math.abs(tr.value - (x + v * 1e-4)) < 0.05, '$c: continuous after the retarget');
				}
			}
		});
		test("a spring's duration: SwiftUI's", () -> {
			// (critically damped from rest: within 1% of the way at about 1.06 durations, as SwiftUI's)
			var tr = new Track(0);
			tr.animate(0, 1, Curve.spring(0.5));
			tr.sample(0.5);
			assert(tr.value > 0.95 && tr.value < 0.99, 'at its duration: ${tr.value}');
			tr.sample(0.25);
			assert(tr.value > 0.6 && tr.value < 0.85, 'at half of it: ${tr.value}');
			// (a bounce overshoots)
			var b = new Track(0), most = 0.0;
			b.animate(0, 1, Curve.spring(0.5, 0.4));
			for (i in 1...100) {
				b.sample(i * 0.01);
				most = Math.max(most, b.value);
			}
			// (ζ = 0.6: e^(-ζπ / √(1 - ζ²)), 9.5% past it)
			assert(Math.abs(most - 1.0948) < 0.002, 'a bounce of 0.4 overshoots by 9.5%: $most');
		});
		test("a tween's ease and the velocity it carries in", () -> {
			var tr = new Track(0);
			tr.animate(0, 10, Curve.tween(0.2));
			tr.sample(0.1);
			assert(Math.abs(tr.value - 5) < 1e-6, 'ease-in-out at half its time: half way (${tr.value})');
			tr.sample(0.2);
			equals(tr.value, 10.0, "at its end");
			equals(tr.moving(), false, "done");
		});
		test("decay: a fling coming to rest where its velocity takes it", () -> {
			var tr = new Track(50, 0.01);
			tr.release(0, 400, 4);
			equals(tr.target, 150.0, "its target: x + v / rate");
			tr.sample(0);
			assert(Math.abs(tr.velocity - 400) < 1e-9, "its velocity at the release");
			tr.sample(0.25);
			assert(Math.abs(tr.value - (150 - 100 * Math.exp(-1))) < 1e-9, 'exponential: ${tr.value}');
			tr.sample(60);
			equals(tr.value, 150.0, "at rest");
		});
	});

	describe("colours", () -> {
		test("through premultiplied OKLab", () -> {
			var red:Color = 0xFFFF0000, blue:Color = 0xFF0000FF;
			var mid = ColorTrack.between(red, blue, 0.5);
			// (OKLab's midpoint of red and blue is a violet brighter than sRGB's #800080)
			assert(mid.r > 128 && mid.b > 128, 'red to blue: ${mid.toHex()}');
			// (transparent to red: red fading in, not through black)
			var fade = ColorTrack.between(Color.TRANSPARENT, red, 0.5);
			assert(fade.r == 255 && fade.g == 0 && fade.b == 0 && Math.abs(fade.a - 128) <= 1, 'transparent to red: ${fade.toHex()}');
			// (the ends are the colours)
			equals(ColorTrack.between(red, blue, 0), red);
			equals(ColorTrack.between(red, blue, 1), blue);
			var c = new ColorTrack(red);
			c.animate(0, blue, Curve.spring(0.3));
			c.sample(0.15);
			var v = c.value();
			assert(v != red && v != blue, "moving between them");
			c.sample(10);
			equals(c.value(), blue, "settled");
		});
	});

	describe("layout", () -> {
		test("edges move from where they are drawn; a stationary edge never moves", () -> {
			var s = scene();
			s.a.style.height = 60;
			frame(s, 0.016);
			var b0 = bounds(s.b), a0 = bounds(s.a), list0 = bounds(s.list);
			equals(b0.y, 40.0, "b as it was drawn the frame its layout moved");
			equals(list0.height, 60.0, "the list too");
			var lastB = b0.y, lastBottom = list0.y + list0.height;
			for (i in 2...40) {
				frame(s, i * 0.016);
				var a = bounds(s.a), b = bounds(s.b), l = bounds(s.list);
				equals(a.y, a0.y, "a's top: stationary");
				equals(a.x, a0.x, "a's left: stationary");
				equals(l.y, list0.y, "the list's top: stationary");
				assert(b.y >= lastB - 1e-9, "b moving down, no jump back");
				assert(b.y - lastB < 12, 'b moving down within what the spring allows a frame (${b.y - lastB})');
				assert(l.y + l.height >= lastBottom - 1e-9, "the list's bottom moving down");
				lastB = b.y;
				lastBottom = l.y + l.height;
			}
			finish(s);
			equals(bounds(s.b).y, 80.0, "b where it is laid out");
			equals(bounds(s.list).height, 100.0, "the list as tall as it is laid out");
		});
		test("children ride their parent", () -> {
			var s = scene();
			s.list.style.marginLeft = 100;
			frame(s, 0.016);
			for (i in 2...20) {
				frame(s, i * 0.016);
				var l = bounds(s.list), a = bounds(s.a);
				equals(a.x - l.x, 0.0, "a rides the list's left edge");
				assert(l.x < 100, "the list on its way");
			}
			finish(s);
			equals(bounds(s.a).x, 100.0, "there");
		});
		test("lead and trail: the edge in the direction of travel leads", () -> {
			var s = scene();
			s.list.motion = MotionSpec.of({curve: "default", lead: "lead", trail: "calm"});
			s.a.style.marginLeft = 100;
			frame(s, 0.016);
			frame(s, 0.1);
			var a = bounds(s.a);
			assert(a.width > 100.5, 'stretched as it travels right: ${a.width}');
			finish(s);
			equals(bounds(s.a).width, 100.0, "its own width at rest");
		});
		test("riding the trailing edge", () -> {
			var s = scene();
			s.b.style.position = Absolute;
			s.b.style.right = 0;
			s.b.style.width = 20;
			s.b.ride = 3;
			finish(s);
			base = Clock.now;
			s.list.style.width = 300;
			frame(s, 0.016);
			assert(bounds(s.list).width == 400, "the list's width on its way");
			for (i in 3...20) {
				frame(s, i * 0.016);
				var l = bounds(s.list), b = bounds(s.b);
				assert(Math.abs(l.x + l.width - (b.x + b.width)) < 1e-6, 'b kept against the list\'s right edge (${l.x + l.width} and ${b.x + b.width})');
			}
			finish(s);
		});
		test("instant: a subtree's changes without motion", () -> {
			var s = scene();
			s.list.instant = true;
			s.a.style.height = 60;
			frame(s, 0.016);
			equals(bounds(s.b).y, 80.0, "b there at once");
		});
		test("reduced motion: travel and size snap, opacity fades over 0.15 s", () -> {
			var s = scene();
			Clock.reducedMotion = true;
			try {
				s.a.style.height = 60;
				s.b.style.opacity = 0;
				frame(s, 0.016);
				equals(bounds(s.b).y, 80.0, "b at its place at once");
				frame(s, 0.016 + 0.075);
				assert(Math.abs(s.b.style.opacity - 0.5) < 0.01, 'half faded half way: ${s.b.style.opacity}');
				frame(s, 0.016 + 0.16);
				equals(s.b.style.opacity, 0.0, "faded");
			} catch (e:Dynamic) {
				Clock.reducedMotion = false;
				throw e;
			}
			Clock.reducedMotion = false;
		});
	});

	describe("presence", () -> {
		test("nothing animates on the first frame", () -> {
			var ui = new Ui(null, 300, 300), c = new Rec();
			var row = box(100, 20);
			row.style.transition = Transition.parse("fade scale");
			var list = new Node();
			list.motion = MotionSpec.DEFAULT;
			list.append(row);
			ui.root.append(list);
			tick(ui, c, now());
			equals(row.present == null || row.present.presence == null, true, "no presence on the first frame");
			equals(c.drawn(row), 1.0, "drawn at full opacity");
		});
		test("entering, leaving drawn until its exit settles, revived from where it is", () -> {
			var ui = new Ui(null, 300, 300), c = new Rec();
			var list = new Node();
			list.motion = MotionSpec.DEFAULT;
			ui.root.append(list);
			var keep = box(100, 20);
			list.append(keep);
			var t = now();
			tick(ui, c, t);
			var row = box(100, 20);
			row.style.background = 0xFF3366FF;
			row.style.transition = Transition.parse("fade slide-up");
			list.append(row);
			tick(ui, c, t += 0.016);
			// (a change between frames moves from the next frame on: absent, not drawn, in the first)
			equals(c.drawn(row), -1.0, "entering from absent");
			tick(ui, c, t += 0.016);
			var op = c.drawn(row);
			assert(op > 0 && op < 0.5, 'fading in: $op');
			var last = op;
			for (_ in 0...10) {
				tick(ui, c, t += 0.016);
				var o = c.drawn(row);
				assert(o >= last - 1e-9, "fading in");
				last = o;
			}
			ui.update();
			Clock.finish();
			tick(ui, c, t = Clock.now + 0.016);
			equals(c.drawn(row), 1.0, "present");
			// (removed: out of the tree and its layout, drawn where it was)
			list.remove(row);
			equals(row.parent, null, "out of the tree");
			equals(row.leftFrom, list, "kept by its old parent");
			tick(ui, c, t += 0.016);
			equals(c.drawn(row), 1.0, "drawn where it was");
			tick(ui, c, t += 0.016);
			var o1 = c.drawn(row);
			assert(o1 > 0.5 && o1 < 1, 'drawn, fading out: $o1');
			tick(ui, c, t += 0.05);
			var o2 = c.drawn(row);
			assert(o2 < o1, 'fading: $o2');
			// (back mid-exit: from where it is, no jump)
			list.append(row);
			tick(ui, c, t += 0.001);
			var o3 = c.drawn(row);
			assert(Math.abs(o3 - o2) < 0.05, 'revived from where it was: $o3 after $o2');
			equals(row.leftFrom, null, "back in the tree");
			ui.update();
			Clock.finish();
			tick(ui, c, Clock.now + 0.016);
			equals(c.drawn(row), 1.0, "present again");
			// (removed for good: gone once its exit settles)
			list.remove(row);
			t = Clock.now;
			for (i in 0...60)
				tick(ui, c, t += 0.016);
			equals(row.leftFrom, null, "its exit settled");
			equals(c.drawn(row), -1.0, "no longer drawn");
			equals(list.exits.length, 0, "no ghost left");
		});
	});

	describe("properties", () -> {
		test("a text colour leads its background", () -> {
			var ui = new Ui(null, 300, 300), c = new Rec();
			var card = box(100, 40);
			card.motion = MotionSpec.of("calm");
			card.style.background = 0xFFFFFFFF;
			card.style.color = 0xFF000000;
			ui.root.append(card);
			var t = now();
			tick(ui, c, t);
			card.style.background = 0xFF000000;
			card.style.color = 0xFFFFFFFF;
			equals(card.style.target("background"), (0xFF000000 : Color), "the background's target");
			tick(ui, c, t += 0.016);
			tick(ui, c, t += 0.1);
			var fg = card.textColor(), bg = card.style.background;
			var fgWay = fg.r / 255, bgWay = 1 - bg.r / 255;
			assert(fgWay > bgWay + 0.1, 'the text colour ahead of the background: ${fg.toHex()} on ${bg.toHex()}');
			assert(bgWay > 0.05 && bgWay < 0.95, 'the background on its way: ${bg.toHex()}');
			ui.update();
			Clock.finish();
			equals(card.textColor(), (0xFFFFFFFF : Color), "the text colour settled");
			equals(card.style.background, (0xFF000000 : Color), "the background settled");
		});
		test("opacity and radius springs; transform as lanes", () -> {
			var ui = new Ui(null, 300, 300), c = new Rec();
			var card = box(100, 40);
			card.motion = MotionSpec.DEFAULT;
			ui.root.append(card);
			var t = now();
			tick(ui, c, t);
			card.style.opacity = 0.2;
			card.style.radius = 20;
			card.style.transform = Transform.translate(50, 0);
			tick(ui, c, t += 0.016);
			tick(ui, c, t += 0.1);
			assert(card.style.opacity < 1 && card.style.opacity > 0.2, 'opacity moving: ${card.style.opacity}');
			assert(card.style.radius > 0 && card.style.radius < 20, 'radius moving: ${card.style.radius}');
			var b = card.windowBounds();
			assert(b.x > 0 && b.x < 50, 'translated part of the way: ${b.x}');
			ui.update();
			Clock.finish();
			equals(card.style.opacity, 0.2);
			equals(card.style.radius, 20.0);
			equals(card.windowBounds().x, 50.0);
		});
	});

	describe("matched", () -> {
		test("one leaves, the other flies from where it was seen", () -> {
			var ui = new Ui(null, 400, 400), c = new Rec();
			var stage = new Node();
			stage.motion = MotionSpec.DEFAULT;
			stage.style.width = 400;
			stage.style.height = 400;
			ui.root.append(stage);
			var grid = new Node();
			grid.style.padding = 20;
			stage.append(grid);
			var small = box(80, 60);
			small.matched = "tile";
			small.style.radius = 12;
			grid.append(small);
			var t = now();
			tick(ui, c, t);
			equals(bounds(small).x, 20.0);
			stage.remove(grid);
			var big = new Node();
			big.matched = "tile";
			big.style.background = 0xFF3366FF;
			big.style.width = 400;
			big.style.height = 400;
			stage.append(big);
			tick(ui, c, t += 0.016);
			var b = bounds(big);
			assert(Math.abs(b.x - 20) < 6 && Math.abs(b.width - 80) < 30, 'from where the small one was: $b');
			assert(c.drawn(big) > 0, "drawn");
			equals(big.style.radius, 12.0, "its radius the small one's at first");
			for (i in 0...10)
				tick(ui, c, t += 0.016);
			var m = bounds(big);
			assert(m.x < b.x && m.width > b.width, 'flying to its place: $m');
			ui.update();
			Clock.finish();
			tick(ui, c, Clock.now + 0.016);
			var e = bounds(big);
			equals([e.x, e.y, e.width, e.height], [0.0, 0.0, 400.0, 400.0], "landed");
			equals(big.style.radius, 0.0, "its own radius");
		});
	});
}

// (a column list of two boxes, a and b, under motion, drawn once)
private function scene():{ui:Ui, c:Rec, list:Node, a:Node, b:Node} {
	var ui = new Ui(null, 400, 400), c = new Rec();
	var list = new Node("list");
	list.motion = MotionSpec.DEFAULT;
	list.style.alignItems = Start;
	var a = box(100, 20), b = box(100, 20);
	b.style.marginTop = 20;
	list.append(a);
	list.append(b);
	ui.root.append(list);
	var s = {ui: ui, c: c, list: list, a: a, b: b};
	base = now();
	frame(s, 0);
	return s;
}

private var base = 0.0;

private function frame(s:{ui:Ui, c:Rec}, t:Float)
	tick(s.ui, s.c, base + t);

private function finish(s:{ui:Ui, c:Rec}) {
	s.ui.update();
	Clock.finish();
	tick(s.ui, s.c, Clock.now + 0.016);
}

private function tick(ui:Ui, c:Rec, t:Float) {
	Clock.tick(t);
	ui.update();
	c.reset();
	ui.paint(c);
}

private function now():Float
	return Clock.now + 1;

private function bounds(n:Node):{x:Float, y:Float, width:Float, height:Float}
	return n.windowBounds();

private function box(w:Float, h:Float):Node {
	var n = new Node();
	n.style.width = w;
	n.style.height = h;
	n.style.background = 0xFF808080;
	return n;
}

// (a canvas recording the opacity each rect was drawn at, by its node: the paint's opacity stack)
private class Rec implements Canvas {
	var alpha = [1.0];
	final seen = new Map<String, Float>();

	public function new() {}

	public function reset()
		seen.clear();

	// the opacity a node's box was last drawn at (-1: not drawn); a node is known by its size and fill
	public function drawn(n:Node):Float {
		var k = key(n.style.background);
		return seen.exists(k) ? seen.get(k) : -1;
	}

	static function key(fill:Color):String
		return Std.string(fill);

	public function translate(dx:Float, dy:Float) {}

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners) {}

	public function popClip() {}

	public function pushOpacity(a:Float)
		alpha.push(alpha[alpha.length - 1] * a);

	public function popOpacity()
		alpha.pop();

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {}

	public function popTransform() {}

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges)
		seen.set(key(fill), alpha[alpha.length - 1]);

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>) {}

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, dx:Float, dy:Float, spread:Float, ?corners:Corners) {}

	public function path(p:Path, fill:Null<Paint>, ?stroke:Stroke) {}

	public function image(img:helder.image.Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners) {}

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>) {}

	public function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>) {}
}
