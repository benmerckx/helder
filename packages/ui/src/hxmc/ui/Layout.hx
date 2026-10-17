package hxmc.ui;

// Flexbox layout of a Node tree, after CSS Flexible Box Layout (section 9),
// and CSS grid for a Display Grid container (grid() below):
// margins are pixels (no auto margins), no baseline alignment. A flex
// item's min size on the main axis is CSS's automatic minimum when auto
// (its content's: the min-content width in a row, the content's height in
// a column; no more than its width or height when given; 0 for Overflow
// Hidden and Scroll), so that content is not squashed. Sizes are border
// boxes; padding and borderWidth are inside.
//
// size(node, known, parent, available, perform) is the one function: the
// node's border-box size when its width or height may already be known
// (known: from the parent's flexing or stretching; NaN otherwise), the
// parent's content box (percentages) and the space available (NaN:
// unbounded, the max-content size). With perform, it also places the
// children (each laid out with both sizes known), else it only measures:
// those results are cached per node (a node and its ancestors forget them
// when it changes: Node.markDirty), so that measuring a child several times
// in a pass costs once. A whole subtree is skipped when it is clean and
// laid out with the same constraints as last time. At the end the boxes are
// rounded to whole pixels in window coordinates (each edge rounded, so that
// adjacent boxes stay adjacent).
class Layout {
	final text:TextEngine;
	// the last size() result
	var rw = 0.0;
	var rh = 0.0;

	static inline var CACHE = 4; // measured results kept per node
	static inline var ENTRY = 6; // knownW, knownH, availW, availH, width, height

	public function new(text:TextEngine)
		this.text = text;

	// lays out the tree in a viewport of width x height
	// whether anything was laid out again (a clean tree of the same size: nothing done)
	public static function run(root:Node, width:Float, height:Float, text:TextEngine):Bool {
		if (!root.dirty && root.lw == width && root.lh == height && !root.relaid) return false;
		var l = new Layout(text);
		l.size(root, width, height, width, height, width, height, true);
		root.lx = 0;
		root.ly = 0;
		round(root, 0, 0, 0, 0);
		return true;
	}

	// --- one node ---

	function size(n:Node, knownW:Float, knownH:Float, parentW:Float, parentH:Float, availW:Float, availH:Float, perform:Bool) {
		var s = n.style;
		if (s.display == None) {
			if (perform) hide(n);
			rw = rh = 0;
			return;
		}
		// the style's own size, clamped
		var minW = min(s.minWidth, parentW), maxW = max(s.maxWidth, parentW);
		var minH = min(s.minHeight, parentH), maxH = max(s.maxHeight, parentH);
		var w = known(knownW) ? knownW : clamp(s.width.resolve(parentW), minW, maxW);
		var h = known(knownH) ? knownH : clamp(s.height.resolve(parentH), minH, maxH);
		var ar = s.aspectRatio;
		if (ar > 0) {
			if (!known(w) && known(h)) w = clamp(h * ar, minW, maxW);
			else if (known(w) && !known(h)) h = clamp(w / ar, minH, maxH);
		}
		if (!perform && known(w) && known(h)) {
			rw = w;
			rh = h;
			return;
		}
		if (perform) {
			// (a clean subtree laid out with these constraints already)
			if (!n.dirty && same(n.lw, w) && same(n.lh, h) && known(w) && known(h)) {
				rw = w;
				rh = h;
				return;
			}
		} else if (lookup(n, w, h, availW, availH)) return;
		var pad = s.padding, be = s.borderEdges;
		var padL = pad.left + be.left, padT = pad.top + be.top, padH = pad.left + pad.right + be.left + be.right, padV = pad.top + pad.bottom + be.top + be.bottom;
		if (n.hasContent() && (n.children.length == 0 || n.contentOwnsChildren())) {
			// content: its measure in the content box
			var iw = known(w) ? Math.max(0, w - padH) : Math.NaN, ih = known(h) ? Math.max(0, h - padV) : Math.NaN;
			var aw = known(iw) ? iw : known(availW) ? Math.max(0, availW - padH) : Math.NaN;
			var ah = known(ih) ? ih : known(availH) ? Math.max(0, availH - padV) : Math.NaN;
			var m = n.measureContent(text, iw, ih, aw, ah);
			rw = known(w) ? w : clamp(m.width + padH, minW, maxW);
			rh = known(h) ? h : clamp(m.height + padV, minH, maxH);
			if (perform) {
				n.lw = rw;
				n.lh = rh;
				n.dirty = false;
				n.relaid = true;
			}
		} else if (s.display == Grid) grid(n, w, h, availW, availH, minW, maxW, minH, maxH, padL, padT, padH, padV, perform);
		else flex(n, w, h, availW, availH, minW, maxW, minH, maxH, padL, padT, padH, padV, perform);
		if (!perform) store(n, w, h, availW, availH, rw, rh);
	}

	// --- a flex container ---

	function flex(n:Node, w:Float, h:Float, availW:Float, availH:Float, minW:Float, maxW:Float, minH:Float, maxH:Float, padL:Float, padT:Float,
			padH:Float, padV:Float, perform:Bool) {
		var s = n.style;
		var row = s.direction == Row || s.direction == RowReverse;
		var reverse = s.direction == RowReverse || s.direction == ColumnReverse;
		// the content box, known or available, on each axis
		var innerW = known(w) ? Math.max(0, w - padH) : Math.NaN, innerH = known(h) ? Math.max(0, h - padV) : Math.NaN;
		var availInW = known(innerW) ? innerW : known(availW) ? Math.max(0, availW - padH) : Math.NaN;
		var availInH = known(innerH) ? innerH : known(availH) ? Math.max(0, availH - padV) : Math.NaN;
		var innerMain = row ? innerW : innerH, innerCross = row ? innerH : innerW;
		var availMain = row ? availInW : availInH, availCross = row ? availInH : availInW;
		var gapMain = row ? s.columnGap : s.rowGap, gapCross = row ? s.rowGap : s.columnGap;
		var minMain = (row ? minW : minH) - (row ? padH : padV), maxMain = (row ? maxW : maxH) - (row ? padH : padV);
		var minCross = (row ? minH : minW) - (row ? padV : padH), maxCross = (row ? maxH : maxW) - (row ? padV : padH);
		var multi = s.wrap;

		// the items and their hypothetical main sizes
		var items:Array<Item> = [], absolute:Array<Node> = [];
		for (c in n.children) {
			var cs = c.style;
			if (cs.display == None) {
				if (perform) hide(c);
				continue;
			}
			if (cs.position == Absolute) {
				absolute.push(c);
				continue;
			}
			var it = new Item(c);
			var m = cs.margin;
			it.mMainStart = row ? m.left : m.top;
			it.mMainEnd = row ? m.right : m.bottom;
			it.mCrossStart = row ? m.top : m.left;
			it.mCrossEnd = row ? m.bottom : m.right;
			it.minMain = min(row ? cs.minWidth : cs.minHeight, innerMain);
			it.maxMain = max(row ? cs.maxWidth : cs.maxHeight, innerMain);
			it.minCross = min(row ? cs.minHeight : cs.minWidth, innerCross);
			it.maxCross = max(row ? cs.maxHeight : cs.maxWidth, innerCross);
			it.align = cs.alignSelf == Auto ? s.alignItems : cs.alignSelf;
			if (it.align == Auto) it.align = Stretch;
			it.styleCross = clamp((row ? cs.height : cs.width).resolve(innerCross), it.minCross, it.maxCross);
			var b = cs.basis.resolve(innerMain);
			if (!known(b)) b = (row ? cs.width : cs.height).resolve(innerMain);
			var contentBasis = !known(b);
			if (!known(b) && cs.aspectRatio > 0 && known(it.styleCross)) b = row ? it.styleCross * cs.aspectRatio : it.styleCross / cs.aspectRatio;
			if (!known(b)) {
				// the content's main size, its cross size known when stretched in a known line
				var kc = it.styleCross;
				if (!known(kc) && it.align == Stretch && !multi && known(innerCross)) kc = Math.max(0, innerCross - it.mCrossStart - it.mCrossEnd);
				var am = known(availMain) ? Math.max(0, availMain - it.mMainStart - it.mMainEnd) : Math.NaN;
				var ac = known(kc) ? kc : known(availCross) ? Math.max(0, availCross - it.mCrossStart - it.mCrossEnd) : Math.NaN;
				if (row) size(c, Math.NaN, kc, innerW, innerH, am, ac, false) else size(c, kc, Math.NaN, innerW, innerH, ac, am, false);
				b = row ? rw : rh;
			}
			it.basis = b;
			// the automatic minimum
			if ((row ? cs.minWidth : cs.minHeight) == DimValue.Auto && cs.overflow == Visible) {
				var content:Float;
				if (row) content = minContentWidth(c, innerW, false) else if (contentBasis) content = b else {
					var kc = it.styleCross;
					if (!known(kc) && it.align == Stretch && !multi && known(innerCross)) kc = Math.max(0, innerCross - it.mCrossStart - it.mCrossEnd);
					var ac = known(kc) ? kc : known(availCross) ? Math.max(0, availCross - it.mCrossStart - it.mCrossEnd) : Math.NaN;
					size(c, kc, Math.NaN, innerW, innerH, ac, Math.NaN, false);
					content = rh;
				}
				var spec = (row ? cs.width : cs.height).resolve(innerMain);
				if (known(spec) && spec < content) content = spec;
				it.minMain = Math.min(content, it.maxMain);
			}
			it.hypo = clamp(b, it.minMain, it.maxMain);
			items.push(it);
		}

		// lines
		var lines:Array<Line> = [];
		var line = new Line(), sum = 0.0;
		for (it in items) {
			var outer = it.hypo + it.mMainStart + it.mMainEnd;
			if (multi && known(availMain) && line.items.length > 0 && sum + gapMain + outer > availMain + 1e-6) {
				lines.push(line);
				line = new Line();
				sum = 0;
			}
			sum += (line.items.length > 0 ? gapMain : 0) + outer;
			line.items.push(it);
		}
		if (line.items.length > 0 || lines.length == 0) lines.push(line);

		// the container's main size
		var mainSize = innerMain;
		if (!known(mainSize)) {
			var content = 0.0;
			for (l in lines) {
				var t = 0.0;
				for (i in 0...l.items.length) {
					var it = l.items[i];
					t += it.hypo + it.mMainStart + it.mMainEnd + (i > 0 ? gapMain : 0);
				}
				if (t > content) content = t;
			}
			mainSize = known(availMain) ? Math.min(content, availMain) : content;
			mainSize = clamp(mainSize, Math.max(0, minMain), maxMain);
		}

		// flexible lengths, then the items' cross sizes
		for (l in lines) {
			resolveFlexible(l, mainSize, gapMain);
			var lc = 0.0;
			for (it in l.items) {
				if (known(it.styleCross)) it.cross = it.styleCross else {
					var ac = known(innerCross) ? Math.max(0, innerCross - it.mCrossStart - it.mCrossEnd) : known(availCross) ? Math.max(0,
						availCross - it.mCrossStart - it.mCrossEnd) : Math.NaN;
					if (it.align == Stretch && !multi && known(innerCross)) it.cross = clamp(ac, it.minCross, it.maxCross) else {
						if (row) size(it.node, it.main, Math.NaN, innerW, innerH, it.main, ac, false) else size(it.node, Math.NaN, it.main, innerW, innerH, ac,
							it.main, false);
						it.cross = clamp(row ? rh : rw, it.minCross, it.maxCross);
					}
				}
				var oc = it.cross + it.mCrossStart + it.mCrossEnd;
				if (oc > lc) lc = oc;
			}
			l.cross = lc;
		}
		if (!multi && known(innerCross)) lines[0].cross = innerCross;

		// the container's cross size
		var crossSize = innerCross;
		if (!known(crossSize)) {
			crossSize = 0;
			for (i in 0...lines.length)
				crossSize += lines[i].cross + (i > 0 ? gapCross : 0);
			crossSize = clamp(crossSize, Math.max(0, minCross), maxCross);
			if (!multi) lines[0].cross = crossSize;
		}
		var bw = row ? mainSize + padH : crossSize + padH, bh = row ? crossSize + padV : mainSize + padV;
		if (!perform) {
			rw = bw;
			rh = bh;
			return;
		}

		// the lines across: align-content
		var used = 0.0;
		for (i in 0...lines.length)
			used += lines[i].cross + (i > 0 ? gapCross : 0);
		var free = crossSize - used, start = 0.0, between = 0.0;
		if (multi) switch s.alignContent {
			case Start | Normal:
			case End: start = free;
			case Center: start = free / 2;
			case Stretch if (free > 0):
				for (l in lines)
					l.cross += free / lines.length;
			case Stretch:
			case SpaceBetween if (free > 0 && lines.length > 1): between = free / (lines.length - 1);
			case SpaceBetween:
			case SpaceAround if (free > 0):
				between = free / lines.length;
				start = between / 2;
			case SpaceAround: start = free / 2;
			case SpaceEvenly if (free > 0):
				between = free / (lines.length + 1);
				start = between;
			case SpaceEvenly: start = free / 2;
		}
		var lineStart = start;
		var cw = 0.0, ch = 0.0;
		for (l in lines) {
			// stretch, then place along the main axis (justify) and across the line (align)
			var n = l.items.length, taken = 0.0;
			for (it in l.items) {
				if (it.align == Stretch && !known(it.styleCross))
					it.cross = clamp(l.cross - it.mCrossStart - it.mCrossEnd, it.minCross, it.maxCross);
				taken += it.main + it.mMainStart + it.mMainEnd;
			}
			taken += gapMain * (n - 1);
			var free = mainSize - taken, pos = 0.0, gap = gapMain;
			switch s.justify {
				case Start | Normal:
				case End: pos = free;
				case Center: pos = free / 2;
				case SpaceBetween if (free > 0 && n > 1): gap += free / (n - 1);
				case SpaceBetween:
				case SpaceAround if (free > 0):
					gap += free / n;
					pos = free / n / 2;
				case SpaceAround: pos = free / 2;
				case SpaceEvenly if (free > 0):
					gap += free / (n + 1);
					pos = free / (n + 1);
				case SpaceEvenly: pos = free / 2;
			}
			for (it in l.items) {
				var mainPos = pos + it.mMainStart;
				var crossPos = lineStart + switch it.align {
					case End: l.cross - it.cross - it.mCrossEnd;
					case Center: it.mCrossStart + (l.cross - it.mCrossStart - it.mCrossEnd - it.cross) / 2;
					case _: it.mCrossStart;
				}
				if (reverse) mainPos = mainSize - mainPos - it.main;
				var c = it.node;
				var cx = padL + (row ? mainPos : crossPos), cy = padT + (row ? crossPos : mainPos);
				var cwid = row ? it.main : it.cross, chei = row ? it.cross : it.main;
				// (Relative: shifted by its offsets)
				var cs = c.style;
				var dx = cs.left.resolve(innerW), dy = cs.top.resolve(innerH);
				if (!known(dx)) dx = -cs.right.resolve(innerW);
				if (!known(dy)) dy = -cs.bottom.resolve(innerH);
				// (Sticky: its offsets are where it sticks, not a shift)
				if (cs.position == Sticky) dx = dy = Math.NaN;
				c.lx = cx + (known(dx) ? dx : 0);
				c.ly = cy + (known(dy) ? dy : 0);
				size(c, cwid, chei, innerW, innerH, cwid, chei, true);
				c.lw = cwid;
				c.lh = chei;
				pos += it.main + it.mMainStart + it.mMainEnd + gap;
				var ex = cx - padL + cwid + (row ? it.mMainEnd : it.mCrossEnd), ey = cy - padT + chei + (row ? it.mCrossEnd : it.mMainEnd);
				if (ex > cw) cw = ex;
				if (ey > ch) ch = ey;
			}
			lineStart += l.cross + gapCross + between;
		}

		absolutes(n, absolute, bw, bh, padL, padT);
		n.lw = bw;
		n.lh = bh;
		@:privateAccess n.contentWidth = cw;
		@:privateAccess n.contentHeight = ch;
		n.dirty = false;
		n.relaid = true;
		rw = bw;
		rh = bh;
	}

	// --- a grid container ---

	// CSS Grid Layout (level 1, a subset): the explicit grid's tracks, implicit
	// ones added as items need (gridAutoRows, gridAutoColumns), the items
	// placed by their lines or auto-placed (sparse, by rows or columns); the
	// tracks sized columns first, then rows at the columns' widths (fixed
	// sizes; intrinsic ones from the items' min- and max-content
	// contributions, a spanning item's growth shared equally; the free space
	// up to the limits; fr shares of what is left; auto tracks stretched when
	// justify and alignContent are their defaults, CSS's normal); each item
	// in its area by justifySelf (or the container's justifyItems) and
	// alignSelf (or alignItems). Named areas (gridTemplateAreas, items
	// placed by their names), no other named lines, no subgrid.
	function grid(n:Node, w:Float, h:Float, availW:Float, availH:Float, minW:Float, maxW:Float, minH:Float, maxH:Float, padL:Float, padT:Float,
			padH:Float, padV:Float, perform:Bool) {
		var s = n.style;
		var innerW = known(w) ? Math.max(0, w - padH) : Math.NaN, innerH = known(h) ? Math.max(0, h - padV) : Math.NaN;
		var availInW = known(innerW) ? innerW : known(availW) ? Math.max(0, availW - padH) : Math.NaN;
		var availInH = known(innerH) ? innerH : known(availH) ? Math.max(0, availH - padV) : Math.NaN;
		var items:Array<GridItem> = [], absolute:Array<Node> = [];
		for (c in n.children) {
			var cs = c.style;
			if (cs.display == None) {
				if (perform) hide(c);
				continue;
			}
			if (cs.position == Absolute) {
				absolute.push(c);
				continue;
			}
			items.push(new GridItem(c));
		}
		var colsTemplate = s.gridTemplateColumns, rowsTemplate = s.gridTemplateRows;
		place(items, s);
		var nCols = gridColumnCount(s), nRows = gridRowCount(s);
		for (it in items) {
			if (it.col + it.colSpan > nCols) nCols = it.col + it.colSpan;
			if (it.row + it.rowSpan > nRows) nRows = it.row + it.rowSpan;
		}
		var colTracks = [for (i in 0...nCols) i < colsTemplate.length ? colsTemplate[i] : s.gridAutoColumns];
		var rowTracks = [for (i in 0...nRows) i < rowsTemplate.length ? rowsTemplate[i] : s.gridAutoRows];
		var colGap = s.columnGap, rowGap = s.rowGap;

		// the columns: at the content box's width, else at their max-content sizes (then the available width, when that is less)
		var stretchCols = s.justify == Normal;
		var cols = tracks(colTracks, items, true, innerW, colGap, stretchCols, innerW, innerH, null);
		var gridW = sum(cols, colGap);
		if (!known(innerW) && known(availInW) && gridW > availInW + 1e-6) {
			cols = tracks(colTracks, items, true, availInW, colGap, false, innerW, innerH, null);
			gridW = sum(cols, colGap);
		}
		var width = known(innerW) ? innerW : clamp(gridW, Math.max(0, minW - padH), maxW - padH);
		if (!known(innerW) && width > gridW + 1e-6 && stretchCols) {
			cols = tracks(colTracks, items, true, width, colGap, true, width, innerH, null);
			gridW = sum(cols, colGap);
		}
		// the rows: the items at their columns' widths
		for (it in items) {
			it.areaW = colGap * (it.colSpan - 1);
			for (i in it.col...it.col + it.colSpan)
				it.areaW += cols[i];
		}
		var stretchRows = s.alignContent == Normal || s.alignContent == Stretch;
		var rows = tracks(rowTracks, items, false, innerH, rowGap, stretchRows, width, innerH, cols);
		var gridH = sum(rows, rowGap);
		var height = known(innerH) ? innerH : clamp(gridH, Math.max(0, minH - padV), maxH - padV);
		var bw = width + padH, bh = height + padV;
		if (!perform) {
			rw = bw;
			rh = bh;
			return;
		}

		// the tracks' places (justify and alignContent: the tracks in the content box)
		var colPos = positions(cols, colGap, width, s.justify);
		var rowPos = positions(rows, rowGap, height, switch s.alignContent {
			case End: Justify.End;
			case Center: Justify.Center;
			case SpaceBetween: Justify.SpaceBetween;
			case SpaceAround: Justify.SpaceAround;
			case SpaceEvenly: Justify.SpaceEvenly;
			case _: Justify.Start;
		});
		var cw = 0.0, ch = 0.0;
		for (it in items) {
			var c = it.node, cs = c.style, m = cs.margin;
			var ax = colPos[it.col], aw = colPos[it.col + it.colSpan - 1] + cols[it.col + it.colSpan - 1] - ax;
			var ay = rowPos[it.row], ah = rowPos[it.row + it.rowSpan - 1] + rows[it.row + it.rowSpan - 1] - ay;
			var jx = cs.justifySelf == Auto ? s.justifyItems : cs.justifySelf;
			if (jx == Auto) jx = Stretch;
			var jy = cs.alignSelf == Auto ? s.alignItems : cs.alignSelf;
			if (jy == Auto) jy = Stretch;
			var minCW = min(cs.minWidth, width), maxCW = max(cs.maxWidth, width), minCH = min(cs.minHeight, height), maxCH = max(cs.maxHeight, height);
			var iw = clamp(cs.width.resolve(width), minCW, maxCW), ih = clamp(cs.height.resolve(height), minCH, maxCH);
			var roomW = Math.max(0, aw - m.left - m.right), roomH = Math.max(0, ah - m.top - m.bottom);
			if (!known(iw)) {
				if (jx == Stretch) iw = clamp(roomW, minCW, maxCW) else {
					// (fit-content: its max-content width, no more than the area)
					size(c, Math.NaN, ih, width, height, roomW, known(ih) ? ih : roomH, false);
					iw = clamp(Math.min(rw, Math.max(roomW, minContentWidth(c, width, false))), minCW, maxCW);
					if (rw <= roomW) iw = clamp(rw, minCW, maxCW);
				}
			}
			if (!known(ih)) {
				if (jy == Stretch) ih = clamp(roomH, minCH, maxCH) else {
					size(c, iw, Math.NaN, width, height, iw, roomH, false);
					ih = clamp(rh, minCH, maxCH);
				}
			}
			var x = ax + m.left + switch jx {
				case End: roomW - iw;
				case Center: (roomW - iw) / 2;
				case _: 0;
			}
			var y = ay + m.top + switch jy {
				case End: roomH - ih;
				case Center: (roomH - ih) / 2;
				case _: 0;
			}
			var dx = cs.left.resolve(width), dy = cs.top.resolve(height);
			if (!known(dx)) dx = -cs.right.resolve(width);
			if (!known(dy)) dy = -cs.bottom.resolve(height);
			if (cs.position == Sticky) dx = dy = Math.NaN;
			c.lx = padL + x + (known(dx) ? dx : 0);
			c.ly = padT + y + (known(dy) ? dy : 0);
			size(c, iw, ih, width, height, iw, ih, true);
			c.lw = iw;
			c.lh = ih;
			if (x + iw + m.right > cw) cw = x + iw + m.right;
			if (y + ih + m.bottom > ch) ch = y + ih + m.bottom;
		}
		absolutes(n, absolute, bw, bh, padL, padT);
		n.lw = bw;
		n.lh = bh;
		@:privateAccess n.contentWidth = Math.max(cw, gridW);
		@:privateAccess n.contentHeight = Math.max(ch, gridH);
		n.dirty = false;
		n.relaid = true;
		rw = bw;
		rh = bh;
	}

	// a grid's min-content width: its columns sized at an available width of 0
	function gridMinContent(n:Node):Float {
		var s = n.style;
		var items = [for (c in n.children) if (c.style.display != None && c.style.position != Absolute) new GridItem(c)];
		place(items, s);
		var nCols = gridColumnCount(s);
		for (it in items)
			if (it.col + it.colSpan > nCols) nCols = it.col + it.colSpan;
		var defs = [for (i in 0...nCols) i < s.gridTemplateColumns.length ? s.gridTemplateColumns[i] : s.gridAutoColumns];
		return sum(tracks(defs, items, true, 0, s.columnGap, false, Math.NaN, Math.NaN, null), s.columnGap);
	}

	static function sum(sizes:Array<Float>, gap:Float):Float {
		var t = 0.0;
		for (v in sizes)
			t += v;
		return t + (sizes.length > 1 ? gap * (sizes.length - 1) : 0);
	}

	// each track's start: packed from the start, or placed as justify puts items
	static function positions(sizes:Array<Float>, gap:Float, room:Float, j:Justify):Array<Float> {
		var n = sizes.length, free = room - sum(sizes, gap), pos = 0.0, g = gap;
		if (n > 0 && free > 0) switch j {
			case End: pos = free;
			case Center: pos = free / 2;
			case SpaceBetween if (n > 1): g += free / (n - 1);
			case SpaceAround:
				g += free / n;
				pos = free / n / 2;
			case SpaceEvenly:
				g += free / (n + 1);
				pos = free / (n + 1);
			case _:
		}
		var out = [];
		for (v in sizes) {
			out.push(pos);
			pos += v + g;
		}
		return out;
	}

	// the explicit grid's size: its templates', its areas' if more
	static function gridColumnCount(s:Style):Int
		return s.gridTemplateAreas == null ? s.gridTemplateColumns.length : Std.int(Math.max(s.gridTemplateColumns.length, s.gridTemplateAreas.columns));

	static function gridRowCount(s:Style):Int
		return s.gridTemplateAreas == null ? s.gridTemplateRows.length : Std.int(Math.max(s.gridTemplateRows.length, s.gridTemplateAreas.rows));

	// the items' cells: those with both lines first, then those locked to a
	// row (a column, flowing by columns), then the rest by the cursor (sparse)
	static function place(items:Array<GridItem>, s:Style) {
		var explicitCols = gridColumnCount(s), explicitRows = gridRowCount(s), byColumn = s.gridAutoFlow == Column;
		var areas = s.gridTemplateAreas;
		// (a line's index from 0; negative lines from the explicit grid's end;
		// a name's: its area's start or end line, else the first line past the explicit grid)
		function resolve(p:Grid.GridPlacement, count:Int, columns:Bool):{start:Int, span:Int} {
			inline function index(line:Int):Int
				return line > 0 ? line - 1 : count + 1 + line;
			function named(name:String, isEnd:Bool):Int {
				var atEnd = isEnd;
				var a = areas == null ? null : areas.areas.get(name);
				if (a == null && areas != null) {
					for (suffix in ["-start", "-end"])
						if (StringTools.endsWith(name, suffix)) {
							a = areas.areas.get(name.substr(0, name.length - suffix.length));
							atEnd = suffix == "-end";
						}
				}
				if (a == null) return count + (isEnd ? 1 : 0);
				return columns ? (atEnd ? a.colEnd : a.col) : (atEnd ? a.rowEnd : a.row);
			}
			if (p.startName != null || p.endName != null) {
				var a = p.startName != null ? named(p.startName, false) : p.start != 0 ? index(p.start) : -1;
				var b = p.endName != null ? named(p.endName, true) : p.end != 0 ? index(p.end) : -1;
				if (a >= 0 && b >= 0) {
					// (the same line twice: the end dropped)
					if (b == a) return {start: a, span: 1};
					if (b < a) return {start: b, span: a - b};
					return {start: a, span: b - a};
				}
				if (a >= 0) return {start: a, span: p.span};
				return {start: Std.int(Math.max(0, b - p.span)), span: p.span};
			}
			if (p.start != 0 && p.end != 0) {
				var a = index(p.start), b = index(p.end);
				if (b < a) {
					var t = a;
					a = b;
					b = t;
				}
				return {start: Std.int(Math.max(0, a)), span: Std.int(Math.max(1, b - a))};
			}
			if (p.start != 0) return {start: Std.int(Math.max(0, index(p.start))), span: p.span};
			if (p.end != 0) return {start: Std.int(Math.max(0, index(p.end) - p.span)), span: p.span};
			return {start: -1, span: p.span};
		}
		// (the flow's axes: major across, minor along a row of the flow)
		var minorCount = byColumn ? explicitRows : explicitCols;
		var taken = new Map<Int, Bool>();
		inline function key(major:Int, minor:Int):Int
			return major * 4096 + minor;
		function free(major:Int, minor:Int, majorSpan:Int, minorSpan:Int):Bool {
			for (a in major...major + majorSpan)
				for (b in minor...minor + minorSpan)
					if (taken.exists(key(a, b))) return false;
			return true;
		}
		function take(it:GridItem, major:Int, minor:Int, majorSpan:Int, minorSpan:Int) {
			for (a in major...major + majorSpan)
				for (b in minor...minor + minorSpan)
					taken.set(key(a, b), true);
			if (byColumn) {
				it.col = major;
				it.row = minor;
				it.colSpan = majorSpan;
				it.rowSpan = minorSpan;
			} else {
				it.row = major;
				it.col = minor;
				it.rowSpan = majorSpan;
				it.colSpan = minorSpan;
			}
		}
		var res = [for (it in items) {
			var c = resolve(it.node.style.gridColumn, explicitCols, true), r = resolve(it.node.style.gridRow, explicitRows, false);
			byColumn ? {major: c, minor: r} : {major: r, minor: c};
		}];
		for (k in 0...items.length) {
			var minorEnd = res[k].minor.start + res[k].minor.span;
			if (res[k].minor.start >= 0 && minorEnd > minorCount) minorCount = minorEnd;
			if (res[k].minor.start < 0 && res[k].minor.span > minorCount) minorCount = res[k].minor.span;
		}
		var done = [for (_ in items) false];
		// both lines given
		for (k in 0...items.length) {
			var a = res[k].major, b = res[k].minor;
			if (a.start >= 0 && b.start >= 0) {
				take(items[k], a.start, b.start, a.span, b.span);
				done[k] = true;
			}
		}
		// locked to a major track: the first place along it, after what this step put there
		var cursors = new Map<Int, Int>();
		for (k in 0...items.length) {
			if (done[k]) continue;
			var a = res[k].major, b = res[k].minor;
			if (a.start < 0) continue;
			var minor = cursors.exists(a.start) ? cursors.get(a.start) : 0;
			while (!free(a.start, minor, a.span, b.span))
				minor++;
			take(items[k], a.start, minor, a.span, b.span);
			cursors.set(a.start, minor + b.span);
			if (minor + b.span > minorCount) minorCount = minor + b.span;
			done[k] = true;
		}
		// the rest: from the cursor on
		var curMajor = 0, curMinor = 0;
		for (k in 0...items.length) {
			if (done[k]) continue;
			var a = res[k].major, b = res[k].minor;
			if (b.start >= 0) {
				// (its minor line given: the next major track where it fits)
				if (b.start < curMinor) curMajor++;
				curMinor = b.start;
				while (!free(curMajor, curMinor, a.span, b.span))
					curMajor++;
			} else {
				while (true) {
					if (curMinor + b.span > minorCount) {
						curMajor++;
						curMinor = 0;
					}
					if (free(curMajor, curMinor, a.span, b.span)) break;
					curMinor++;
				}
			}
			take(items[k], curMajor, curMinor, a.span, b.span);
			curMinor += b.span;
		}
	}

	// the sizes of one axis's tracks (room: the content box's size on it,
	// NaN when indefinite; stretch: auto tracks take what is left); the
	// items' contributions measured with gridW and gridH as their
	// percentages' base, rows at the columns' sizes (cols)
	function tracks(defs:Array<Grid.Track>, items:Array<GridItem>, columns:Bool, room:Float, gap:Float, stretch:Bool, gridW:Float, gridH:Float,
			cols:Null<Array<Float>>):Array<Float> {
		var n = defs.length;
		var base = [for (_ in 0...n) 0.0], limit = [for (_ in 0...n) Math.POSITIVE_INFINITY], flex = [for (_ in 0...n) 0.0];
		inline function fixed(t:Grid.TrackSize):Float
			return switch t {
				case Px(v): v;
				case Percent(p): known(room) ? room * p / 100 : Math.NaN;
				case _: Math.NaN;
			}
		for (i in 0...n) {
			var d = defs[i];
			var mn = fixed(d.min), mx = fixed(d.max);
			if (known(mn)) base[i] = mn;
			switch d.max {
				case Fr(f): flex[i] = f;
				case _: if (known(mx)) limit[i] = mx;
			}
			// (a percentage of an indefinite size: auto)
			if (limit[i] < base[i]) limit[i] = base[i];
		}
		inline function intrinsicMin(i:Int):Bool
			return switch defs[i].min {
				case Auto | MinContent | MaxContent: true;
				case Percent(_): !known(room);
				case _: false;
			}
		// the items' contributions on this axis (outer sizes)
		var mins = [], maxes = [];
		for (it in items) {
			var c = it.node, cs = c.style, m = cs.margin;
			if (columns) {
				mins.push(minContentWidth(c, gridW, true) + m.left + m.right);
				size(c, Math.NaN, Math.NaN, gridW, gridH, Math.NaN, Math.NaN, false);
				maxes.push(rw + m.left + m.right);
			} else {
				var room2 = Math.max(0, it.areaW - m.left - m.right);
				var iw = cs.width.resolve(gridW);
				var jx = cs.justifySelf == Auto ? it.node.parent.style.justifyItems : cs.justifySelf;
				if (!known(iw) && (jx == Stretch || jx == Auto)) iw = room2;
				size(c, iw, Math.NaN, gridW, gridH, known(iw) ? iw : room2, Math.NaN, false);
				var v = rh + m.top + m.bottom;
				mins.push(v);
				maxes.push(v);
			}
		}
		inline function startOf(it:GridItem):Int
			return columns ? it.col : it.row;
		inline function spanOf(it:GridItem):Int
			return columns ? it.colSpan : it.rowSpan;
		// items not crossing a flexible track, by their span
		var maxSpan = 1;
		for (it in items)
			if (spanOf(it) > maxSpan) maxSpan = spanOf(it);
		for (span in 1...maxSpan + 1)
			for (k in 0...items.length) {
				var it = items[k];
				if (spanOf(it) != span) continue;
				var a = startOf(it), crossesFlex = false;
				for (i in a...a + span)
					if (flex[i] > 0) crossesFlex = true;
				if (crossesFlex) continue;
				var g = gap * (span - 1);
				// the minimums: what is missing shared by the tracks whose minimum is intrinsic
				var have = g, targets = [];
				for (i in a...a + span) {
					have += base[i];
					if (intrinsicMin(i)) targets.push(i);
				}
				var wantMin = switch span == 1 ? defs[a].min : Grid.TrackSize.Auto {
					case MaxContent: maxes[k];
					case _: mins[k];
				}
				if (wantMin > have && targets.length > 0)
					for (i in targets)
						base[i] += (wantMin - have) / targets.length;
				// the limits: an intrinsic maximum grows to the max-content contribution
				var haveL = g, ltargets = [];
				for (i in a...a + span) {
					var mx = defs[i].max;
					var intrinsic = switch mx {
						case Auto | MinContent | MaxContent: true;
						case _: false;
					}
					if (intrinsic) {
						ltargets.push(i);
						haveL += limit[i] == Math.POSITIVE_INFINITY ? base[i] : limit[i];
					} else haveL += limit[i];
				}
				var wantMax = span == 1 && defs[a].max == Grid.TrackSize.MinContent ? mins[k] : maxes[k];
				for (i in ltargets)
					if (limit[i] == Math.POSITIVE_INFINITY) limit[i] = base[i];
				if (wantMax > haveL && ltargets.length > 0)
					for (i in ltargets)
						limit[i] += (wantMax - haveL) / ltargets.length;
				for (i in a...a + span)
					if (limit[i] < base[i]) limit[i] = base[i];
			}
		for (i in 0...n)
			if (limit[i] == Math.POSITIVE_INFINITY && flex[i] == 0) limit[i] = base[i];
		// items crossing flexible tracks: their minimum shared by the flexible tracks, by flex factor
		for (k in 0...items.length) {
			var it = items[k], a = startOf(it), span = spanOf(it);
			var have = gap * (span - 1), fsum = 0.0;
			for (i in a...a + span) {
				have += base[i];
				if (flex[i] > 0 && intrinsicMin(i)) fsum += flex[i];
			}
			if (fsum > 0 && mins[k] > have)
				for (i in a...a + span)
					if (flex[i] > 0 && intrinsicMin(i)) base[i] += (mins[k] - have) * flex[i] / fsum;
		}
		var gaps = n > 1 ? gap * (n - 1) : 0.0;
		// the free space up to the limits (indefinite: every limit)
		if (known(room)) {
			var free = room - gaps;
			for (i in 0...n)
				free -= base[i];
			var growing = [for (i in 0...n) if (flex[i] == 0 && limit[i] > base[i]) i];
			while (free > 1e-9 && growing.length > 0) {
				var share = free / growing.length, next = [];
				for (i in growing) {
					var d = Math.min(share, limit[i] - base[i]);
					base[i] += d;
					free -= d;
					if (limit[i] > base[i] + 1e-9) next.push(i);
				}
				growing = next;
			}
		} else
			for (i in 0...n)
				if (flex[i] == 0) base[i] = limit[i];
		// fr: shares of what is left (indefinite: the largest share an item or track needs)
		var anyFlex = false;
		for (f in flex)
			if (f > 0) anyFlex = true;
		if (anyFlex) {
			var fr = 0.0;
			if (known(room)) {
				var inflexible = [for (i in 0...n) flex[i] == 0];
				while (true) {
					var left = room - gaps, fsum = 0.0;
					for (i in 0...n)
						if (inflexible[i]) left -= base[i] else fsum += flex[i];
					fr = fsum > 0 ? Math.max(0, left) / Math.max(1, fsum) : 0;
					var again = false;
					for (i in 0...n)
						if (!inflexible[i] && fr * flex[i] < base[i]) {
							inflexible[i] = true;
							again = true;
						}
					if (!again) break;
				}
			} else {
				for (i in 0...n)
					if (flex[i] > 0) fr = Math.max(fr, base[i] / Math.max(1, flex[i]));
				for (k in 0...items.length) {
					var it = items[k], a = startOf(it), span = spanOf(it), fsum = 0.0, rest = gap * (span - 1);
					for (i in a...a + span)
						if (flex[i] > 0) fsum += flex[i] else rest += base[i];
					if (fsum > 0) fr = Math.max(fr, (maxes[k] - rest) / Math.max(1, fsum));
				}
			}
			for (i in 0...n)
				if (flex[i] > 0) base[i] = Math.max(base[i], fr * flex[i]);
		}
		// auto tracks stretched over what is left
		if (stretch && known(room)) {
			var free = room - gaps, autos = [];
			for (i in 0...n) {
				free -= base[i];
				if (defs[i].max == Grid.TrackSize.Auto) autos.push(i);
			}
			if (free > 1e-9 && autos.length > 0)
				for (i in autos)
					base[i] += free / autos.length;
		}
		return base;
	}

	// absolute children, in the padding box of a container bw x bh
	function absolutes(n:Node, absolute:Array<Node>, bw:Float, bh:Float, padL:Float, padT:Float) {
		var s = n.style;
		var be = s.borderEdges, pbW = bw - be.left - be.right, pbH = bh - be.top - be.bottom;
		for (c in absolute) {
			var cs = c.style, m = cs.margin;
			var l = cs.left.resolve(pbW), r = cs.right.resolve(pbW), t = cs.top.resolve(pbH), b = cs.bottom.resolve(pbH);
			var aw = cs.width.resolve(pbW), ah = cs.height.resolve(pbH);
			if (!known(aw) && known(l) && known(r)) aw = Math.max(0, pbW - l - r - m.left - m.right);
			if (!known(ah) && known(t) && known(b)) ah = Math.max(0, pbH - t - b - m.top - m.bottom);
			aw = clamp(aw, min(cs.minWidth, pbW), max(cs.maxWidth, pbW));
			ah = clamp(ah, min(cs.minHeight, pbH), max(cs.maxHeight, pbH));
			if (!known(aw) || !known(ah)) {
				size(c, aw, ah, pbW, pbH, known(aw) ? aw : pbW, known(ah) ? ah : pbH, false);
				aw = rw;
				ah = rh;
			}
			var ax = known(l) ? l + m.left : known(r) ? pbW - r - aw - m.right : padL - be.left + m.left;
			var ay = known(t) ? t + m.top : known(b) ? pbH - b - ah - m.bottom : padT - be.top + m.top;
			c.lx = be.left + ax;
			c.ly = be.top + ay;
			size(c, aw, ah, pbW, pbH, aw, ah, true);
			c.lw = aw;
			c.lh = ah;
		}
	}

	// the min-content width of a node's border box (CSS: its words unbroken,
	// a row's items side by side, a column's or wrapping row's widest item;
	// content is measured at an available width of 0); as a contribution to
	// its parent's, a given width is its own
	function minContentWidth(n:Node, parentW:Float, contribution:Bool):Float {
		var s = n.style;
		if (s.display == None) return 0;
		var minW = min(s.minWidth, parentW), maxW = max(s.maxWidth, parentW);
		var w = s.width.resolve(parentW);
		if (contribution && known(w)) return clamp(w, minW, maxW);
		var cached = n.minContent;
		if (known(cached)) return cached;
		var padH = s.padding.left + s.padding.right + s.borderEdges.left + s.borderEdges.right;
		var inner = 0.0;
		if (n.hasContent() && (n.children.length == 0 || n.contentOwnsChildren())) inner = n.minContentWidth(text) else if (s.display == Grid) inner = gridMinContent(n) else {
			var row = (s.direction == Row || s.direction == RowReverse) && !s.wrap;
			var count = 0;
			for (c in n.children) {
				var cs = c.style;
				if (cs.display == None || cs.position == Absolute) continue;
				var m = cs.margin;
				var cw = clamp(minContentWidth(c, Math.NaN, true), min(cs.minWidth, Math.NaN), max(cs.maxWidth, Math.NaN)) + m.left + m.right;
				if (row) inner += cw + (count > 0 ? s.columnGap : 0) else if (cw > inner) inner = cw;
				count++;
			}
		}
		// (the content alone: not clamped by this node's own min or max)
		var r = inner + padH;
		n.minContent = r;
		return contribution ? clamp(r, minW, maxW) : r;
	}

	// CSS 9.7: the items' main sizes in a line of the container's main size
	static function resolveFlexible(l:Line, mainSize:Float, gap:Float) {
		var items = l.items;
		var gaps = gap * (items.length - 1);
		var hypo = gaps;
		for (it in items)
			hypo += it.hypo + it.mMainStart + it.mMainEnd;
		var growing = hypo < mainSize;
		for (it in items) {
			var factor = growing ? it.node.style.grow : it.node.style.shrink;
			it.frozen = factor == 0 || (growing && it.basis > it.hypo) || (!growing && it.basis < it.hypo);
			it.main = it.frozen ? it.hypo : it.basis;
		}
		function free():Float {
			var t = gaps;
			for (it in items)
				t += (it.frozen ? it.main : it.basis) + it.mMainStart + it.mMainEnd;
			return mainSize - t;
		}
		var initial = free();
		var guard = items.length + 1;
		while (guard-- > 0) {
			var open = false;
			for (it in items)
				if (!it.frozen) open = true;
			if (!open) break;
			var remaining = free();
			var factors = 0.0, scaled = 0.0;
			for (it in items)
				if (!it.frozen) {
					factors += growing ? it.node.style.grow : it.node.style.shrink;
					scaled += it.node.style.shrink * it.basis;
				}
			if (factors < 1 && Math.abs(initial * factors) < Math.abs(remaining)) remaining = initial * factors;
			var violation = 0.0;
			for (it in items)
				if (!it.frozen) {
					var target = it.basis;
					if (growing) target += remaining * it.node.style.grow / factors;
					else if (scaled > 0) target += remaining * (it.node.style.shrink * it.basis) / scaled;
					var c = clamp(target, it.minMain, it.maxMain);
					if (c < 0) c = 0;
					it.violation = c - target;
					violation += it.violation;
					it.main = c;
				}
			for (it in items)
				if (!it.frozen && (violation == 0 || (violation > 0 && it.violation > 0) || (violation < 0 && it.violation < 0)))
					it.frozen = true;
		}
	}

	// --- helpers ---

	static function hide(n:Node) {
		n.lx = n.ly = n.lw = n.lh = 0;
		n.dirty = false;
		n.relaid = true;
		for (c in n.children)
			hide(c);
	}

	// rounds each box's edges in window coordinates (a subtree neither laid
	// out again nor moved is as it was), then its ink's bounds
	static function round(n:Node, parentAbsX:Float, parentAbsY:Float, parentRoundX:Float, parentRoundY:Float) {
		var ax = parentAbsX + n.lx, ay = parentAbsY + n.ly;
		if (!n.relaid && ax == n.rawX && ay == n.rawY && n.lw == n.rawW && n.lh == n.rawH) return;
		n.relaid = false;
		n.rawX = ax;
		n.rawY = ay;
		n.rawW = n.lw;
		n.rawH = n.lh;
		var x0 = Math.fround(ax), y0 = Math.fround(ay), x1 = Math.fround(ax + n.lw), y1 = Math.fround(ay + n.lh);
		@:privateAccess n.setLayout(x0 - parentRoundX, y0 - parentRoundY, x1 - x0, y1 - y0, x0, y0, n.contentWidth, n.contentHeight);
		// (scrolled children: the scroll offset moves them when drawn and hit, not here)
		for (c in n.children)
			round(c, ax, ay, x0, y0);
		n.measureInk();
	}

	function lookup(n:Node, w:Float, h:Float, aw:Float, ah:Float):Bool {
		var c = n.cache;
		var i = 0;
		while (i < c.length) {
			if (same(c[i], w) && same(c[i + 1], h) && same(c[i + 2], aw) && same(c[i + 3], ah)) {
				rw = c[i + 4];
				rh = c[i + 5];
				return true;
			}
			i += ENTRY;
		}
		return false;
	}

	static function store(n:Node, w:Float, h:Float, aw:Float, ah:Float, rw:Float, rh:Float) {
		var c = n.cache;
		if (c.length >= CACHE * ENTRY) c.splice(0, ENTRY);
		c.push(w);
		c.push(h);
		c.push(aw);
		c.push(ah);
		c.push(rw);
		c.push(rh);
	}

	static inline function known(v:Float):Bool
		return !Math.isNaN(v);

	static inline function same(a:Float, b:Float):Bool
		return a == b || (Math.isNaN(a) && Math.isNaN(b));

	// NaN stays NaN
	static inline function clamp(v:Float, lo:Float, hi:Float):Float
		return Math.isNaN(v) ? v : v > hi ? (hi < lo ? lo : hi) : v < lo ? lo : v;

	// a min length: 0 when auto or unknown
	static inline function min(d:Dim, base:Float):Float {
		var v = d.resolve(base);
		return Math.isNaN(v) ? 0 : v;
	}

	// a max length: infinite when auto or unknown
	static inline function max(d:Dim, base:Float):Float {
		var v = d.resolve(base);
		return Math.isNaN(v) ? Math.POSITIVE_INFINITY : v;
	}
}

private class Item {
	public final node:Node;
	public var mMainStart = 0.0;
	public var mMainEnd = 0.0;
	public var mCrossStart = 0.0;
	public var mCrossEnd = 0.0;
	public var minMain = 0.0;
	public var maxMain = 0.0;
	public var minCross = 0.0;
	public var maxCross = 0.0;
	public var align:Align = Stretch;
	public var styleCross = 0.0;
	public var basis = 0.0;
	public var hypo = 0.0;
	public var main = 0.0;
	public var cross = 0.0;
	public var frozen = false;
	public var violation = 0.0;

	public function new(node:Node)
		this.node = node;
}

private class GridItem {
	public final node:Node;
	// its cells: the first column and row (from 0), how many
	public var col = 0;
	public var row = 0;
	public var colSpan = 1;
	public var rowSpan = 1;
	// its area's width (the columns' sizes, the gaps between)
	public var areaW = 0.0;

	public function new(node:Node)
		this.node = node;
}

private class Line {
	public final items:Array<Item> = [];
	public var cross = 0.0;

	public function new() {}
}
