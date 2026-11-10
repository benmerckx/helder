package helder.ui.widgets;

import helder.test.Test;
import helder.ui.Ui;

// DataGrid on a monospace engine (no gutter but where asked): the keys, a range and its
// text, a press on a cell, the cursor kept in view, the editor
function tests() {
	describe("DataGrid", () -> {
		function grid():{ui:Ui, grid:DataGrid} {
			var ui = new Ui(new Mono(), 400, 214);
			var g = new DataGrid();
			g.rowNumbers = false;
			g.columns = [new GridColumn("id", 60, Right), new GridColumn("name", 200), new GridColumn("note", 200)];
			g.text = (row, col) -> col == 2 && row % 2 == 1 ? null : '$row.$col';
			g.rowCount = 100;
			ui.root.append(g);
			ui.update();
			ui.paint(new Nothing());
			g.focus(false);
			return {ui: ui, grid: g};
		}
		function key(ui:Ui, k:Int, mods = 0) {
			ui.keyDown(k, mods);
			ui.update();
		}
		test("arrows move the cursor, Shift extends the range", () -> {
			var t = grid();
			key(t.ui, Key.DOWN);
			key(t.ui, Key.RIGHT);
			equals([t.grid.cursorRow, t.grid.cursorCol], [1, 1]);
			key(t.ui, Key.DOWN, Key.MOD_SHIFT);
			key(t.ui, Key.RIGHT, Key.MOD_SHIFT);
			equals(t.grid.range(), {top: 1, bottom: 2, left: 1, right: 2});
			equals(t.grid.selectionText(), "1.1\t\n2.1\t2.2");
			key(t.ui, Key.ESCAPE);
			equals(t.grid.range(), {top: 2, bottom: 2, left: 2, right: 2});
		});
		test("the ends and the edges stop the cursor", () -> {
			var t = grid();
			key(t.ui, Key.UP);
			key(t.ui, Key.LEFT);
			equals([t.grid.cursorRow, t.grid.cursorCol], [0, 0]);
			key(t.ui, Key.END, Key.MOD_CONTROL);
			equals([t.grid.cursorRow, t.grid.cursorCol], [99, 2]);
		});
		test("the cursor is kept in view", () -> {
			var t = grid();
			// (180 pixels of rows under the 34 of the header: 6 rows)
			key(t.ui, Key.PAGE_DOWN);
			key(t.ui, Key.PAGE_DOWN);
			equals(t.grid.cursorRow, 10);
			equals(t.grid.scrollTop, 11 * 30.0 - 180);
			key(t.ui, Key.HOME, Key.MOD_CONTROL);
			equals(t.grid.scrollTop, 0.0);
		});
		test("the cursor stays in view when the grid gets shorter", () -> {
			var t = grid();
			// (rows 0 to 5 in view; the last one moved to)
			for (_ in 0...5)
				key(t.ui, Key.DOWN);
			equals(t.grid.scrollTop, 0.0);
			t.ui.resize(400, 214 - 60);
			t.ui.update();
			t.ui.paint(new Nothing());
			equals(t.grid.scrollTop, 6 * 30.0 - (154 - 34));
		});
				test("a press on a cell moves the cursor there, Shift selects to it", () -> {
			var t = grid();
			t.ui.pointerDown(70, 34 + 30 * 2 + 5, 1);
			t.ui.pointerUp(70, 34 + 30 * 2 + 5, 1);
			equals([t.grid.cursorRow, t.grid.cursorCol], [2, 1]);
			t.ui.keyDown(Key.SHIFT, 0);
			t.ui.pointerDown(300, 34 + 30 * 4 + 5, 1);
			t.ui.pointerUp(300, 34 + 30 * 4 + 5, 1);
			equals(t.grid.range(), {top: 2, bottom: 4, left: 1, right: 2});
		});
		test("a LINK cell's arrow shows on its hovered row and follows it", () -> {
			var t = grid();
			var followed = [];
			t.grid.flags = (row, col) -> col == 1 ? DataGrid.LINK : 0;
			t.grid.onLink = (row, col) -> followed.push('$row,$col');
			// (column 1 is 60 to 260; its arrow in its last 22 pixels)
			t.ui.pointerMove(250, 34 + 30 + 5);
			equals(@:privateAccess t.grid.hoverRow, 1);
			t.ui.pointerDown(250, 34 + 30 + 5, 1);
			t.ui.pointerUp(250, 34 + 30 + 5, 1);
			equals(followed, ["1,1"]);
		});
				test("a double click edits the cell; one on a title sorts twice", () -> {
			var t = grid();
			var sorts = [];
			t.grid.onSort = col -> sorts.push(col);
			for (_ in 0...2) {
				t.ui.pointerDown(100, 34 + 30 * 3 + 5, 1);
				t.ui.pointerUp(100, 34 + 30 * 3 + 5, 1);
			}
			t.ui.update();
			equals(t.grid.editor != null, true);
			equals(t.grid.editor.text, "3.1");
			t.grid.cancelEdit();
			for (_ in 0...2) {
				t.ui.pointerDown(100, 10, 1);
				t.ui.pointerUp(100, 10, 1);
			}
			equals(sorts, [1, 1]);
		});
				test("a press in the editor stays in it; its text where the cell's was", () -> {
			var t = grid();
			key(t.ui, Key.ENTER);
			var f = t.grid.editor;
			equals(f != null, true);
			t.ui.pointerDown(f.absX + 4, f.absY + 4, 1);
			t.ui.pointerUp(f.absX + 4, f.absY + 4, 1);
			t.ui.update();
			equals(t.grid.editor, f);
			// (inset 3 in its cell, its padding 3 less: the cell's 10)
			equals(f.absX + f.style.padding.left, 0 + 10.0);
		});
		test("after a press in it, the cursor over a node outside the grid is that node's", () -> {
			var ui = new Ui(new Mono(), 400, 260);
			var button = new Node("button");
			button.style.height = 40;
			button.style.cursor = Pointer;
			var g = new DataGrid();
			g.rowNumbers = false;
			g.columns = [new GridColumn("id", 60), new GridColumn("name", 200)];
			g.rowCount = 10;
			ui.root.append(button);
			ui.root.append(g);
			ui.update();
			ui.paint(new Nothing());
			ui.pointerMove(100, 40 + 34 + 5);
			ui.pointerDown(100, 40 + 34 + 5, 1);
			ui.pointerUp(100, 40 + 34 + 5, 1);
			for (x in [20, 60, 100, 300]) {
				ui.pointerMove(x, 20);
				equals(ui.cursor(), Pointer);
			}
		});
				test("a mouse's notches glide, slowing; a trackpad's deltas land at once", () -> {
			var t = grid();
			// (the first tick long after the last: an idle window's; the glide starts there)
			var t0 = Clock.now + 100;
			t.ui.wheel(100, 100, 0, 90, true);
			t.ui.wheel(100, 100, 0, 90, true);
			Clock.tick(t0);
			equals(t.grid.scrollTop, 0.0);
			Clock.tick(t0 + 0.1);
			assert(t.grid.scrollTop > 0 && t.grid.scrollTop < 180);
			Clock.tick(t0 + 1);
			equals(t.grid.scrollTop, 180.0);
			t.ui.wheel(100, 100, 0, -30);
			equals(t.grid.scrollTop, 150.0);
		});
				test("Enter edits the cell, Enter again keeps it and moves down", () -> {
			var t = grid();
			var kept = [];
			t.grid.onCommit = (row, col, text) -> kept.push('$row,$col=$text');
			key(t.ui, Key.ENTER);
			equals(t.grid.editor != null, true);
			equals(t.grid.editor.text, "0.0");
			t.ui.textInput("7");
			key(t.ui, Key.ENTER);
			equals(kept, ["0,0=7"]);
			equals(t.grid.editor, null);
			equals(t.grid.cursorRow, 1);
		});
		test("painting asks for the rows in view", () -> {
			var t = grid();
			var asked = [];
			t.grid.rowNumbers = true;
			t.grid.onWindow = (first, end) -> asked.push('$first-$end');
			t.grid.refresh();
			t.ui.paint(new Nothing());
			t.grid.scrollTo(0, 300);
			t.ui.paint(new Nothing());
			// (the last row partly in view)
			equals(asked, ["0-7", "10-17"]);
		});
		test("typing starts an edit with what was typed, Escape drops it", () -> {
			var t = grid();
			var kept = 0;
			t.grid.onCommit = (_, _, _) -> kept++;
			t.ui.textInput("x");
			t.ui.update();
			equals(t.grid.editor.text, "x");
			key(t.ui, Key.ESCAPE);
			equals(t.grid.editor, null);
			equals(kept, 0);
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
