package helder.ui.widgets;

import helder.ui.access.Role;

// A grid of many rows, drawn (a table browser's, a spreadsheet's): only
// the cells in view are laid out and drawn, their text cut with an
// ellipsis and kept laid out by its text and width. A header of columns
// that stays at the top (a press sorts by one, onSort; its right edge drags
// to resize it, a double click fits it to what is shown), a gutter of row
// numbers that stays at the left (a press selects rows), both scrolled
// with the cells; scrollbars over the edges, dragged too. Cells are given
// by text (a cell's text: null for SQL's NULL) and flags (NULL, EDITED,
// LOADING, ADDED, DELETED; DEFAULT: what a new row's cell will be; LINK: an
// arrow on the hovered row's cell that follows it, onLink): what the grid
// shows of a row is asked for when it comes into view (onWindow), so a
// source can load it then. A secondary press on a title or a cell is
// onHeaderContext's or onContext's.
//
// A cell is the cursor (the keyboard's, focused), a range from an anchor
// to it is selected (Shift with the keys or a press, a drag). The keys:
// the arrows, Home and End (the row's ends; with Control or Command the
// grid's), Page Up and Down, Control or Command+A (all), +C (the selection
// as tab separated text, rows by lines), +V (onPaste: the clipboard's text), Enter or F2 or a double click
// edits the cursor's cell (onEdit, or the grid's own editor: edit), a
// character typed starts it with that character, Delete or Backspace clears
// the selection (onClear), Escape collapses it. The editor is a TextField
// inside the cell's ring (slot "grid-editor"; a press in it its own): Enter or Down keeps the text
// (onCommit) and moves down, Up up, Tab right, Escape drops it.
//
// It has no look of its own beyond its tokens (GridTheme: "grid-*" colours
// of the sheet) and its font (the style's, its figures tabular; the titles'
// family may be another). To
// assistive technology a table, its name the label given, the cursor's
// cell its value.
class DataGrid extends Node {
	public static inline var NULL = 1;
	public static inline var EDITED = 2;
	public static inline var LOADING = 4;
	public static inline var ADDED = 8;
	public static inline var DELETED = 16;
	public static inline var DEFAULT = 32;
	public static inline var LINK = 64;

	public final gridTheme = new GridTheme();

	public var columns(default, set):Array<GridColumn> = [];
	public var rowCount(default, set) = 0;
	public var rowHeight(default, set) = 30.0;
	public var headerHeight(default, set) = 34.0;
	// the row numbers' gutter
	public var rowNumbers = true;
	// the titles' family (null: the cells', the style's)
	public var titleFamily(default, set):Null<String> = null;
	// the cells can't be edited
	public var readOnly = false;

	// a cell's text (null: NULL), its flags
	public var text:(row:Int, col:Int) -> Null<String> = (_, _) -> "";
	public var flags:Null<(row:Int, col:Int) -> Int> = null;

	// the rows in view changed (first, before end), drawn as LOADING until given
	public var onWindow:Null<(first:Int, end:Int) -> Void> = null;
	// a column's title pressed
	public var onSort:Null<Int->Void> = null;
	// the cursor or the selection moved
	public var onSelect:Null<Void->Void> = null;
	// the cursor's cell asked to be edited (null: the grid's editor), with the character typed if any
	public var onEdit:Null<(row:Int, col:Int, typed:Null<String>) -> Void> = null;
	// the grid's editor's text kept
	public var onCommit:Null<(row:Int, col:Int, text:String) -> Void> = null;
	// the selection to clear (Delete, Backspace)
	public var onClear:Null<Void->Void> = null;
	// a secondary press on a cell (window pixels); the cursor moved there first unless it is in the selection
	public var onContext:Null<(row:Int, col:Int, x:Float, y:Float) -> Void> = null;
	// a secondary press on a column's title (window pixels)
	public var onHeaderContext:Null<(col:Int, x:Float, y:Float) -> Void> = null;
	// a LINK cell's arrow pressed
	public var onLink:Null<(row:Int, col:Int) -> Void> = null;
	// the clipboard's text to paste at the selection
	public var onPaste:Null<String->Void> = null;

	// the column sorted by (-1: none) and whether descending: an arrow in its title
	public var sortColumn = -1;
	public var sortDown = false;

	// the cursor and the selection's anchor (row, column); whole rows selected from the gutter
	public var cursorRow(default, null) = 0;
	public var cursorCol(default, null) = 0;
	public var anchorRow(default, null) = 0;
	public var anchorCol(default, null) = 0;
	public var wholeRows(default, null) = false;

	public var scrollTop(default, null) = 0.0;
	public var scrollLeft(default, null) = 0.0;

	// the editor while a cell is edited
	public var editor(default, null):Null<TextField> = null;

	// (fonts: the cells', the titles', the details')
	var cellFont:Null<Font> = null;
	var titleFont:Null<Font> = null;
	var detailFont:Null<Font> = null;
	var fontOf:Null<Font> = null;
	var engineOf:Null<TextEngine> = null;
	var generation = -1;
	// (texts laid out by text, width and font: kept until there are many)
	final laid = new Map<String, Paragraph>();
	var laidCount = 0;
	// (columns' left edges, from 0, and the total width)
	var lefts:Array<Float> = [0];
	var gutterW = 0.0;
	var seenW = 0.0;
	var seenH = 0.0;
	// (the window last told)
	var toldFirst = -1;
	var toldEnd = -1;
	var hoverRow = -1;
	var hoverEdge = -1;
	var hoverCol = -1;
	// (the column whose LINK arrow the pointer is on, in hoverRow; -1: none)
	var hoverArrow = -1;
	// (a drag: 1 cells, 2 rows, 3 a column's edge, 4 the vertical bar, 5 the horizontal)
	var drag = 0;
	var dragCol = -1;
	var dragFrom = 0.0;
	var dragStart = 0.0;
	var clickAt = -1e9;
	var clickX = 0.0;
	var clickY = 0.0;
	var editRow = -1;
	var editCol = -1;
	// (since when cells in view are loading: their skeletons held back a moment, a quick load showing none)
	var loadingSince = -1.0;

	static inline var PAD = 10.0;
	// (the editor's inset in its cell: the cursor's ring around it)
	static inline var INSET = 3.0;
	static inline var SKELETON_AFTER = 0.3;
	static inline var EDGE = 4.0;
	static inline var BAR = 10.0;
	// (a text drawn at most this long: a cell is one line)
	static inline var MAX_CHARS = 240;

	public function new(?tag:String) {
		super(tag ?? "data-grid");
		focusable = true;
		style.grow = 1;
		style.shrink = 1;
		style.minHeight = 0;
		style.minWidth = 0;
		style.overflow = Hidden;
		semantics = {role: Role.Table, label: "Data"};
		onKeyDown = key;
		onTextInput = e -> {
			if (e.target != this || e.text == "" || readOnly || rowCount == 0 || columns.length == 0) return;
			startEdit(e.text);
		};
		onPointerDown = pointerDown;
		onPointerMove = pointerMove;
		onPointerUp = e -> {
			drag = 0;
			releaseCapture();
		};
		onPointerLeave = e -> {
			if (drag != 0) return;
			hoverRow = -1;
			hoverEdge = -1;
			hoverCol = -1;
			hoverArrow = -1;
			repaint();
		};
		onWheel = e -> {
			var dx = e.deltaX, dy = e.deltaY;
			if (e.mods & Key.MOD_SHIFT != 0 && dx == 0) {
				dx = dy;
				dy = 0;
			}
			if (e.eased) {
				if (glide(dx, dy)) e.preventDefault();
				return;
			}
			stopGlide();
			if (scrollTo(scrollLeft + dx, scrollTop + dy)) e.preventDefault();
		};
		onFocus = e -> repaint();
		onBlur = e -> repaint();
	}

	function set_columns(v:Array<GridColumn>):Array<GridColumn> {
		cancelEdit();
		columns = v;
		if (cursorCol >= v.length) cursorCol = anchorCol = v.length > 0 ? v.length - 1 : 0;
		measureColumns();
		scrollTo(scrollLeft, scrollTop);
		repaint();
		return v;
	}

	function set_rowCount(v:Int):Int {
		rowCount = v;
		if (cursorRow >= v) cursorRow = v > 0 ? v - 1 : 0;
		if (anchorRow >= v) anchorRow = cursorRow;
		toldFirst = toldEnd = -1;
		scrollTo(scrollLeft, scrollTop);
		repaint();
		return v;
	}

	function set_titleFamily(v:Null<String>):Null<String> {
		titleFamily = v;
		cellFont = null;
		repaint();
		return v;
	}

	function set_rowHeight(v:Float):Float {
		rowHeight = v;
		repaint();
		return v;
	}

	function set_headerHeight(v:Float):Float {
		headerHeight = v;
		repaint();
		return v;
	}

	// the cells' text or flags changed: drawn again
	public function refresh() {
		toldFirst = toldEnd = -1;
		repaint();
	}

	// back to the top left, the cursor on the first cell
	public function reset() {
		cancelEdit();
		scrollTop = scrollLeft = 0;
		cursorRow = cursorCol = anchorRow = anchorCol = 0;
		wholeRows = false;
		refresh();
	}

	inline function repaint()
		if (ui != null) ui.requestFrame();

	override public function hasContent():Bool
		return true;

	override public function measureContent(engine:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):Size {
		var w = !Math.isNaN(knownWidth) ? knownWidth : !Math.isNaN(availWidth) ? availWidth : 640;
		return new Size(w, !Math.isNaN(knownHeight) ? knownHeight : headerHeight + rowHeight * 4);
	}

	override public function minContentWidth(engine:TextEngine):Float
		return 0;

	// ---- the selection

	// the selected range: its first and last rows and columns
	public function range():{top:Int, bottom:Int, left:Int, right:Int} {
		var top = anchorRow < cursorRow ? anchorRow : cursorRow, bottom = anchorRow < cursorRow ? cursorRow : anchorRow;
		if (wholeRows) return {top: top, bottom: bottom, left: 0, right: columns.length - 1};
		var left = anchorCol < cursorCol ? anchorCol : cursorCol, right = anchorCol < cursorCol ? cursorCol : anchorCol;
		return {top: top, bottom: bottom, left: left, right: right};
	}

	public function selected(row:Int, col:Int):Bool {
		var r = range();
		return row >= r.top && row <= r.bottom && col >= r.left && col <= r.right;
	}

	// the cursor to a cell (extend: the anchor kept), brought into view
	public function moveTo(row:Int, col:Int, extend = false, rows = false) {
		if (rowCount == 0 || columns.length == 0) return;
		row = row < 0 ? 0 : row >= rowCount ? rowCount - 1 : row;
		col = col < 0 ? 0 : col >= columns.length ? columns.length - 1 : col;
		if (!extend) {
			anchorRow = row;
			anchorCol = col;
			wholeRows = rows;
		} else if (rows) wholeRows = true;
		cursorRow = row;
		cursorCol = col;
		reveal(row, wholeRows && !extend ? -1 : col);
		describe();
		if (onSelect != null) onSelect();
		repaint();
	}

	public function selectAll() {
		if (rowCount == 0) return;
		anchorRow = 0;
		anchorCol = 0;
		cursorRow = rowCount - 1;
		cursorCol = columns.length - 1;
		wholeRows = true;
		if (onSelect != null) onSelect();
		repaint();
	}

	// (the cursor's cell to assistive technology)
	function describe() {
		if (semantics == null || columns.length == 0) return;
		var t = text(cursorRow, cursorCol);
		semantics.valueText = 'Row ${cursorRow + 1}, ${columns[cursorCol].title}: ${t == null ? "null" : t}';
		Ui.accessEpoch++;
	}

	// text to the clipboard: the selection's (selectionText), or what is given
	public function copy(?text:String)
		if (ui != null) ui.clipboard.write(text ?? selectionText());

	// the clipboard's text to onPaste (it may come later)
	public function paste()
		if (ui != null && onPaste != null && !readOnly) ui.clipboard.read(t -> if (t != null && t != "") onPaste(t));

	// the selection as tab separated text: a row a line, NULL empty
	public function selectionText():String {
		var r = range(), b = new StringBuf();
		for (row in r.top...r.bottom + 1) {
			if (row > r.top) b.add("\n");
			for (col in r.left...r.right + 1) {
				if (col > r.left) b.add("\t");
				var t = text(row, col);
				if (t != null) b.add(StringTools.replace(StringTools.replace(t, "\t", " "), "\n", " "));
			}
		}
		return b.toString();
	}

	// ---- scrolling

	inline function dataW():Float
		return lefts[lefts.length - 1];

	inline function dataH():Float
		return rowCount * rowHeight;

	// (the view: the node's box, no padding)
	var viewW(get, never):Float;
	var viewH(get, never):Float;

	inline function get_viewW():Float
		return width;

	inline function get_viewH():Float
		return height;

	inline function bodyW():Float
		return Math.max(0, viewW - gutterW);

	inline function bodyH():Float
		return Math.max(0, viewH - headerHeight);

	// scrolled to (clamped): whether it moved; the editor moved with its
	// cell, kept when the cell leaves the view
	public function scrollTo(left:Float, top:Float):Bool {
		var maxTop = Math.max(0, dataH() - bodyH()), maxLeft = Math.max(0, dataW() - bodyW());
		top = top > maxTop ? maxTop : top < 0 ? 0 : top;
		left = left > maxLeft ? maxLeft : left < 0 ? 0 : left;
		if (top == scrollTop && left == scrollLeft) return false;
		scrollTop = top;
		scrollLeft = left;
		if (editor != null) {
			var y = editRow * rowHeight - scrollTop, x = lefts[editCol] - scrollLeft;
			if (y + rowHeight <= 0 || y >= bodyH() || x + columns[editCol].width <= 0 || x >= bodyW()) commitEdit(false) else place(editor);
		}
		repaint();
		return true;
	}

	// (a mouse's notches glided to, as the platform glides them: ScrollGlide)
	var glider:Null<ScrollGlide> = null;

	// a scroll by dx, dy glided to: whether it moves
	function glide(dx:Float, dy:Float):Bool {
		var g = glider ??= new ScrollGlide(this, (x, y) -> scrollTo(x, y));
		return g.to(scrollLeft, scrollTop, g.heading(scrollLeft, scrollTop, dx, dy, Math.max(0, dataW() - bodyW()), Math.max(0, dataH() - bodyH())));
	}

	function stopGlide()
		if (glider != null) glider.stop();

	// (the editor inside its cell's ring, its text where the cell's was: as
	// much less padding as it is inset)
	function place(f:Node) {
		f.style.left = gutterW + lefts[editCol] - scrollLeft + INSET;
		f.style.top = headerHeight + editRow * rowHeight - scrollTop + INSET;
		f.style.width = Math.min(columns[editCol].width, bodyW()) - INSET * 2;
		f.style.height = rowHeight - 1 - INSET * 2;
	}

	// a cell brought into view (col -1: only its row)
	public function reveal(row:Int, col:Int) {
		var top = scrollTop, left = scrollLeft;
		var y = row * rowHeight;
		if (y < top) top = y else if (y + rowHeight > top + bodyH()) top = y + rowHeight - bodyH();
		if (col >= 0 && col < columns.length) {
			var x = lefts[col], w = columns[col].width;
			if (x < left) left = x else if (x + w > left + bodyW()) left = Math.min(x, x + w - bodyW());
		}
		scrollTo(left, top);
	}

	// ---- columns

	function measureColumns() {
		lefts = [0.0];
		for (c in columns)
			lefts.push(lefts[lefts.length - 1] + c.width);
	}

	// a column's width (at least 48)
	public function resizeColumn(col:Int, width:Float) {
		if (col < 0 || col >= columns.length) return;
		columns[col].width = Math.round(width < 48 ? 48 : width);
		measureColumns();
		scrollTo(scrollLeft, scrollTop);
		repaint();
	}

	// a column as wide as its title and the cells in view
	public function fitColumn(col:Int) {
		if (ui == null || col < 0 || col >= columns.length) return;
		fonts(ui.text);
		var c = columns[col], engine = ui.text;
		var w = engine.layout(c.title, titleFont, Math.NaN).width + PAD * 2 + 16;
		if (c.detail != "") w += engine.layout(c.detail, detailFont, Math.NaN).width + 6;
		var first = Std.int(scrollTop / rowHeight), last = Std.int((scrollTop + bodyH()) / rowHeight);
		if (last >= rowCount) last = rowCount - 1;
		for (row in first...last + 1) {
			var t = text(row, col);
			var p = engine.layout(t == null ? "NULL" : shown(t), cellFont, Math.NaN);
			if (p.width + PAD * 2 > w) w = p.width + PAD * 2;
		}
		resizeColumn(col, Math.min(w + 2, 560));
	}

	// ---- hit testing (local pixels)

	function colAt(lx:Float):Int {
		var x = lx - gutterW + scrollLeft;
		if (x < 0) return -1;
		var lo = 0, hi = columns.length - 1;
		while (lo <= hi) {
			var m = (lo + hi) >> 1;
			if (x < lefts[m]) hi = m - 1 else if (x >= lefts[m + 1]) lo = m + 1 else return m;
		}
		return -1;
	}

	inline function rowAt(ly:Float):Int {
		var r = Math.floor((ly - headerHeight + scrollTop) / rowHeight);
		return r < 0 || r >= rowCount ? -1 : r;
	}

	// the column whose right edge is at lx in the header (-1: none)
	function edgeAt(lx:Float):Int {
		var x = lx - gutterW + scrollLeft;
		for (i in 0...columns.length)
			if (Math.abs(x - lefts[i + 1]) <= EDGE) return i;
		return -1;
	}

	// ---- the pointer

	function pointerDown(e:Event) {
		// (a press in the editor is the editor's: the caret, a selection)
		if (ui == null || e.target != this) return;
		stopGlide();
		focus(false);
		var lx = localX(e.x, e.y), ly = localY(e.x, e.y), t = Ui.now();
		var double = t - clickAt < 0.45 && Math.abs(e.x - clickX) < 5 && Math.abs(e.y - clickY) < 5;
		clickAt = double ? -1e9 : t;
		clickX = e.x;
		clickY = e.y;
		var shift = e.mods & Key.MOD_SHIFT != 0;
		// (the scrollbars)
		if (dataH() > bodyH() && lx >= viewW - BAR && ly >= headerHeight) {
			var th = thumb(bodyH(), dataH(), scrollTop);
			var top = headerHeight + th.at;
			if (ly < top || ly > top + th.size) scrollTo(scrollLeft, (ly - headerHeight - th.size / 2) / (bodyH() - th.size) * (dataH() - bodyH()));
			startDrag(4, ly, scrollTop);
			return;
		}
		if (dataW() > bodyW() && ly >= viewH - BAR && lx >= gutterW) {
			var th = thumb(bodyW(), dataW(), scrollLeft);
			var left = gutterW + th.at;
			if (lx < left || lx > left + th.size) scrollTo((lx - gutterW - th.size / 2) / (bodyW() - th.size) * (dataW() - bodyW()), scrollTop);
			startDrag(5, lx, scrollLeft);
			return;
		}
		if (ly < headerHeight) {
			var edge = edgeAt(lx);
			if (edge >= 0) {
				if (double) fitColumn(edge) else startDrag(3, lx, columns[edge].width, edge);
				return;
			}
			if (lx < gutterW) {
				if (e.button != 3) selectAll();
				return;
			}
			var col = colAt(lx);
			if (col < 0) return;
			if (e.button == 3) {
				if (onHeaderContext != null) onHeaderContext(col, e.x, e.y);
			} else if (onSort != null) onSort(col);
			return;
		}
		var row = rowAt(ly);
		if (row < 0) return;
		if (lx < gutterW) {
			moveTo(row, cursorCol, shift, true);
			startDrag(2, ly, 0);
			return;
		}
		var col = colAt(lx);
		if (col < 0) return;
		if (e.button != 3 && onLink != null && onArrow(row, col, lx)) {
			moveTo(row, col);
			onLink(row, col);
			return;
		}
		if (e.button == 3) {
			if (!selected(row, col)) moveTo(row, col);
			if (onContext != null) onContext(row, col, e.x, e.y);
			return;
		}
		moveTo(row, col, shift);
		if (double && !shift && !readOnly) {
			startEdit(null);
			// (the focus left where the edit put it: the press would focus the grid, closing its editor)
			e.preventDefault();
			return;
		}
		startDrag(1, ly, 0);
	}

	function startDrag(kind:Int, from:Float, start:Float, col = -1) {
		drag = kind;
		dragFrom = from;
		dragStart = start;
		dragCol = col;
		capture();
	}

	function pointerMove(e:Event) {
		// (a move in the editor is the editor's: its I-beam, its selection)
		if (e.target != this && drag == 0) return;
		var lx = localX(e.x, e.y), ly = localY(e.x, e.y);
		switch drag {
			case 1 | 2:
				// (past an edge: scrolled that way)
				if (ly > viewH) scrollTo(scrollLeft, scrollTop + Math.min(rowHeight, ly - viewH));
				if (ly < headerHeight) scrollTo(scrollLeft, scrollTop - Math.min(rowHeight, headerHeight - ly));
				if (drag == 1) {
					if (lx > viewW) scrollTo(scrollLeft + Math.min(40, lx - viewW), scrollTop);
					if (lx < gutterW) scrollTo(scrollLeft - Math.min(40, gutterW - lx), scrollTop);
				}
				var row = Math.floor((Math.max(headerHeight, Math.min(viewH - 1, ly)) - headerHeight + scrollTop) / rowHeight);
				var col = drag == 2 ? cursorCol : colAt(Math.max(gutterW, Math.min(viewW - 1, lx)));
				if (row >= rowCount) row = rowCount - 1;
				if (col < 0) col = cursorCol;
				if (row != cursorRow || col != cursorCol) moveTo(row, col, true, drag == 2);
			case 3:
				resizeColumn(dragCol, dragStart + lx - dragFrom);
			case 4:
				var th = thumb(bodyH(), dataH(), dragStart);
				scrollTo(scrollLeft, dragStart + (ly - dragFrom) / Math.max(1, bodyH() - th.size) * (dataH() - bodyH()));
			case 5:
				var th = thumb(bodyW(), dataW(), dragStart);
				scrollTo(dragStart + (lx - dragFrom) / Math.max(1, bodyW() - th.size) * (dataW() - bodyW()), scrollTop);
			case _:
				var row = ly >= headerHeight ? rowAt(ly) : -1, edge = ly < headerHeight ? edgeAt(lx) : -1;
				var col = ly < headerHeight && edge < 0 && lx >= gutterW ? colAt(lx) : -1;
				var arrow = row >= 0 && onLink != null && onArrow(row, colAt(lx), lx);
				var arrowCol = arrow ? colAt(lx) : -1;
				if (row != hoverRow || edge != hoverEdge || col != hoverCol || arrowCol != hoverArrow) {
					hoverRow = row;
					hoverEdge = edge;
					hoverCol = col;
					hoverArrow = arrowCol;
					repaint();
				}
				style.cursor = edge >= 0 ? ResizeEW : col >= 0 || arrow ? Pointer : Default;
		}
	}

	// (a scrollbar's thumb: where it is along the track and how long)
	static function thumb(view:Float, total:Float, scroll:Float):{at:Float, size:Float} {
		var size = Math.max(28, view * view / total);
		return {at: (view - size) * (scroll / Math.max(1, total - view)), size: size};
	}

	// (the LINK arrow's square at a cell's right end)
	static inline var ARROW = 18.0;

	function onArrow(row:Int, col:Int, lx:Float):Bool {
		if (row < 0 || col < 0 || flags == null || flags(row, col) & LINK == 0) return false;
		var x = gutterW + arrowX(col) - scrollLeft;
		return lx >= x - ARROW / 2 - 2 && lx < x + ARROW / 2 + 2;
	}

	// (the LINK arrow's centre in a cell, from the columns' left: on the side
	// the text is not aligned to, over it rather than moving it)
	inline function arrowX(col:Int):Float
		return columns[col].align == Right ? lefts[col] + 4 + ARROW / 2 : lefts[col + 1] - 4 - ARROW / 2;

	// a cell's box in window pixels (as it is scrolled now)
	public function cellBounds(row:Int, col:Int):{x:Float, y:Float, width:Float, height:Float} {
		var b = windowBounds();
		return {
			x: b.x + gutterW + lefts[col] - scrollLeft,
			y: b.y + headerHeight + row * rowHeight - scrollTop,
			width: columns[col].width,
			height: rowHeight
		};
	}

	// a view kept earlier (scroll, cursor) given back
	public function restore(top:Float, left:Float, row:Int, col:Int) {
		cancelEdit();
		cursorRow = anchorRow = row < 0 ? 0 : row;
		cursorCol = anchorCol = col < 0 ? 0 : col;
		wholeRows = false;
		scrollTop = top;
		scrollLeft = left;
		scrollTo(left, top);
		refresh();
	}

	// ---- the keys

	function key(e:Event) {
		if (e.target != this || e.defaultPrevented || rowCount == 0 || columns.length == 0) return;
		stopGlide();
		var shift = e.mods & Key.MOD_SHIFT != 0, primary = e.mods & (Key.MOD_CONTROL | Key.MOD_META) != 0;
		var page = Std.int(Math.max(1, Math.floor(bodyH() / rowHeight) - 1));
		switch e.key {
			case Key.UP: moveTo(primary ? 0 : cursorRow - 1, cursorCol, shift, wholeRows && shift);
			case Key.DOWN: moveTo(primary ? rowCount - 1 : cursorRow + 1, cursorCol, shift, wholeRows && shift);
			case Key.LEFT: moveTo(cursorRow, primary ? 0 : cursorCol - 1, shift);
			case Key.RIGHT: moveTo(cursorRow, primary ? columns.length - 1 : cursorCol + 1, shift);
			case Key.HOME: moveTo(primary ? 0 : cursorRow, 0, shift);
			case Key.END: moveTo(primary ? rowCount - 1 : cursorRow, columns.length - 1, shift);
			case Key.PAGE_UP: moveTo(cursorRow - page, cursorCol, shift);
			case Key.PAGE_DOWN: moveTo(cursorRow + page, cursorCol, shift);
			case Key.ENTER | 0xFFBF if (!readOnly):
				startEdit(null);
			case Key.ESCAPE:
				if (anchorRow == cursorRow && anchorCol == cursorCol && !wholeRows) return;
				moveTo(cursorRow, cursorCol);
			case Key.DELETE | Key.BACKSPACE if (onClear != null):
				onClear();
			case "a".code if (primary):
				selectAll();
			case "c".code if (primary):
				copy();
			case "v".code if (primary && onPaste != null && !readOnly):
				paste();
			case _:
				return;
		}
		e.preventDefault();
		e.stop();
	}

	// ---- editing

	function startEdit(typed:Null<String>) {
		if (onEdit != null) {
			onEdit(cursorRow, cursorCol, typed);
			return;
		}
		edit(cursorRow, cursorCol, typed);
	}

	// the grid's editor over a cell, its text the cell's (or typed: replacing it)
	public function edit(row:Int, col:Int, ?typed:String) {
		if (row < 0 || row >= rowCount || col < 0 || col >= columns.length) return;
		commitEdit(false);
		reveal(row, col);
		editRow = row;
		editCol = col;
		var t = text(row, col);
		var f = new CellEditor(this, typed ?? (t ?? ""));
		f.slot = "grid-editor";
		f.style.position = Absolute;
		place(f);
		f.style.padding = [0, PAD - INSET];
		f.style.textAlign = columns[col].align;
		f.style.cursor = Text;
		f.onBlur = e -> commitEdit(false);
		editor = f;
		append(f);
		f.focus(false);
		if (typed == null) f.selectAll() else f.select(f.text.length, f.text.length);
	}

	// the editor's text kept (then the cursor down a row, or moved by dx)
	public function commitEdit(refocus = true, dy = 0, dx = 0) {
		var f = editor;
		if (f == null) return;
		var row = editRow, col = editCol, t = f.text;
		close(refocus);
		if (onCommit != null) onCommit(row, col, t);
		if (dy != 0 || dx != 0) moveTo(row + dy, col + dx);
		repaint();
	}

	public function cancelEdit()
		close(true);

	function close(refocus:Bool) {
		var f = editor;
		if (f == null) return;
		editor = null;
		f.onBlur = null;
		remove(f);
		if (refocus) focus(false);
	}

	// ---- paint

	function fonts(engine:TextEngine) {
		var f = font();
		if (f == fontOf && engine == engineOf && engine.generation() == generation && cellFont != null) return;
		fontOf = f;
		engineOf = engine;
		generation = engine.generation();
		cellFont = new Font(f.family, f.size, f.weight, false, f.lineHeight, 0, 0, Normal, Normal, "'tnum'");
		titleFont = new Font(titleFamily ?? f.family, f.size, 500, false, f.lineHeight, 0, 0, Normal, Normal, "");
		detailFont = new Font(f.family, f.size - 1, f.weight, false, f.lineHeight, 0, 0, Normal, Normal, "");
		laid.clear();
		laidCount = 0;
	}

	// (a cell's text on one line, not too long)
	static function shown(t:String):String {
		if (t.length > MAX_CHARS) t = t.substr(0, MAX_CHARS);
		if (t.indexOf("\n") >= 0 || t.indexOf("\r") >= 0 || t.indexOf("\t") >= 0) t = ~/[\r\n\t]+/g.replace(t, " ");
		return t;
	}

	// (a text laid out on one line, cut at width with an ellipsis: kept)
	function layout(engine:TextEngine, t:String, f:Font, width:Float):Paragraph {
		var w = Std.int(width);
		var k = t + "\u0001" + w + (f == cellFont ? "c" : f == titleFont ? "t" : "d");
		var p = laid.get(k);
		if (p != null) return p;
		if (laidCount > 6000) {
			laid.clear();
			laidCount = 0;
		}
		p = engine.layout(t, f, Math.NaN, null, 1, false, -1, w);
		laid.set(k, p);
		laidCount++;
		return p;
	}

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (ui == null) return;
		var engine = ui.text;
		gridTheme.resolve(sheet(), ui.dark);
		fonts(engine);
		var c = gridTheme.colors, rh = rowHeight, hh = headerHeight;
		var digits = Std.string(rowCount < 1 ? 1 : rowCount).length;
		// (whole pixels, rounded up: the widest number fits without its ellipsis)
		var gw = rowNumbers ? Math.ceil(layout(engine, StringTools.lpad("", "0", digits < 2 ? 2 : digits), cellFont, 1e4).width + PAD * 2 + 2) : 0;
		if (gw != gutterW || width != seenW || height != seenH) {
			// (the cursor's row in view before: in view after, a bar under the grid or a smaller window not hiding it)
			var y = cursorRow * rowHeight, was = y >= scrollTop && y + rowHeight <= scrollTop + seenH - headerHeight;
			gutterW = gw;
			seenW = width;
			seenH = height;
			scrollTo(scrollLeft, scrollTop);
			if (was && rowCount > 0) reveal(cursorRow, -1);
		}
		var first = Std.int(scrollTop / rh), last = Std.int((scrollTop + bodyH()) / rh);
		if (last >= rowCount) last = rowCount - 1;
		if (first != toldFirst || last + 1 != toldEnd) {
			toldFirst = first;
			toldEnd = last + 1;
			if (onWindow != null && rowCount > 0) onWindow(first, last + 1);
		}
		var c0 = colAt(gutterW), c1 = colAt(width - 1);
		if (c0 < 0) c0 = 0;
		if (c1 < 0) c1 = columns.length - 1;
		// (the scroll in whole device pixels: rows, lines and text move together, crisp)
		var px = ui.scale > 0 ? ui.scale : 1.0;
		var bx = x + gutterW, by = y + hh, ox = bx - Math.round(scrollLeft * px) / px, oy = by - Math.round(scrollTop * px) / px;
		var right = Math.min(x + width, ox + dataW());
		var r = range(), focusedNow = focused || editor != null;
		var flagsOf = flags, anyLoading = false, now = Ui.now();
		var skeleton = loadingSince < 0 ? 0.0 : Math.min(1, (now - loadingSince - SKELETON_AFTER) / 0.15);
		canvas.pushClip(x, y, width, height, 0);
		canvas.rect(x, y, width, height, 0, c[GridTheme.BACKGROUND], 0, 0);
		// (the cells)
		canvas.pushClip(bx, by, width - gutterW, height - hh, 0);
		for (row in first...last + 1) {
			var ry = oy + row * rh;
			var rowFlags = flagsOf == null ? 0 : flagsOf(row, -1);
			if (rowFlags & ADDED != 0) canvas.rect(bx, ry, right - bx, rh, 0, c[GridTheme.ADDED], 0, 0);
			else if (rowFlags & DELETED != 0) canvas.rect(bx, ry, right - bx, rh, 0, c[GridTheme.DELETED], 0, 0);
			else if (row == hoverRow && drag <= 2) canvas.rect(bx, ry, right - bx, rh, 0, c[GridTheme.HOVER], 0, 0);
			for (col in c0...c1 + 1) {
				var cx = ox + lefts[col], cw = columns[col].width;
				var fl = flagsOf == null ? 0 : flagsOf(row, col);
				if (row >= r.top && row <= r.bottom && col >= r.left && col <= r.right) canvas.rect(cx, ry, cw, rh, 0, c[GridTheme.SELECTION], 0, 0);
				if (fl & EDITED != 0) canvas.rect(cx, ry, cw, rh, 0, c[GridTheme.EDITED], 0, 0);
				if (fl & LOADING != 0) {
					anyLoading = true;
					var sw = Math.min(cw - PAD * 2, 24 + ((row * 7 + col * 13) % 5) * 12);
					if (skeleton > 0) canvas.rect(cx + PAD, ry + rh / 2 - 4, sw, 8, 4, c[GridTheme.SKELETON].fade(skeleton), 0, 0);
					continue;
				}
				if (row == editRow && col == editCol && editor != null) continue;
				var t = text(row, col), isDefault = fl & DEFAULT != 0, isNull = isDefault || t == null || fl & NULL != 0;
				var link = fl & LINK != 0 && row == hoverRow && drag <= 2;
				var room = cw - PAD * 2;
				var p = layout(engine, isDefault ? "DEFAULT" : isNull ? "NULL" : shown(t), isNull ? detailFont : cellFont, room);
				var color = isNull ? c[GridTheme.MUTED] : rowFlags & DELETED != 0 ? c[GridTheme.MUTED] : c[GridTheme.FOREGROUND];
				var ty = Math.round((ry + (rh - p.height) / 2) * px) / px;
				canvas.text(p, cx + PAD, ty, room, columns[col].align, color);
				if (link) {
					// (a patch under it while the pointer is on it: what a press there does)
					var ax = ox + arrowX(col);
					if (col == hoverArrow) canvas.rect(ax - ARROW / 2, ry + 4, ARROW, rh - 8, 4, c[GridTheme.SELECTION], 0, 0);
					arrowOut(canvas, ax, ry + rh / 2, c[GridTheme.CURSOR]);
				}
				if (rowFlags & DELETED != 0) {
					var lw = Math.min(p.width, cw - PAD * 2), lx = columns[col].align == Right ? cx + cw - PAD - lw : cx + PAD;
					canvas.rect(lx, Math.round(ry + rh / 2), lw, 1, 0, c[GridTheme.MUTED], 0, 0);
				}
			}
			// (a hairline under the row)
			canvas.rect(bx, ry + rh - 1, right - bx, 1, 0, c[GridTheme.LINE], 0, 0);
		}
		// (loading: the skeletons shown after a moment, fading in; frames asked for until they are)
		if (!anyLoading) loadingSince = -1 else {
			if (loadingSince < 0) loadingSince = now;
			if (skeleton < 1) ui.requestFrame();
		}
		// (hairlines between the columns)
		var bottom = Math.min(y + height, oy + rowCount * rh);
		for (col in c0...c1 + 1)
			canvas.rect(ox + lefts[col + 1] - 1, by, 1, bottom - by, 0, c[GridTheme.LINE], 0, 0);
		// (the cursor: a ring round its cell)
		if (rowCount > 0 && columns.length > 0 && !wholeRows) {
			var cx = ox + lefts[cursorCol], cy = oy + cursorRow * rh;
			var ring = focusedNow ? c[GridTheme.CURSOR] : c[GridTheme.MUTED];
			// (inside its cell: the first row's under the header, the first column's beside the gutter, not cut)
			canvas.rect(cx + 1, cy, columns[cursorCol].width - 2, rh - 1, 2, Color.TRANSPARENT, focusedNow ? 2 : 1, ring);
		}
		canvas.popClip();
		paintHeader(canvas, engine, x, y, width, ox, c0, c1, right);
		if (rowNumbers) paintGutter(canvas, engine, x, oy, by, height, first, last, r);
		// (the corner)
		canvas.rect(x, y, gutterW, hh, 0, c[GridTheme.HEADER], 0, 0);
		canvas.rect(x, y + hh - 1, gutterW, 1, 0, c[GridTheme.LINE], 0, 0);
		if (gutterW > 0) canvas.rect(x + gutterW - 1, y, 1, hh, 0, c[GridTheme.LINE], 0, 0);
		paintBars(canvas, x, y, width, height);
		canvas.popClip();
	}

	function paintHeader(canvas:Canvas, engine:TextEngine, x:Float, y:Float, width:Float, ox:Float, c0:Int, c1:Int, right:Float) {
		var c = gridTheme.colors, hh = headerHeight;
		canvas.rect(x + gutterW, y, width - gutterW, hh, 0, c[GridTheme.HEADER], 0, 0);
		canvas.pushClip(x + gutterW, y, width - gutterW, hh, 0);
		for (col in c0...c1 + 1) {
			var col_ = columns[col], cx = ox + lefts[col], cw = col_.width;
			if (col == hoverCol && drag == 0) canvas.rect(cx, y, cw, hh, 0, c[GridTheme.HOVER], 0, 0);
			var room = cw - PAD * 2 - (col == sortColumn ? 14 : 0);
			var tp = layout(engine, col_.title, titleFont, room);
			var ty = Math.round(y + (hh - tp.height) / 2);
			var tx = cx + PAD;
			if (col_.align == Right) {
				var dw = col_.detail == "" ? 0 : Math.min(layout(engine, col_.detail, detailFont, room).width + 6, room - tp.width);
				tx = cx + cw - PAD - (col == sortColumn ? 14 : 0) - tp.width - (dw > 0 ? dw : 0);
			}
			canvas.text(tp, tx, ty, room, Left, c[GridTheme.HEADER_FOREGROUND]);
			var used = tp.width;
			if (col_.detail != "" && room - used > 24) {
				var dp = layout(engine, col_.detail, detailFont, room - used - 6);
				canvas.text(dp, tx + used + 6, Math.round(ty + tp.baseline - dp.baseline), room - used - 6, Left, c[GridTheme.MUTED]);
			}
			if (col == sortColumn) arrow(canvas, cx + cw - PAD - 8, y + hh / 2, sortDown, c[GridTheme.HEADER_FOREGROUND]);
			canvas.rect(cx + cw - 1, y + 8, 1, hh - 16, 0, c[GridTheme.LINE], 0, 0);
			if (col == hoverEdge || col == dragCol && drag == 3) canvas.rect(cx + cw - 2, y, 3, hh, 1, c[GridTheme.RESIZE], 0, 0);
		}
		canvas.popClip();
		canvas.rect(x + gutterW, y + hh - 1, width - gutterW, 1, 0, c[GridTheme.LINE], 0, 0);
	}

	// (a small chevron: down or up)
	static function arrow(canvas:Canvas, cx:Float, cy:Float, down:Bool, color:Color) {
		var p = new Path();
		var d = down ? 1 : -1;
		p.moveTo(cx - 3.5, cy - 1.75 * d);
		p.lineTo(cx, cy + 1.75 * d);
		p.lineTo(cx + 3.5, cy - 1.75 * d);
		canvas.path(p, null, {width: 1.5, paint: color, cap: Round, join: Round});
	}

	// (an arrow up and to the right: a link out)
	static function arrowOut(canvas:Canvas, cx:Float, cy:Float, color:Color) {
		var p = new Path();
		p.moveTo(cx - 3.5, cy + 3.5);
		p.lineTo(cx + 3.5, cy - 3.5);
		p.moveTo(cx - 2.5, cy - 3.5);
		p.lineTo(cx + 3.5, cy - 3.5);
		p.lineTo(cx + 3.5, cy + 2.5);
		canvas.path(p, null, {width: 1.5, paint: color, cap: Round, join: Round});
	}

	function paintGutter(canvas:Canvas, engine:TextEngine, x:Float, oy:Float, by:Float, height:Float, first:Int, last:Int, r:{top:Int, bottom:Int, left:Int, right:Int}) {
		var c = gridTheme.colors, rh = rowHeight;
		canvas.rect(x, by, gutterW, height - headerHeight, 0, c[GridTheme.GUTTER], 0, 0);
		canvas.pushClip(x, by, gutterW, height - headerHeight, 0);
		for (row in first...last + 1) {
			var ry = oy + row * rh, sel = row >= r.top && row <= r.bottom;
			if (sel) canvas.rect(x, ry, gutterW, rh, 0, c[GridTheme.SELECTION], 0, 0);
			var p = layout(engine, Std.string(row + 1), cellFont, gutterW - PAD * 2);
			var px = ui.scale > 0 ? ui.scale : 1.0;
			canvas.text(p, x + PAD, Math.round((ry + (rh - p.height) / 2) * px) / px, gutterW - PAD * 2, Right, sel ? c[GridTheme.FOREGROUND] : c[GridTheme.MUTED]);
			canvas.rect(x, ry + rh - 1, gutterW, 1, 0, c[GridTheme.LINE], 0, 0);
		}
		canvas.popClip();
		canvas.rect(x + gutterW - 1, by, 1, height - headerHeight, 0, c[GridTheme.LINE], 0, 0);
	}

	function paintBars(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		var color = gridTheme.colors[GridTheme.SCROLLBAR], held = gridTheme.colors[GridTheme.FOREGROUND].fade(0.5);
		if (dataH() > bodyH()) {
			var th = thumb(bodyH(), dataH(), scrollTop);
			canvas.rect(x + width - 8, y + headerHeight + th.at + 2, 5, th.size - 4, 2.5, drag == 4 ? held : color, 0, 0);
		}
		if (dataW() > bodyW()) {
			var th = thumb(bodyW(), dataW(), scrollLeft);
			canvas.rect(x + gutterW + th.at + 2, y + height - 8, th.size - 4, 5, 2.5, drag == 5 ? held : color, 0, 0);
		}
	}
}

// (the grid's editor: Enter and Down keep and move down, Up up, Tab right, Escape drops)
private class CellEditor extends TextField {
	final grid:DataGrid;

	public function new(grid:DataGrid, text:String) {
		super(text);
		this.grid = grid;
	}

	override function moreKeys(e:Event, shift:Bool, ctrl:Bool):Bool {
		switch e.key {
			case Key.ENTER:
				grid.commitEdit(true, shift ? -1 : 1);
			case Key.UP | Key.DOWN:
				grid.commitEdit(true, e.key == Key.UP ? -1 : 1);
			case Key.TAB:
				e.preventDefault();
				grid.commitEdit(true, 0, shift ? -1 : 1);
			case Key.ESCAPE:
				grid.cancelEdit();
			case _:
				return false;
		}
		return true;
	}
}
