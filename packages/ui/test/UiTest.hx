import hxmc.ui.*;
import hxmc.ui.DimValue;
import hxmc.ui.widgets.TextField;
import hxmc.ui.widgets.TextArea;

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
// - fields: TextField's editing and the clipboard (copy, cut, paste), an
//   input method's composition (shown, then committed);
//   TextArea's lines (wrapping, Enter, Up and Down, Home and End, scrolling)
// - popups: placed by their anchors (flipped, kept in the window), drawn
//   and hit over the tree, dismissed by outside presses and Escape, a
//   modal one keeping the focus
// - images: png/*.png decoded (every colour type and depth, tRNS, the
//   filters, Adam7; png-cases.mjs writes them and the pixels expected);
//   jpeg/*.jpg against Chromium's pixels (jpeg-cases.mjs)
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
		images(here);
		fields();
		popups();
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
		// JPEG: jpeg/*.jpg against the pixels Chromium decoded (jpeg-cases.mjs)
		var jdir = here + "/jpeg";
		var cases:Array<{name:String, width:Int, height:Int}> = haxe.Json.parse(sys.io.File.getContent(jdir + "/cases.json"));
		check("jpeg: the cases", cases.length >= 15, '${cases.length}');
		for (c in cases) {
			var want = sys.io.File.getBytes(jdir + "/" + c.name + ".rgba");
			var img = try Image.decode(sys.io.File.getBytes(jdir + "/" + c.name + ".jpg")) catch (e:Dynamic) {
				check("jpeg: " + c.name, false, Std.string(e));
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
			check("jpeg: " + c.name, img.width == c.width && img.height == c.height && differ == 0,
				'${img.width}x${img.height}' + (differ > 0 ? ': $differ values differ, by at most $most (first: pixel ${first >> 2} channel ${first & 3})' : ""));
		}
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
		var c = new Recording();
		ui.paint(c);
		check("images: painted", c.calls.join("|") == "image 40x20 0 0 40 20 0 0 1 1 0|image 40x20 0 20 100 50 0 0 1 1 0|image 40x20 30 110 40 20 0 0 1 1 12", c.calls.join("|"));
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
		// the focus ring: shown when Tab moves the focus, hidden by a press
		a.focusable = true;
		ui.keyDown(Key.TAB, 0);
		var c = new Recording();
		ui.paint(c);
		check("paint: the focus ring", ui.focus == a && c.calls[c.calls.length - 1] == "rect 6 6 108 58 12 0 2 ff3b82f6", c.calls[c.calls.length - 1]);
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

	public function image(img:Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float)
		calls.push('image ${img.width}x${img.height} $x $y $w $h $u0 $v0 $u1 $v1 $radius');
}

// a clipboard whose reads are answered by the test, later (UiTest's fields)
class LaterClipboard implements ClipboardHost {
	public final waiting:Array<Null<String>->Void> = [];

	public function new() {}

	public function write(text:String) {}

	public function read(callback:Null<String>->Void)
		waiting.push(callback);
}
