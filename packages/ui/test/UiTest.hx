import hxmc.ui.*;
import hxmc.ui.DimValue;

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
		var sh = Shadow.parse("0 4");
		check("paint: Shadow.parse defaults", sh.x == 0 && sh.y == 4 && sh.blur == 0 && sh.spread == 0 && sh.color == 0x40000000);
		var threw = try {
			Shadow.parse("4");
			false;
		} catch (e:Dynamic) true;
		check("paint: Shadow.parse rejects one length", threw);
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
			return s == "auto" ? Auto : Percent(Std.parseFloat(s.substr(0, s.length - 1)));
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
			case "borderWidth": s.borderWidth = v;
			case "padding": s.padding = Std.isOfType(v, Array) ? (v : Array<Float>) : (v : Float);
			case "margin": s.margin = Std.isOfType(v, Array) ? (v : Array<Float>) : (v : Float);
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
			case "alignItems" | "alignSelf":
				var a:Align = switch (v : String) {
					case "Start": Start;
					case "End": End;
					case "Center": Center;
					case "Stretch": Stretch;
					case _: Auto;
				}
				if (k == "alignItems") s.alignItems = a else s.alignSelf = a;
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
			case "display": s.display = v == "None" ? None : Flex;
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

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float)
		calls.push('clip $x $y $w $h $radius');

	public function popClip()
		calls.push("pop");

	public function pushOpacity(a:Float)
		calls.push('opacity $a');

	public function popOpacity()
		calls.push("popOpacity");

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color)
		calls.push('rect $x $y $w $h $radius ${hex(fill)} $borderWidth ${hex(border)}');

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float)
		calls.push('shadow $x $y $w $h $radius ${hex(color)} $blur');

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color)
		calls.push('text $x $y $width');
}
