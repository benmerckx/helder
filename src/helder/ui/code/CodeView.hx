package helder.ui.code;

import helder.syntax.Lexer.TokenClass;
import helder.ui.code.CodeAction;
import helder.ui.code.CodeModel;

// A code editor's text, drawn (CodeEditor's; usable alone): a CodeModel's
// lines virtualised (only the lines in view are highlighted, laid out and
// drawn; a line laid out is kept with it until its text or tokens change,
// and by its content: lines alike share one), in a monospace font
// (JetBrains Mono, bundled; ligatures off unless asked), on a grid of
// columns (tabs to tabSize, wide characters two). A gutter of line
// numbers and diagnostics' markers, the current line, selections,
// cursors that blink and spring to where they go, indentation guides,
// whitespace shown in selections, decorations, find's matches,
// diagnostics' squiggles with their message on hover. Typing, an input
// method's composition (at the primary caret, its text context the
// caret's line: TSF, NSTextInputClient, text-input-v3 and XIM as for
// EditableText), the pointer (a click places the caret, a drag selects,
// a double click a word, a triple click a line, Shift extends, Alt adds a
// cursor; in the gutter, lines) and the wheel; keys are CodeAction's,
// through the keymap. To assistive technology a multi-line text input:
// its text, the primary selection and caret.
class CodeView extends Node {
	public final model:CodeModel;
	public final codeTheme = new CodeTheme();

	// the font: a monospace family (the bundled JetBrains Mono by default), its size, the lines' height in pixels
	public var fontFamily(default, set) = "JetBrains Mono";
	public var fontSize(default, set) = 13.0;
	public var lineHeight(default, set) = 20.0;
	// ligatures (calt, liga): off by default
	public var ligatures(default, set) = false;
	public var lineNumbers = true;
	public var indentGuides = true;

	// the scroll offsets (pixels)
	public var scrollTop(default, null) = 0.0;
	public var scrollLeft(default, null) = 0.0;

	// after each edit, move or change of what is shown (a status bar's line and column)
	public var onUpdate:Null<Void->Void> = null;

	// a find's matches drawn (start, end pairs, in order) and the current one (-1: none)
	public var matches:Array<Int> = [];
	public var currentMatch = -1;

	// (the font laid out with, a character's width, the gutter's)
	var codeFont:Null<Font> = null;
	var cw = 8.0;
	var metricsOf:Null<TextEngine> = null;
	var metricsGeneration = -1;
	var gutterW = 0.0;
	var viewW = 0.0;
	var viewH = 0.0;
	// (the longest line seen, in columns: the horizontal scroll's extent)
	var maxCols = 0;
	// (the primary caret brought into view at the next paint; centred)
	var revealPending = false;
	var revealCenter = false;
	var lastVersion = -1;

	// (lines laid out by their text: lines alike share one; let go when many)
	final shaped = new Map<String, ShapedLine>();
	var shapedCount = 0;
	// (spans by start and end, in the font: kept, a line laid out again makes none)
	final spanPool = new Map<Int, TextSpan>();
	var spanFont:Null<Font> = null;
	final spansScratch:Array<TextSpan> = [];
	final colorScratch:Array<Color> = [];
	final numbers:Array<String> = [];

	// (the cursors as drawn: springing to their targets; columns and lines in pixels from the text's origin)
	final curX:Array<Float> = [];
	final curY:Array<Float> = [];
	final velX:Array<Float> = [];
	final velY:Array<Float> = [];
	final tgtX:Array<Float> = [];
	final tgtY:Array<Float> = [];
	var animating = false;
	var ticking = false;
	var lastTick = -1.0;
	// (the last activity: the caret shown solid, then blinking)
	var activeAt = 0.0;
	final tick:Float->Bool;

	// (clicks in a row, the last one's time and place; a drag's granularity and its first selection)
	var clicks = 0;
	var clickAt = -1e9;
	var clickX = 0.0;
	var clickY = 0.0;
	var dragging = false;
	var dragFrom = 0;
	var dragTo = 0;
	// (the pointer over the text, for a diagnostic's message: window pixels)
	var hoverX = -1.0;
	var hoverY = -1.0;

	// an input method's composition at the primary caret (not in the text until committed)
	public var composition(default, null) = "";
	var compositionCaret = 0;
	// (the caret's place for the input method, the caret line's text context: kept objects)
	final area = {x: 0.0, y: 0.0, width: 1.0, height: 0.0};
	final context = {text: "", start: 0, end: 0, multiline: true, secret: false};
	var contextLineStart = 0;
	var caretShown = false;
	final bounds = new Bounds();

	// the space left of the text, right of the gutter (pixels)
	static inline var PAD = 8.0;

	public function new(?model:CodeModel) {
		super("code-view");
		this.model = model ?? new CodeModel();
		CodeActions.declare();
		addFont();
		focusable = true;
		style.grow = 1;
		style.shrink = 1;
		style.minHeight = 0;
		style.minWidth = 0;
		style.overflow = Hidden;
		style.cursor = Text;
		keyContext = helder.ui.actions.KeyContext.parse("CodeEditor");
		semantics = {role: helder.ui.access.Role.MultilineTextInput, label: "Code editor"};
		tick = t -> step(t);
		onKeyDown = e -> {
			// (a character typed: text input's, not a shortcut: the keymap not asked)
			if (e.mods & (Key.MOD_CONTROL | Key.MOD_ALT | Key.MOD_META) == 0 && e.key >= 0x20 && e.key < 0xFF00) e.stop();
		};
		onTextInput = e -> {
			if (e.text == "") return;
			if (composition != "") composition = "";
			if (e.text.length == 1 || e.text.length == 2 && StringTools.fastCodeAt(e.text, 0) >= 0xD800) this.model.type(e.text) else this.model.insert(e.text, CodeModel.TYPE);
			changed();
		};
		onComposition = e -> compose(e.text, e.caret);
		onPointerDown = pointerDown;
		onPointerMove = pointerMove;
		onPointerUp = e -> dragging = false;
		onPointerLeave = e -> {
			hoverX = hoverY = -1;
			if (ui != null) ui.requestFrame();
		};
		onWheel = e -> {
			var dx = e.deltaX, dy = e.deltaY;
			if (e.mods & Key.MOD_SHIFT != 0 && dx == 0) {
				dx = dy;
				dy = 0;
			}
			if (scrollTo(scrollLeft + dx, scrollTop + dy)) e.preventDefault();
		};
		onFocus = e -> {
			activeAt = Ui.now();
			startTicking();
			changed(false);
		};
		onBlur = e -> {
			if (composition != "") compose("", 0);
			changed(false);
		};
		this.model.onChange = null;
	}

	// (the bundled font added to helder.text's, once)
	static var fontAdded = false;

	static function addFont() {
		if (fontAdded) return;
		fontAdded = true;
		#if !macro
		try helder.text.SystemFonts.get().add(helder.asset.Asset.embed("helder/ui/code/fonts/JetBrainsMono-Regular.ttf")) catch (e:Dynamic) {}
		#end
	}

	function set_fontFamily(v:String):String {
		fontFamily = v;
		codeFont = null;
		return v;
	}

	function set_fontSize(v:Float):Float {
		fontSize = v;
		codeFont = null;
		return v;
	}

	function set_lineHeight(v:Float):Float {
		lineHeight = v;
		codeFont = null;
		return v;
	}

	function set_ligatures(v:Bool):Bool {
		ligatures = v;
		codeFont = null;
		return v;
	}

	override public function hasContent():Bool
		return true;

	override public function measureContent(engine:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):Size {
		// (as wide as it is given, three lines high: it grows into the room it has)
		var w = !Math.isNaN(knownWidth) ? knownWidth : !Math.isNaN(availWidth) ? availWidth : 480;
		return new Size(w, !Math.isNaN(knownHeight) ? knownHeight : lineHeight * 3);
	}

	override public function minContentWidth(engine:TextEngine):Float
		return 0;

	// (keys that type are its: not shortcuts, not the window's scrolling)
	override public function takesText():Bool
		return true;

	// ---- the model changed (an edit, a move): drawn again, the caret brought into view

	public function changed(reveal = true) {
		if (reveal) revealPending = true;
		if (onUpdate != null) onUpdate();
		activeAt = Ui.now();
		Ui.accessEpoch++;
		if (ui != null) {
			ui.requestFrame();
			if (focused) startTicking();
		}
	}

	// the range's start brought into view (centred: in the middle of the view)
	public function revealRange(start:Int, end:Int, center = true) {
		var l = model.lineOf(start);
		var top = l * lineHeight;
		if (center) scrollTo(scrollLeft, top - (viewH - lineHeight) / 2) else revealLine(l);
		var c = model.column(start), x = c * cw;
		if (x < scrollLeft || x > scrollLeft + textWidth() - cw * 4) scrollTo(Math.max(0, x - textWidth() / 2), scrollTop);
		if (ui != null) ui.requestFrame();
	}

	function revealLine(l:Int) {
		var top = l * lineHeight;
		if (top < scrollTop) scrollTo(scrollLeft, top);
		else if (top + lineHeight > scrollTop + viewH) scrollTo(scrollLeft, top + lineHeight - viewH);
	}

	// scrolled to (clamped): whether it moved
	public function scrollTo(left:Float, top:Float):Bool {
		var maxTop = Math.max(0, model.lineCount * lineHeight - viewH), maxLeft = Math.max(0, (maxCols + 2) * cw + PAD - textWidth());
		if (top > maxTop) top = maxTop;
		if (top < 0) top = 0;
		if (left > maxLeft) left = maxLeft;
		if (left < 0) left = 0;
		if (top == scrollTop && left == scrollLeft) return false;
		scrollTop = top;
		scrollLeft = left;
		if (ui != null) ui.requestFrame();
		return true;
	}

	inline function textWidth():Float
		return Math.max(cw, viewW - gutterW - PAD);

	// the lines a page moves by
	inline function pageLines():Int
		return Std.int(Math.max(1, Math.floor(viewH / lineHeight) - 1));

	// ---- metrics

	function metrics(engine:TextEngine) {
		var fresh = codeFont == null;
		if (fresh) codeFont = new Font(fontFamily, fontSize, 400, false, lineHeight / fontSize, 0, 0, Normal, Normal, ligatures ? "" : "'liga' 0, 'calt' 0");
		if (!fresh && engine == metricsOf && engine.generation() == metricsGeneration) return;
		metricsOf = engine;
		metricsGeneration = engine.generation();
		var p = engine.layout("0000000000", codeFont, Math.NaN);
		cw = p.width / 10;
		if (cw <= 0) cw = fontSize * 0.6;
		// (everything laid out again)
		shaped.clear();
		shapedCount = 0;
		spanPool.clear();
		spanFont = codeFont;
		for (k in 0...model.laid.length)
			model.laid[k] = null;
	}

	// a line's number as text (kept)
	function number(i:Int):String {
		while (numbers.length <= i)
			numbers.push(Std.string(numbers.length + 1));
		return numbers[i];
	}

	// ---- lines laid out

	// (a span of the font from start to end: one per pair, kept)
	function span(start:Int, end:Int):TextSpan {
		var key = start * 65536 + end;
		var s = spanPool.get(key);
		if (s == null) {
			s = new TextSpan(start, end, codeFont);
			spanPool.set(key, s);
		}
		return s;
	}

	// line i laid out with its tokens' spans: kept with the line, else one
	// laid out alike by its text, else laid out now
	function shape(engine:TextEngine, i:Int):ShapedLine {
		var sh = model.laid[i];
		if (sh != null) return sh;
		var t = model.line(i), toks = model.lineTokens(i);
		var shown = t.indexOf("\t") >= 0 ? expandTabs(t) : t;
		var same = shaped.get(shown);
		if (same != null && sameTokens(same.tokens, toks)) {
			model.laid[i] = same;
			return same;
		}
		var classes:Array<Int> = [];
		spansScratch.resize(0);
		if (toks != null) {
			var k = 0;
			while (k + 2 < toks.length) {
				var a = toks[k], b = toks[k + 1];
				if (shown != t) {
					a = shownIndex(t, a);
					b = shownIndex(t, b);
				}
				spansScratch.push(span(a, b));
				classes.push(toks[k + 2]);
				k += 3;
			}
		}
		var p = engine.layout(shown, codeFont, Math.NaN, spansScratch.length > 0 ? spansScratch : null, 0, false, 0);
		sh = new ShapedLine(shown, toks == null ? [] : toks.copy(), p, classes);
		model.laid[i] = sh;
		if (shapedCount >= 8192) {
			shaped.clear();
			shapedCount = 0;
		}
		shaped.set(shown, sh);
		shapedCount++;
		var cols = model.columnIn(t, t.length);
		if (cols > maxCols) maxCols = cols;
		return sh;
	}

	static function sameTokens(a:Array<Int>, b:Null<Array<Int>>):Bool {
		if (b == null) return a.length == 0;
		if (a.length != b.length) return false;
		for (k in 0...a.length)
			if (a[k] != b[k]) return false;
		return true;
	}

	// a line with its tabs as spaces to the next stop
	function expandTabs(t:String):String {
		var b = new StringBuf(), col = 0;
		for (k in 0...t.length) {
			var c = StringTools.fastCodeAt(t, k);
			if (c == "\t".code) {
				var w = model.tabSize - col % model.tabSize;
				for (_ in 0...w)
					b.addChar(" ".code);
				col += w;
			} else {
				b.addChar(c);
				col += model.width(c, col);
			}
		}
		return b.toString();
	}

	// (index k of t in its text with the tabs as spaces)
	function shownIndex(t:String, k:Int):Int {
		var col = 0, out = 0;
		for (j in 0...k) {
			var c = StringTools.fastCodeAt(t, j);
			if (c == "\t".code) {
				var w = model.tabSize - col % model.tabSize;
				out += w;
				col += w;
			} else {
				out++;
				col += model.width(c, col);
			}
		}
		return out;
	}

	// ---- paint

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (ui == null) return;
		var engine = ui.text;
		codeTheme.resolve(sheet(), ui.dark);
		metrics(engine);
		var c = codeTheme.colors, lh = lineHeight;
		viewW = width;
		viewH = height;
		model.pageLines = pageLines();
		var n = model.lineCount;
		var digits = n < 10 ? 1 : Std.int(Math.log(n) / Math.log(10) + 1e-9) + 1;
		if (digits < 2) digits = 2;
		gutterW = lineNumbers ? Math.round((digits + 3) * cw) : Math.round(cw * 2);
		if (model.version != lastVersion) {
			lastVersion = model.version;
			if (revealPending) {
				revealPending = false;
				revealLine(model.lineOf(model.primary.head));
				var col = model.column(model.primary.head) * cw;
				if (col < scrollLeft) scrollTo(Math.max(0, col - cw * 4), scrollTop);
				else if (col > scrollLeft + textWidth() - cw * 2) scrollTo(col - textWidth() + cw * 6, scrollTop);
			}
		}
		// (scrolled past the end by an edit that took lines: back)
		scrollTo(scrollLeft, scrollTop);
		var first = Std.int(scrollTop / lh), last = Std.int((scrollTop + height) / lh);
		if (last >= n) last = n - 1;
		model.highlight(last);
		if (!model.highlighted()) startTicking();
		canvas.pushClip(x, y, width, height, 0);
		canvas.rect(x, y, width, height, 0, c[CodeTheme.BACKGROUND], 0, 0);
		var left = x + gutterW, tx = left + PAD - scrollLeft, ty = y - scrollTop;
		canvas.pushClip(left, y, width - gutterW, height, 0);
		var sels = model.sels;
		// (the current lines: the carets' with no selection)
		for (k in 0...sels.length) {
			var s = sels[k];
			if (!s.empty()) continue;
			var l = model.lineOf(s.head);
			if (l >= first && l <= last) canvas.rect(left, ty + l * lh, width - gutterW, lh, 0, c[CodeTheme.CURRENT_LINE], 0, 0);
		}
		paintDecorations(canvas, tx, ty, left, width - gutterW, first, last, true);
		paintMatches(canvas, tx, ty, first, last);
		paintSelections(canvas, tx, ty, first, last);
		if (indentGuides) paintGuides(canvas, tx, ty, first, last);
		// (the lines)
		for (i in first...last + 1) {
			var sh = shape(engine, i);
			var cl = sh.classes;
			colorScratch.resize(cl.length);
			for (k in 0...cl.length)
				colorScratch[k] = codeTheme.token(cl[k]);
			canvas.text(sh.paragraph, tx, ty + i * lh, sh.paragraph.width + 1, Left, c[CodeTheme.FOREGROUND], cl.length > 0 ? colorScratch : null);
		}
		paintWhitespace(canvas, tx, ty, first, last);
		paintDecorations(canvas, tx, ty, left, width - gutterW, first, last, false);
		paintDiagnostics(canvas, tx, ty, first, last);
		paintComposition(canvas, engine, tx, ty);
		paintCursors(canvas, tx, ty, first, last);
		canvas.popClip();
		paintGutter(canvas, engine, x, y, ty, first, last);
		paintScrollbar(canvas, x, y, width, height);
		paintHover(canvas, engine, x, y, width, height, tx, ty);
		canvas.popClip();
	}

	// (the x of offset pos on line l, from the text's origin)
	inline function xOf(l:Int, pos:Int):Float
		return model.columnIn(model.line(l), pos - model.lineStart(l)) * cw;

	function paintSelections(canvas:Canvas, tx:Float, ty:Float, first:Int, last:Int) {
		var sels = model.sels, color = codeTheme.colors[CodeTheme.SELECTION], lh = lineHeight;
		for (k in 0...sels.length) {
			var s = sels[k];
			if (s.empty()) continue;
			var a = model.lineOf(s.from), b = model.lineOf(s.to);
			if (b < first || a > last) continue;
			var l0 = a < first ? first : a, l1 = b > last ? last : b;
			for (l in l0...l1 + 1) {
				var st = model.lineStart(l), len = model.line(l).length;
				var x0 = l == a ? xOf(l, s.from) : 0.0;
				// (a line the selection goes past: its line break shown, a character wide)
				var x1 = l == b ? xOf(l, s.to) : model.columnIn(model.line(l), len) * cw + cw * 0.6;
				if (x1 > x0) canvas.rect(tx + x0, ty + l * lh, x1 - x0, lh, 0, color, 0, 0);
			}
		}
	}

	// (find's matches in view: their first by a binary search)
	function paintMatches(canvas:Canvas, tx:Float, ty:Float, first:Int, last:Int) {
		if (matches.length == 0) return;
		var from = model.lineStart(first), to = last + 1 < model.lineCount ? model.lineStart(last + 1) : model.length;
		var lo = 0, hi = matches.length >> 1;
		while (lo < hi) {
			var mid = (lo + hi) >> 1;
			if (matches[mid * 2 + 1] < from) lo = mid + 1 else hi = mid;
		}
		var lh = lineHeight;
		for (m in lo...matches.length >> 1) {
			var a = matches[m * 2], b = matches[m * 2 + 1];
			if (a > to) break;
			var color = codeTheme.colors[m == currentMatch ? CodeTheme.FIND_CURRENT : CodeTheme.FIND_MATCH];
			var la = model.lineOf(a), lb = model.lineOf(b);
			for (l in la...lb + 1) {
				if (l < first || l > last) continue;
				var x0 = l == la ? xOf(l, a) : 0.0, x1 = l == lb ? xOf(l, b) : model.columnIn(model.line(l), model.line(l).length) * cw;
				canvas.rect(tx + x0, ty + l * lh, Math.max(2, x1 - x0), lh, 2, color, 0, 0);
			}
		}
	}

	// (decorations: backgrounds and whole lines under the text, borders and underlines over it)
	function paintDecorations(canvas:Canvas, tx:Float, ty:Float, left:Float, w:Float, first:Int, last:Int, under:Bool) {
		var ds = model.decorations, lh = lineHeight;
		for (k in 0...ds.length) {
			var d = ds[k];
			var la = model.lineOf(d.start), lb = model.lineOf(d.end);
			if (lb < first || la > last) continue;
			if (d.wholeLine) {
				var l0 = la < first ? first : la, l1 = lb > last ? last : lb;
				if (under && d.background != null) canvas.rect(left, ty + l0 * lh, w, (l1 - l0 + 1) * lh, 0, d.background, 0, 0);
				if (!under && d.border != null) canvas.rect(left, ty + la * lh, 2, (lb - la + 1) * lh, 0, d.border, 0, 0);
				continue;
			}
			for (l in (la < first ? first : la)...(lb > last ? last : lb) + 1) {
				var x0 = l == la ? xOf(l, d.start) : 0.0, x1 = l == lb ? xOf(l, d.end) : model.columnIn(model.line(l), model.line(l).length) * cw;
				var yy = ty + l * lh;
				if (under && d.background != null) canvas.rect(tx + x0, yy, x1 - x0, lh, 2, d.background, 0, 0);
				if (!under && d.border != null) canvas.rect(tx + x0 - 1, yy, x1 - x0 + 2, lh, 3, Color.TRANSPARENT, 1, d.border);
				if (!under && d.underline != null) canvas.rect(tx + x0, yy + lh - 3, x1 - x0, 2, 0, d.underline, 0, 0);
			}
		}
	}

	// (indentation guides: a line at each stop of a line's indentation; a blank line takes the one after it's)
	function paintGuides(canvas:Canvas, tx:Float, ty:Float, first:Int, last:Int) {
		var color = codeTheme.colors[CodeTheme.INDENT_GUIDE], lh = lineHeight, size = model.tabSize;
		for (l in first...last + 1) {
			var cols = indentOf(l);
			if (cols < 0) {
				// (blank: the next non-blank line's, within a screen; the line before's if less)
				var k = l + 1, next = 0;
				while (k < model.lineCount && k < last + 40 && (next = indentOf(k)) < 0)
					k++;
				var j = l - 1, prev = 0;
				while (j >= 0 && j > first - 40 && (prev = indentOf(j)) < 0)
					j--;
				cols = next < 0 ? 0 : prev < 0 ? next : (next < prev ? next : prev);
			}
			var g = size;
			while (g < cols + 1 && g <= cols) {
				canvas.rect(Math.round(tx + (g - size) * cw), ty + l * lh, 1, lh, 0, color, 0, 0);
				g += size;
			}
		}
	}

	// (a line's indentation in columns; -1: blank)
	function indentOf(l:Int):Int {
		var t = model.line(l), col = 0;
		for (k in 0...t.length) {
			var c = StringTools.fastCodeAt(t, k);
			if (c == " ".code) col++ else if (c == "\t".code) col += model.tabSize - col % model.tabSize else return col;
		}
		return -1;
	}

	// (spaces as dots and tabs as arrows, in the selections)
	function paintWhitespace(canvas:Canvas, tx:Float, ty:Float, first:Int, last:Int) {
		var sels = model.sels, color = codeTheme.colors[CodeTheme.WHITESPACE], lh = lineHeight;
		for (k in 0...sels.length) {
			var s = sels[k];
			if (s.empty()) continue;
			var a = model.lineOf(s.from), b = model.lineOf(s.to);
			for (l in (a < first ? first : a)...(b > last ? last : b) + 1) {
				var st = model.lineStart(l), t = model.line(l), col = 0;
				var from = s.from - st, to = s.to - st;
				for (j in 0...t.length) {
					var ch = StringTools.fastCodeAt(t, j), w = model.width(ch, col);
					if (j >= from && j < to) {
						var cx = tx + col * cw, cy = ty + l * lh + lh / 2;
						if (ch == " ".code) canvas.rect(cx + cw / 2 - 1, cy - 1, 2, 2, 1, color, 0, 0);
						else if (ch == "\t".code) {
							canvas.rect(cx + 2, cy, w * cw - 5, 1, 0, color, 0, 0);
							canvas.rect(cx + w * cw - 5, cy - 2, 1, 5, 0, color, 0, 0);
						}
					}
					col += w;
				}
			}
		}
	}

	// (squiggles under the diagnostics' ranges: a zigzag of small rectangles, no path made)
	function paintDiagnostics(canvas:Canvas, tx:Float, ty:Float, first:Int, last:Int) {
		var ds = model.diagnostics, lh = lineHeight;
		for (k in 0...ds.length) {
			var d = ds[k];
			var la = model.lineOf(d.start), lb = model.lineOf(d.end);
			if (lb < first || la > last) continue;
			var color = codeTheme.colors[severityColor(d.severity)];
			for (l in (la < first ? first : la)...(lb > last ? last : lb) + 1) {
				var x0 = l == la ? xOf(l, d.start) : 0.0, x1 = l == lb ? xOf(l, d.end) : model.columnIn(model.line(l), model.line(l).length) * cw;
				if (x1 - x0 < cw) x1 = x0 + cw;
				var base = ty + l * lh + lh - 3, px = tx + x0, step = 0;
				while (px < tx + x1) {
					canvas.rect(px, base + (step % 2 == 0 ? 0 : 1.5), 2, 1.5, 0, color, 0, 0);
					px += 2;
					step++;
				}
			}
		}
	}

	static inline function severityColor(s:String):Int
		return s == "error" ? CodeTheme.ERROR : s == "warning" ? CodeTheme.WARNING : CodeTheme.INFO;

	function paintComposition(canvas:Canvas, engine:TextEngine, tx:Float, ty:Float) {
		if (composition == "") return;
		var p = model.primary, l = model.lineOf(p.head), cx = tx + xOf(l, p.head), cy = ty + l * lineHeight;
		var laid = engine.layout(composition, codeFont, Math.NaN);
		canvas.rect(cx, cy, laid.width + 2, lineHeight, 0, codeTheme.colors[CodeTheme.BACKGROUND], 0, 0);
		canvas.text(laid, cx, cy, laid.width + 1, Left, codeTheme.colors[CodeTheme.FOREGROUND]);
		canvas.rect(cx, cy + lineHeight - 2, laid.width, 1, 0, codeTheme.colors[CodeTheme.FOREGROUND], 0, 0);
	}

	// (the cursors: where they spring to; drawn while focused, blinking after a moment)
	function paintCursors(canvas:Canvas, tx:Float, ty:Float, first:Int, last:Int) {
		var sels = model.sels, lh = lineHeight;
		var count = sels.length;
		var snap = curX.length != count;
		if (snap) {
			curX.resize(count);
			curY.resize(count);
			velX.resize(count);
			velY.resize(count);
			tgtX.resize(count);
			tgtY.resize(count);
		}
		for (k in 0...count) {
			var s = sels[k], l = model.lineOf(s.head);
			var gx = xOf(l, s.head), gy = l * lh;
			if (snap || Clock.reducedMotion || Math.abs(gy - curY[k]) > lh * 4 || Math.abs(gx - curX[k]) > cw * 40) {
				curX[k] = gx;
				curY[k] = gy;
				velX[k] = velY[k] = 0;
			} else if (gx != tgtX[k] || gy != tgtY[k]) {
				animating = true;
				startTicking();
			}
			tgtX[k] = gx;
			tgtY[k] = gy;
			if (s == model.primary) {
				// (the input method's place: the primary caret, window pixels)
				var b = windowBoundsInto(bounds);
				area.x = tx + gx + (b.x - absX);
				area.y = ty + gy + (b.y - absY);
				area.height = lh;
			}
		}
		caretShown = focused;
		if (!focused) return;
		var since = Ui.now() - activeAt;
		var on = Clock.reducedMotion || since < 0.5 || since > 30 || Std.int((since - 0.5) / 0.5) % 2 == 1;
		if (!on) return;
		var color = codeTheme.colors[CodeTheme.CURSOR], w = Math.max(2, Math.round(fontSize / 8));
		for (k in 0...count) {
			var cy = curY[k];
			if (cy + lh < scrollTop || cy > scrollTop + viewH) continue;
			canvas.rect(tx + curX[k], ty + cy + 1, w, lh - 2, 0, color, 0, 0);
		}
	}

	// (the gutter: its background, the lines' numbers, diagnostics' markers)
	function paintGutter(canvas:Canvas, engine:TextEngine, x:Float, y:Float, ty:Float, first:Int, last:Int) {
		var c = codeTheme.colors, lh = lineHeight;
		canvas.rect(x, y, gutterW, viewH, 0, c[CodeTheme.GUTTER], 0, 0);
		var active = model.lineOf(model.primary.head);
		if (lineNumbers)
			for (l in first...last + 1) {
				var p = engine.layout(number(l), codeFont, Math.NaN);
				canvas.text(p, x + gutterW - cw * 1.5 - p.width, ty + l * lh, p.width + 1, Left, c[l == active ? CodeTheme.LINE_NUMBER_ACTIVE : CodeTheme.LINE_NUMBER]);
			}
		// (a diagnostic's marker: a dot by the line, the most severe's colour)
		var ds = model.diagnostics;
		for (k in 0...ds.length) {
			var d = ds[k], l = model.lineOf(d.start);
			if (l < first || l > last) continue;
			var r = Math.round(cw * 0.35);
			canvas.rect(x + cw * 0.5, ty + l * lh + lh / 2 - r, r * 2, r * 2, r, c[severityColor(d.severity)], 0, 0);
		}
	}

	// (a thin scrollbar's thumb, while the text is taller than the view)
	function paintScrollbar(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		var total = model.lineCount * lineHeight;
		if (total <= height) return;
		var h = Math.max(24, height * height / total), top = y + (height - h) * (scrollTop / (total - height));
		canvas.rect(x + width - 8, top, 6, h, 3, codeTheme.colors[CodeTheme.LINE_NUMBER].fade(0.4), 0, 0);
	}

	// (the message of a diagnostic under the pointer, below its line)
	function paintHover(canvas:Canvas, engine:TextEngine, x:Float, y:Float, width:Float, height:Float, tx:Float, ty:Float) {
		if (hoverX < 0 || model.diagnostics.length == 0) return;
		var lx = localX(hoverX, hoverY), ly = localY(hoverX, hoverY);
		if (lx < gutterW) return;
		var pos = offsetAt(lx, ly);
		var d:Null<CodeDiagnostic> = null;
		for (k in 0...model.diagnostics.length) {
			var e = model.diagnostics[k];
			if (pos >= e.start && pos <= e.end && (d == null || rankOf(e.severity) < rankOf(d.severity))) d = e;
		}
		if (d == null) return;
		var l = model.lineOf(d.start);
		var p = engine.layout(d.message, codeFont, Math.min(width - 24, 520));
		var bx = Math.min(tx + xOf(l, d.start), x + width - p.width - 16), by = ty + (l + 1) * lineHeight + 2;
		if (by + p.height + 12 > y + height) by = ty + l * lineHeight - p.height - 14;
		if (bx < x + gutterW) bx = x + gutterW;
		var c = codeTheme.colors;
		canvas.shadow(bx, by, p.width + 16, p.height + 12, 4, Color.rgba(0, 0.18), 8);
		canvas.rect(bx, by, p.width + 16, p.height + 12, 4, c[CodeTheme.TOOLTIP], 1, c[severityColor(d.severity)]);
		canvas.text(p, bx + 8, by + 6, p.width + 1, Left, c[CodeTheme.FOREGROUND]);
	}

	static inline function rankOf(s:String):Int
		return s == "error" ? 0 : s == "warning" ? 1 : 2;

	// ---- the clock: cursors springing, the caret blinking, highlighting the rest of the file

	function startTicking() {
		if (ticking) return;
		ticking = true;
		lastTick = -1;
		Clock.add(tick);
	}

	function step(t:Float):Bool {
		var dt = lastTick < 0 ? 1 / 60 : t - lastTick;
		lastTick = t;
		if (dt > 0.05) dt = 0.05;
		if (animating) {
			var moving = false, k = 900.0, damp = 60.0;
			for (i in 0...curX.length) {
				var ax = k * (tgtX[i] - curX[i]) - damp * velX[i], ay = k * (tgtY[i] - curY[i]) - damp * velY[i];
				velX[i] += ax * dt;
				velY[i] += ay * dt;
				curX[i] += velX[i] * dt;
				curY[i] += velY[i] * dt;
				if (Math.abs(tgtX[i] - curX[i]) < 0.25 && Math.abs(velX[i]) < 4 && Math.abs(tgtY[i] - curY[i]) < 0.25 && Math.abs(velY[i]) < 4) {
					curX[i] = tgtX[i];
					curY[i] = tgtY[i];
					velX[i] = velY[i] = 0;
				} else moving = true;
			}
			animating = moving;
		}
		// (the rest of the file highlighted, a few thousand lines a frame)
		if (!model.highlighted()) model.highlight(model.lineCount, 4000);
		var blinking = focused && Ui.now() - activeAt <= 30;
		if (ui != null && (animating || blinking || !model.highlighted())) ui.requestFrame();
		ticking = animating || blinking || !model.highlighted();
		return ticking;
	}

	// ---- the pointer

	// the offset at a point of the node (its own pixels)
	public function offsetAt(lx:Float, ly:Float):Int {
		var l = Std.int(Math.floor((ly + scrollTop) / lineHeight));
		if (l < 0) return 0;
		if (l >= model.lineCount) return model.length;
		var col = (lx - gutterW - PAD + scrollLeft) / cw;
		return model.offsetAtColumn(l, col < 0 ? 0 : Std.int(Math.round(col)));
	}

	function pointerDown(e:Event) {
		if (e.button == 3) return;
		var lx = localX(e.x, e.y), ly = localY(e.x, e.y), t = Ui.now();
		var pos = offsetAt(lx, ly);
		clicks = t - clickAt < 0.45 && Math.abs(e.x - clickX) < 5 && Math.abs(e.y - clickY) < 5 ? clicks + 1 : 1;
		clickAt = t;
		clickX = e.x;
		clickY = e.y;
		var shift = e.mods & Key.MOD_SHIFT != 0, alt = e.mods & Key.MOD_ALT != 0;
		if (lx < gutterW) {
			// (the gutter: a line, or lines from the selection's anchor)
			var l = model.lineOf(pos), a = model.lineStart(l), b = l + 1 < model.lineCount ? model.lineStart(l + 1) : model.length;
			if (shift) model.setSels([new Sel(model.primary.anchor, b)]) else model.select(a, b);
			dragFrom = a;
			dragTo = b;
			clicks = 3;
		} else if (alt && clicks == 1) {
			model.addSel(pos, pos);
			dragFrom = dragTo = pos;
		} else if (clicks == 2) {
			var w = model.wordAt(pos);
			model.select(w.start, w.end);
			dragFrom = w.start;
			dragTo = w.end;
		} else if (clicks >= 3) {
			var l = model.lineOf(pos), a = model.lineStart(l), b = l + 1 < model.lineCount ? model.lineStart(l + 1) : model.length;
			model.select(a, b);
			dragFrom = a;
			dragTo = b;
		} else if (shift) {
			model.setSels([new Sel(model.primary.anchor, pos)]);
			dragFrom = model.primary.anchor;
			dragTo = model.primary.anchor;
		} else {
			model.select(pos, pos);
			dragFrom = dragTo = pos;
		}
		dragging = true;
		changed();
	}

	function pointerMove(e:Event) {
		hoverX = e.x;
		hoverY = e.y;
		if (ui != null && model.diagnostics.length > 0) ui.requestFrame();
		if (!dragging || !pressed) return;
		var lx = localX(e.x, e.y), ly = localY(e.x, e.y);
		var pos = offsetAt(lx, ly);
		var p = model.primary;
		// (by the granularity it started with: characters, words, lines)
		if (clicks == 2) {
			var w = model.wordAt(pos);
			if (pos < dragFrom) {
				p.anchor = dragTo;
				p.head = w.start;
			} else {
				p.anchor = dragFrom;
				p.head = w.end;
			}
		} else if (clicks >= 3) {
			var l = model.lineOf(pos), a = model.lineStart(l), b = l + 1 < model.lineCount ? model.lineStart(l + 1) : model.length;
			if (a < dragFrom) {
				p.anchor = dragTo;
				p.head = a;
			} else {
				p.anchor = dragFrom;
				p.head = b;
			}
		} else {
			p.anchor = dragFrom;
			p.head = pos;
		}
		model.normalize();
		@:privateAccess model.version++;
		changed();
	}

	// ---- an input method

	// the composition now (empty: none), its caret: shown at the primary caret, not typed
	public function compose(s:String, at:Int) {
		if (s == composition && at == compositionCaret) return;
		if (s != "" && composition == "" && !model.primary.empty()) model.insert("", CodeModel.TYPE);
		composition = s;
		compositionCaret = at;
		changed();
	}

	override public function textInputArea():Null<{x:Float, y:Float, width:Float, height:Float}>
		return focused && caretShown ? area : null;

	// (the caret's line and the primary selection in it, for the input method)
	override public function textContext():Null<{text:String, start:Int, end:Int, multiline:Bool, secret:Bool}> {
		if (!focused) return null;
		var p = model.primary, l = model.lineOf(p.head), st = model.lineStart(l), t = model.line(l);
		contextLineStart = st;
		context.text = t;
		var a = p.from - st, b = p.to - st;
		context.start = a < 0 ? 0 : a > t.length ? t.length : a;
		context.end = b < 0 ? 0 : b > t.length ? t.length : b;
		return context;
	}

	// (an input method's edit of the caret's line: start...end of it replaced)
	override public function replaceText(start:Int, end:Int, s:String) {
		var st = contextLineStart;
		model.select(st + start, st + end);
		model.insert(s, CodeModel.TYPE);
		composition = "";
		changed();
	}

	// ---- assistive technology

	override public function accessValue():Null<String>
		return model.text();

	override public function accessText():Null<{start:Int, end:Int, caret:Int, readOnly:Bool}>
		return {start: model.primary.from, end: model.primary.to, caret: model.primary.head, readOnly: model.readOnly};

	override public function accessSetValue(value:String):Bool {
		if (model.readOnly) return false;
		model.selectAll();
		model.insert(value);
		changed();
		return true;
	}

	override public function select(start:Int, end:Int) {
		model.select(start, end);
		changed();
	}

	// ---- actions

	// a CodeAction on the text: whether it did something
	public function run(a:CodeAction):Bool {
		var m = model;
		switch a {
			case MoveLeft: m.moveLeft();
			case MoveRight: m.moveRight();
			case MoveUp: m.moveUp();
			case MoveDown: m.moveDown();
			case MoveWordLeft: m.moveWordLeft();
			case MoveWordRight: m.moveWordRight();
			case MoveLineStart: m.moveLineStart();
			case MoveLineEnd: m.moveLineEnd();
			case MovePageUp:
				m.movePageUp();
				scrollTo(scrollLeft, scrollTop - pageLines() * lineHeight);
			case MovePageDown:
				m.movePageDown();
				scrollTo(scrollLeft, scrollTop + pageLines() * lineHeight);
			case MoveDocStart: m.moveDocStart();
			case MoveDocEnd: m.moveDocEnd();
			case SelectLeft: m.moveLeft(true);
			case SelectRight: m.moveRight(true);
			case SelectUp: m.moveUp(true);
			case SelectDown: m.moveDown(true);
			case SelectWordLeft: m.moveWordLeft(true);
			case SelectWordRight: m.moveWordRight(true);
			case SelectLineStart: m.moveLineStart(true);
			case SelectLineEnd: m.moveLineEnd(true);
			case SelectPageUp: m.movePageUp(true);
			case SelectPageDown: m.movePageDown(true);
			case SelectDocStart: m.moveDocStart(true);
			case SelectDocEnd: m.moveDocEnd(true);
			case SelectAll: m.selectAll();
			case SelectLine:
				var list = [];
				for (s in m.sels) {
					var a = m.lineOf(s.from), b = m.lineOf(s.to);
					list.push(new Sel(m.lineStart(a), b + 1 < m.lineCount ? m.lineStart(b + 1) : m.length));
				}
				m.setSels(list);
			case Backspace: m.backspace();
			case Delete: m.deleteForward();
			case DeleteWordLeft: m.backspace(true);
			case DeleteWordRight: m.deleteForward(true);
			case Newline: m.newline();
			case Indent: m.indent();
			case Outdent: m.outdent();
			case ToggleComment: m.toggleComment();
			case DuplicateLineDown: m.duplicateLines();
			case DuplicateLineUp: m.duplicateLines(true);
			case MoveLineUp: m.moveLinesUp();
			case MoveLineDown: m.moveLinesDown();
			case DeleteLine: m.deleteLines();
			case AddCursorAbove: m.addCursorVertical(-1);
			case AddCursorBelow: m.addCursorVertical(1);
			case AddNextOccurrence:
				if (!m.addNextOccurrence()) return true;
			case Cancel:
				if (composition != "") compose("", 0) else if (!m.collapse()) return false;
			case Undo:
				m.undo();
			case Redo:
				m.redo();
			case Copy:
				if (ui != null) ui.clipboard.write(m.copyText());
				return true;
			case Cut:
				if (ui != null) ui.clipboard.write(m.cutText());
			case Paste:
				if (ui != null) ui.clipboard.read(t -> if (t != null && t != "") {
					m.insert(StringTools.replace(StringTools.replace(t, "\r\n", "\n"), "\r", "\n"));
					changed();
				});
				return true;
			case _:
				return false;
		}
		changed();
		return true;
	}
}
