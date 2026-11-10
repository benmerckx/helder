package helder.ui.code;

// A code editor's suggestions at the caret (CodeEditor.complete): a list
// drawn under the word they replace, eight rows at most (it scrolls to
// keep the chosen one in view), the chosen one tinted; a row's label, its
// detail quieter at its right. A press on a row chooses and accepts it.
// Colours are the editor's CodeTheme's (its panel, panel border, foreground,
// line numbers and selection).
class CodeCompletion extends Node {
	public var items(default, null):Array<Completion> = [];
	public var chosen(default, null) = 0;
	public var open(default, null) = false;
	// a row pressed
	public var onPick:Null<Int->Void> = null;

	final editor:CodeEditor;
	var first = 0;
	var listFont:Null<Font> = null;
	var fontOf = "";

	static inline var ROWS = 8;
	static inline var PAD = 8.0;

	public function new(editor:CodeEditor) {
		super("code-completion");
		this.editor = editor;
		style.position = Absolute;
		style.display = None;
		semantics = {role: helder.ui.access.Role.ListBox, label: "Suggestions"};
		onPointerDown = e -> {
			var i = first + Std.int(localY(e.x, e.y) / rowHeight());
			if (i >= 0 && i < items.length && onPick != null) {
				chosen = i;
				onPick(i);
			}
			e.preventDefault();
			e.stop();
		};
	}

	inline function rowHeight():Float
		return Math.round(editor.view.fontSize * 1.75);

	// shown with these items, its top left at x, y (the editor's pixels)
	public function show(list:Array<Completion>, x:Float, y:Float) {
		items = list;
		chosen = 0;
		first = 0;
		open = true;
		var w = 220.0;
		if (ui != null) {
			var f = fontFor();
			for (k in 0...Std.int(Math.min(list.length, 50))) {
				var it = list[k];
				var t = ui.text.layout(it.label, f, Math.NaN).width + (it.detail == null ? 0 : ui.text.layout(it.detail, f, Math.NaN).width + 24);
				if (t + PAD * 2 > w) w = t + PAD * 2;
			}
		}
		style.width = Math.min(w, 480);
		style.height = Math.min(list.length, ROWS) * rowHeight() + 2;
		style.left = x;
		style.top = y;
		style.display = Flex;
		describe();
		if (ui != null) ui.requestFrame();
	}

	public function hide() {
		if (!open) return;
		open = false;
		items = [];
		style.display = None;
		if (ui != null) ui.requestFrame();
	}

	// the chosen row moved by d (wrapping)
	public function move(d:Int) {
		if (items.length == 0) return;
		chosen = (chosen + d + items.length) % items.length;
		if (chosen < first) first = chosen;
		if (chosen >= first + ROWS) first = chosen - ROWS + 1;
		describe();
		if (ui != null) ui.requestFrame();
	}

	function describe() {
		var it = items[chosen];
		semantics.valueText = it == null ? null : it.label + (it.detail == null ? "" : ", " + it.detail);
		Ui.accessEpoch++;
	}

	function fontFor():Font {
		var key = editor.view.fontFamily + editor.view.fontSize;
		if (listFont == null || key != fontOf) {
			fontOf = key;
			listFont = new Font(editor.view.fontFamily, editor.view.fontSize, 400, false, 1.2, 0, 0, Normal, Normal, "'liga' 0, 'calt' 0");
		}
		return listFont;
	}

	override public function hasContent():Bool
		return true;

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (ui == null || !open) return;
		var c = editor.view.codeTheme.colors, rh = rowHeight(), f = fontFor();
		canvas.shadow(x, y, width, height, 6, Color.rgba(0, ui.dark ? 0.4 : 0.14), 18, null, [0, 6, 0]);
		canvas.rect(x, y, width, height, 6, c[CodeTheme.PANEL], 1, c[CodeTheme.PANEL_BORDER]);
		canvas.pushClip(x + 1, y + 1, width - 2, height - 2, 5);
		for (k in first...Std.int(Math.min(items.length, first + ROWS))) {
			var it = items[k], ry = y + 1 + (k - first) * rh;
			if (k == chosen) canvas.rect(x + 3, ry + 1, width - 6, rh - 2, 4, c[CodeTheme.SELECTION], 0, 0);
			var detailW = 0.0;
			if (it.detail != null) {
				var d = ui.text.layout(it.detail, f, Math.NaN, null, 1, false, -1, width / 2);
				detailW = d.width + 12;
				canvas.text(d, x + width - PAD - d.width, Math.round(ry + (rh - d.height) / 2), d.width + 1, Left, c[CodeTheme.LINE_NUMBER]);
			}
			var p = ui.text.layout(it.label, f, Math.NaN, null, 1, false, -1, width - PAD * 2 - detailW);
			canvas.text(p, x + PAD, Math.round(ry + (rh - p.height) / 2), width - PAD * 2 - detailW, Left, c[CodeTheme.FOREGROUND]);
		}
		canvas.popClip();
	}
}

// a suggestion: what it shows, a quieter detail (a kind, a type), what it puts in (else its label)
typedef Completion = {label:String, ?detail:String, ?insert:String};

// suggestions for the word that starts at from and ends at the caret
typedef Completions = {from:Int, items:Array<Completion>};
