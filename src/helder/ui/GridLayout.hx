package helder.ui;

// Layout's CSS grid, for a Display Grid container (Layout.size calls grid):
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
@:allow(helder.ui.Layout)
@:access(helder.ui.Layout)
@:access(helder.ui.Node)
class GridLayout {
	static function grid(l:Layout, n:Node, w:Float, h:Float, availW:Float, availH:Float, minW:Float, maxW:Float, minH:Float, maxH:Float, padL:Float, padT:Float,
			padH:Float, padV:Float, perform:Bool, least:Float, defH:Bool) {
		var s = n.style, rtl = n.rtl();
		var innerW = Layout.known(w) ? Math.max(0, w - padH) : Math.NaN, innerH = Layout.known(h) ? Math.max(0, h - padV) : Math.NaN;
		var availInW = Layout.known(innerW) ? innerW : Layout.known(availW) ? Math.max(0, availW - padH) : Math.NaN;
		var availInH = Layout.known(innerH) ? innerH : Layout.known(availH) ? Math.max(0, availH - padV) : Math.NaN;
		var items:Array<GridItem> = [], absolute:Array<Node> = [];
		for (c in n.inOrder()) {
			var cs = c.style;
			if (cs.display == None) {
				if (perform) Layout.hide(c);
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
		var stretchCols = s.justify == Normal, stretchRows = s.alignContent == Normal || s.alignContent == Stretch;
		// (an item with an aspect ratio and neither size its own: the columns sized again, its contribution its rows'
		// height through the ratio, then the rows again, as CSS's grid sizing has it; its height its first rows', as
		// Chromium's)
		var again = false;
		for (it in items) {
			var cs = it.node.style;
			if (cs.aspectRatio > 0 && !Layout.known(cs.width.resolve(Math.NaN)) && !Layout.known(cs.height.resolve(Math.NaN))) again = true;
		}
		var cols:Array<Float> = null, rows:Array<Float> = null, gridW = 0.0, width = 0.0, gridH = 0.0;
		for (pass in 0...2) {
			// (its percentages auto while its width is its content's, as Chromium sizes it)
			cols = tracks(l, colTracks, items, true, innerW, innerW, colGap, stretchCols, innerW, innerH, null);
			gridW = sum(cols, colGap);
			if (!Layout.known(innerW) && Layout.known(availInW) && gridW > availInW + 1e-6) {
				cols = tracks(l, colTracks, items, true, availInW, innerW, colGap, false, innerW, innerH, null);
				gridW = sum(cols, colGap);
			}
			width = Layout.known(innerW) ? innerW : Layout.clamp(gridW, Math.max(0, minW - padH), maxW - padH);
			if (!Layout.known(innerW) && width > gridW + 1e-6 && stretchCols) {
				cols = tracks(l, colTracks, items, true, width, innerW, colGap, true, width, innerH, null);
				gridW = sum(cols, colGap);
			}
			if (pass == 1 && !perform) break;
			// the rows: the items at their columns' widths
			for (it in items) {
				it.areaW = colGap * (it.colSpan - 1);
				for (i in it.col...it.col + it.colSpan)
					it.areaW += cols[i];
			}
			// (a height laid out, not definite (an auto one within its min- or max-height): the rows sized in an
			// indefinite room, their percentages of it; stretched to it when it is more (a min-height's), not shrunk
			// to it when less (a max-height's: the grid overflowing it), as Chromium has it)
			rows = tracks(l, rowTracks, items, false, defH ? innerH : Math.NaN, innerH, rowGap, stretchRows && defH, width, innerH, cols);
			if (!defH && stretchRows && Layout.known(innerH) && innerH > sum(rows, rowGap) + 1e-6)
				rows = tracks(l, rowTracks, items, false, innerH, innerH, rowGap, true, width, innerH, cols);
			if (pass == 0) gridH = sum(rows, rowGap);
			if (!again || pass == 1) break;
			for (it in items) {
				it.areaH = rowGap * (it.rowSpan - 1);
				for (i in it.row...it.row + it.rowSpan)
					it.areaH += rows[i];
			}
		}
		var height = Layout.known(innerH) ? innerH : Layout.clamp(gridH, Math.max(0, (rows.length > 0 ? Math.max(minH, least) : minH) - padV), maxH - padV);
		var bw = width + padH, bh = height + padV;
		if (!perform) {
			l.rw = bw;
			l.rh = bh;
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
		var cw = 0.0, ch = 0.0, left = 0.0;
		for (it in items) {
			var c = it.node, cs = c.style, m = cs.margin;
			var ax = colPos[it.col], aw = colPos[it.col + it.colSpan - 1] + cols[it.col + it.colSpan - 1] - ax;
			var ay = rowPos[it.row], ah = rowPos[it.row + it.rowSpan - 1] + rows[it.row + it.rowSpan - 1] - ay;
			var jx = cs.justifySelf == Auto ? s.justifyItems : cs.justifySelf;
			if (jx == Auto) jx = Stretch;
			var jy = cs.alignSelf == Auto ? s.alignItems : cs.alignSelf;
			if (jy == Auto) jy = Stretch;
			// (auto margins: not stretched on that axis; placed by them once sized)
			var autoS = Math.isNaN(rtl ? m.right : m.left), autoE = Math.isNaN(rtl ? m.left : m.right), autoT = Math.isNaN(m.top), autoB = Math.isNaN(m.bottom);
			if ((autoS || autoE) && jx == Stretch) jx = Start;
			if ((autoT || autoB) && jy == Stretch) jy = Start;
			// (its percentages of its grid area, as CSS's)
			var roomW = Math.max(0, aw - Layout.mz(m.left) - Layout.mz(m.right)), roomH = Math.max(0, ah - Layout.mz(m.top) - Layout.mz(m.bottom));
			var minCW = Math.max(l.minWidthOf(c, cs.minWidth, aw, roomW), Layout.edgesH(cs)), maxCW = l.maxWidthOf(c, cs.maxWidth, aw, roomW);
			var minCH = Math.max(Layout.min(cs.minHeight, ah), Layout.edgesV(cs)), maxCH = Layout.max(cs.maxHeight, ah);
			var iw = Layout.clamp(cs.width.intrinsic() ? l.intrinsicWidth(c, cs.width, aw, roomW) : cs.width.resolve(aw), minCW, maxCW);
			var ih = Layout.clamp(cs.height.resolve(ah), minCH, maxCH);
			// (an aspect ratio and one size its own: the other its through the ratio, not stretched)
			var ar = cs.aspectRatio;
			if (ar > 0 && Layout.known(iw) && !Layout.known(ih) && jy == Stretch) jy = Start;
			if (ar > 0 && Layout.known(ih) && !Layout.known(iw) && jx == Stretch) jx = Start;
			// (an aspect ratio and neither size its own: not stretched but at its start, as wide as the
			// area within its widths and the heights it may have through the ratio, as Chromium has it)
			if (ar > 0 && !Layout.known(iw) && !Layout.known(ih) && jx == Stretch && jy == Stretch) {
				iw = Layout.clamp(Math.min(roomW, maxCH * ar), Math.max(minCW, minCH * ar), maxCW);
				ih = Layout.clamp(iw / ar, minCH, maxCH);
				jx = jy = Start;
			}
			if (!Layout.known(iw)) {
				if (jx == Stretch) iw = Layout.clamp(roomW, minCW, maxCW) else {
					// (fit-content: its max-content width, no more than the area)
					l.size(c, Math.NaN, ih, aw, ah, roomW, Layout.known(ih) ? ih : roomH, false);
					iw = Layout.clamp(Math.min(l.rw, Math.max(roomW, l.minContentWidth(c, aw, false))), minCW, maxCW);
					// (its height's through its aspect ratio however wide)
					if (l.rw <= roomW || ar > 0 && Layout.known(ih)) iw = Layout.clamp(l.rw, minCW, maxCW);
				}
			}
			if (!Layout.known(ih)) {
				if (jy == Stretch) ih = Layout.clamp(roomH, minCH, maxCH) else {
					l.size(c, iw, Math.NaN, aw, ah, iw, roomH, false);
					ih = Layout.clamp(l.rh, minCH, maxCH);
				}
			}
			// (the room left shared among its auto margins, none when it overflows)
			if (autoS || autoE) jx = roomW - iw <= 0 ? Start : autoS && autoE ? Center : autoS ? End : Start;
			if (autoT || autoB) jy = roomH - ih <= 0 ? Start : autoT && autoB ? Center : autoT ? End : Start;
			// (right to left: the columns from the right, each item's margins on its own sides)
			var x = ax + (rtl ? Layout.mz(m.right) : Layout.mz(m.left)) + switch jx {
				case End: roomW - iw;
				case Center: (roomW - iw) / 2;
				case _: 0;
			}
			if (rtl) x = width - x - iw;
			var y = ay + Layout.mz(m.top) + switch jy {
				case End: roomH - ih;
				case Center: (roomH - ih) / 2;
				case _: 0;
			}
			var dx = cs.left.resolve(aw), dy = cs.top.resolve(ah);
			if (!Layout.known(dx)) dx = -cs.right.resolve(aw);
			if (!Layout.known(dy)) dy = -cs.bottom.resolve(ah);
			if (cs.position == Sticky) dx = dy = Math.NaN;
			c.lx = padL + x + (Layout.known(dx) ? dx : 0);
			c.ly = padT + y + (Layout.known(dy) ? dy : 0);
			// (its height definite for its children when stretched or its own, not its content's)
			l.looseH = !(jy == Stretch || Layout.known(cs.height.resolve(ah)));
			l.size(c, iw, ih, aw, ah, iw, ih, true);
			c.lw = iw;
			c.lh = ih;
			if (x + iw + Layout.mz(m.right) > cw) cw = x + iw + Layout.mz(m.right);
			if (y + ih + Layout.mz(m.bottom) > ch) ch = y + ih + Layout.mz(m.bottom);
			if (x - Layout.mz(m.left) < left) left = x - Layout.mz(m.left);
		}
		// (right to left: what overflows on the left, the columns' too)
		if (rtl) cw = width - Math.min(left, width - gridW);
		// (its lines from the padding box's start, for its absolute children's areas)
		if (absolute != null) {
			var colLines = cols.length == 0 ? [] : [for (k in 0...cols.length + 1) (rtl ? s.padding.right : s.padding.left) + (k < cols.length ? colPos[k] : colPos[k - 1] + cols[k - 1])];
			var rowLines = rows.length == 0 ? [] : [for (k in 0...rows.length + 1) s.padding.top + (k < rows.length ? rowPos[k] : rowPos[k - 1] + rows[k - 1])];
			l.absolutes(n, absolute, bw, bh, padL, padT, {cols: colLines, rows: rowLines, nCols: gridColumnCount(s), nRows: gridRowCount(s)});
		}
		n.lw = bw;
		n.lh = bh;
		@:privateAccess n.contentWidth = Math.max(cw, gridW);
		@:privateAccess n.contentHeight = Math.max(ch, gridH);
		n.dirty = false;
		n.relaid = true;
		l.rw = bw;
		l.rh = bh;
	}

	// a grid's min-content width: its columns sized at an available width of 0
	static function minContent(l:Layout, n:Node):Float {
		var s = n.style;
		var items = [for (c in n.inOrder()) if (c.style.display != None && c.style.position != Absolute) new GridItem(c)];
		place(items, s);
		var nCols = gridColumnCount(s);
		for (it in items)
			if (it.col + it.colSpan > nCols) nCols = it.col + it.colSpan;
		var defs = [for (i in 0...nCols) i < s.gridTemplateColumns.length ? s.gridTemplateColumns[i] : s.gridAutoColumns];
		return sum(tracks(l, defs, items, true, 0, Math.NaN, s.columnGap, false, Math.NaN, Math.NaN, null), s.columnGap);
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
		// (too little room: overflowing at the start too when centred or at the end, as Chromium; distributed: at the start)
		if (n > 0 && free < 0) switch j {
			case End: pos = free;
			case Center: pos = free / 2;
			case _:
		} else if (n > 0 && free > 0) switch j {
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
	// row (a column, flowing by columns), then the rest by the cursor
	// (sparse; dense: the cursor back at the start for each)
	static function place(items:Array<GridItem>, s:Style) {
		var explicitCols = gridColumnCount(s), explicitRows = gridRowCount(s), flow = s.gridAutoFlow;
		var byColumn = flow == Column || flow == ColumnDense, dense = flow == RowDense || flow == ColumnDense;
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
			var minor = !dense && cursors.exists(a.start) ? cursors.get(a.start) : 0;
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
			if (dense) {
				curMajor = 0;
				curMinor = b.start >= 0 ? b.start : 0;
			}
			if (b.start >= 0) {
				// (its minor line given: the next major track where it fits)
				if (!dense && b.start < curMinor) curMajor++;
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
	// NaN when indefinite; pct: what percentage tracks are of, NaN: auto; stretch: auto tracks take what is left); the
	// items' contributions measured with gridW and gridH as their
	// percentages' base, rows at the columns' sizes (cols)
	static function tracks(l:Layout, defs:Array<Grid.Track>, items:Array<GridItem>, columns:Bool, room:Float, pct:Float, gap:Float, stretch:Bool, gridW:Float, gridH:Float,
			cols:Null<Array<Float>>):Array<Float> {
		var n = defs.length;
		var base = [for (_ in 0...n) 0.0], limit = [for (_ in 0...n) Math.POSITIVE_INFINITY], flex = [for (_ in 0...n) 0.0];
		inline function fixed(t:Grid.TrackSize):Float
			return switch t {
				case Px(v): v;
				case Percent(p): Layout.known(pct) ? pct * p / 100 : Math.NaN;
				case _: Math.NaN;
			}
		for (i in 0...n) {
			var d = defs[i];
			var mn = fixed(d.min), mx = fixed(d.max);
			if (Layout.known(mn)) base[i] = mn;
			switch d.max {
				case Fr(f): flex[i] = f;
				case _: if (Layout.known(mx)) limit[i] = mx;
			}
			// (a percentage of an indefinite size: auto)
			if (limit[i] < base[i]) limit[i] = base[i];
		}
		inline function intrinsicMin(i:Int):Bool
			return switch defs[i].min {
				case Auto | MinContent | MaxContent: true;
				case Percent(_): !Layout.known(pct);
				case _: false;
			}
		// the items' contributions on this axis (outer sizes); autoMins: their
		// minimum contributions to a track whose minimum is auto (CSS's
		// automatic minimum size: a min-width or min-height set, else 0 for a
		// scroll container, its padding and border, else the min-content)
		var mins = [], maxes = [], autoMins = [];
		for (it in items) {
			var c = it.node, cs = c.style, m = cs.margin;
			// (a percentage of its area, not known yet: auto meanwhile)
			var given = (columns ? cs.minWidth : cs.minHeight).resolve(Math.NaN);
			var edges = columns ? Layout.mz(m.left) + Layout.mz(m.right) : Layout.mz(m.top) + Layout.mz(m.bottom);
			var clipped = cs.overflow != Visible ? edges
				+ (columns ? cs.padding.left + cs.padding.right + cs.borderEdges.left + cs.borderEdges.right : cs.padding.top + cs.padding.bottom
					+ cs.borderEdges.top + cs.borderEdges.bottom) : Math.NaN;
			if (columns && Layout.known(it.areaH) && cs.aspectRatio > 0 && !Layout.known(cs.width.resolve(Math.NaN)) && !Layout.known(cs.height.resolve(Math.NaN))) {
				// (sized again, its rows known: its width through the ratio from their height, within its heights)
				var ih = Layout.clamp(Math.max(0, it.areaH - Layout.mz(m.top) - Layout.mz(m.bottom)), Math.max(Layout.min(cs.minHeight, it.areaH), Layout.edgesV(cs)), Layout.max(cs.maxHeight, it.areaH));
				l.size(c, Math.NaN, ih, Math.NaN, it.areaH, Math.NaN, ih, false);
				mins.push(l.rw + Layout.mz(m.left) + Layout.mz(m.right));
				maxes.push(mins[mins.length - 1]);
			} else if (columns) {
				// (its percentages of its area, not known yet: auto meanwhile)
				mins.push(l.minContentWidth(c, Math.NaN, true) + Layout.mz(m.left) + Layout.mz(m.right));
				l.size(c, Math.NaN, Math.NaN, Math.NaN, gridH, Math.NaN, Math.NaN, false);
				maxes.push(l.rw + Layout.mz(m.left) + Layout.mz(m.right));
			} else {
				// (its percentages of its area: its width's known, its height's the rows' to come, auto meanwhile)
				var room2 = Math.max(0, it.areaW - Layout.mz(m.left) - Layout.mz(m.right));
				var iw = cs.width.resolve(it.areaW);
				var jx = cs.justifySelf == Auto ? it.node.parent.style.justifyItems : cs.justifySelf;
				var jy = cs.alignSelf == Auto ? it.node.parent.style.alignItems : cs.alignSelf;
				var minCW = Math.max(l.minWidthOf(c, cs.minWidth, it.areaW, room2), Layout.edgesH(cs)), maxCW = l.maxWidthOf(c, cs.maxWidth, it.areaW, room2);
				// (stretched within its widths; with an aspect ratio and no height its own, at its start, as placed)
				if (!Layout.known(iw) && (jx == Stretch || jx == Auto)) iw = cs.aspectRatio > 0 && !Layout.known(cs.height.resolve(Math.NaN)) && (jy == Stretch || jy == Auto)
					? Layout.clamp(Math.min(room2, Layout.max(cs.maxHeight, Math.NaN) * cs.aspectRatio), Math.max(minCW, Layout.min(cs.minHeight, Math.NaN) * cs.aspectRatio), maxCW)
					: Layout.clamp(room2, minCW, maxCW);
				l.size(c, iw, Math.NaN, it.areaW, Math.NaN, Layout.known(iw) ? iw : room2, Math.NaN, false);
				var v = l.rh + Layout.mz(m.top) + Layout.mz(m.bottom);
				mins.push(v);
				maxes.push(v);
			}
			// (its minimum contribution: its min-content one when it has a size of its own, as CSS's)
			var own = (columns ? cs.width.resolve(Math.NaN) : cs.height.resolve(Math.NaN));
			autoMins.push(Layout.known(own) ? mins[mins.length - 1] : Layout.known(given) ? given + edges : Layout.known(clipped) ? clipped : mins[mins.length - 1]);
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
					case MinContent: mins[k];
					case _: autoMins[k];
				}
				// (shared up to the tracks' growth limits first, then beyond them equally, as CSS's)
				if (wantMin > have && targets.length > 0) {
					var extra = wantMin - have, open = [for (i in targets) if (base[i] < limit[i]) i];
					while (extra > 1e-9 && open.length > 0) {
						var share = extra / open.length, next = [];
						for (i in open) {
							var d = Math.min(share, limit[i] - base[i]);
							base[i] += d;
							extra -= d;
							if (limit[i] - base[i] > 1e-9) next.push(i);
						}
						open = next;
					}
					if (extra > 1e-9)
						for (i in targets)
							base[i] += extra / targets.length;
				}
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
			if (fsum > 0 && autoMins[k] > have)
				for (i in a...a + span)
					if (flex[i] > 0 && intrinsicMin(i)) base[i] += (autoMins[k] - have) * flex[i] / fsum;
		}
		var gaps = n > 1 ? gap * (n - 1) : 0.0;
		// the free space up to the limits (indefinite: every limit)
		if (Layout.known(room)) {
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
			if (Layout.known(room)) {
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
		if (stretch && Layout.known(room)) {
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
	// its area's height, once the rows are sized (NaN before)
	public var areaH = Math.NaN;

	public function new(node:Node)
		this.node = node;
}
