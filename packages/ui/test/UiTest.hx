import hxmc.ui.*;
import hxmc.ui.DimValue;
import hxmc.ui.widgets.TextField;
import hxmc.ui.widgets.TextArea;
import hxmc.ui.widgets.EditableText;

// hxmc.ui's tests, on Eval (make ui-check):
//
//   <tool> -cp packages/ui/src -cp packages/ui/test --run UiTest
//
// - layout: layout-cases.json laid out by Layout against Chromium's
//   flexbox (layout-expected.json, from layout-ref.mjs), every box exact
// - text: TextNode measured and wrapped by MonoText
// - events: hit testing, hover, press and click, bubbling, focus and Tab,
//   the wheel scrolling an Overflow Scroll node, relayout after changes
// - paint: what Ui draws on a Canvas, in order (shadows under backgrounds,
//   rounded clips inside borders), and Shadow.parse
// - fields: TextField's editing (words, undo and redo, double and triple
//   clicks, Shift+click) and the clipboard (copy, cut, paste), an
//   input method's composition (shown, then committed);
//   TextArea's lines (wrapping, Enter, Up and Down, Home and End, scrolling)
// - popups: placed by their anchors (flipped, kept in the window), drawn
//   and hit over the tree, dismissed by outside presses and Escape, a
//   modal one keeping the focus
// - images: png/*.png decoded (every colour type and depth, tRNS, the
//   filters, Adam7; png-cases.mjs writes them and the pixels expected);
//   jpeg/*.jpg and gif/*.gif against Chromium's pixels (jpeg-cases.mjs,
//   gif-cases.mjs); webp/*.webp against libwebp's (webp-cases.mjs);
//   apng/*.png's frames against Chromium's (apng-cases.mjs)
class UiTest {
	static var checks = 0;
	static var failed = 0;

	static function main() {
		var here = haxe.io.Path.directory(haxe.macro.Compiler.getDefine("UiTest") ?? Sys.programPath() ?? "packages/ui/test/UiTest.hx");
		if (!sys.FileSystem.exists(here + "/layout-cases.json")) here = "packages/ui/test";
		layouts(here);
		texts();
		events();
		dirty();
		paint();
		themes();
		transitions();
		images(here);
		svgs(here);
		svgApi();
		css(here);
		decorations();
		transforms();
		sticky();
		stacking();
		visibility();
		pointerEvents();
		rtlScroll();
		noWrap();
		textTransform();
		culling();
		selection();
		fields();
		popups();
		shortcuts();
		Sys.println('UiTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('UiTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	// --- svg ---

	// svg/*.svg drawn by Svg.render against Chromium's pixels (svg-cases.mjs):
	// compared premultiplied. Edge pixels differ by their anti-aliasing
	// (Skia's approximates; ours is the exact area, within a few levels of
	// a 16x16 supersampling of the true curves, where Skia's strokes of
	// quadratic curves are off by up to 80, its clips' edges by 25), so the
	// shapes must agree: a small mean difference, few pixels far apart.
	static function svgs(here:String) {
		var dir = here + "/svg";
		var cases:Array<{name:String, width:Int, height:Int}> = haxe.Json.parse(sys.io.File.getContent(dir + "/cases.json"));
		check("svg: the cases", cases.length >= 20, '${cases.length}');
		// (SVG_STATS=1: each case's differences; SVG_OUT=dir: our pixels into dir/<case>.rgba)
		var stats = Sys.getEnv("SVG_STATS") != null, dump = Sys.getEnv("SVG_OUT");
		for (c in cases) {
			var img = Svg.parse(sys.io.File.getContent(dir + "/" + c.name + ".svg")).render(c.width, c.height);
			if (dump != null) sys.io.File.saveBytes(dump + "/" + c.name + ".rgba", img.pixels);
			var ref = PngDecoder.decode(sys.io.File.getBytes(dir + "/" + c.name + ".png"));
			var total = 0.0, worst = 0, far = 0, a = img.pixels, b = ref.rgba;
			for (i in 0...c.width * c.height) {
				var o = i * 4, aa = a.get(o + 3), ba = b.get(o + 3), d = Std.int(Math.abs(aa - ba));
				for (k in 0...3) {
					var e = Std.int(Math.abs(a.get(o + k) * aa / 255 - b.get(o + k) * ba / 255));
					if (e > d) d = e;
				}
				total += d;
				if (d > worst) worst = d;
				if (d > 64) far++;
			}
			var mean = total / (c.width * c.height);
			if (stats) Sys.println('svg ${c.name}: mean ${Math.round(mean * 100) / 100} worst $worst far $far');
			check("svg: " + c.name + " as Chromium draws it", mean < 5 && far <= c.width * c.height / 50, 'mean $mean, worst $worst, $far pixels off by more than 64');
		}
	}

	// Svg's own behaviour, and an svg in an ImageNode
	static function svgApi() {
		var icon = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect width="24" height="24" fill="currentColor"/></svg>');
		check("svg: the viewBox's size by itself", icon.width == 24 && icon.height == 24);
		var img = icon.render(4, 4, 0xFF2563EB);
		check("svg: currentColor painted render's colour", img.pixels.get(0) == 0x25 && img.pixels.get(1) == 0x63 && img.pixels.get(2) == 0xEB && img.pixels.get(3) == 255);
		var none = 0;
		try Svg.parse("<html/>") catch (_:Dynamic) none++;
		check("svg: no svg element throws", none == 1);
		var nums = Svg.SvgParse.numbers("1,2 3-4.5.5e1 -.5");
		check("svg: number lists as SVG splits them", nums.join(" ") == "1 2 3 -4.5 5 -0.5", nums.join(" "));
		var p = Svg.SvgParse.pathData("M1 1 L2 2 X 3 3");
		check("svg: path data up to an error", p.length == 6, '$p');
		var ui = new Ui(new MonoText(), 200, 100);
		ui.root.style.alignItems = Start;
		ui.root.style.color = Color.rgb(0xFF0000);
		var n = new ImageNode();
		n.svg = icon;
		ui.root.append(n);
		ui.scale = 2;
		ui.update();
		var rec = new Recording();
		ui.paint(rec);
		var drawn = [for (c in rec.calls) if (StringTools.startsWith(c, "image")) c];
		check("svg: an ImageNode its size, drawn at the window's pixels", n.width == 24 && n.height == 24 && drawn.length == 1 && StringTools.startsWith(drawn[0], "image 48x48 0 0 24 24")
			&& n.image.pixels.get(0) == 255 && n.image.pixels.get(2) == 0, drawn.join("|"));
		n.style.width = 40;
		ui.root.style.color = Color.rgb(0x0000FF);
		ui.update();
		rec = new Recording();
		ui.paint(rec);
		drawn = [for (c in rec.calls) if (StringTools.startsWith(c, "image")) c];
		check("svg: drawn again at a new size and colour", n.height == 40 && StringTools.startsWith(drawn[0], "image 80x80") && n.image.pixels.get(2) == 255, drawn.join("|"));
	}

	// --- css ---

	// css/: colours against Chromium's computed ones (within 1 a channel),
	// gradients against its backgrounds (within 2 levels)
	static function css(here:String) {
		var dir = here + "/css";
		var colors:Array<{css:String, rgba:Array<Int>}> = haxe.Json.parse(sys.io.File.getContent(dir + "/colors.json"));
		var bad = [];
		for (c in colors) {
			var v = Color.tryParse(c.css);
			if (v == null || Math.abs(v.r - c.rgba[0]) > 1 || Math.abs(v.g - c.rgba[1]) > 1 || Math.abs(v.b - c.rgba[2]) > 1 || Math.abs(v.a - c.rgba[3]) > 1)
				bad.push(c.css + " " + (v == null ? "null" : v.toHex()) + " vs " + c.rgba.join(","));
		}
		check("css: colours as Chromium computes them (" + colors.length + ")", bad.length == 0, bad.join("; "));
		check("css: not a colour", Color.tryParse("bluish") == null && Color.tryParse("rgb(1, 2)") == null && Color.tryParse("#12345") == null);
		check("css: hex in either case, short and long", Color.tryParse("#AbCdEf") == Color.rgb(0xabcdef) && Color.tryParse("#F0a") == Color.rgb(0xff00aa)
			&& Color.tryParse("#0F08") == Color.rgba(0x00ff00, 0x88 / 255) && Color.tryParse(" #fff ") == Color.WHITE && Color.tryParse("#ggg") == null);
		check("css: toHex, and back", Color.rgba(0x3366ff, 0.5).toHex() == "#3366FF80" && Color.parse(Color.rgb(0xa1b2c3).toHex()) == Color.rgb(0xa1b2c3)
			&& Color.TRANSPARENT.toHex() == "#00000000", Color.rgba(0x3366ff, 0.5).toHex());
		var stats = Sys.getEnv("CSS_STATS") != null;
		var cases:Array<{name:String, css:String, width:Int, height:Int}> = haxe.Json.parse(sys.io.File.getContent(dir + "/gradients.json"));
		for (c in cases) {
			var img = Gradient.parse(c.css).render(c.width, c.height);
			var ref = PngDecoder.decode(sys.io.File.getBytes(dir + "/" + c.name + ".png"));
			var total = 0.0, worst = 0, a = img.pixels, b = ref.rgba;
			for (i in 0...c.width * c.height) {
				var o = i * 4, aa = a.get(o + 3), ba = b.get(o + 3), d = Std.int(Math.abs(aa - ba));
				for (k in 0...3) {
					var e = Std.int(Math.abs(a.get(o + k) * aa / 255 - b.get(o + k) * ba / 255));
					if (e > d) d = e;
				}
				total += d;
				if (d > worst) worst = d;
			}
			var mean = total / (c.width * c.height);
			if (stats) Sys.println('css ${c.name}: mean ${Math.round(mean * 100) / 100} worst $worst');
			check("css: " + c.name + " as Chromium draws it", mean < 1 && worst <= 2, 'mean $mean, worst $worst');
		}
		// a node's gradient: over its colour, under its border, at the window's pixels
		var ui = new Ui(new MonoText(), 200, 100);
		ui.root.style.alignItems = Start;
		var n = new Node("card");
		n.style.set({width: 40, height: 20, radius: 4, background: Color.rgb(0xFFFFFF), borderWidth: 1, borderColor: Color.rgb(0x000000),
			backgroundImage: Gradient.parse("linear-gradient(to right, red, blue)")});
		ui.root.append(n);
		ui.scale = 2;
		ui.update();
		var rec = new Recording();
		ui.paint(rec);
		var calls = [for (c in rec.calls) if (StringTools.startsWith(c, "rect") || StringTools.startsWith(c, "image")) c.split(" ").slice(0, 2).join(" ")];
		check("css: a node's gradient between its colour and its border", calls.join(",") == "rect 0,image 80x40,rect 0", calls.join(","));
		// each corner's radius and each side's border: drawn with them, the clip inside them
		var card = new Node("card2");
		card.style.set({width: 60, height: 40, corners: [12, 12, 0, 0], borders: [1, 2, 4, 2], borderColor: Color.rgb(0x000000), overflow: Hidden});
		ui.root.append(card);
		ui.scale = 1;
		ui.update();
		rec = new Recording();
		ui.paint(rec);
		var all = rec.calls.join("|");
		// (the clip: the padding box, each corner less the wider side meeting there)
		check("corners and sides: drawn with them, clipped inside them", all.indexOf("corners 12,12,0,0 sides 1,2,4,2") > 0
			&& all.indexOf("clip " + (card.absX + 2) + " " + (card.absY + 1) + " 56 35 0 corners 10,10,0,0") >= 0, all);
		ui.root.remove(card);
		ui.scale = 2;
		var img = n.backgroundImage(2);
		check("css: kept while the node's size stays", n.backgroundImage(2) == img && img.pixels.get(0) > 200 && img.pixels.get((79) * 4 + 2) > 200);
	}

	// CSS transforms: parsed and composed as CSS composes them, about the
	// origin; drawn by pushing the matrix around the subtree; hit and
	// pointed at through the inverse
	static function transforms() {
		function near(a:Array<Float>, b:Array<Float>):Bool {
			for (i in 0...6)
				if (Math.abs(a[i] - b[i]) > 1e-9) return false;
			return true;
		}
		var m = Transform.parse("translate(10px, 50%) rotate(90deg) scale(2)").toMatrix(100, 40);
		check("transform: composed left to right", near(m, [0, 2, -2, 0, 10, 20]), "" + m);
		var t2 = Transform.parse("skewX(45deg) matrix(1, 0, 0, 1, 5, 6) rotate(0.25turn)").toMatrix(10, 10);
		check("transform: skew, matrix and turns", near(t2, [1, 1, -1, 0, 11, 6]), "" + t2);
		check("transform: none", Transform.parse("none").isIdentity());
		var bad = try {
			Transform.parse("spin(3deg)");
			false;
		} catch (e:Dynamic) true;
		check("transform: an unknown function is an error", bad);
		var inv = Transform.invert(m);
		check("transform: inverted", inv != null && near(Transform.multiply(m, inv), [1, 0, 0, 1, 0, 0]));
		var o = Transform.origin("left top");
		check("transform origin: keywords", o[0].resolve(80) == 0 && o[1].resolve(40) == 0);
		var o2 = Transform.origin("bottom");
		check("transform origin: one keyword, the other centred", o2[0].resolve(80) == 40 && o2[1].resolve(40) == 40);

		var ui = new Ui(new MonoText(), 300, 300);
		ui.root.style.alignItems = Start;
		var box = new Node("box");
		box.style.set({width: 100, height: 20, margin: 50, background: Color.rgb(0xFF0000)});
		var inner = new Node("inner");
		inner.style.set({width: 10, height: 10, background: Color.rgb(0x0000FF)});
		box.append(inner);
		ui.root.append(box);
		ui.update();
		// (rotated a quarter about its centre (100, 60): 100 wide becomes 100 high)
		box.style.transform = Transform.rotate(90);
		ui.update();
		var rec = new Recording();
		ui.paint(rec);
		var calls = [for (c in rec.calls) if (!StringTools.startsWith(c, "text")) c];
		var first = calls.length > 0 ? calls[0].split(" ") : [];
		var drawn = first.length == 7 && first[0] == "transform" && Math.abs(Std.parseFloat(first[1])) < 1e-9 && Std.parseFloat(first[2]) == 1
			&& Std.parseFloat(first[3]) == -1 && Math.abs(Std.parseFloat(first[5]) - 160) < 1e-9 && Math.abs(Std.parseFloat(first[6]) - (-40)) < 1e-9;
		check("transform: pushed around the subtree", drawn && calls[calls.length - 1] == "popTransform", calls.join(" | "));
		var hitTop = ui.root.hitTest(100, 15), hitOld = ui.root.hitTest(140, 60);
		var wb = box.windowBounds();
		check("transform: its bounds where it is drawn", Math.abs(wb.x - 90) < 1e-9 && Math.abs(wb.y - 10) < 1e-9 && Math.abs(wb.width - 20) < 1e-9
			&& Math.abs(wb.height - 100) < 1e-9, wb.x + "," + wb.y + " " + wb.width + "x" + wb.height);
		inner.focusable = true;
		var at = ui.accessTree(), ids = [for (id in at.order) if (at.node(id) == inner) id], an = ids.length == 1 ? at.nodes.get(ids[0]) : null;
		check("transform: the accessibility tree's box through it", an != null && Math.abs(an.x - 100) < 1e-9 && Math.abs(an.y - 10) < 1e-9,
			an == null ? "none" : an.x + "," + an.y);
		inner.focusable = false;
		check("transform: hit through it", hitTop == box && hitOld == ui.root, hitTop + " " + hitOld);
		// (the inner box's top left (50, 50) turns to (110, 10): its 10x10 at x 100...110)
		var hitInner = ui.root.hitTest(105, 15);
		check("transform: children hit through their ancestor's", hitInner == inner, "" + hitInner);
		check("transform: local coordinates through it", Math.abs(box.localX(100, 15) - 5) < 1e-9 && Math.abs(box.localY(100, 15) - 10) < 1e-9,
			box.localX(100, 15) + "," + box.localY(100, 15));
		var at = [];
		box.onPointerDown = e -> at.push(e.localX + "," + e.localY);
		ui.pointerDown(102, 15, 1);
		ui.pointerUp(102, 15, 1);
		check("transform: events' local coordinates through it", at.length == 1 && at[0] == "5,8", at.join(" "));
		box.style.transformOrigin = Transform.origin("left top");
		box.style.transform = Transform.parse("scale(2)");
		ui.update();
		check("transform: about its origin", ui.root.hitTest(240, 85) == box && ui.root.hitTest(45, 55) == ui.root);
		box.style.transform = Transform.parse("scale(0)");
		ui.update();
		check("transform: flattened, it hits nothing", ui.root.hitTest(50, 50) == ui.root && box.hitTest(50, 50) == null);
		ui.root.remove(box);
	}

	// position: Sticky against Chromium's tops (a scroller 200x100, border 2,
	// padding 4: a header sticking 5 inside its content box within its
	// 120-high section; a footer sticking 3 above its bottom), at five scroll
	// positions
	// zIndex and order: painted and hit by them (zIndex, then positioned over
	// in-flow, then order); Tab still in the tree's order
	static function stacking() {
		var ui = new Ui(new MonoText(), 200, 100);
		function box(tag:String, color:Int, x:Float):Node {
			var n = new Node(tag);
			n.style.set({width: 40, height: 40, background: Color.rgb(color), position: Absolute, left: x, top: 0});
			ui.root.append(n);
			return n;
		}
		var a = box("a", 0x110000, 10), b = box("b", 0x220000, 20), c = box("c", 0x330000, 30);
		ui.update();
		function painted():String {
			var rec = new Recording();
			ui.paint(rec);
			return [for (l in rec.calls) if (StringTools.startsWith(l, "rect")) l.split(" ")[6].substr(2, 2)].join(",");
		}
		check("stacking: the tree's order", painted() == "11,22,33" && ui.root.hitTest(35, 10) == c, painted());
		a.style.zIndex = 2;
		ui.update();
		check("stacking: a higher zIndex over the others, hit first", painted() == "22,33,11" && ui.root.hitTest(35, 10) == a, painted());
		c.style.zIndex = -1;
		ui.update();
		check("stacking: a negative one under", painted() == "33,22,11" && ui.root.hitTest(55, 10) == b, painted());
		// in the flow: order rearranges them; Tab follows the tree
		var ui2 = new Ui(new MonoText(), 200, 100);
		ui2.root.style.direction = Row;
		var x = new Node("x"), y = new Node("y");
		for (n in [x, y]) {
			n.style.set({width: 40, height: 40});
			n.focusable = true;
			ui2.root.append(n);
		}
		y.style.order = -1;
		ui2.update();
		ui2.keyDown(Key.TAB, 0);
		check("stacking: order moves it, Tab keeps the tree's order", y.absX == 0 && x.absX == 40 && ui2.focus == x, '${y.absX} ${x.absX} ${ui2.focus}');
	}

	// visibility: hidden keeps the place, draws, hits, focuses and shows
	// nothing of the node, but a visible descendant still is
	static function visibility() {
		var ui = new Ui(new MonoText(), 200, 100);
		ui.root.style.direction = Row;
		var a = new Node("a"), b = new Node("b"), inner = new Node("inner");
		for (n in [a, b]) {
			n.style.set({width: 60, height: 40, background: Color.rgb(n == a ? 0x110000 : 0x220000)});
			n.focusable = true;
			n.semantics = {role: Button, label: n.tag};
			ui.root.append(n);
		}
		inner.style.set({width: 20, height: 20, background: Color.rgb(0x330000)});
		inner.focusable = true;
		inner.semantics = {role: Button, label: "inner"};
		a.append(inner);
		a.style.visibility = Hidden;
		ui.update();
		function painted():String {
			var rec = new Recording();
			ui.paint(rec);
			return [for (l in rec.calls) if (StringTools.startsWith(l, "rect")) l.split(" ")[6].substr(2, 2)].join(",");
		}
		function labels():String {
			var at = ui.accessTree();
			return [for (id in at.order) if (at.nodes.get(id).name != null && at.nodes.get(id).name != "") at.nodes.get(id).name].join(",");
		}
		check("visibility: hidden keeps its place, not drawn", b.absX == 60 && painted() == "22", painted());
		check("visibility: hidden not hit, nor focused, nor seen", ui.root.hitTest(30, 30) == ui.root && labels() == "b" && {
			ui.keyDown(Key.TAB, 0);
			ui.focus == b;
		}, labels());
		// (its ring not drawn)
		ui.setFocus(null);
		inner.style.visibility = Visible;
		ui.update();
		check("visibility: a visible descendant drawn, hit, seen", painted() == "33,22" && ui.root.hitTest(10, 10) == inner && labels() == "inner,b",
			painted() + " " + labels());
		a.style.visibility = null;
		ui.update();
		check("visibility: shown again", painted() == "11,33,22" && ui.root.hitTest(30, 30) == a, painted());
	}

	// right to left, a row overflowing a scroller overflows on the left:
	// scrolled there by negative offsets (Chromium's scrollLeft), from 0 at
	// its right end; the vertical bar on the left
	// pointerEvents None: the pointer through to what is under it; an Auto descendant still found
	static function pointerEvents() {
		var ui = new Ui(new MonoText(), 200, 100);
		var under = new Node("under"), cover = new Node("cover"), knob = new Node("knob");
		under.style.set({width: 100, height: 50});
		cover.style.set({position: Absolute, left: 0, top: 0, width: 100, height: 50, pointerEvents: None});
		knob.style.set({width: 20, height: 20, pointerEvents: Auto});
		cover.append(knob);
		ui.root.append(under);
		ui.root.append(cover);
		ui.update();
		var clicked = 0;
		under.onClick = _ -> clicked++;
		ui.pointerDown(50, 30, 1);
		ui.pointerUp(50, 30, 1);
		check("pointer events: through a None node to the one under it", ui.root.hitTest(50, 30) == under && clicked == 1, "" + ui.root.hitTest(50, 30));
		check("pointer events: its Auto child still found", ui.root.hitTest(10, 10) == knob);
	}

	static function rtlScroll() {
		var ui = new Ui(new MonoText(), 200, 100);
		ui.scrollDuration = 0;
		var s = new Node("s");
		s.style.set({width: 100, height: 50, overflow: Scroll, direction: Row, dir: Rtl});
		for (i in 0...3) {
			var c = new Node("c" + i);
			c.style.set({width: 60, height: 20, shrink: 0});
			s.append(c);
		}
		ui.root.append(s);
		ui.update();
		var c2 = s.children[2];
		check("rtl scroll: the content to the left counted", s.contentWidth == 180 && s.scrollX == 0 && c2.absX == -80, s.contentWidth + " " + c2.absX);
		ui.scrollBy(s, -1000, 0);
		ui.update();
		check("rtl scroll: scrolled left to its end", s.scrollX == -80 && ui.root.hitTest(5, 10) == c2, s.scrollX + " " + ui.root.hitTest(5, 10));
		ui.scrollBy(s, 1000, 0);
		check("rtl scroll: back to 0 at most", s.scrollX == 0, "" + s.scrollX);
		// (a column taller than it: its bar on the left)
		var t = new Node("t");
		t.style.set({width: 100, height: 50, overflow: Scroll, dir: Rtl});
		var tall = new Node("tall");
		tall.style.set({height: 200, shrink: 0});
		t.append(tall);
		ui.root.append(t);
		ui.update();
		var bar:Array<Float> = @:privateAccess Ui.thumb(t, false);
		check("rtl scroll: the vertical bar on the left", bar != null && bar[0] == t.absX + Ui.SCROLLBAR_INSET, "" + bar);
	}

	// textWrap NoWrap (inherited): a line kept whole past its box, its
	// min-content as wide; Wrap again inside
	static function noWrap() {
		var ui = new Ui(new MonoText(), 300, 200);
		ui.root.style.alignItems = Start;
		var box = new Node("box"), t = new TextNode("one two three");
		box.style.set({width: 40, textWrap: NoWrap});
		box.append(t);
		ui.root.append(box);
		ui.update();
		var p = t.laidOut(), whole = p.width;
		check("no wrap: one line, past its box", p.lineCount == 1 && t.width == 40 && whole > 40, p.lineCount + " " + whole);
		box.style.width = DimValue.Auto;
		var row = new Node("row");
		row.style.set({width: 10, direction: Row});
		ui.root.append(row);
		var u = new TextNode("alpha beta");
		row.append(u);
		row.style.textWrap = NoWrap;
		ui.update();
		check("no wrap: the min-content width the whole line", u.width == u.laidOut().width && u.laidOut().lineCount == 1, "" + u.width);
		t.style.textWrap = Wrap;
		box.style.width = 40;
		ui.update();
		check("no wrap: Wrap again inside", t.laidOut().lineCount > 1, "" + t.laidOut().lineCount);
		// text-overflow: ellipsis: the line cut within its box, its intrinsic width the whole text's
		t.style.textWrap = NoWrap;
		t.style.textOverflow = Ellipsis;
		ui.update();
		var m:MonoText.MonoParagraph = cast t.laidOut();
		check("text overflow: one line cut to its box with an ellipsis", m.lineCount == 1 && m.ellipsis && m.width <= 40 && t.minContentWidth(ui.text) > 40,
			m.lineCount + " " + m.width);
		box.style.width = 400;
		ui.update();
		check("text overflow: none where it fits", !(cast t.laidOut() : MonoText.MonoParagraph).ellipsis);
	}

	// textTransform (inherited): the letters shown, the indices kept; a span its own
	static function textTransform() {
		var ui = new Ui(new MonoText(), 300, 200);
		var box = new Node("box"), t = new TextNode("hello big world");
		box.append(t);
		ui.root.append(box);
		box.style.textTransform = Uppercase;
		ui.update();
		check("text transform: inherited, upper case", t.allText() == "HELLO BIG WORLD" && t.text == "hello big world", t.allText());
		t.style.textTransform = Capitalize;
		ui.update();
		check("text transform: each word's first letter", t.allText() == "Hello Big World", t.allText());
		var rich = new TextNode(""), a = new TextNode("one "), b = new TextNode("two");
		rich.append(a);
		rich.append(b);
		b.style.textTransform = Lowercase;
		box.append(rich);
		ui.update();
		check("text transform: a span its own", rich.allText() == "ONE two", rich.allText());
	}

	static function sticky() {
		var ui = new Ui(new MonoText(), 300, 300);
		ui.root.style.alignItems = Start;
		var s = new Node("s");
		s.style.set({width: 200, height: 100, overflow: Scroll, borderWidth: 2, padding: 4});
		function block(h:Float):Node {
			var n = new Node();
			n.style.set({height: h, shrink: 0});
			return n;
		}
		var sec = block(120);
		sec.style.padding = 6;
		var h = block(20);
		h.style.set({position: Sticky, top: 5});
		sec.append(h);
		sec.append(block(20));
		var f = block(10);
		f.style.set({position: Sticky, bottom: 3});
		for (c in [block(30), sec, block(200), f, block(100)])
			s.append(c);
		ui.root.append(s);
		ui.update();
		var got = [], want = "0:42,81 50:11,81 100:11,81 140:-10,81 372:-242,-16";
		for (st in [0.0, 50, 100, 140, 400]) {
			ui.scrollTo(s, 0, st);
			got.push(s.scrollY + ":" + h.windowBounds().y + "," + f.windowBounds().y);
		}
		check("sticky: where Chromium sticks it as it scrolls", got.join(" ") == want, got.join(" "));
		ui.scrollTo(s, 0, 100);
		check("sticky: hit where it sticks", ui.root.hitTest(50, 15) == h, "" + ui.root.hitTest(50, 15));
		// (over what scrolls under it: drawn after its siblings)
		sec.children[1].style.background = Color.rgb(0x00FF00);
		h.style.background = Color.rgb(0xFF0000);
		// (h is first in the section, its sibling after it)
		ui.update();
		var rec = new Recording();
		ui.paint(rec);
		var order = [for (c in rec.calls) if (c.indexOf("ff00ff00") > 0) "green" else if (c.indexOf("ffff0000") > 0) "red"].filter(x -> x != null);
		check("sticky: drawn over its siblings", order.join(",") == "green,red", order.join(","));
		// (an absolute box first, an in-flow one under it after: drawn and hit over it)
		var ui2 = new Ui(new MonoText(), 100, 100);
		var abs = new Node("abs");
		abs.style.set({position: Absolute, left: 0, top: 0, width: 50, height: 50, background: Color.rgb(0xFF0000)});
		var flow = new Node("flow");
		flow.style.set({height: 50, background: Color.rgb(0x00FF00)});
		ui2.root.append(abs);
		ui2.root.append(flow);
		ui2.update();
		var rec2 = new Recording();
		ui2.paint(rec2);
		var order2 = [for (c in rec2.calls) if (c.indexOf("ff00ff00") > 0) "green" else if (c.indexOf("ffff0000") > 0) "red"].filter(x -> x != null);
		check("absolute: drawn and hit over its in-flow siblings", order2.join(",") == "green,red" && ui2.root.hitTest(10, 10) == abs, order2.join(","));
	}

	// what a frame leaves out: rows out of a scroller's view not drawn (those
	// in it all drawn), a clean tree not laid out again, the accessibility
	// tree kept until something it reads changes
	static function culling() {
		var ui = new Ui(new MonoText(), 200, 200);
		var list = new Node("list");
		list.style.set({height: 100, overflow: Scroll});
		for (i in 0...100) {
			var row = new Node("row" + i);
			row.style.set({height: 20, shrink: 0, background: Color.rgb(0x010000 * (i + 1))});
			row.focusable = true;
			list.append(row);
		}
		ui.root.append(list);
		ui.update();
		ui.scrollTo(list, 0, 500);
		var rec = new Recording();
		ui.paint(rec);
		var rows = [for (c in rec.calls) if (StringTools.startsWith(c, "rect")) c];
		var visible = [for (i in 25...30) "ff" + StringTools.hex(i + 1, 2).toLowerCase() + "0000"];
		check("culling: the rows in view drawn, not the others", rows.length >= 5 && rows.length <= 14 && visible.filter(v -> rows.join("|").indexOf(v) < 0).length == 0,
			rows.length + " " + rows.join("|"));
		check("culling: hit in the scrolled view", ui.root.hitTest(10, 30) == list.children[26], "" + ui.root.hitTest(10, 30));
		var a = ui.accessTree(), b = ui.accessTree();
		list.children[3].semantics = {label: "third"};
		var c = ui.accessTree();
		ui.scrollTo(list, 0, 520);
		var d = ui.accessTree();
		check("culling: the accessibility tree kept, built again after a change", a == b && c != b && d != c);
		var laid = @:privateAccess Layout.run(ui.root, 200, 200, ui.text);
		list.children[2].style.height = 30;
		var again = @:privateAccess Layout.run(ui.root, 200, 200, ui.text);
		check("culling: a clean tree not laid out, a changed one laid out", !laid && again && list.children[3].y == 70, list.children[3].y + "");
	}

	// an ancestor's decorations over a text: the underline before it, the
	// line-through after, both moved with its centred lines, in its colour
	static function decorations() {
		var ui = new Ui(new MonoText(), 200, 100);
		ui.root.style.fontSize = 10;
		var box = new Node("box");
		box.style.set({textDecoration: (TextDecoration.Underline : Int) | (TextDecoration.LineThrough : Int), color: Color.rgb(0xAA0000), textAlign: Center, width: 100});
		var t = new TextNode("abcd");
		t.style.color = Color.rgb(0x0000AA);
		box.append(t);
		ui.root.append(box);
		ui.update();
		var rec = new Recording();
		ui.paint(rec);
		var calls = [for (c in rec.calls) if (StringTools.startsWith(c, "rect") || StringTools.startsWith(c, "text")) c.split(" ").slice(0, 6).join(" ")];
		// (MonoText at 10: 5 a character, lines 12.5 high; "abcd" 20 wide, centred in 100 at 40)
		var spaced = new TextNode("abcd");
		spaced.style.letterSpacing = 1;
		ui.root.append(spaced);
		ui.update();
		check("letter spacing: in the text's font", spaced.laidOut() != null && spaced.laidOut().width == 24 && spaced.font().letterSpacing == 1, spaced.laidOut() == null ? "none" : "" + spaced.laidOut().width);
		ui.root.remove(spaced);
		var just = new TextNode("one two three four five six");
		just.style.set({width: 60, textAlign: Justify});
		ui.root.append(just);
		ui.update();
		var jp:MonoText.MonoParagraph = cast just.laidOut();
		var asked = jp != null && jp.justified;
		just.style.textAlign = Left;
		ui.update();
		jp = cast just.laidOut();
		check("justify: asked of the engine, laid out again when it changes", asked && jp != null && !jp.justified);
		ui.root.remove(just);
		ui.update();
		check("decorations: an ancestor's, around the text, aligned, in its colour",
			calls.join("|") == "rect 40 11.25 20 1 0|text 0 0 100|rect 40 6.25 20 1 0" && rec.calls.filter(c -> c.indexOf("ffaa0000") >= 0).length == 2, calls.join("|"));
	}

	// selectable text: a drag, a double click, a triple, copied, dropped
	static function selection() {
		var ui = new Ui(new MonoText(), 300, 100);
		ui.root.style.fontSize = 10;
		ui.root.style.alignItems = Start;
		var t = new TextNode("hello world foo");
		t.selectable = true;
		ui.root.append(t);
		var other = new Node("other");
		other.style.set({width: 50, height: 20});
		ui.root.append(other);
		ui.update();
		var time = 0.0;
		Ui.now = () -> time;
		// (MonoText at 10: 5 pixels a character, the line 12.5 high)
		ui.pointerDown(t.absX + 1, t.absY + 5, 1);
		ui.pointerMove(t.absX + 26, t.absY + 5);
		ui.pointerUp(t.absX + 26, t.absY + 5, 1);
		check("selection: a drag selects", ui.selectedText() == "hello" && t.style.cursor == Text, ui.selectedText());
		var rec = new Recording();
		ui.paint(rec);
		var calls = [for (c in rec.calls) if (StringTools.startsWith(c, "rect") || StringTools.startsWith(c, "text")) c.split(" ").slice(0, 5).join(" ")];
		check("selection: painted under the text", calls.join("|") == "rect 0 0 25 12.5|text 0 0 75", calls.join("|"));
		ui.keyDown("c".code, Key.MOD_CONTROL);
		var copied:Null<String> = null;
		ui.clipboard.read(s -> copied = s);
		check("selection: Control+C copies it", copied == "hello", copied);
		time = 10;
		ui.pointerDown(t.absX + 33, t.absY + 5, 1);
		ui.pointerUp(t.absX + 33, t.absY + 5, 1);
		time = 10.2;
		ui.pointerDown(t.absX + 33, t.absY + 5, 1);
		ui.pointerUp(t.absX + 33, t.absY + 5, 1);
		check("selection: a double click, the word", ui.selectedText() == "world", ui.selectedText());
		time = 10.4;
		ui.pointerDown(t.absX + 33, t.absY + 5, 1);
		ui.pointerUp(t.absX + 33, t.absY + 5, 1);
		check("selection: a triple click, all of it", ui.selectedText() == "hello world foo", ui.selectedText());
		time = 20;
		ui.pointerDown(other.absX + 5, other.absY + 5, 1);
		check("selection: a press elsewhere drops it", ui.textSelection == null);
		// (user-select: none on it, not selected; all, all of it at a click; text on an ancestor, a text of its own flag unset)
		t.style.userSelect = None;
		time = 30;
		ui.pointerDown(t.absX + 3, t.absY + 5, 1);
		ui.pointerUp(t.absX + 3, t.absY + 5, 1);
		var none = ui.textSelection == null;
		t.style.userSelect = All;
		time = 40;
		ui.pointerDown(t.absX + 3, t.absY + 5, 1);
		ui.pointerUp(t.absX + 3, t.absY + 5, 1);
		var all = ui.selectedText();
		t.style.userSelect = null;
		t.selectable = false;
		ui.root.style.userSelect = Text;
		time = 50;
		ui.pointerDown(t.absX + 33, t.absY + 5, 1);
		ui.pointerUp(t.absX + 33, t.absY + 5, 1);
		time = 50.2;
		ui.pointerDown(t.absX + 33, t.absY + 5, 1);
		ui.pointerUp(t.absX + 33, t.absY + 5, 1);
		check("selection: user-select none, all, text inherited", none && all == "hello world foo" && ui.selectedText() == "world", all + " " + ui.selectedText());
		ui.root.style.userSelect = null;
		t.selectable = true;
		time = 60;
		ui.pointerDown(other.absX + 5, other.absY + 5, 1);
		// (centred in 300: the line of 75 starts at 112.5)
		t.style.width = 300;
		t.style.textAlign = Center;
		ui.update();
		time = 30;
		ui.pointerDown(t.absX + 113, t.absY + 5, 1);
		ui.pointerMove(t.absX + 113 + 25, t.absY + 5);
		ui.pointerUp(t.absX + 113 + 25, t.absY + 5, 1);
		check("selection: on a centred line", ui.selectedText() == "hello", ui.selectedText());
		Ui.now = haxe.Timer.stamp;
	}

	// --- shortcuts ---

	static function shortcuts() {
		var s = Shortcut.parse("Mod+Shift+S");
		check("shortcuts: Mod with Control or Command, Shift's capital", s.matches("s".code, Key.MOD_CONTROL | Key.MOD_SHIFT) && s.matches("S".code, Key.MOD_META | Key.MOD_SHIFT)
			&& !s.matches("s".code, Key.MOD_CONTROL) && !s.matches("s".code, Key.MOD_CONTROL | Key.MOD_META | Key.MOD_SHIFT) && !s.matches("s".code, Key.MOD_SHIFT));
		check("shortcuts: keys by name", Shortcut.parse("F5").matches(0xFFC2, 0) && Shortcut.parse("Ctrl+PageDown").matches(Key.PAGE_DOWN, Key.MOD_CONTROL)
			&& Shortcut.parse("Mod++").matches("+".code, Key.MOD_CONTROL) && Shortcut.parse("alt+enter").matches(Key.ENTER, Key.MOD_ALT));
		var labels = [s.label(), Shortcut.parse("Alt+F4").label(), Shortcut.parse("Escape").label()].join(" ");
		Shortcut.mac = true;
		var mac = [s.label(), Shortcut.parse("Ctrl+Alt+Delete").label(), Shortcut.parse("Mod+Enter").label()].join(" ");
		Shortcut.mac = false;
		check("shortcuts: labels", labels == "Ctrl+Shift+S Alt+F4 Esc" && mac == "⇧⌘S ⌃⌥⌦ ⌘↩", labels + " / " + mac);
		var bad = 0;
		for (t in ["Hyper+S", "Ctrl+", "Ctrl+Nope", "F99"])
			try Shortcut.parse(t) catch (_:Dynamic) bad++;
		check("shortcuts: what is not one throws", bad == 4, '$bad');
		var ui = new Ui(new MonoText(), 300, 200);
		var panel = new Node("panel"), button = new Node("button"), field = new TextField(""), other = new Node("other");
		button.focusable = other.focusable = true;
		panel.append(button);
		panel.append(field);
		ui.root.append(panel);
		ui.root.append(other);
		ui.update();
		var log = [];
		var removeSave = ui.shortcut("Mod+S", () -> log.push("save"));
		ui.shortcut("Delete", () -> log.push("delete"), panel);
		ui.shortcut("n", () -> log.push("n"));
		ui.keyDown("s".code, Key.MOD_CONTROL);
		ui.keyDown(Key.DELETE, 0);
		check("shortcuts: a global one; a scoped one not with the focus outside", log.join(",") == "save", log.join(","));
		ui.setFocus(button);
		ui.keyDown(Key.DELETE, 0);
		ui.keyDown("n".code, 0);
		check("shortcuts: scoped, with the focus inside; a plain key", log.join(",") == "save,delete,n", log.join(","));
		ui.setFocus(field);
		ui.keyDown("n".code, 0);
		ui.keyDown(Key.DELETE, 0);
		ui.keyDown("s".code, Key.MOD_META);
		check("shortcuts: not a typed key or one the field takes; Mod+S in a field", log.join(",") == "save,delete,n,save", log.join(","));
		ui.shortcut("Mod+S", () -> log.push("later"));
		ui.setFocus(other);
		ui.keyDown("s".code, Key.MOD_CONTROL);
		removeSave();
		check("shortcuts: the latest added wins", log[log.length - 1] == "later");
		var stopper = new Node("stopper");
		stopper.focusable = true;
		stopper.onKeyDown = e -> e.preventDefault();
		ui.root.append(stopper);
		ui.update();
		ui.setFocus(stopper);
		var n = log.length;
		ui.keyDown("s".code, Key.MOD_CONTROL);
		check("shortcuts: not a key the focused node took", log.length == n);
		var d = new Popup("dialog");
		d.modal = true;
		var inside = new Node("inside");
		inside.focusable = true;
		d.append(inside);
		ui.open(d);
		ui.update();
		ui.shortcut("Enter", () -> log.push("ok"), d);
		ui.setFocus(inside);
		ui.keyDown("s".code, Key.MOD_CONTROL);
		ui.keyDown(Key.ENTER, 0);
		check("shortcuts: under a modal popup, only its own", log.slice(n).join(",") == "ok", log.slice(n).join(","));
	}

	// --- popups ---

	static function popups() {
		var ui = new Ui(new MonoText(), 300, 200);
		ui.root.style.alignItems = Start;
		ui.root.style.padding = 10;
		var clip = new Node("clip");
		clip.style.set({width: 100, height: 30, overflow: Hidden});
		var button = new Node("button");
		button.style.set({width: 60, height: 20});
		button.focusable = true;
		clip.append(button);
		ui.root.append(clip);
		var p = new Popup("menu");
		p.anchor = button;
		p.style.set({width: 80, height: 50, background: Color.WHITE});
		var item = new Node("item");
		item.style.set({width: 80, height: 20});
		item.focusable = true;
		p.append(item);
		var dismissed = 0;
		p.onDismiss = () -> dismissed++;
		ui.update();
		ui.open(p);
		ui.update();
		check("popups: below the anchor, out of its clip", p.absX == 10 && p.absY == 34 && p.parent == ui.overlay, '${p.absX},${p.absY}');
		check("popups: hit over the tree", @:privateAccess ui.hit(15, 40) == item && @:privateAccess ui.hit(15, 15) == button);
		var rec = new Recording();
		ui.paint(rec);
		check("popups: drawn after the tree", rec.calls[rec.calls.length - 1].indexOf("80 50") >= 0, rec.calls.join("|"));
		var at = ui.accessTree();
		check("popups: in the accessibility tree", at.order.length > 0 && at.node(at.order[at.order.length - 1]) == item || [for (id in at.order) at.node(id)].contains(item));
		// flipped above near the bottom, kept inside on the right
		clip.style.set({margin: [150.0, 0, 0, 250]});
		ui.update();
		check("popups: flipped above, kept in the window", p.absY == 160 - 4 - 50 && p.absX == 300 - 80, '${p.absX},${p.absY}');
		// right to left: the anchor's right edge and the popup's lined up
		clip.style.set({margin: [0.0, 0, 0, 100]});
		ui.root.style.dir = Rtl;
		ui.update();
		var anchorRight = button.absX + button.width;
		check("popups: right to left, their right edges lined up", p.absX + p.width == anchorRight, '${p.absX + p.width} ${anchorRight}');
		ui.root.style.dir = null;
		// at a point: there, flipped left and up where it does not fit
		p.placement = Point;
		p.atX = 20;
		p.atY = 30;
		ui.update();
		var there = p.absX == 20 && p.absY == 30;
		p.atX = 290;
		p.atY = 190;
		ui.update();
		check("popups: at a point, flipped where it does not fit", there && p.absX == 290 - 80 && p.absY == 190 - 50, '${p.absX},${p.absY}');
		p.placement = Below;
		ui.update();
		// dismissed by a press outside, not on the anchor or inside
		ui.pointerDown(p.absX + 5, p.absY + 5, 1);
		ui.pointerUp(p.absX + 5, p.absY + 5, 1);
		ui.pointerDown(button.absX + 5, button.absY + 5, 1);
		ui.pointerUp(button.absX + 5, button.absY + 5, 1);
		check("popups: not dismissed inside or on the anchor", dismissed == 0, '$dismissed');
		ui.pointerDown(5, 5, 1);
		ui.pointerUp(5, 5, 1);
		check("popups: dismissed by a press outside", dismissed == 1, '$dismissed');
		ui.keyDown(Key.ESCAPE, 0);
		check("popups: dismissed by Escape", dismissed == 2, '$dismissed');
		ui.close(p);
		ui.update();
		check("popups: closed", p.parent == null && ui.overlay.children.length == 0);
		// a modal dialog: the focus inside, Tab cycling in it, the tree covered
		ui.setFocus(button);
		var d = new Popup("dialog");
		d.modal = true;
		var box = new Node("box");
		box.style.set({width: 120, height: 60});
		var a = new Node("a"), b = new Node("b");
		for (n in [a, b]) {
			n.style.set({width: 40, height: 20});
			n.focusable = true;
			box.append(n);
		}
		d.append(box);
		var closed = 0;
		d.onDismiss = () -> closed++;
		ui.open(d);
		ui.update();
		check("popups: a modal covers the window, its content centred", d.width == 300 && d.height == 200 && box.absX == 90 && box.absY == 70, '${d.width}x${d.height} ${box.absX},${box.absY}');
		check("popups: a modal takes the focus", ui.focus == a);
		ui.keyDown(Key.TAB, 0);
		ui.keyDown(Key.TAB, 0);
		check("popups: Tab cycles inside it", ui.focus == a, '${ui.focus}');
		check("popups: the tree under it covered", @:privateAccess ui.hit(button.absX + 2, button.absY + 2) == d);
		ui.pointerDown(box.absX + 2, box.absY + 2, 1);
		ui.pointerUp(box.absX + 2, box.absY + 2, 1);
		ui.pointerDown(2, 2, 1);
		ui.pointerUp(2, 2, 1);
		check("popups: its backdrop dismisses it, its content does not", closed == 1, '$closed');
		ui.close(d);
		check("popups: closing gives the focus back", ui.focus == button, '${ui.focus}');
	}

	// --- fields ---

	static function fields() {
		var ui = new Ui(new MonoText(), 300, 100);
		var f = new TextField("");
		var changes = 0;
		f.onChange = _ -> changes++;
		ui.root.append(f);
		ui.update();
		ui.setFocus(f);
		function type(t:String)
			for (c in new haxe.iterators.StringIteratorUnicode(t)) {
				ui.keyDown(c, 0);
				ui.textInput(String.fromCharCode(c));
			}
		function key(k:Int, mods = 0)
			ui.keyDown(k, mods);
		type("hello world");
		check("fields: typing", f.text == "hello world" && f.caret == 11 && changes == 11, f.text);
		key(Key.LEFT, Key.MOD_SHIFT);
		key(Key.LEFT, Key.MOD_SHIFT);
		key(Key.LEFT, Key.MOD_SHIFT);
		key(Key.LEFT, Key.MOD_SHIFT);
		key(Key.LEFT, Key.MOD_SHIFT);
		key("c".code, Key.MOD_CONTROL);
		var clip:ClipboardHost.MemoryClipboard = cast ui.clipboard;
		check("fields: copy", clip.text == "world" && f.text == "hello world", clip.text);
		key("x".code, Key.MOD_CONTROL);
		check("fields: cut", clip.text == "world" && f.text == "hello " && f.caret == 6, f.text);
		key(Key.HOME);
		key("v".code, Key.MOD_META);
		check("fields: paste (Command too)", f.text == "worldhello " && f.caret == 5, f.text);
		clip.text = "two\nlines\r\nhere";
		key("a".code, Key.MOD_CONTROL);
		key("v".code, Key.MOD_CONTROL);
		check("fields: a paste over the selection, on one line", f.text == "two lines here", f.text);
		key(Key.BACKSPACE);
		key(Key.BACKSPACE);
		key(Key.BACKSPACE);
		key(Key.BACKSPACE);
		check("fields: Backspace", f.text == "two lines ", f.text);
		key("c".code, Key.MOD_CONTROL);
		check("fields: copy without a selection leaves the clipboard", clip.text == "two\nlines\r\nhere");
		// a clipboard that answers later
		var lc = new LaterClipboard();
		var later = lc.waiting;
		ui.clipboard = lc;
		key("v".code, Key.MOD_CONTROL);
		check("fields: a paste waits for the text", f.text == "two lines " && later.length == 1);
		later[0]("later");
		check("fields: then types it", f.text == "two lines later", f.text);
		// words, undo and redo, clicks in a row
		var ui = new Ui(new MonoText(), 300, 100);
		ui.root.style.fontSize = 10;
		ui.root.style.alignItems = Start;
		var h = new TextField("");
		h.style.width = 200;
		ui.root.append(h);
		ui.update();
		ui.setFocus(h);
		function typeH(t:String)
			for (c in new haxe.iterators.StringIteratorUnicode(t))
				ui.textInput(String.fromCharCode(c));
		typeH("hello big world");
		ui.keyDown(Key.LEFT, Key.MOD_CONTROL);
		check("words: Control+Left to the word's start", h.caret == 10, '${h.caret}');
		ui.keyDown(Key.LEFT, Key.MOD_ALT);
		check("words: Alt+Left (Option) too", h.caret == 6, '${h.caret}');
		ui.keyDown(Key.RIGHT, Key.MOD_CONTROL | Key.MOD_SHIFT);
		check("words: Shift selects to the word's end", h.selectionStart == 6 && h.selectionEnd == 9, '${h.selectionStart}-${h.selectionEnd}');
		ui.keyDown(Key.END, 0);
		ui.keyDown(Key.BACKSPACE, Key.MOD_CONTROL);
		check("words: Control+Backspace deletes a word", h.text == "hello big ", h.text);
		ui.keyDown(Key.LEFT, Key.MOD_META);
		check("words: Command+Left to the start", h.caret == 0);
		check("undo: a word deleted, undone", { ui.keyDown("z".code, Key.MOD_CONTROL); h.text == "hello big world"; }, h.text);
		ui.keyDown("z".code, Key.MOD_META);
		check("undo: typing undone as runs (words apart)", h.text == "hello big ", h.text);
		ui.keyDown("z".code, Key.MOD_CONTROL | Key.MOD_SHIFT);
		check("redo: Control+Shift+Z", h.text == "hello big world", h.text);
		ui.keyDown("y".code, Key.MOD_CONTROL);
		check("redo: Control+Y", h.text == "hello big ", h.text);
		for (_ in 0...10)
			ui.keyDown("z".code, Key.MOD_CONTROL);
		check("undo: back to empty", h.text == "", h.text);
		ui.keyDown("y".code, Key.MOD_CONTROL);
		typeH("x");
		ui.keyDown("y".code, Key.MOD_CONTROL);
		check("redo: an edit clears what was undone", StringTools.endsWith(h.text, "x"), h.text);
		h.setText("one two three");
		ui.update();
		ui.paint(new Recording());
		var t = 0.0;
		EditableText.now = () -> t;
		var cx = h.absX + h.style.borderWidth + h.style.padding.left + 5.5 * 5; // (within "two")
		var cy = h.absY + h.height / 2;
		function clickH(x:Float, at:Float, mods = 0) {
			t = at;
			if (mods != 0) ui.keyDown(Key.SHIFT, mods);
			ui.pointerDown(x, cy, 1);
			ui.pointerUp(x, cy, 1);
			if (mods != 0) ui.keyUp(Key.SHIFT, 0);
		}
		clickH(cx, 10);
		clickH(cx, 10.2);
		check("clicks: a double click selects a word", h.selectionStart == 4 && h.selectionEnd == 7, '${h.selectionStart}-${h.selectionEnd}');
		clickH(cx, 10.4);
		check("clicks: a triple click the line", h.selectionStart == 0 && h.selectionEnd == 13, '${h.selectionStart}-${h.selectionEnd}');
		clickH(cx, 20);
		clickH(h.absX + h.style.borderWidth + h.style.padding.left + 1, 30, Key.MOD_SHIFT);
		check("clicks: Shift+click extends the selection", h.selectionStart == 0 && h.selectionEnd == 6, '${h.selectionStart}-${h.selectionEnd}');
		EditableText.now = haxe.Timer.stamp;
		// the focus moved by Tab: its node scrolled into view; a press does not scroll
		var sui = new Ui(new MonoText(), 200, 100);
		var box = new Node("scroller");
		box.style.overflow = Scroll;
		box.style.height = 60;
		box.style.padding = 5;
		sui.root.append(box);
		var rows = [for (i in 0...10) {
			var r = new Node("row" + i);
			r.style.height = 20;
			// (as in CSS: an empty box of a fixed height shrinks in a column it overflows)
			r.style.shrink = 0;
			r.focusable = true;
			box.append(r);
			r;
		}];
		sui.update();
		sui.setFocus(rows[0]);
		for (_ in 0...4)
			sui.keyDown(Key.TAB, 0);
		check("focus: Tab scrolls the focused row into view", sui.focus == rows[4] && box.scrollY == 4 * 20 + 20 - 50, '${box.scrollY}');
		sui.keyDown(Key.TAB, Key.MOD_SHIFT);
		sui.keyDown(Key.TAB, Key.MOD_SHIFT);
		sui.keyDown(Key.TAB, Key.MOD_SHIFT);
		check("focus: and back up", sui.focus == rows[1] && box.scrollY == 20, '${box.scrollY}');
		// grapheme clusters: a letter and its marks, an emoji with its modifier, a flag move as one; Backspace takes a mark at a time
		var q = "e\u0301\u{1F44D}\u{1F3FD}\u{1F1E7}\u{1F1EA}";
		var units = "\u{1F600}".length;
		h.setText(q);
		h.select(0, 0);
		var steps = [];
		for (_ in 0...4) {
			ui.keyDown(Key.RIGHT, 0);
			steps.push(h.caret);
		}
		check("graphemes: Right steps over clusters", steps.join(",") == [2, 2 + 2 * units, 2 + 4 * units, 2 + 4 * units].join(","), steps.join(","));
		ui.keyDown(Key.LEFT, 0);
		check("graphemes: Left too", h.caret == 2 + 2 * units, '${h.caret}');
		h.select(2, 2);
		ui.keyDown(Key.BACKSPACE, 0);
		check("graphemes: Backspace takes a mark", h.text == "e\u{1F44D}\u{1F3FD}\u{1F1E7}\u{1F1EA}" && h.caret == 1, h.text);
		h.select(1 + 2 * units, 1 + 2 * units);
		ui.keyDown(Key.BACKSPACE, 0);
		check("graphemes: Backspace takes an emoji with its modifier", h.text == "e\u{1F1E7}\u{1F1EA}", h.text);
		h.select(1, 1);
		ui.keyDown(Key.DELETE, 0);
		check("graphemes: Delete takes a flag", h.text == "e", h.text);
		// Left and Right in right-to-left text move the caret as it looks (real fonts: DrawText, with DejaVu Sans)
		var dejavu = hxmc.text.SystemFonts.get().match("DejaVu Sans");
		if (dejavu != null && dejavu.family == "DejaVu Sans") {
			var rui = new Ui(new hxmc.ui.draw.DrawText(), 300, 100);
			rui.root.style.fontFamily = "DejaVu Sans";
			rui.root.style.alignItems = Start;
			var r = new TextField("ab \u05D0\u05D1\u05D2");
			r.style.width = 200;
			rui.root.append(r);
			rui.update();
			rui.setFocus(r);
			r.select(2, 2);
			var seq = [];
			for (_ in 0...5) {
				rui.keyDown(Key.RIGHT, 0);
				seq.push(r.caret);
			}
			check("bidi: Right goes rightward through Hebrew, then stays", seq.join(",") == "6,5,4,3,3", seq.join(","));
			r.setText("\u05D0\u05D1\u05D2");
			r.select(0, 0);
			var back = [];
			for (_ in 0...4) {
				rui.keyDown(Key.LEFT, 0);
				back.push(r.caret);
			}
			rui.keyDown(Key.RIGHT, 0);
			check("bidi: Left in Hebrew goes forward, Right back", back.join(",") == "1,2,3,3" && r.caret == 2, back.join(",") + " " + r.caret);
		}
		// an input method's composition: shown at the caret, underlined, typed when committed
		var ui = new Ui(new MonoText(), 300, 100);
		ui.root.style.fontSize = 10;
		ui.root.style.alignItems = Start;
		var g = new TextField("ab");
		g.style.width = 100;
		var gc = 0;
		g.onChange = _ -> gc++;
		ui.root.append(g);
		ui.update();
		ui.paint(new Recording());
		check("composition: no text input without the focus", ui.textInputArea() == null);
		ui.setFocus(g);
		ui.update();
		ui.paint(new Recording());
		var at = ui.textInputArea();
		check("composition: the caret's area", at != null && at.height == 12.5 && at.width == 1, '$at');
		var x0 = at == null ? 0.0 : at.x;
		g.select(1, 2);
		ui.composition("にほん", 3);
		check("composition: the selection goes, the text waits", g.text == "a" && g.composition == "にほん" && gc == 1, g.text + "|" + g.composition);
		ui.update();
		var rec = new Recording();
		ui.paint(rec);
		check("composition: drawn in the text", rec.calls.filter(s -> StringTools.startsWith(s, "text")).map(s -> s.split(" ")[3]).join(",") == "20", rec.calls.join("|"));
		check("composition: underlined", rec.calls.filter(s -> StringTools.startsWith(s, "rect") && s.split(" ")[3] == "15" && s.split(" ")[4] == "1").length == 1, rec.calls.join("|"));
		at = ui.textInputArea();
		check("composition: the caret in it", at != null && at.x == x0 - 5 + 15, '$at $x0');
		ui.composition("日本", 1);
		ui.update();
		ui.paint(new Recording());
		at = ui.textInputArea();
		check("composition: its caret moves", at != null && at.x == x0 - 5 + 5 && g.text == "a", '$at');
		ui.composition("", 0);
		ui.textInput("日本");
		check("composition: committed", g.text == "a日本" && g.composition == "" && g.caret == 3 && gc == 2, g.text);
		ui.composition("x", 1);
		ui.setFocus(null);
		check("composition: dropped on blur", g.composition == "" && g.text == "a日本" && ui.textInputArea() == null);
		// a text area: 100 wide, 20 characters a line (MonoText at 10: 5 each, lines of 12.5)
		var ui = new Ui(new MonoText(), 300, 200);
		ui.root.style.fontSize = 10;
		ui.root.style.alignItems = Start;
		var a = new TextArea("");
		a.style.width = 100;
		a.rows = 2;
		ui.root.append(a);
		ui.update();
		check("area: rows high", a.height == 25 && a.width == 100, '${a.width}x${a.height}');
		ui.setFocus(a);
		function typeIn(t:String)
			for (c in new haxe.iterators.StringIteratorUnicode(t)) {
				ui.keyDown(c, 0);
				ui.textInput(String.fromCharCode(c));
			}
		typeIn("first line");
		ui.keyDown(Key.ENTER, 0);
		typeIn("second");
		check("area: Enter types a line", a.text == "first line\nsecond" && a.caret == 17, a.text);
		ui.keyDown(Key.UP, 0);
		check("area: Up keeps the column", a.caret == 6, '${a.caret}');
		ui.keyDown(Key.END, 0);
		check("area: End of the line", a.caret == 10, '${a.caret}');
		ui.keyDown(Key.DOWN, 0);
		check("area: Down to a shorter line: its end", a.caret == 17, '${a.caret}');
		ui.keyDown(Key.HOME, 0);
		check("area: Home of the line", a.caret == 11, '${a.caret}');
		ui.keyDown(Key.UP, Key.MOD_SHIFT);
		check("area: Shift+Up selects", a.selectionStart == 0 && a.selectionEnd == 11, '${a.selectionStart}-${a.selectionEnd}');
		ui.keyDown(Key.END, Key.MOD_CONTROL);
		typeIn(" and a third line that wraps");
		ui.update();
		var c = new Recording();
		ui.paint(c);
		check("area: wrapped and scrolled to the caret (three lines in two)", c.calls.filter(s -> StringTools.startsWith(s, "text")).join("") == "text 0 -12.5 100", c.calls.join("|"));
		var clip:ClipboardHost.MemoryClipboard = cast ui.clipboard;
		clip.text = "x\ny";
		ui.keyDown("v".code, Key.MOD_CONTROL);
		check("area: a paste keeps its lines", StringTools.endsWith(a.text, "wrapsx\ny"), a.text);
	}

	// --- images ---

	static function images(here:String) {
		var dir = here + "/png";
		var names = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".png")) f.substr(0, f.length - 4)];
		names.sort(Reflect.compare);
		check("images: the cases", names.length >= 20, '${names.length}');
		for (n in names) {
			var want = sys.io.File.getBytes(dir + "/" + n + ".rgba");
			var img = try Image.decode(sys.io.File.getBytes(dir + "/" + n + ".png")) catch (e:Dynamic) {
				check("images: " + n, false, Std.string(e));
				continue;
			}
			var first = -1;
			for (i in 0...want.length)
				if (img.pixels.get(i) != want.get(i)) {
					first = i;
					break;
				}
			check("images: " + n, img.width == 13 && img.height == 11 && first < 0,
				first < 0 ? '${img.width}x${img.height}' : 'pixel ${first >> 2} channel ${first & 3}: ${img.pixels.get(first)}, not ${want.get(first)}');
		}
		// JPEG and GIF: jpeg/*.jpg and gif/*.gif against the pixels Chromium
		// decoded (jpeg-cases.mjs, gif-cases.mjs)
		for (kind in [{dir: "jpeg", ext: ".jpg", least: 15}, {dir: "gif", ext: ".gif", least: 8}, {dir: "webp", ext: ".webp", least: 25}, {dir: "apng", ext: ".png", least: 3}]) {
		var jdir = here + "/" + kind.dir;
		var cases:Array<{name:String, width:Int, height:Int, ?durations:Array<Float>, ?repetition:Int}> = haxe.Json.parse(sys.io.File.getContent(jdir + "/cases.json"));
		check(kind.dir + ": the cases", cases.length >= kind.least, '${cases.length}');
		for (c in cases) {
			// (an animation: every frame as Chromium's ImageDecoder composes it, its duration, the repetitions)
			if (c.durations != null) {
				var want = sys.io.File.getBytes(jdir + "/" + c.name + ".frames.rgba");
				var bytes = sys.io.File.getBytes(jdir + "/" + c.name + kind.ext);
				var a = try kind.dir == "webp" ? WebpDecoder.frames(bytes) : kind.dir == "apng" ? PngDecoder.frames(bytes) : GifDecoder.frames(bytes) catch (e:Dynamic) {
					check(kind.dir + ": " + c.name, false, Std.string(e));
					continue;
				}
				var size = c.width * c.height * 4, bad = [];
				for (k in 0...a.frames.length)
					if (k * size + size > want.length || a.frames[k].rgba.compare(want.sub(k * size, size)) != 0) bad.push(k);
				check(kind.dir + ": " + c.name + ", its frames", a.width == c.width && a.frames.length == c.durations.length && bad.length == 0
					&& [for (f in a.frames) f.delay].join(",") == c.durations.join(",") && a.repetitions == c.repetition,
					'${a.frames.length} frames, wrong: ${bad.join(",")}; ' + [for (f in a.frames) f.delay].join(",") + ' ${a.repetitions}');
				// (an APNG's default image: libpng's, whether in the animation or not)
				if (kind.dir == "apng")
					check("apng: " + c.name + ", its default image", Image.decode(bytes).pixels.compare(sys.io.File.getBytes(jdir + "/" + c.name + ".rgba")) == 0);
				continue;
			}
			var want = sys.io.File.getBytes(jdir + "/" + c.name + ".rgba");
			var img = try Image.decode(sys.io.File.getBytes(jdir + "/" + c.name + kind.ext)) catch (e:Dynamic) {
				check(kind.dir + ": " + c.name, false, Std.string(e));
				continue;
			}
			var differ = 0, most = 0, first = -1;
			if (img.pixels.length == want.length)
				for (i in 0...want.length) {
					var d = img.pixels.get(i) - want.get(i);
					if (d != 0) {
						if (first < 0) first = i;
						differ++;
						if (d < 0) d = -d;
						if (d > most) most = d;
					}
				}
			check(kind.dir + ": " + c.name, img.width == c.width && img.height == c.height && differ == 0,
				'${img.width}x${img.height}' + (differ > 0 ? ': $differ values differ, by at most $most (first: pixel ${first >> 2} channel ${first & 3})' : ""));
		}
		}
		// an animation played on the Clock: frames by their delays, three plays (two repetitions), then the last frame stays
		var anim = AnimatedImage.decode(sys.io.File.getBytes(here + "/gif/anim-background.gif"));
		var shown = [];
		anim.play();
		for (t in [10.0, 10.1, 10.2, 10.35, 10.5, 11.1, 11.4, 12.0]) {
			Clock.tick(t);
			shown.push(anim.frame);
		}
		check("animation: frames by their delays, played three times", shown.join(",") == "0,0,1,2,0,1,2,2" && !anim.playing && !Clock.active, shown.join(","));
		check("animation: the image shows the frame", anim.image.pixels.compare(anim.frames[2].rgba) == 0 && anim.image.version > 0);
		var zero = AnimatedImage.decode(sys.io.File.getBytes(here + "/gif/anim-transparent.gif"));
		zero.play();
		var z = [];
		for (t in [20.0, 20.05, 20.15, 20.25]) {
			Clock.tick(t);
			z.push(zero.frame);
		}
		zero.stop();
		check("animation: a delay of 0 shows for 100 ms, forever", z.join(",") == "0,0,1,0" && !zero.playing, z.join(","));
		Clock.tick(21);
		check("animation: stopped, nothing more animates", !Clock.active);
		var threw = try {
			Image.decode(haxe.io.Bytes.ofString("GIF89a"));
			false;
		} catch (e:Dynamic) true;
		check("images: not a PNG file", threw);
		// ImageNode: its size from the image's, its placement by fit
		var ui = new Ui(new MonoText(), 300, 200);
		ui.root.style.alignItems = Start;
		var img = new Image(40, 20);
		var natural = new ImageNode(img), wide = new ImageNode(img), box = new ImageNode(img);
		wide.style.width = 100;
		box.style.set({width: 100, height: 100, radius: 12});
		for (n in [natural, wide, box])
			ui.root.append(n);
		ui.update();
		check("images: the natural size", natural.width == 40 && natural.height == 20, '${natural.width}x${natural.height}');
		check("images: the aspect ratio kept", wide.width == 100 && wide.height == 50, '${wide.width}x${wide.height}');
		check("images: Fill", box.placement(0, 0, 100, 100).join(",") == "0,0,100,100,0,0,1,1");
		box.fit = Contain;
		check("images: Contain", box.placement(0, 0, 100, 100).join(",") == "0,25,100,50,0,0,1,1", box.placement(0, 0, 100, 100).join(","));
		box.fit = Cover;
		check("images: Cover", box.placement(0, 0, 100, 100).join(",") == "0,0,100,100,0.25,0,0.75,1", box.placement(0, 0, 100, 100).join(","));
		box.fit = ImageFit.None;
		check("images: None", box.placement(0, 0, 100, 100).join(",") == "30,40,40,20,0,0,1,1", box.placement(0, 0, 100, 100).join(","));
		// object-position: a share of the room left over and pixels more, the part outside cut
		function placed(fit:ImageFit, pos:String):String {
			box.fit = fit;
			box.position(pos);
			return box.placement(0, 0, 100, 100).join(",");
		}
		var got = [
			placed(Contain, "left top"), placed(Contain, "bottom"), placed(Cover, "right"), placed(Cover, "25% 0"), placed(ImageFit.None, "right 10px bottom 5px"),
			placed(ImageFit.None, "-30px 10px"), placed(ImageFit.None, "center top")
		];
		var want = [
			"0,0,100,50,0,0,1,1", "0,50,100,50,0,0,1,1", "0,0,100,100,0.5,0,1,1", "0,0,100,100,0.125,0,0.625,1", "50,75,40,20,0,0,1,1",
			"0,10,10,20,0.75,0,1,1", "30,0,40,20,0,0,1,1"
		];
		check("images: object-position", got.join("|") == want.join("|"), got.join("|"));
		var badPosition = try {
			box.position("sideways");
			false;
		} catch (e:Dynamic) true;
		box.position("center");
		check("images: object-position rejects what CSS does not write", badPosition && box.positionX == 0.5 && box.positionY == 0.5);
		var c = new Recording();
		ui.paint(c);
		check("images: painted", c.calls.join("|") == "image 40x20 0 0 40 20 0 0 1 1 0|image 40x20 0 20 100 50 0 0 1 1 0|image 40x20 30 110 40 20 0 0 1 1 12", c.calls.join("|"));
	}

	// --- themes: rules by slot, variant, size and state; tokens; the node's own style ---

static function transitions() {
		// parsed as CSS writes them; CSS's easings
		var t = Transition.parse("background-color 150ms ease-in-out, opacity 0.2s 50ms, box-shadow 1s cubic-bezier(0.4, 0, 0.2, 1)");
		check("transitions: parsed", t.properties.join(",") == "background,opacity,shadow" && t.durations.join(",") == "0.15,0.2,1"
			&& t.delays.join(",") == "0,0.05,0" && t.easings[0] == Transition.EASE_IN_OUT && t.easings[2].join(",") == "0.4,0,0.2,1"
			&& t.timing("color") == null && Transition.parse("all 1s").timing("borderColor").duration == 1 && Transition.parse("none") == null,
			t.properties.join(","));
		check("transitions: ease's curve as CSS's", Math.abs(Transition.ease(Transition.EASE, 0.5) - 0.8024) < 1e-3
			&& Math.abs(Transition.ease(Transition.LINEAR, 0.3) - 0.3) < 1e-6 && Math.abs(Transition.ease(Transition.EASE_IN_OUT, 0.5) - 0.5) < 1e-6,
			"" + Transition.ease(Transition.EASE, 0.5));
		check("transitions: colours with their alphas premultiplied", Color.between(Color.TRANSPARENT, Color.rgb(0xFF0000), 0.5) == Color.rgba(0xFF0000, 0.5)
			&& Color.between(Color.rgb(0x000000), Color.rgb(0xFFFFFF), 0.5) == Color.rgb(0x808080));
		var tr = Transform.between(null, Transform.parse("translateX(14px)"), 0.5).toString();
		var sh = Shadow.between(null, Shadow.parse("0 4px 8px #00000080"), 0.5);
		check("transitions: a transform from none, a shadow from none", tr == "translatex(7)" && sh.y == 2 && sh.blur == 4 && sh.color.a == 64,
			tr + " " + sh.y + " " + sh.blur + " " + sh.color.a);
		// a node's change, once drawn, eases on the Clock; the target known
		var ui = new Ui(new MonoText(), 100, 100);
		var n = new Node("n");
		n.style.set({width: 20, height: 20, background: Color.rgb(0x000000), transition: Transition.parse("background-color 100ms linear")});
		ui.root.append(n);
		n.style.background = Color.rgb(0x0000FF);
		check("transitions: not drawn yet, a change jumps", n.style.background == Color.rgb(0x0000FF));
		ui.update();
		ui.paint(new Recording());
		Clock.tick(10);
		n.style.background = Color.rgb(0xFFFFFF);
		check("transitions: drawn, a change starts where it is", n.style.background == Color.rgb(0x0000FF) && n.style.target("background") == Color.rgb(0xFFFFFF)
			&& Clock.active);
		Clock.tick(10.5);
		Clock.tick(10.55);
		var mid = n.style.background;
		Clock.tick(10.61);
		check("transitions: halfway, then there", Math.abs(mid.r - 0x80) <= 1 && mid.b == 0xFF && n.style.background == Color.rgb(0xFFFFFF) && !Clock.active, mid.toHex());
		// (set back mid-way: from where it is; the same value again: the run stopped)
		n.style.background = Color.rgb(0x000000);
		Clock.tick(20);
		Clock.tick(20.05);
		n.style.background = Color.rgb(0xFFFFFF);
		var from = n.style.background;
		Clock.tick(20.06);
		Clock.tick(20.11);
		check("transitions: turned back from where it was", Math.abs(from.r - 0x80) <= 1 && n.style.background.r > 0x80 && n.style.background.r < 0xFF,
			from.toHex() + " " + n.style.background.toHex());
		Clock.finish();
		// a theme's rules: a hover's colour eased, the rules still the node's own's judge
		var sheet:StyleSheet = {rules: [
			{slot: "b", style: {background: Color.rgb(0x000000), transition: Transition.parse("background-color 150ms linear")}},
			{slot: "b", when: ["hover"], style: {background: Color.rgb(0xFFFFFF)}}
		]};
		ui.theme = sheet;
		var b = new Node("b");
		b.slot = "b";
		b.style.set({width: 20, height: 20});
		ui.root.append(b);
		ui.update();
		ui.paint(new Recording());
		check("transitions: a theme's first style jumps", b.style.background == Color.rgb(0x000000));
		ui.pointerMove(b.absX + 5, b.absY + 5);
		ui.update();
		check("transitions: the hover's colour eases", b.style.background == Color.rgb(0x000000) && b.style.target("background") == Color.rgb(0xFFFFFF));
		Clock.finish();
		ui.pointerMove(90, 90);
		ui.update();
		Clock.finish();
		check("transitions: and back, the rules' all along", b.style.background == Color.rgb(0x000000), b.style.background.toHex());
		// (starting rules, as CSS's @starting-style: before the first draw; then eased from)
		ui.theme = {rules: [
			{slot: "pop", style: {opacity: 1, transition: Transition.parse("opacity 100ms linear")}},
			{slot: "pop", when: ["starting"], style: {opacity: 0}}
		]};
		var pop = new Node("pop");
		pop.slot = "pop";
		pop.style.set({width: 10, height: 10});
		ui.root.append(pop);
		ui.update();
		var first = pop.style.opacity;
		ui.paint(new Recording());
		ui.update();
		Clock.tick(200);
		Clock.tick(200.05);
		var mid = pop.style.opacity;
		Clock.finish();
		check("themes: starting rules before the first draw, then eased from", first == 0 && mid > 0.4 && mid < 0.6 && pop.style.opacity == 1,
			first + " " + mid + " " + pop.style.opacity);
		ui.root.remove(pop);
		ui.root.append(pop);
		ui.update();
		check("themes: again when it comes back", pop.style.opacity == 0, "" + pop.style.opacity);
		Clock.finish();
		// (one side of padding from one rule over the four from another; an auto margin from a rule)
		ui.theme = {rules: [
			{slot: "p", style: {padding: [8, 16]}},
			{slot: "p", when: ["data-dense"], style: {paddingTop: 2}},
			{slot: "row", style: {direction: Row, width: 100}},
			{slot: "end", style: {width: 10, height: 10, marginLeft: Edges.AUTO}}
		]};
		var pn = new Node("p"), row = new Node("row"), end = new Node("end");
		pn.slot = "p";
		row.slot = "row";
		end.slot = "end";
		row.append(end);
		ui.root.append(pn);
		ui.root.append(row);
		pn.setAttr("data-dense", "");
		ui.update();
		ui.update();
		check("themes: padding-top over padding, an auto margin (ml-auto)", pn.style.padding.top == 2 && pn.style.padding.left == 16
			&& pn.style.padding.bottom == 8 && end.x == 90, pn.style.padding.top + " " + end.x);
		pn.setAttr("data-dense", null);
		ui.update();
		check("themes: the side back with the rule gone", pn.style.padding.top == 8 && pn.style.padding.left == 16, "" + pn.style.padding.top);
		ui.root.remove(pn);
		ui.root.remove(row);
		// (rules for a breakpoint: the window at least so wide; again across it)
		ui.theme = {rules: [{slot: "w", style: {opacity: 0.5}}, {slot: "w", when: ["md"], style: {opacity: 0.75}}]};
		var wide = new Node("w");
		wide.slot = "w";
		ui.root.append(wide);
		ui.update();
		var narrow = wide.style.opacity;
		ui.resize(800, 100);
		ui.update();
		check("themes: md rules from 768 pixels wide", narrow == 0.5 && wide.style.opacity == 0.75, narrow + " " + wide.style.opacity);
		ui.resize(100, 100);
		// (a rule for right to left: again when the direction changes)
		ui.theme = {rules: [{slot: "t", style: {opacity: 0.5}}, {slot: "t", when: ["rtl"], style: {opacity: 0.25}}]};
		var th = new Node("t");
		th.slot = "t";
		ui.root.append(th);
		ui.update();
		var ltr = th.style.opacity;
		ui.root.style.dir = Rtl;
		ui.update();
		check("themes: rtl rules, again when the direction changes", ltr == 0.5 && th.style.opacity == 0.25, ltr + " " + th.style.opacity);
		ui.root.style.dir = null;
		ui.theme = null;
	}

	static function themes() {
		var ui = new Ui(new MonoText(), 200, 100);
		ui.root.style.alignItems = Start;
		var sheet:StyleSheet = {
			rules: [
				{slot: "button", style: {background: Color.parse("var(--primary)"), radius: 6, padding: 8}},
				{slot: "button", when: ["hover"], style: {background: Color.parse("var(--primary)/50")}},
				{slot: "button", variant: "outline", style: {background: Color.TRANSPARENT, borderWidth: 1, borderColor: Color.parse("var(--border)")}},
				{slot: "button", size: "sm", style: {padding: 4}},
				{slot: "button", when: ["focus-visible"], style: {shadow: Shadow.parse("0 0 0 3px var(--ring)/50")}},
				{slot: "button", when: ["dark"], style: {radius: 2}},
				{slot: "switch", style: {background: Color.parse("var(--input)")}},
				{slot: "switch", when: ["data-state=checked"], style: {background: Color.parse("var(--primary)")}},
				{slot: "input", when: ["placeholder"], style: {color: Color.parse("var(--muted-foreground)")}},
				{slot: "input", when: ["selection"], style: {background: Color.parse("var(--primary)/30")}}
			],
			light: ["primary" => Color.rgb(0x171717), "border" => Color.rgb(0xE5E5E5), "ring" => Color.rgb(0xA1A1A1), "input" => Color.rgb(0xE5E5E5),
				"muted-foreground" => Color.rgb(0x737373)],
			dark: ["primary" => Color.rgb(0xE5E5E5), "border" => Color.rgb(0x262626), "ring" => Color.rgb(0x737373), "input" => Color.rgb(0x333333),
				"muted-foreground" => Color.rgb(0xA1A1A1)]
		};
		var a = new Node("a"), b = new Node("b"), own = new Node("own"), sw = new Node("sw");
		for (n in [a, b, own, sw]) {
			n.style.set({width: 30, height: 20});
			ui.root.append(n);
		}
		a.slot = b.slot = own.slot = "button";
		b.variant = "outline";
		b.size = "sm";
		own.style.background = Color.rgb(0xFF0000);
		sw.slot = "switch";
		ui.update();
		check("themes: no sheet, no style", a.style.background == Color.TRANSPARENT && a.style.radius == 0);
		ui.theme = sheet;
		ui.update();
		ui.update();
		check("themes: a slot's rules, tokens resolved", a.style.background == Color.rgb(0x171717) && a.style.radius == 6 && a.style.padding.left == 8);
		ui.update();
		check("themes: a variant's and a size's rules after the slot's", b.style.background == Color.TRANSPARENT && b.style.borderWidth == 1
			&& b.style.borderColor == Color.rgb(0xE5E5E5) && b.style.padding.left == 4 && b.style.radius == 6);
		ui.update();
		check("themes: the node's own style wins", own.style.background == Color.rgb(0xFF0000) && own.style.radius == 6);
		// (hover: on and off again)
		ui.pointerMove(a.absX + 5, a.absY + 5);
		ui.update();
		check("themes: hover, an alpha on the token", a.style.background == Color.rgb(0x171717).fade(0.5), StringTools.hex(a.style.background));
		ui.pointerMove(190, 90);
		ui.update();
		check("themes: hover left", a.style.background == Color.rgb(0x171717));
		// (an attribute's state)
		ui.update();
		check("themes: an attribute's state, off", sw.style.background == Color.rgb(0xE5E5E5));
		sw.setAttr("data-state", "checked");
		ui.update();
		check("themes: data-state=checked", sw.style.background == Color.rgb(0x171717));
		sw.setAttr("data-state", "unchecked");
		ui.update();
		check("themes: data-state=unchecked", sw.style.background == Color.rgb(0xE5E5E5));
		// (focus-visible: a ring as a shadow, its token resolved)
		a.focusable = true;
		ui.keyDown(Key.TAB, 0);
		ui.update();
		check("themes: focus-visible", ui.focus == a && a.style.shadow != null && a.style.shadow.spread == 3 && a.style.shadow.color == Color.rgb(0xA1A1A1).fade(0.5));
		ui.pointerDown(190, 90, 1);
		ui.pointerUp(190, 90, 1);
		ui.update();
		check("themes: no ring after a press", a.style.shadow == null);
		// (dark: the dark colours, the rules for dark)
		ui.dark = true;
		ui.update();
		check("themes: dark", a.style.background == Color.rgb(0xE5E5E5) && a.style.radius == 2 && sw.style.background == Color.rgb(0x333333));
		ui.dark = false;
		ui.update();
		check("themes: light again", a.style.background == Color.rgb(0x171717) && a.style.radius == 6);
		// (a subtree's own sheet)
		var other:StyleSheet = {rules: [{slot: "button", style: {background: Color.rgb(0x00FF00)}}]};
		var box = new Node("box"), inner = new Node("inner");
		inner.slot = "button";
		box.append(inner);
		ui.root.append(box);
		box.theme = other;
		ui.update();
		check("themes: a subtree's sheet", inner.style.background == Color.rgb(0x00FF00) && inner.style.radius == 0);
		box.theme = null;
		ui.update();
		check("themes: the window's again", inner.style.background == Color.rgb(0x171717) && inner.style.radius == 6);
		// (a placeholder's colour)
		var f = new TextField("");
		f.slot = "input";
		ui.root.append(f);
		ui.update();
		check("themes: a placeholder's colour, a selection's", f.placeholderColor == Color.rgb(0x737373) && f.selectionColor == Color.rgb(0x171717).fade(0.3));
		// (no sheet: what the rules wrote taken back, the node's own kept)
		ui.theme = null;
		ui.update();
		check("themes: taken back", a.style.background == Color.TRANSPARENT && a.style.radius == 0 && a.style.padding.left == 0 && b.style.borderWidth == 0
			&& own.style.background == Color.rgb(0xFF0000) && f.placeholderColor == Color.rgba(0, 0.4) && f.selectionColor == Color.rgba(0x3B82F6, 0.3));
		// (a change of the node's own after the rules: kept)
		ui.theme = sheet;
		a.style.radius = 9;
		a.variant = "outline";
		ui.update();
		check("themes: a value set over the rules' kept", a.style.radius == 9 && a.style.borderWidth == 1);
		// (tokens and oklch() in colours)
		var t = Color.parse("var(--ring)/50");
		ui.update();
		check("themes: token references", t.isToken && t.tokenName() == "ring" && t.tokenAlpha() == 0.5 && !Color.parse("rgba(255, 0, 0, 0)").isToken
			&& Color.parse("oklch(0.205 0 0)") == Color.rgb(0x171717) && Color.parse("oklch(0.577 0.245 27.325)") == Color.rgb(0xE7000B)
			&& Color.parse("oklch(1 0 0 / 10%)") == Color.rgba(0xFFFFFF, 0.1));
	}

	// --- paint ---

	static function paint() {
		var ui = new Ui(new MonoText(), 200, 100);
		var a = new Node();
		a.style.set({width: 100, height: 50, radius: 8, borderWidth: 2, background: Color.WHITE, borderColor: Color.BLACK,
			overflow: Hidden, shadow: Shadow.parse("1px 2px 6px 3 #00000080")});
		a.style.margin = 10;
		ui.root.append(a);
		var b = new Node();
		b.style.set({height: 10, background: Color.rgb(0xFF0000)});
		a.append(b);
		ui.update();
		var c = new Recording();
		ui.paint(c);
		var want = [
			"shadow 8 9 106 56 11 80000000 6",
			"rect 10 10 100 50 8 ffffffff 2 ff000000",
			"clip 12 12 96 46 6",
			"rect 12 12 96 10 0 ffff0000 0 0",
			"pop"
		];
		check("paint: calls", c.calls.join("|") == want.join("|"), c.calls.join("|"));
		// (a ring and its offset: over the shadow, as Tailwind composes them; each from its own property)
		a.style.set({ringWidth: 3, ringColor: Color.rgb(0xFF0000), ringOffsetWidth: 2});
		var r = new Recording();
		ui.paint(r);
		check("paint: a ring and its offset over the shadow", r.calls[0] == want[0] && r.calls[1] == "shadow 5 5 110 60 13 ffff0000 0"
			&& r.calls[2] == "shadow 8 8 104 54 10 ffffffff 0" && r.calls[3] == want[1], r.calls.slice(0, 4).join("|"));
		a.style.set({ringWidth: 0, ringOffsetWidth: 0});
		var sh = Shadow.parse("0 4");
		check("paint: Shadow.parse defaults", sh.x == 0 && sh.y == 4 && sh.blur == 0 && sh.spread == 0 && sh.color == 0x40000000);
		var threw = try {
			Shadow.parse("4");
			false;
		} catch (e:Dynamic) true;
		check("paint: Shadow.parse rejects one length", threw);
		var list = Shadow.parse("0 0 0 3px #3b82f6, inset 0 1px 3px rgba(0, 0, 0, 0.5)");
		check("paint: Shadow.parse, a list with inset and rgba()", list.spread == 3 && !list.inset && list.next != null && list.next.inset && list.next.y == 1
			&& list.next.blur == 3 && list.next.color == Color.rgba(0, 0.5) && list.next.next == null && list.painted()[0] == list.next);
		var ui2 = new Ui(new MonoText(), 200, 100);
		ui2.root.style.alignItems = Start;
		var sb = new Node("sb");
		sb.style.set({width: 40, height: 20, background: Color.rgb(0xFFFFFF), borderWidth: 2, borderColor: Color.rgb(0), shadow: list});
		ui2.root.append(sb);
		ui2.update();
		var rec2 = new Recording();
		ui2.paint(rec2);
		var kinds = [for (c in rec2.calls) c.split(" ")[0]];
		check("paint: outer shadows under the background, inset ones over it in the padding box", kinds.join(",") == "shadow,rect,inset"
			&& rec2.calls[2].indexOf("inset 2 2 36 16 0 ") == 0, rec2.calls.join("|"));
		// "none": no shadow; as a text shadow, stopping the parent's
		sb.style.shadow = Shadow.parse(" none ");
		var rec3 = new Recording();
		ui2.paint(rec3);
		check("paint: Shadow.parse(\"none\") draws none", sb.style.shadow == Shadow.NONE && rec3.calls.join("|").indexOf("shadow") < 0, rec3.calls.join("|"));
		// text shadows: inherited, under the text and its underline (the
		// last first), without a colour the text's; "none" stopping them
		var ui3 = new Ui(new MonoText(), 200, 100);
		ui3.root.style.alignItems = Start;
		var box = new Node("box");
		box.style.set({textShadow: Shadow.parse("1 2 4 #ff0000, -1 0"), color: Color.rgb(0x0000FF)});
		var t = new TextNode("ab");
		t.style.textDecoration = (TextDecoration.Underline : Int);
		box.append(t);
		var plain = new TextNode("cd");
		plain.style.textShadow = Shadow.NONE;
		box.append(plain);
		ui3.root.append(box);
		ui3.update();
		var rec4 = new Recording();
		ui3.paint(rec4);
		var calls = rec4.calls.join("|");
		var underline = [for (c in rec4.calls) if (c.indexOf("rect ") == 0) c];
		check("paint: text shadows, the last first, each under the text", rec4.calls.length == 7 && rec4.calls[1].indexOf("textShadow -1 0 ") == 0
			&& StringTools.endsWith(rec4.calls[1], " ff0000ff 0") && rec4.calls[3].indexOf("textShadow 1 2 ") == 0
			&& StringTools.endsWith(rec4.calls[3], " ffff0000 4") && rec4.calls[5].indexOf("text 0 0 ") == 0 && rec4.calls[6].indexOf("text 0 18 ") == 0, calls);
		check("paint: a text shadow's underline: offset, blurred as a box shadow", rec4.calls[0].indexOf("rect -1 ") == 0
			&& rec4.calls[2].indexOf("shadow 1 ") == 0 && StringTools.endsWith(rec4.calls[2], " ffff0000 4") && underline.length == 2, calls);
		check("paint: Shadow.NONE stops an inherited text shadow", t.textShadow() == box.style.textShadow && plain.textShadow() == null);
		// text-decoration-color: the lines' own colour, the glyphs keeping theirs
		t.style.set({textDecorationColor: Color.rgb(0x00FF00), textShadow: Shadow.NONE});
		var rec5 = new Recording();
		ui3.paint(rec5);
		var lines = [for (c in rec5.calls) if (c.indexOf("rect ") == 0) c];
		check("paint: text-decoration-color", lines.length == 1 && lines[0].indexOf(" ff00ff00 ") > 0 && rec5.calls.join("|").indexOf("text 0 0 14") >= 0,
			rec5.calls.join("|"));
		// its thickness (a percentage of the font size) and the underline's offset (inherited)
		var before = lines[0].split(" ");
		t.style.textDecorationThickness = "25%";
		box.style.textUnderlineOffset = 3;
		var rec7 = new Recording();
		ui3.paint(rec7);
		var after = [for (c in rec7.calls) if (c.indexOf("rect ") == 0) c][0].split(" ");
		check("paint: text-decoration-thickness and an inherited text-underline-offset", Std.parseFloat(after[4]) == t.font().size / 4
			&& Std.parseFloat(after[2]) == Std.parseFloat(before[2]) + 3, before.join(" ") + " | " + after.join(" "));
		t.style.textDecorationThickness = "auto";
		box.style.textUnderlineOffset = "auto";
		// an outline: around the border box, over the children, the focus ring over it
		var framed = new Node("framed"), inner = new Node("inner");
		framed.style.set({width: 20, height: 10, radius: 4, outlineWidth: 2, outlineOffset: 1, color: Color.rgb(0x112233)});
		inner.style.set({height: 10, background: Color.rgb(0xFF0000)});
		framed.append(inner);
		framed.focusable = true;
		ui3.root.append(framed);
		ui3.update();
		ui3.keyDown(Key.TAB, 0);
		var rec6 = new Recording();
		ui3.paint(rec6);
		var at = rec6.calls.indexOf("rect " + framed.absX + " " + framed.absY + " 20 10 0 ffff0000 0 0");
		var o = "rect " + (framed.absX - 3) + " " + (framed.absY - 3) + " 26 16 7 0 2 ff112233";
		check("paint: an outline over the children, in the text colour, the ring over it", at >= 0 && rec6.calls[at + 1] == o
			&& rec6.calls[at + 2].indexOf("rect " + (framed.absX - 4)) == 0, rec6.calls.slice(at).join("|"));
		framed.parent.remove(framed);
		ui3.update();
		// a text field's text and placeholder: shadowed too
		var field = new TextField("");
		field.placeholder = "Name";
		field.style.set({width: 80, textShadow: Shadow.parse("0 1 2 #000000")});
		ui3.root.append(field);
		ui3.update();
		function fieldCalls() {
			var r = new Recording();
			ui3.paint(r);
			var at = r.calls.indexOf("clip " + field.absX + " " + field.absY + " 80 " + field.height + " 0");
			return [for (k in at + 1...r.calls.length) if (StringTools.startsWith(r.calls[k], "text")) r.calls[k].split(" ")[0]].join(",");
		}
		var placeholderCalls = fieldCalls();
		field.text = "Bo";
		check("paint: a text field's shadows under its placeholder and its text", placeholderCalls == "textShadow,text" && fieldCalls() == "textShadow,text",
			placeholderCalls + " | " + fieldCalls());
		// the focus ring: shown when Tab moves the focus, hidden by a press
		a.focusable = true;
		ui.keyDown(Key.TAB, 0);
		var c = new Recording();
		ui.paint(c);
		check("paint: the focus ring", ui.focus == a && c.calls[c.calls.length - 1] == "rect 6 6 108 58 12 0 2 ff3b82f6", c.calls[c.calls.length - 1]);
		// (outline-style none: no ring, a theme drawing its own)
		a.style.outlineStyle = None;
		var c2 = new Recording();
		ui.paint(c2);
		check("paint: outline-style none, no focus ring", c2.calls.length == c.calls.length - 1, c2.calls[c2.calls.length - 1]);
		a.style.outlineStyle = null;
		ui.pointerDown(50, 30, 1);
		ui.pointerUp(50, 30, 1);
		var c = new Recording();
		ui.paint(c);
		check("paint: no ring after a press", ui.focus == a && !ui.focusVisible && c.calls.length == want.length);
		// the cursor: the hovered node's, Auto taking the parent's
		check("cursor: Default by default", ui.cursor() == Default);
		a.style.cursor = Pointer;
		ui.pointerMove(50, 15);
		check("cursor: inherited from the parent", ui.hover == b && ui.cursor() == Pointer);
		b.style.cursor = Text;
		check("cursor: the node's own", ui.cursor() == Text);
		ui.pointerMove(190, 90);
		check("cursor: outside", ui.cursor() == Default);
	}

	// --- layout against Chromium ---

	static function layouts(here:String) {
		var cases:Array<Dynamic> = haxe.Json.parse(sys.io.File.getContent(here + "/layout-cases.json"));
		var expected:Dynamic = haxe.Json.parse(sys.io.File.getContent(here + "/layout-expected.json"));
		for (c in cases) {
			var ui = new Ui(new MonoText(), c.width, c.height);
			build(ui.root, c.tree);
			ui.update();
			var want:Array<Array<Int>> = Reflect.field(expected, c.name);
			var got = [];
			function walk(n:Node) {
				got.push([Std.int(n.absX), Std.int(n.absY), Std.int(n.width), Std.int(n.height)]);
				for (ch in n.children)
					walk(ch);
			}
			walk(ui.root);
			var same = want.length == got.length;
			var detail = [];
			for (i in 0...Std.int(Math.min(want.length, got.length)))
				if (want[i].join(",") != got[i].join(",")) {
					same = false;
					detail.push('box $i: [${got[i].join(", ")}], Chromium [${want[i].join(", ")}]');
				}
			check('layout: ${c.name}', same, detail.join("; "));
		}
	}

	static function build(n:Node, d:Dynamic) {
		var style:Dynamic = d.style;
		if (style != null)
			for (k in Reflect.fields(style))
				setStyle(n.style, k, Reflect.field(style, k));
		var children:Array<Dynamic> = d.children;
		if (children != null)
			for (c in children) {
				var ch = new Node();
				n.append(ch);
				build(ch, c);
			}
	}

	static function dim(v:Dynamic):Dim {
		if (Std.isOfType(v, String)) {
			var s:String = v;
			return s == "auto" || StringTools.endsWith(s, "content") ? Dim.parse(s) : Percent(Std.parseFloat(s.substr(0, s.length - 1)));
		}
		return Px(v);
	}

	static function setStyle(s:Style, k:String, v:Dynamic) {
		switch k {
			case "width": s.width = dim(v);
			case "height": s.height = dim(v);
			case "minWidth": s.minWidth = dim(v);
			case "minHeight": s.minHeight = dim(v);
			case "maxWidth": s.maxWidth = dim(v);
			case "maxHeight": s.maxHeight = dim(v);
			case "basis": s.basis = dim(v);
			case "left": s.left = dim(v);
			case "top": s.top = dim(v);
			case "right": s.right = dim(v);
			case "bottom": s.bottom = dim(v);
			case "grow": s.grow = v;
			case "shrink": s.shrink = v;
			case "aspectRatio": s.aspectRatio = v;
			case "wrap": s.wrap = v;
			case "rowGap": s.rowGap = v;
			case "columnGap": s.columnGap = v;
			case "gap": s.gap = v;
			case "inset": s.inset = (v : Float);
			case "flex": s.flex = v;
			case "borderWidth": s.borderWidth = v;
			case "borders": s.borders = (v : Array<Float>);
			case "padding": s.padding = Std.isOfType(v, Array) ? (v : Array<Float>) : (v : Float);
			// ("auto": NaN)
			case "margin": s.margin = Std.isOfType(v, Array) ? [for (x in (v : Array<Dynamic>)) x == "auto" ? Math.NaN : (x : Float)] : v == "auto" ? Math.NaN : (v : Float);
			case "dir": s.dir = v == "Rtl" ? Rtl : Ltr;
			case "order": s.order = v;
			case "direction": s.direction = switch (v : String) {
					case "Row": Row;
					case "RowReverse": RowReverse;
					case "ColumnReverse": ColumnReverse;
					case _: Column;
				}
			case "justify": s.justify = switch (v : String) {
					case "End": End;
					case "Center": Center;
					case "SpaceBetween": SpaceBetween;
					case "SpaceAround": SpaceAround;
					case "SpaceEvenly": SpaceEvenly;
					case _: Start;
				}
			case "alignItems" | "alignSelf" | "justifyItems" | "justifySelf":
				var a:Align = switch (v : String) {
					case "Start": Start;
					case "End": End;
					case "Center": Center;
					case "Stretch": Stretch;
					case "Baseline": Baseline;
					case _: Auto;
				}
				switch k {
					case "alignItems": s.alignItems = a;
					case "alignSelf": s.alignSelf = a;
					case "justifyItems": s.justifyItems = a;
					case _: s.justifySelf = a;
				}
			case "gridTemplateColumns": s.gridTemplateColumns = Grid.tracks(v);
			case "gridTemplateRows": s.gridTemplateRows = Grid.tracks(v);
			case "gridAutoColumns": s.gridAutoColumns = Grid.tracks(v)[0];
			case "gridAutoRows": s.gridAutoRows = Grid.tracks(v)[0];
			case "gridAutoFlow": s.gridAutoFlow = switch v {
					case "Column": Grid.GridFlow.Column;
					case "RowDense": Grid.GridFlow.RowDense;
					case "ColumnDense": Grid.GridFlow.ColumnDense;
					case _: Grid.GridFlow.Row;
				}
			case "gridColumn": s.gridColumn = Grid.GridPlacement.parse(Std.string(v));
			case "gridRow": s.gridRow = Grid.GridPlacement.parse(Std.string(v));
			case "gridArea": s.gridArea = Std.string(v);
			case "gridTemplateAreas": s.gridTemplateAreas = Grid.GridAreas.parse(v);
			case "alignContent": s.alignContent = switch (v : String) {
					case "End": End;
					case "Center": Center;
					case "Stretch": Stretch;
					case "SpaceBetween": SpaceBetween;
					case "SpaceAround": SpaceAround;
					case "SpaceEvenly": SpaceEvenly;
					case _: Start;
				}
			case "position": s.position = v == "Absolute" ? Absolute : Relative;
			case "display": s.display = v == "None" ? None : v == "Grid" ? Grid : Flex;
			case "overflow": s.overflow = v == "Hidden" ? Hidden : v == "Scroll" ? Scroll : Visible;
			case _: throw "UiTest: no style " + k;
		}
	}

	// --- text ---

	static function texts() {
		var ui = new Ui(new MonoText(), 200, 200);
		ui.root.style.fontSize = 16;
		ui.root.style.lineHeight = 1.5;
		ui.root.style.alignItems = Start;
		var t = new TextNode("hello world");
		ui.root.append(t);
		ui.update();
		check("text: one line", t.width == 88 && t.height == 24, '$t');
		t.text = "the quick brown fox jumps over the lazy dog";
		ui.update();
		// (25 characters a line at 8 pixels: three lines)
		check("text: wrapped to the parent", t.width == 200 && t.height == 48, '$t');
		var row = new Node();
		row.style.direction = Row;
		row.style.width = 100;
		row.style.alignItems = Start;
		var a = new TextNode("aaa bbb");
		var b = new TextNode("cc");
		a.style.fontSize = 8;
		row.append(a);
		row.append(b);
		ui.root.append(row);
		ui.update();
		check("text: inherited and own font sizes", a.width == 28 && a.height == 12 && b.x == 28 && b.width == 16 && b.height == 24, '$a $b');
		var p = a.laidOut();
		check("text: paragraph", p != null && p.lineCount == 1 && p.caret(3).x == 12);
		check("text: font resolves", b.font().size == 16 && b.font().lineHeight == 1.5 && a.font().size == 8);
		// a long word in a narrow column: cut
		var narrow = new TextNode("abcdefghij");
		narrow.style.width = 40;
		ui.root.append(narrow);
		ui.update();
		check("text: a word cut to the width", narrow.height == 48, '$narrow');
	}

	// --- events ---

	static function events() {
		var ui = new Ui(new MonoText(), 300, 200);
		var log = [];
		var panel = new Node("panel");
		panel.style.direction = Row;
		panel.style.padding = 10;
		panel.style.columnGap = 10;
		var a = new Node("a"), b = new Node("b"), inner = new Node("inner");
		for (n in [a, b]) {
			n.style.width = 100;
			n.style.height = 50;
			n.focusable = true;
			panel.append(n);
		}
		inner.style.width = 20;
		inner.style.height = 20;
		b.append(inner);
		ui.root.append(panel);
		for (n in [ui.root, panel, a, b, inner]) {
			var name = n.tag;
			n.onPointerDown = e -> log.push('down $name<-${e.target.tag}');
			n.onClick = e -> log.push('click $name');
			n.onPointerEnter = e -> log.push('enter $name');
			n.onPointerLeave = e -> log.push('leave $name');
			n.onFocus = e -> log.push('focus $name');
			n.onBlur = e -> log.push('blur $name');
			n.onKeyDown = e -> log.push('key $name ${e.key}');
		}
		ui.update();
		check("events: hit test", ui.root.hitTest(15, 15) == a && ui.root.hitTest(125, 15) == inner && ui.root.hitTest(150, 40) == b
			&& ui.root.hitTest(5, 5) == panel && ui.root.hitTest(250, 150) == ui.root);
		ui.pointerMove(130, 15);
		check("events: enter, outermost first", log.join("|") == "enter root|enter panel|enter b|enter inner", log.join("|"));
		log.resize(0);
		ui.pointerMove(150, 40);
		check("events: leave the child only", log.join("|") == "leave inner" && b.hovered && !inner.hovered, log.join("|"));
		log.resize(0);
		inner.onClick = e -> {
			log.push("click inner (stopped)");
			e.stop();
		};
		ui.pointerDown(125, 15, 1);
		// (inner is entered again: the pointer moved onto it)
		check("events: down bubbles, then focus", log.join("|") == "enter inner|down inner<-inner|down b<-inner|down panel<-inner|down root<-inner|focus b"
			&& ui.focus == b && b.focused && inner.pressed && b.pressed, log.join("|"));
		log.resize(0);
		ui.pointerUp(126, 16, 1);
		check("events: click stopped at the target", log.join("|") == "click inner (stopped)" && !inner.pressed, log.join("|"));
		log.resize(0);
		// released elsewhere: no click
		ui.pointerDown(20, 20, 1);
		ui.pointerUp(250, 150, 1);
		check("events: no click when released outside", log.indexOf("click a") < 0 && ui.focus == a, log.join("|"));
		log.resize(0);
		ui.keyDown(Key.TAB, 0);
		check("events: Tab moves the focus", log.join("|") == "key a 65289|key panel 65289|key root 65289|blur a|focus b" && ui.focus == b, log.join("|"));
		ui.keyDown(Key.TAB, 0);
		check("events: Tab wraps", ui.focus == a);
		ui.keyDown(Key.TAB, Key.MOD_SHIFT);
		check("events: Shift+Tab goes back", ui.focus == b);
		log.resize(0);
		ui.pointerDown(250, 150, 1);
		check("events: a click outside focusables blurs", ui.focus == null && log.indexOf("blur b") >= 0, log.join("|"));
		ui.pointerUp(250, 150, 1);
		// removing the hovered node
		ui.pointerMove(125, 15);
		b.remove(inner);
		check("events: a removed node is no longer hovered", ui.hover == null || ui.hover != inner);

		// scrolling
		var ui = new Ui(new MonoText(), 100, 100);
		var list = new Node("list");
		list.style.height = 100;
		list.style.overflow = Scroll;
		for (i in 0...10) {
			var item = new Node("item" + i);
			item.style.height = 30;
			item.style.shrink = 0;
			list.append(item);
		}
		ui.root.append(list);
		ui.update();
		check("scroll: content height", list.contentHeight == 300, '${list.contentHeight}');
		ui.wheel(50, 50, 0, 50);
		check("scroll: by the wheel", list.scrollY == 50);
		check("scroll: hit test follows", ui.root.hitTest(50, 15).tag == "item2", ui.root.hitTest(50, 15).tag);
		ui.wheel(50, 50, 0, 1000);
		check("scroll: clamped", list.scrollY == 200);
		ui.wheel(50, 50, 0, -5000);
		check("scroll: back to the top", list.scrollY == 0);
		// (overflow-y hidden: still clipped, not scrolled by the wheel, no scrollbar; scrollTo still moves it)
		list.style.overflowY = Hidden;
		ui.wheel(50, 50, 0, 50);
		var r = new Recording();
		ui.paint(r);
		var thumbs = r.calls.filter(c -> StringTools.startsWith(c, "rect 92")).length;
		ui.scrollTo(list, 0, 30);
		check("scroll: overflow-y hidden: clipped, not scrolled by the wheel, scrolled by scrollTo", list.style.overflow == Scroll && thumbs == 0
			&& list.scrollY == 30, list.scrollY + " " + thumbs);
		list.style.overflowY = Scroll;
		ui.scrollTo(list, 0, 0);
		// the keys, when the focus takes none of them: arrows by 40, pages by seven eighths, the ends; eased on the clock
		var item1 = list.children[1];
		item1.focusable = true;
		ui.setFocus(item1, false);
		ui.keyDown(Key.DOWN, 0);
		var mid = -1.0;
		Clock.tick(Clock.now + ui.scrollDuration / 2);
		mid = list.scrollY;
		Clock.finish();
		check("scroll keys: an arrow, eased", list.scrollY == 40 && mid > 0 && mid < 40, mid + " " + list.scrollY);
		ui.keyDown(Key.DOWN, 0);
		ui.keyDown(Key.DOWN, 0);
		Clock.finish();
		check("scroll keys: twice before it ends, twice as far", list.scrollY == 120, "" + list.scrollY);
		ui.keyDown(Key.PAGE_UP, 0);
		Clock.finish();
		check("scroll keys: a page up", list.scrollY == 120 - 87.5, "" + list.scrollY);
		ui.keyDown(Key.END, 0);
		Clock.finish();
		var end = list.scrollY;
		ui.keyDown(Key.SPACE, Key.MOD_SHIFT);
		Clock.finish();
		var shiftSpace = list.scrollY;
		ui.keyDown(Key.HOME, 0);
		Clock.finish();
		check("scroll keys: the end, Shift+Space up a page, home", end == 200 && shiftSpace == 112.5 && list.scrollY == 0, end + " " + shiftSpace + " " + list.scrollY);
		item1.onKeyDown = e -> if (e.key == Key.DOWN) e.preventDefault();
		ui.keyDown(Key.DOWN, 0);
		ui.keyDown(Key.DOWN, Key.MOD_CONTROL);
		Clock.finish();
		check("scroll keys: not a key the focus took, nor with Control", list.scrollY == 0, "" + list.scrollY);
		item1.onKeyDown = null;
		ui.scrollDuration = 0;
		ui.keyDown(Key.PAGE_DOWN, 0);
		check("scroll keys: at once without easing", list.scrollY == 87.5 && !Clock.active, "" + list.scrollY);
		ui.scrollDuration = 0.15;
		ui.scrollTo(list, 0, 0);
		ui.setFocus(null, false);
		// the scrollbar: a track from y 2 of 96 px at x 92, its thumb 96 * 100 / 300 = 32 px
		var clicks = 0;
		for (c in list.children)
			c.onClick = e -> clicks++;
		ui.pointerDown(95, 10, 1);
		ui.pointerMove(95, 42);
		check("scroll: dragging the thumb", list.scrollY == 100, '${list.scrollY}');
		ui.pointerMove(95, 500);
		check("scroll: the drag clamped", list.scrollY == 200, '${list.scrollY}');
		ui.pointerMove(95, 42);
		ui.pointerUp(95, 42, 1);
		ui.pointerDown(95, 90, 1);
		ui.pointerUp(95, 90, 1);
		check("scroll: a press on the track pages", list.scrollY == 200, '${list.scrollY}');
		ui.pointerDown(95, 5, 1);
		ui.pointerUp(95, 5, 1);
		check("scroll: and back", list.scrollY == 100, '${list.scrollY}');
		check("scroll: the scrollbar takes the presses", clicks == 0 && ui.capture == null);
		var c = new Recording();
		ui.paint(c);
		check("scroll: the thumb painted", c.calls[c.calls.length - 1] == "rect 92 34 6 32 3 59000000 0 0", c.calls[c.calls.length - 1]);
	}

	// --- relayout ---

	static function dirty() {
		var ui = new Ui(new MonoText(), 200, 200);
		var a = new Node(), b = new Node();
		a.style.height = 50;
		b.style.height = 50;
		ui.root.append(a);
		ui.root.append(b);
		ui.update();
		check("dirty: first layout", b.y == 50);
		a.style.height = 80;
		check("dirty: marked", @:privateAccess ui.root.dirty);
		ui.update();
		check("dirty: relaid", b.y == 80 && !@:privateAccess ui.root.dirty);
		ui.resize(100, 300);
		ui.update();
		check("dirty: resized", a.width == 100);
		var c = new Node();
		c.style.height = 10;
		ui.root.insert(c, 0);
		ui.update();
		check("dirty: insert", a.y == 10 && b.y == 90);
		ui.root.insert(c, 3);
		ui.update();
		check("dirty: move to the end", a.y == 0 && c.y == 130);
	}
}

// a Canvas that records its calls (UiTest's paint)
class Recording implements Canvas {
	public final calls:Array<String> = [];

	public function new() {}

	static function hex(c:Color):String
		return c == 0 ? "0" : StringTools.hex(c, 8).toLowerCase();

	public function translate(dx:Float, dy:Float)
		calls.push('translate $dx $dy');

	static function cs(c:Null<Corners>):String
		return c == null ? "" : ' corners ${c.topLeft},${c.topRight},${c.bottomRight},${c.bottomLeft}';

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners)
		calls.push('clip $x $y $w $h $radius' + cs(corners));

	public function popClip()
		calls.push("pop");

	public function pushOpacity(a:Float)
		calls.push('opacity $a');

	public function popOpacity()
		calls.push("popOpacity");

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float)
		calls.push('transform $a $b $c $d $e $f');

	public function popTransform()
		calls.push("popTransform");

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges)
		calls.push('rect $x $y $w $h $radius ${hex(fill)} $borderWidth ${hex(border)}' + cs(corners)
			+ (sides == null ? "" : ' sides ${sides.top},${sides.right},${sides.bottom},${sides.left}'));

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>)
		calls.push('shadow $x $y $w $h $radius ${hex(color)} $blur' + cs(corners));

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, dx:Float, dy:Float, spread:Float,
			?corners:Corners)
		calls.push('inset $x $y $w $h $radius ${hex(color)} $blur $dx $dy $spread' + cs(corners));

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>)
		calls.push('text $x $y $width' + (colors == null ? "" : " colors " + [for (c in colors) hex(c)].join(",")));

	public function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>)
		calls.push('textShadow $x $y $width ${hex(color)} $blur' + (colors == null ? "" : " colors " + [for (c in colors) hex(c)].join(",")));

	public function image(img:Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners)
		calls.push('image ${img.width}x${img.height} $x $y $w $h $u0 $v0 $u1 $v1 $radius' + cs(corners));
}

// a clipboard whose reads are answered by the test, later (UiTest's fields)
class LaterClipboard implements ClipboardHost {
	public final waiting:Array<Null<String>->Void> = [];

	public function new() {}

	public function write(text:String) {}

	public function read(callback:Null<String>->Void)
		waiting.push(callback);
}
