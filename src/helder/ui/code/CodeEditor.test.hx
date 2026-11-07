package helder.ui.code;

import helder.syntax.Transaction;
import helder.test.Test;
import helder.ui.*;

// helder.ui.code's editor in a Ui (a monospace engine of its own, no
// renderer): keys through the keymap (CodeAction's bindings), typing, an
// input method's context and replacement on the caret's line, the
// pointer (a click, a double click, Alt+click, the gutter), the wheel,
// find and replace, go to line, and what assistive technology reads
function tests() {
	describe("CodeEditor", () -> {
		var ui:Ui = null, editor:CodeEditor = null;
		beforeEach(() -> {
			helder.ui.actions.Keymap.mac = false;
			ui = new Ui(new Mono(), 400, 200);
			editor = new CodeEditor("const a = 1;\nconst b = a + 1;\n\tlet c = <view/>;\n", "x.tsx");
			ui.root.append(editor);
			ui.update();
			ui.paint(new Nothing());
			ui.setFocus(editor.view);
		});
		function key(k:Int, mods = 0, ?text:String) {
			ui.keyDown(k, mods);
			if (text != null) ui.textInput(text);
			ui.keyUp(k, mods);
			ui.update();
			ui.paint(new Nothing());
		}
		test("typed text and keys through the keymap: moves, secondary-D, undo", () -> {
			key(Key.END, Key.MOD_CONTROL);
			equals(editor.model.primary.head, editor.model.length);
			key(Key.HOME, Key.MOD_CONTROL);
			key("x".code, 0, "x");
			equals(editor.text.substr(0, 7), "xconst ");
			key(Key.RIGHT, Key.MOD_CONTROL);
			key(Key.RIGHT, Key.MOD_CONTROL);
			key("d".code, Key.MOD_CONTROL);
			key("d".code, Key.MOD_CONTROL);
			key("d".code, Key.MOD_CONTROL);
			equals(editor.model.sels.length, 2);
			key("z".code, 0, "z");
			equals(editor.text, "xconst z = 1;\nconst b = z + 1;\n\tlet c = <view/>;\n");
			key("z".code, Key.MOD_CONTROL);
			equals(editor.text, "xconst a = 1;\nconst b = a + 1;\n\tlet c = <view/>;\n");
			key(Key.ESCAPE);
			equals(editor.model.sels.length, 1);
		});
		test("Enter keeps the indentation; Tab indents; secondary-/ comments", () -> {
			editor.setSelection(editor.text.indexOf(";\n\tlet") + 1, editor.text.indexOf(";\n\tlet") + 1);
			key(Key.DOWN);
			key(Key.END);
			key(Key.ENTER);
			equals(editor.model.line(3), "\t");
			key("/".code, Key.MOD_CONTROL);
			key(Key.UP);
			key("/".code, Key.MOD_CONTROL);
			equals(editor.model.line(2), "\t// let c = <view/>;");
		});
		test("an input method: the caret's line as its context, its edit there", () -> {
			editor.setSelection(19, 19);
			var c = ui.textContext();
			equals(c.text, "const b = a + 1;");
			equals(c.start, 6);
			ui.replaceText(6, 7, "bee");
			equals(editor.model.line(1), "const bee = a + 1;");
			equals(editor.model.primary.head, 13 + 9);
			editor.view.compose("か", 1);
			equals(editor.view.composition, "か");
			ui.textInput("家");
			equals(editor.view.composition, "");
			equals(editor.model.line(1), "const bee家 = a + 1;");
		});
		test("the pointer: a click, a double click, Alt+click, the gutter; the wheel", () -> {
			var v = editor.view, x0 = v.absX + @:privateAccess v.gutterW + 8, cw = 5.0;
			// (Mono: characters half the size wide; 13 px: 6.5)
			cw = @:privateAccess v.cw;
			ui.pointerDown(x0 + cw * 6 + 1, v.absY + 30, 1);
			ui.pointerUp(x0 + cw * 6 + 1, v.absY + 30, 1);
			equals(editor.model.primary.head, editor.model.lineStart(1) + 6);
			ui.pointerDown(x0 + cw * 6 + 1, v.absY + 30, 1);
			ui.pointerUp(x0 + cw * 6 + 1, v.absY + 30, 1);
			equals(editor.model.primary.toString(), '${editor.model.lineStart(1) + 6}-${editor.model.lineStart(1) + 7}');
			Clock.tick(Clock.now + 1);
			@:privateAccess ui.mods = Key.MOD_ALT;
			ui.pointerDown(x0 + cw * 2, v.absY + 10, 1);
			ui.pointerUp(x0 + cw * 2, v.absY + 10, 1);
			@:privateAccess ui.mods = 0;
			equals(editor.model.sels.length, 2);
			Clock.tick(Clock.now + 1);
			ui.pointerDown(v.absX + 4, v.absY + 50, 1);
			ui.pointerUp(v.absX + 4, v.absY + 50, 1);
			equals(editor.model.primary.toString(), '${editor.model.lineStart(2)}-${editor.model.lineStart(3)}');
			editor.text = [for (i in 0...200) 'line $i'].join("\n");
			ui.update();
			ui.paint(new Nothing());
			ui.wheel(v.absX + 100, v.absY + 50, 0, 100);
			equals(v.scrollTop, 100.0);
		});
		test("find and replace, go to line", () -> {
			key("f".code, Key.MOD_CONTROL);
			assert(editor.findOpen);
			equals(editor.search("const"), 2);
			equals(editor.model.primary.toString(), "0-5");
			assert(editor.findNext(1));
			equals(editor.model.primary.from, editor.model.lineStart(1));
			editor.setReplacement("var");
			equals(editor.replaceAll(), 2);
			equals(editor.model.line(0), "var a = 1;");
			key(Key.ESCAPE);
			assert(!editor.findOpen);
			key("g".code, Key.MOD_CONTROL);
			assert(editor.gotoOpen);
			editor.goToLine(3, 2);
			equals(editor.model.primary.head, editor.model.lineStart(2) + 1);
		});
		test("onChange: a Transaction's changes; decorations and diagnostics", () -> {
			var text = editor.text;
			editor.onChange = cs -> text = new Transaction(cs).apply(text);
			editor.setSelections([0, 0, 13, 13]);
			key("/".code, 0, "/");
			equals(text, editor.text);
			var id = editor.addDecoration(2, 7, Color.rgba(0x3B82F6, 0.1));
			equals(editor.model.decorations.length, 1);
			editor.setDiagnostics([{file: "x.tsx", line: 2, column: 7, endColumn: 8, severity: "error", message: "no b"}]);
			equals(editor.model.diagnostics.length, 1);
			assert(editor.removeDecoration(id));
		});
		test("assistive technology: a multi-line text input, its text, caret and selection", () -> {
			editor.setSelection(6, 7);
			var t = ui.accessTree(), found = null;
			for (n in t.nodes)
				if (n.role == helder.ui.access.Role.MultilineTextInput) found = n;
			assert(found != null);
			equals(found.value, editor.text);
			equals(found.textStart, 6);
			equals(found.textEnd, 7);
			equals(found.caret, 7);
			assert(editor.view.accessSetValue("x"));
			equals(editor.text, "x");
		});
	});
}

// (characters half the size wide, size * lineHeight high, one line per hard break)
private class Mono implements TextEngine {
	public function new() {}

	public function generation():Int
		return 0;

	public function layout(text:String, font:Font, maxWidth:Float, ?spans:Array<TextSpan>, maxLines:Int = 0, justify:Bool = false, base:Int = -1, cut:Float = -1,
			?into:Paragraph):Paragraph
		return new MonoParagraph(text, font.size / 2, font.size * font.lineHeight);
}

private class MonoParagraph implements Paragraph {
	public var width(get, never):Float;
	public var height(get, never):Float;
	public var lineCount(get, never):Int;
	public var minWidth(get, never):Float;
	public var baseline(get, never):Float;

	final text:String;
	final cw:Float;
	final lh:Float;

	public function new(text, cw, lh) {
		this.text = text;
		this.cw = cw;
		this.lh = lh;
	}

	function get_width():Float {
		var w = 0;
		for (l in text.split("\n"))
			if (l.length > w) w = l.length;
		return w * cw;
	}

	function get_height():Float
		return text.split("\n").length * lh;

	function get_lineCount():Int
		return text.split("\n").length;

	function get_minWidth():Float
		return get_width();

	function get_baseline():Float
		return lh * 0.8;

	public function caret(i:Int):{x:Float, y:Float, height:Float}
		return {x: i * cw, y: 0, height: lh};

	public function hit(x:Float, y:Float):Int
		return Std.int(Math.max(0, Math.min(text.length, Math.round(x / cw))));

	public function selection(start:Int, end:Int):Array<{x:Float, y:Float, width:Float}>
		return [{x: start * cw, y: 0, width: (end - start) * cw}];

	public function runs(width:Float, align:TextAlign):Array<GlyphRun>
		return [];

	public function lineWidth(y:Float):Float
		return get_width();

	public function decoration(start:Int, end:Int, kind:TextDecoration, scale:Float, ?thickness:Float, ?offset:Float):Array<{
		x:Float,
		y:Float,
		width:Float,
		height:Float,
		lineWidth:Float
	}>
		return [];
}

// (draws nothing)
private class Nothing implements Canvas {
	public function new() {}

	public function translate(dx:Float, dy:Float) {}

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners) {}

	public function popClip() {}

	public function pushOpacity(alpha:Float) {}

	public function popOpacity() {}

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {}

	public function popTransform() {}

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges) {}

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>) {}

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, dx:Float, dy:Float, spread:Float, ?corners:Corners) {}

	public function path(p:Path, fill:Null<Paint>, ?stroke:Stroke) {}

	public function image(img:helder.image.Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners) {}

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>) {}

	public function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>) {}
}
