package hxmc.ui;

// Flexbox layout of a Node tree, after CSS Flexible Box Layout (section 9),
// and CSS grid for a Display Grid container (grid() below):
// margins are pixels or auto (NaN), a column's baselines its start edges. A flex
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
	// (true: the next size() measures its node's content on that axis, its own
	// size, min and max left out: CSS's flex base size and content size suggestion)
	var bareW = false;
	var bareH = false;
	// (true: the next size()'s known height is a laid-out size, not a definite
	// one: its children's percentages of it resolve as of an auto height, as CSS's)
	var looseH = false;
	// (a column measured bare: the height its lines break at, its own; flex takes it)
	var breakH = Math.NaN;
	// flex items and lines, kept from layout to layout: a container's are
	// taken from the top and given back when it is done (its children's
	// taken above them meanwhile)
	static final items:Array<Item> = [];
	static var itemTop = 0;
	static final lines:Array<Line> = [];
	static var lineTop = 0;

	static inline var CACHE = 4; // measured results kept per node
	static inline var ENTRY = 7; // knownW, knownH, availW, availH, bare (1: its width, 2: its height), width, height

	public function new(text:TextEngine)
		this.text = text;

	// lays out the tree in a viewport of width x height
	// whether anything was laid out again (a clean tree of the same size: nothing done);
	// the scrollers rounded again (their extents may have changed) are added to scrollers
	public static function run(root:Node, width:Float, height:Float, text:TextEngine, ?scrollers:Array<Node>):Bool {
		if (!root.dirty && root.lw == width && root.lh == height && !root.relaid) return false;
		var l = new Layout(text);
		itemTop = lineTop = 0;
		l.size(root, width, height, width, height, width, height, true);
		// (the nodes let go)
		for (it in items)
			it.node = null;
		root.lx = 0;
		root.ly = 0;
		round(root, 0, 0, 0, 0, scrollers);
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
		// (bare on an axis where the node has no size, min or max of its own: as measured normally, cached alike)
		var bw = bareW && (s.width != DimValue.Auto || s.minWidth != DimValue.Auto || s.maxWidth != DimValue.Auto);
		var bh = bareH && (s.height != DimValue.Auto || s.minHeight != DimValue.Auto || s.maxHeight != DimValue.Auto);
		var bare = (bw ? 1 : 0) | (bh ? 2 : 0);
		bareW = bareH = false;
		// (measured bare, a column still breaks its lines at its own height within its max-height, in pixels)
		var bareBreak = bh && s.height.match(DimValue.Px(_)) ? s.height.resolve(parentH) : Math.NaN;
		if (bh && s.maxHeight.match(DimValue.Px(_))) {
			var most = s.maxHeight.resolve(parentH);
			if (!known(bareBreak) || most < bareBreak) bareBreak = most;
		}
		// (cached by how bare it was measured; not when that height, of its parent's, breaks it)
		var cached = !known(bareBreak);
		// (its height definite for its children: given so, or its own)
		var defH = !looseH || known(s.height.resolve(parentH));
		looseH = false;
		var minW = Math.max(bw ? 0.0 : minWidthOf(n, s.minWidth, parentW, availW), edgesH(s)), maxW = bw ? Math.POSITIVE_INFINITY : maxWidthOf(n, s.maxWidth, parentW, availW);
		var minH = Math.max(bh ? 0.0 : min(s.minHeight, parentH), edgesV(s)), maxH = bh ? Math.POSITIVE_INFINITY : max(s.maxHeight, parentH);
		var w = known(knownW) ? knownW : bw ? Math.NaN : clamp(s.width.intrinsic() ? intrinsicWidth(n, s.width, parentW, availW) : s.width.resolve(parentW), minW, maxW);
		var h = known(knownH) ? knownH : bh ? Math.NaN : clamp(s.height.resolve(parentH), minH, maxH);
		var ar = s.aspectRatio;
		if (ar > 0) {
			if (!known(w) && known(h)) w = clamp(h * ar, minW, maxW);
			else if (known(w) && !known(h)) h = clamp(w / ar, minH, maxH);
		}
		// (a border box is never smaller than its padding and border, the size given it included)
		if (w < minW) w = minW;
		if (h < minH) h = minH;
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
		} else if (cached && lookup(n, w, defH ? h : -1 - h, availW, availH, bare)) return;
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
		else {
			breakH = bareBreak;
			flex(n, w, h, availW, availH, minW, maxW, minH, maxH, padL, padT, padH, padV, perform, defH);
		}
		if (!perform && cached) store(n, w, defH ? h : -1 - h, availW, availH, bare, rw, rh);
	}

	// --- a flex container ---

	function flex(n:Node, w:Float, h:Float, availW:Float, availH:Float, minW:Float, maxW:Float, minH:Float, maxH:Float, padL:Float, padT:Float,
			padH:Float, padV:Float, perform:Bool, defH:Bool) {
		var s = n.style;
		var bareBreak = breakH;
		breakH = Math.NaN;
		var row = s.direction == Row || s.direction == RowReverse;
		var reverse = s.direction == RowReverse || s.direction == ColumnReverse;
		// (placed from the far side: a reversed direction, and right to left the
		// inline axis, a row's main and a column's cross; each item's margins
		// on its own sides)
		var rtl = n.rtl();
		var flipMain = row ? reverse != rtl : reverse, flipCross = !row && rtl;
		// the content box, known or available, on each axis
		var innerW = known(w) ? Math.max(0, w - padH) : Math.NaN, innerH = known(h) ? Math.max(0, h - padV) : Math.NaN;
		var availInW = known(innerW) ? innerW : known(availW) ? Math.max(0, availW - padH) : Math.NaN;
		var availInH = known(innerH) ? innerH : known(availH) ? Math.max(0, availH - padV) : Math.NaN;
		var innerMain = row ? innerW : innerH, innerCross = row ? innerH : innerW;
		// (what the items' percentages resolve against: the content box, its height when definite)
		var pctH = defH ? innerH : Math.NaN;
		var pctMain = row ? innerW : pctH, pctCross = row ? pctH : innerW;
		var availMain = row ? availInW : availInH, availCross = row ? availInH : availInW;
		var gapMain = row ? s.columnGap : s.rowGap, gapCross = row ? s.rowGap : s.columnGap;
		var minMain = (row ? minW : minH) - (row ? padH : padV), maxMain = (row ? maxW : maxH) - (row ? padH : padV);
		var minCross = (row ? minH : minW) - (row ? padV : padH), maxCross = (row ? maxH : maxW) - (row ? padV : padH);
		var multi = s.wrap;

		// the items and their hypothetical main sizes
		var first = itemTop, absolute:Null<Array<Node>> = null;
		for (c in n.inOrder()) {
			var cs = c.style;
			if (cs.display == None) {
				if (perform) hide(c);
				continue;
			}
			if (cs.position == Absolute) {
				if (absolute == null) absolute = [];
				absolute.push(c);
				continue;
			}
			var it = takeItem(c);
			var m = cs.margin;
			var ms = row ? (flipMain ? m.right : m.left) : (flipMain ? m.bottom : m.top), me = row ? (flipMain ? m.left : m.right) : (flipMain ? m.top : m.bottom);
			var cs0 = row ? m.top : (flipCross ? m.right : m.left), ce = row ? m.bottom : (flipCross ? m.left : m.right);
			// (auto margins: 0 until the free space is shared among them)
			it.autoMain = (Math.isNaN(ms) ? 1 : 0) | (Math.isNaN(me) ? 2 : 0);
			it.autoCross = (Math.isNaN(cs0) ? 1 : 0) | (Math.isNaN(ce) ? 2 : 0);
			it.mMainStart = mz(ms);
			it.mMainEnd = mz(me);
			it.mCrossStart = mz(cs0);
			it.mCrossEnd = mz(ce);
			// (the room across and along it, what fit-content fits in)
			var roomC = known(innerCross) ? Math.max(0, innerCross - it.mCrossStart - it.mCrossEnd) : known(availCross) ? Math.max(0, availCross - it.mCrossStart - it.mCrossEnd) : Math.NaN;
			var roomM = known(availMain) ? Math.max(0, availMain - it.mMainStart - it.mMainEnd) : Math.NaN;
			it.minMain = Math.max(row ? minWidthOf(c, cs.minWidth, pctMain, roomM) : min(cs.minHeight, pctMain), row ? edgesH(cs) : edgesV(cs));
			it.maxMain = row ? maxWidthOf(c, cs.maxWidth, pctMain, roomM) : max(cs.maxHeight, pctMain);
			it.minCross = Math.max(row ? min(cs.minHeight, pctCross) : minWidthOf(c, cs.minWidth, pctCross, roomC), row ? edgesV(cs) : edgesH(cs));
			it.maxCross = row ? max(cs.maxHeight, pctCross) : maxWidthOf(c, cs.maxWidth, pctCross, roomC);
			it.align = cs.alignSelf == Auto ? s.alignItems : cs.alignSelf;
			if (it.align == Auto) it.align = Stretch;
			// (an auto margin across: not stretched, placed by its margins)
			if (it.autoCross != 0) it.align = Start;
			// (stretched only when its size across is auto: a percentage of an indefinite one is not)
			if (it.align == Stretch && (row ? cs.height : cs.width) != DimValue.Auto) it.align = Start;
			it.styleCross = clamp(!row && cs.width.intrinsic() ? intrinsicWidth(c, cs.width, pctCross, roomC) : (row ? cs.height : cs.width).resolve(pctCross), it.minCross,
				it.maxCross);
			var b = cs.basis.resolve(pctMain);
			// (a percentage basis of an indefinite size: content, the width or height left out)
			if (!known(b) && cs.basis == DimValue.Auto) b = row && cs.width.intrinsic() ? intrinsicWidth(c, cs.width, pctMain, roomM) : (row ? cs.width : cs.height).resolve(pctMain);
			var contentBasis = !known(b);
			if (!known(b) && cs.aspectRatio > 0 && known(it.styleCross)) b = row ? it.styleCross * cs.aspectRatio : it.styleCross / cs.aspectRatio;
			if (!known(b)) {
				// the content's main size, its cross size known when stretched in a known line (a
				// wrapping column in a row that is a column's item not, as Chromium sizes it: its
				// max-content, its lines unbroken but at its max-height; a wrapping column's basis its
				// max-content, not the room's)
				var kc = it.styleCross;
				var columns = row && looseColumns(c) && columnItem(n);
				if (!known(kc) && it.align == Stretch && !multi && known(innerCross) && !columns)
					kc = clamp(Math.max(0, innerCross - it.mCrossStart - it.mCrossEnd), it.minCross, it.maxCross);
				var am = known(availMain) && !(row && cs.wrap && (cs.direction == Column || cs.direction == ColumnReverse)) ? Math.max(0, availMain - it.mMainStart - it.mMainEnd) : Math.NaN;
				var ac = known(kc) ? kc : known(availCross) ? Math.max(0, availCross - it.mCrossStart - it.mCrossEnd) : Math.NaN;
				if (!row && cs.aspectRatio > 0 && !known(kc)) {
					// (a column's item with an aspect ratio and a fit-content width: its height that width's)
					size(c, Math.NaN, Math.NaN, innerW, pctH, ac, Math.NaN, false);
					b = rw / cs.aspectRatio;
				} else {
					// (the base size: not clamped by its own min or max, which the hypothetical size is)
					if (row) bareW = true else bareH = true;
					if (row) size(c, Math.NaN, kc, innerW, pctH, am, ac, false) else size(c, kc, Math.NaN, innerW, pctH, ac, am, false);
					b = row ? rw : rh;
				}
			}
			it.edges = row ? edgesH(cs) : edgesV(cs);
			// (a border box no smaller than its padding and border: CSS's content box floored at 0)
			it.basis = Math.max(b, it.edges);
			// the automatic minimum
			if ((row ? cs.minWidth : cs.minHeight) == DimValue.Auto && cs.overflow == Visible) {
				var content:Float;
				if (row) content = minContentWidth(c, innerW, false) else if (contentBasis) content = b else {
					var kc = it.styleCross;
					if (!known(kc) && it.align == Stretch && !multi && known(innerCross))
						kc = clamp(Math.max(0, innerCross - it.mCrossStart - it.mCrossEnd), it.minCross, it.maxCross);
					var ac = known(kc) ? kc : known(availCross) ? Math.max(0, availCross - it.mCrossStart - it.mCrossEnd) : Math.NaN;
					// (its content's height: not its own, CSS's content size suggestion; a wrapping
					// column's lines broken at its own definite height, its tallest line's, as Chromium's)
					bareH = true;
					size(c, kc, Math.NaN, innerW, pctH, ac, Math.NaN, false);
					content = rh;
					// (with an aspect ratio: the size its width gives, that width its own height's when not known)
					if (cs.aspectRatio > 0) {
						var given = cs.height.resolve(pctMain);
						if (known(kc)) content = kc / cs.aspectRatio else if (known(given)) content = given;
					}
				}
				var spec = (row ? cs.width : cs.height).resolve(pctMain);
				if (known(spec) && spec < content) content = spec;
				it.minMain = Math.max(Math.min(content, it.maxMain), row ? edgesH(cs) : edgesV(cs));
			}
			it.hypo = clamp(b, it.minMain, it.maxMain);
		}

		// lines: runs of the items
		var firstLine = lineTop;
		var line = takeLine(first), sum = 0.0;
		// (where lines break: the main size, else a row's room within its min and max, else the max:
		// a column of auto height breaks only at its max-height)
		var finiteMax = maxMain < Math.POSITIVE_INFINITY ? maxMain : Math.NaN;
		// (a wrapping row's room: no narrower than its min-content, its widest item, as fit-content has it)
		var room = row && multi && !known(innerMain) && known(availMain) ? Math.max(availMain, minContentWidth(n, Math.NaN, false) - padH) : availMain;
		var breakAt = known(innerMain) ? innerMain : row && known(room) ? clamp(room, Math.max(0, minMain), maxMain) : !row
			&& known(bareBreak) ? Math.max(0, bareBreak - padV) : finiteMax;
		for (i in first...itemTop) {
			var it = items[i];
			var outer = it.hypo + it.mMainStart + it.mMainEnd;
			if (multi && known(breakAt) && line.end > line.start && sum + gapMain + outer > breakAt + 1e-6) {
				line = takeLine(i);
				sum = 0;
			}
			sum += (line.end > line.start ? gapMain : 0) + outer;
			line.end = i + 1;
		}
		var lastLine = lineTop, count = lastLine - firstLine;

		// the container's main size
		var mainSize = innerMain;
		if (!known(mainSize)) {
			var content = 0.0;
			for (k in firstLine...lastLine) {
				var l = lines[k], t = 0.0;
				for (i in l.start...l.end) {
					var it = items[i];
					t += contribution(it, row, innerW, pctH) + it.mMainStart + it.mMainEnd + (i > l.start ? gapMain : 0);
				}
				if (t > content) content = t;
			}
			// (a wrapping row's max-content: its items on one line)
			if (row && multi && lastLine - firstLine > 1) {
				var t = 0.0;
				for (i in first...itemTop)
					t += contribution(items[i], row, innerW, pctH) + items[i].mMainStart + items[i].mMainEnd + (i > first ? gapMain : 0);
				content = t;
			}
			// (a wrapping row's max-content no less than its min-content, its widest item's, which an item's basis can
			// make it, as Chromium keeps it)
			if (row && multi && basisItems(n)) content = Math.max(content, minContentWidth(n, Math.NaN, false) - padH);
			// (a row shrinks to fit the room; a column's auto height is its content's, the room or not)
			mainSize = known(room) && row ? Math.min(content, room) : content;
			mainSize = clamp(mainSize, Math.max(0, minMain), maxMain);
			// (a row whose items' widths are percentages of its own: laid out again at the width
			// found, which they resolve against then, their lines broken there, as Chromium does)
			if (row && percentItems(n)) {
				itemTop = first;
				lineTop = firstLine;
				breakH = bareBreak;
				flex(n, mainSize + padH, h, availW, availH, minW, maxW, minH, maxH, padL, padT, padH, padV, perform, defH);
				return;
			}
		}

		// flexible lengths, then the items' cross sizes
		for (k in firstLine...lastLine) {
			var l = lines[k];
			resolveFlexible(l, mainSize, gapMain);
			// (items on their baselines: laid out to find them, the line as deep as the deepest above
			// them and below them)
			var lc = 0.0, above = 0.0, below = 0.0;
			for (i in l.start...l.end) {
				var it = items[i];
				if (known(it.styleCross)) it.cross = it.styleCross else {
					var ac = known(innerCross) ? Math.max(0, innerCross - it.mCrossStart - it.mCrossEnd) : known(availCross) ? Math.max(0,
						availCross - it.mCrossStart - it.mCrossEnd) : Math.NaN;
					if (it.align == Stretch && !multi && known(innerCross)) it.cross = clamp(ac, it.minCross, it.maxCross) else {
						// (a column's item's flexed height: definite when the column's is)
						if (row) size(it.node, it.main, Math.NaN, innerW, pctH, it.main, ac, false) else {
							looseH = !known(pctH);
							// (a wrapping column in a column of unknown width, or loose (looseColumns): as wide as on one line, unless
							// its own height is fixed (pixels: a percentage is not, sizing it), as Chromium sizes
							// it; its flexed height then wraps it)
							var ics = it.node.style;
							var oneLine = ics.wrap && (ics.direction == Column || ics.direction == ColumnReverse) && !ics.height.match(DimValue.Px(_))
								&& (!known(innerCross) || looseColumns(it.node));
							// (a stretched item's width as a contribution to the column's own: its aspect ratio not from its
							// flexed height, only its own height, as Chromium has it)
							var given = oneLine || ics.aspectRatio > 0 && it.align == Stretch && !known(ics.height.resolve(pctH)) ? Math.NaN : it.main;
							size(it.node, Math.NaN, given, innerW, pctH, ac, oneLine ? Math.NaN : it.main, false);
						}
						// (a column's item across: fit-content, its min-content when the room is less)
						it.cross = clamp(row ? rh : Math.max(rw, minContentWidth(it.node, innerW, false)), it.minCross, it.maxCross);
					}
				}
				var oc = it.cross + it.mCrossStart + it.mCrossEnd;
				if (oc > lc) lc = oc;
				if (it.align == Baseline) {
					// (a column's: each one's start edge, as Chromium synthesizes it across)
					var b = 0.0;
					if (row) {
						looseH = true;
						size(it.node, it.main, it.cross, innerW, pctH, it.main, it.cross, true);
						b = it.node.firstBaseline();
						if (Math.isNaN(b)) b = it.cross;
					}
					it.baseline = it.mCrossStart + b;
					if (it.baseline > above) above = it.baseline;
					if (oc - it.baseline > below) below = oc - it.baseline;
				}
			}
			if (above + below > lc) lc = above + below;
			l.cross = lc;
			l.baseline = above;
		}
		if (!multi && known(innerCross)) lines[firstLine].cross = innerCross;

		// the container's cross size
		var crossSize = innerCross;
		if (!known(crossSize)) {
			crossSize = 0;
			var widest = 0.0;
			for (k in firstLine...lastLine) {
				crossSize += lines[k].cross + (k > firstLine ? gapCross : 0);
				if (lines[k].cross > widest) widest = lines[k].cross;
			}
			// (a wrapping column's width, fit-content: its lines', within the room but no narrower than its widest)
			if (!row && multi && known(availCross)) crossSize = Math.min(crossSize, Math.max(widest, availCross));
			crossSize = clamp(crossSize, Math.max(0, minCross), maxCross);
			if (!multi) lines[firstLine].cross = crossSize;
		}
		var bw = row ? mainSize + padH : crossSize + padH, bh = row ? crossSize + padV : mainSize + padV;
		if (!perform) {
			itemTop = first;
			lineTop = firstLine;
			rw = bw;
			rh = bh;
			return;
		}

		// the lines across: align-content
		var used = 0.0;
		for (k in firstLine...lastLine)
			used += lines[k].cross + (k > firstLine ? gapCross : 0);
		var free = crossSize - used, start = 0.0, between = 0.0;
		if (multi) switch s.alignContent {
			case Start | Normal:
			case End: start = free;
			case Center: start = lu(free / 2);
			case Stretch if (free > 0):
				for (k in firstLine...lastLine)
					lines[k].cross += free / count;
			case Stretch:
			case SpaceBetween if (free > 0 && count > 1): between = lu(free / (count - 1));
			case SpaceBetween:
			case SpaceAround if (free > 0):
				between = lu(free / count);
				start = lu(free / (2 * count));
			// (overflowing: at the start, as Chromium falls back, safely)
			case SpaceAround:
			case SpaceEvenly if (free > 0):
				between = lu(free / (count + 1));
				start = between;
			case SpaceEvenly:
		}
		var lineStart = start;
		// (its first baseline: its first line's items aligned on theirs, if any)
		n.lb = Math.NaN;
		if (row)
			for (i in lines[firstLine].start...lines[firstLine].end)
				if (items[i].align == Baseline) {
					n.lb = padT + start + lines[firstLine].baseline;
					break;
				}
		// (right to left: the content's leftmost edge, what overflows that way scrolled to)
		var cw = 0.0, ch = 0.0, left = 0.0;
		for (k in firstLine...lastLine) {
			var l = lines[k];
			// stretch, then place along the main axis (justify) and across the line (align)
			var n = l.end - l.start, taken = 0.0;
			for (i in l.start...l.end) {
				var it = items[i];
				if (it.align == Stretch && !known(it.styleCross))
					it.cross = clamp(l.cross - it.mCrossStart - it.mCrossEnd, it.minCross, it.maxCross);
				taken += it.main + it.mMainStart + it.mMainEnd;
			}
			taken += gapMain * (n - 1);
			var free = mainSize - taken, pos = 0.0, gap = gapMain;
			// (auto margins along: the free space shared among them, justify-content left out; none
			// when it overflows, justify-content as usual)
			var autos = 0;
			for (i in l.start...l.end)
				autos += (items[i].autoMain & 1) + (items[i].autoMain >> 1);
			var share = autos > 0 && free > 0 ? free / autos : 0.0;
			if (share > 0) free = 0;
			switch s.justify {
				case Start | Normal:
				case End: pos = free;
				case Center: pos = lu(free / 2);
				case SpaceBetween if (free > 0 && n > 1): gap += lu(free / (n - 1));
				case SpaceBetween:
				case SpaceAround if (free > 0):
					gap += lu(free / n);
					pos = lu(free / (2 * n));
				// (overflowing: at the start, safely, as Chromium falls back: the writing mode's, not
				// the flex start, so a reversed direction's far end)
				case SpaceAround if (reverse): pos = free;
				case SpaceAround:
				case SpaceEvenly if (free > 0):
					gap += lu(free / (n + 1));
					pos = lu(free / (n + 1));
				case SpaceEvenly if (reverse): pos = free;
				case SpaceEvenly:
			}
			// (from the far side, fitting and without auto margins: placed from the
			// near side, the last first, as Chromium places them, the free space
			// before the last what is after the first)
			var near = flipMain && free >= 0 && share == 0;
			if (near) {
				// (distributed: the same space before as after; else what was after)
				var x = switch s.justify {
					case Center: pos;
					case SpaceBetween if (free > 0 && n > 1): pos;
					case SpaceAround | SpaceEvenly if (free > 0): pos;
					case _: free - pos;
				};
				var q = l.end;
				while (q > l.start) {
					var it = items[--q];
					x += it.mMainEnd;
					it.near = x;
					x += it.main + it.mMainStart + gap;
				}
			}
			for (i in l.start...l.end) {
				var it = items[i];
				var startMargin = it.mMainStart + (it.autoMain & 1 != 0 ? share : 0), endMargin = it.mMainEnd + (it.autoMain & 2 != 0 ? share : 0);
				var mainPos = pos + startMargin;
				// (auto margins across: the line's room left shared among them, none when it overflows)
				var roomC = l.cross - it.mCrossStart - it.mCrossEnd - it.cross;
				var crossPos = lineStart + if (it.autoCross != 0) it.mCrossStart + (roomC <= 0 ? 0 : it.autoCross == 3 ? roomC / 2 : it.autoCross == 1 ? roomC : 0) else switch it.align {
					case End: l.cross - it.cross - it.mCrossEnd;
					case Center: it.mCrossStart + lu((l.cross - it.mCrossStart - it.mCrossEnd - it.cross) / 2);
					case Baseline: l.baseline - it.baseline + it.mCrossStart;
					case _: it.mCrossStart;
				}
				if (near) mainPos = it.near else if (flipMain) mainPos = mainSize - mainPos - it.main;
				if (flipCross) crossPos = crossSize - crossPos - it.cross;
				var c = it.node;
				var cx = padL + (row ? mainPos : crossPos), cy = padT + (row ? crossPos : mainPos);
				var cwid = row ? it.main : it.cross, chei = row ? it.cross : it.main;
				// (Relative: shifted by its offsets)
				var cs = c.style;
				var dx = cs.left.resolve(innerW), dy = cs.top.resolve(pctH);
				if (!known(dx)) dx = -cs.right.resolve(innerW);
				if (!known(dy)) dy = -cs.bottom.resolve(pctH);
				// (Sticky: its offsets are where it sticks, not a shift)
				if (cs.position == Sticky) dx = dy = Math.NaN;
				c.lx = cx + (known(dx) ? dx : 0);
				c.ly = cy + (known(dy) ? dy : 0);
				// (its height definite: stretched, a column's item when the column's is or its basis is
				// in pixels, as Chromium has it, or its own)
				looseH = row ? !(it.align == Stretch && !known(it.styleCross)) : !known(pctH) && !cs.basis.match(DimValue.Px(_));
				size(c, cwid, chei, innerW, pctH, cwid, chei, true);
				c.lw = cwid;
				c.lh = chei;
				pos += it.main + startMargin + endMargin + gap;
				// (what it overflows, unclipped, is its parent's to scroll too, as CSS's scrollable overflow)
				var ow = cwid, oh = chei;
				if (cs.overflow == Visible && !rtl) {
					var cp = cs.padding, cb = cs.borderEdges;
					ow = Math.max(ow, c.contentWidth + cp.left + cb.left);
					oh = Math.max(oh, c.contentHeight + cp.top + cb.top);
				}
				var ex = cx - padL + ow + (row ? it.mMainEnd : it.mCrossEnd), ey = cy - padT + oh + (row ? it.mCrossEnd : it.mMainEnd);
				if (ex > cw) cw = ex;
				if (ey > ch) ch = ey;
				if (cx - padL < left) left = cx - padL;
			}
			lineStart += l.cross + gapCross + between;
		}
		if (rtl) cw = (row ? mainSize : crossSize) - left;

		itemTop = first;
		lineTop = firstLine;
		if (absolute != null) absolutes(n, absolute, bw, bh, padL, padT);
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
		var s = n.style, rtl = n.rtl();
		var innerW = known(w) ? Math.max(0, w - padH) : Math.NaN, innerH = known(h) ? Math.max(0, h - padV) : Math.NaN;
		var availInW = known(innerW) ? innerW : known(availW) ? Math.max(0, availW - padH) : Math.NaN;
		var availInH = known(innerH) ? innerH : known(availH) ? Math.max(0, availH - padV) : Math.NaN;
		var items:Array<GridItem> = [], absolute:Array<Node> = [];
		for (c in n.inOrder()) {
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
			var roomW = Math.max(0, aw - mz(m.left) - mz(m.right)), roomH = Math.max(0, ah - mz(m.top) - mz(m.bottom));
			var minCW = Math.max(minWidthOf(c, cs.minWidth, aw, roomW), edgesH(cs)), maxCW = maxWidthOf(c, cs.maxWidth, aw, roomW);
			var minCH = Math.max(min(cs.minHeight, ah), edgesV(cs)), maxCH = max(cs.maxHeight, ah);
			var iw = clamp(cs.width.intrinsic() ? intrinsicWidth(c, cs.width, aw, roomW) : cs.width.resolve(aw), minCW, maxCW);
			var ih = clamp(cs.height.resolve(ah), minCH, maxCH);
			if (!known(iw)) {
				if (jx == Stretch) iw = clamp(roomW, minCW, maxCW) else {
					// (fit-content: its max-content width, no more than the area)
					size(c, Math.NaN, ih, aw, ah, roomW, known(ih) ? ih : roomH, false);
					iw = clamp(Math.min(rw, Math.max(roomW, minContentWidth(c, aw, false))), minCW, maxCW);
					if (rw <= roomW) iw = clamp(rw, minCW, maxCW);
				}
			}
			if (!known(ih)) {
				if (jy == Stretch) ih = clamp(roomH, minCH, maxCH) else {
					size(c, iw, Math.NaN, aw, ah, iw, roomH, false);
					ih = clamp(rh, minCH, maxCH);
				}
			}
			// (the room left shared among its auto margins, none when it overflows)
			if (autoS || autoE) jx = roomW - iw <= 0 ? Start : autoS && autoE ? Center : autoS ? End : Start;
			if (autoT || autoB) jy = roomH - ih <= 0 ? Start : autoT && autoB ? Center : autoT ? End : Start;
			// (right to left: the columns from the right, each item's margins on its own sides)
			var x = ax + (rtl ? mz(m.right) : mz(m.left)) + switch jx {
				case End: roomW - iw;
				case Center: (roomW - iw) / 2;
				case _: 0;
			}
			if (rtl) x = width - x - iw;
			var y = ay + mz(m.top) + switch jy {
				case End: roomH - ih;
				case Center: (roomH - ih) / 2;
				case _: 0;
			}
			var dx = cs.left.resolve(aw), dy = cs.top.resolve(ah);
			if (!known(dx)) dx = -cs.right.resolve(aw);
			if (!known(dy)) dy = -cs.bottom.resolve(ah);
			if (cs.position == Sticky) dx = dy = Math.NaN;
			c.lx = padL + x + (known(dx) ? dx : 0);
			c.ly = padT + y + (known(dy) ? dy : 0);
			// (its height definite for its children when stretched or its own, not its content's)
			looseH = !(jy == Stretch || known(cs.height.resolve(ah)));
			size(c, iw, ih, aw, ah, iw, ih, true);
			c.lw = iw;
			c.lh = ih;
			if (x + iw + mz(m.right) > cw) cw = x + iw + mz(m.right);
			if (y + ih + mz(m.bottom) > ch) ch = y + ih + mz(m.bottom);
			if (x - mz(m.left) < left) left = x - mz(m.left);
		}
		// (right to left: what overflows on the left, the columns' too)
		if (rtl) cw = width - Math.min(left, width - gridW);
		// (its lines from the padding box's start, for its absolute children's areas)
		if (absolute != null) {
			var colLines = cols.length == 0 ? [] : [for (k in 0...cols.length + 1) (rtl ? s.padding.right : s.padding.left) + (k < cols.length ? colPos[k] : colPos[k - 1] + cols[k - 1])];
			var rowLines = rows.length == 0 ? [] : [for (k in 0...rows.length + 1) s.padding.top + (k < rows.length ? rowPos[k] : rowPos[k - 1] + rows[k - 1])];
			absolutes(n, absolute, bw, bh, padL, padT, {cols: colLines, rows: rowLines, nCols: gridColumnCount(s), nRows: gridRowCount(s)});
		}
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
		var items = [for (c in n.inOrder()) if (c.style.display != None && c.style.position != Absolute) new GridItem(c)];
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
		// the items' contributions on this axis (outer sizes); autoMins: their
		// minimum contributions to a track whose minimum is auto (CSS's
		// automatic minimum size: a min-width or min-height set, else 0 for a
		// scroll container, its padding and border, else the min-content)
		var mins = [], maxes = [], autoMins = [];
		for (it in items) {
			var c = it.node, cs = c.style, m = cs.margin;
			var given = (columns ? cs.minWidth : cs.minHeight).resolve(columns ? Math.NaN : gridH);
			var edges = columns ? mz(m.left) + mz(m.right) : mz(m.top) + mz(m.bottom);
			var clipped = cs.overflow != Visible ? edges
				+ (columns ? cs.padding.left + cs.padding.right + cs.borderEdges.left + cs.borderEdges.right : cs.padding.top + cs.padding.bottom
					+ cs.borderEdges.top + cs.borderEdges.bottom) : Math.NaN;
			if (columns) {
				// (its percentages of its area, not known yet: auto meanwhile)
				mins.push(minContentWidth(c, Math.NaN, true) + mz(m.left) + mz(m.right));
				size(c, Math.NaN, Math.NaN, Math.NaN, gridH, Math.NaN, Math.NaN, false);
				maxes.push(rw + mz(m.left) + mz(m.right));
			} else {
				// (its percentages of its area: its width's known, its height's the rows' to come, auto meanwhile)
				var room2 = Math.max(0, it.areaW - mz(m.left) - mz(m.right));
				var iw = cs.width.resolve(it.areaW);
				var jx = cs.justifySelf == Auto ? it.node.parent.style.justifyItems : cs.justifySelf;
				if (!known(iw) && (jx == Stretch || jx == Auto)) iw = room2;
				size(c, iw, Math.NaN, it.areaW, Math.NaN, known(iw) ? iw : room2, Math.NaN, false);
				var v = rh + mz(m.top) + mz(m.bottom);
				mins.push(v);
				maxes.push(v);
			}
			// (its minimum contribution: its min-content one when it has a size of its own, as CSS's)
			var own = (columns ? cs.width.resolve(Math.NaN) : cs.height.resolve(Math.NaN));
			autoMins.push(known(own) ? mins[mins.length - 1] : known(given) ? given + edges : known(clipped) ? clipped : mins[mins.length - 1]);
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
			if (fsum > 0 && autoMins[k] > have)
				for (i in a...a + span)
					if (flex[i] > 0 && intrinsicMin(i)) base[i] += (autoMins[k] - have) * flex[i] / fsum;
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
	function absolutes(n:Node, absolute:Array<Node>, bw:Float, bh:Float, padL:Float, padT:Float, ?lines:{cols:Array<Float>, rows:Array<Float>, nCols:Int, nRows:Int}) {
		var s = n.style;
		var be = s.borderEdges, fullW = bw - be.left - be.right, fullH = bh - be.top - be.bottom;
		var rtl = n.rtl();
		for (c in absolute) {
			var cs = c.style, m = cs.margin;
			// (its containing block: the padding box, or in a grid the area its lines give, an auto
			// line or one the grid has not its padding edge, as CSS's)
			var ox = 0.0, oy = 0.0, pbW = fullW, pbH = fullH;
			if (lines != null) {
				if (cs.gridColumn != Grid.GridPlacement.AUTO) {
					var a = area(cs.gridColumn, lines.cols, lines.nCols, fullW);
					ox = rtl ? fullW - a.to : a.from;
					pbW = a.to - a.from;
				}
				if (cs.gridRow != Grid.GridPlacement.AUTO) {
					var a = area(cs.gridRow, lines.rows, lines.nRows, fullH);
					oy = a.from;
					pbH = a.to - a.from;
				}
			}
			var l = cs.left.resolve(pbW), r = cs.right.resolve(pbW), t = cs.top.resolve(pbH), b = cs.bottom.resolve(pbH);
			// (what an auto or fit-content width fits in: the room its offsets and margins leave)
			var room = Math.max(0, pbW - (known(l) ? l : 0) - (known(r) ? r : 0) - mz(m.left) - mz(m.right));
			var aw = cs.width.intrinsic() ? intrinsicWidth(c, cs.width, pbW, room) : cs.width.resolve(pbW), ah = cs.height.resolve(pbH);
			// (both offsets: the room between them, unless its self-alignment is set: fit-content then)
			if (!known(aw) && known(l) && known(r) && (cs.justifySelf == Auto || cs.justifySelf == Stretch)) aw = Math.max(0, pbW - l - r - mz(m.left) - mz(m.right));
			if (!known(ah) && known(t) && known(b) && (cs.alignSelf == Auto || cs.alignSelf == Stretch)) ah = Math.max(0, pbH - t - b - mz(m.top) - mz(m.bottom));
			aw = clamp(aw, Math.max(minWidthOf(c, cs.minWidth, pbW, room), edgesH(cs)), maxWidthOf(c, cs.maxWidth, pbW, room));
			ah = clamp(ah, Math.max(min(cs.minHeight, pbH), edgesV(cs)), max(cs.maxHeight, pbH));
			var heightGiven = known(ah);
			if (!known(aw) || !known(ah)) {
				// (an auto height: its content's, the block axis indefinite; an auto width shrinks to fit
				// the room, not below its min-content width)
				var fit = !known(aw), fixedH = known(ah);
				size(c, aw, ah, pbW, pbH, known(aw) ? aw : room, known(ah) ? ah : Math.NaN, false);
				aw = rw;
				ah = rh;
				// (its height at the width it shrank to)
				if (fit && !fixedH) {
					size(c, aw, Math.NaN, pbW, pbH, aw, Math.NaN, false);
					ah = rh;
				}
				if (fit && aw >= room - 1e-6) {
					var mc = clamp(minContentWidth(c, pbW, false), Math.max(min(cs.minWidth, pbW), edgesH(cs)), max(cs.maxWidth, pbW));
					if (mc > aw) {
						aw = mc;
						if (!fixedH) {
							size(c, aw, Math.NaN, pbW, pbH, aw, Math.NaN, false);
							ah = rh;
						}
					}
				}
			}
			// (neither offset: its static position, as if it were the container's only
			// item: justify along the main axis, its alignment across, in the content box)
			// (a grid's: in its padding box, as if the only item of an area that is all of it)
			var grid = s.display == Grid;
			var cx = grid ? 0 : padL - be.left, cy = grid ? 0 : padT - be.top;
			var cw = grid ? pbW : pbW - s.padding.left - s.padding.right, ch = grid ? pbH : pbH - s.padding.top - s.padding.bottom;
			var ax = known(l) ? l + mz(m.left) : known(r) ? pbW - r - aw - mz(m.right) : cx + mz(m.left)
				+ staticOffset(n, c, true, cw - aw - mz(m.left) - mz(m.right));
			var ay = known(t) ? t + mz(m.top) : known(b) ? pbH - b - ah - mz(m.bottom) : cy + mz(m.top) + staticOffset(n, c, false, ch - ah - mz(m.top) - mz(m.bottom));
			// (both offsets and a size that leaves room: placed in the rectangle they leave by its
			// justifySelf and alignSelf, start by default (the right right to left), as Chromium; one
			// that overflows it moved back into the containing block as far as it fits, unless its alignment is Auto)
			if (known(l) && known(r)) ax = selfAligned(cs.justifySelf, l + mz(m.left), pbW - r - mz(m.right), aw, pbW, rtl);
			if (known(t) && known(b)) ay = selfAligned(cs.alignSelf, t + mz(m.top), pbH - b - mz(m.bottom), ah, pbH, false);
			// (auto margins with both offsets: the room left theirs, shared when both are, as CSS 2's
			// equations solve them; both auto and too little room: the start one 0)
			if (known(l) && known(r) && (Math.isNaN(m.left) || Math.isNaN(m.right))) {
				var free = pbW - l - r - mz(m.left) - mz(m.right) - aw;
				ax = Math.isNaN(m.left) && Math.isNaN(m.right) ? l + (free >= 0 ? free / 2 : rtl ? free : 0) : Math.isNaN(m.left) ? l + free : l + mz(m.left);
			}
			if (known(t) && known(b) && (Math.isNaN(m.top) || Math.isNaN(m.bottom))) {
				var free = pbH - t - b - mz(m.top) - mz(m.bottom) - ah;
				ay = Math.isNaN(m.top) && Math.isNaN(m.bottom) ? t + Math.max(0, free) / 2 : Math.isNaN(m.top) ? t + free : t + mz(m.top);
			}
			c.lx = be.left + ox + ax;
			c.ly = be.top + oy + ay;
			// (a height of its content's: not definite for its children's percentages)
			looseH = !heightGiven;
			size(c, aw, ah, pbW, pbH, aw, ah, true);
			c.lw = aw;
			c.lh = ah;
		}
	}

	// (an absolute grid child's area on an axis, from the start: its lines, lines counted from
	// the explicit grid's, a span from the other line, else the padding edges)
	static function area(p:Grid.GridPlacement, lines:Array<Float>, explicit:Int, full:Float):{from:Float, to:Float} {
		inline function index(k:Int):Int
			return k > 0 ? k - 1 : k < 0 ? explicit + 1 + k : -1;
		var a = p.startName == null ? index(p.start) : -1, b = p.endName == null ? index(p.end) : -1;
		if (a >= 0 && b < 0 && p.end == 0 && p.span > 1) b = a + p.span;
		if (b >= 0 && a < 0 && p.start == 0 && p.span > 1) a = b - p.span;
		if (a >= 0 && b >= 0 && b < a) {
			var t = a;
			a = b;
			b = t;
		}
		var from = a >= 0 && a < lines.length ? lines[a] : 0.0, to = b >= 0 && b < lines.length ? lines[b] : full;
		return {from: from, to: Math.max(from, to)};
	}

	// a box size wide placed between from and to by its self-alignment (flip: start at the far end),
	// moved within 0...room as far as it fits if it overflows them and its alignment is set (not Auto)
	static function selfAligned(a:Align, from:Float, to:Float, size:Float, room:Float, flip:Bool):Float {
		// (the rectangle no less than empty, at its start)
		var free = Math.max(0, to - from) - size;
		var at = switch a {
			case End: flip ? from : from + free;
			case Center: from + free / 2;
			case _: flip ? from + free : from;
		}
		if (free < 0 && a != Auto) at = Math.max(0, Math.min(at, room - size));
		return at;
	}

	// an absolute child's static position on an axis (across: horizontal):
	// its offset in the container's content box, free the room left on that
	// axis, as the container's only flex item (in a grid: at the start, or the
	// right right to left)
	static function staticOffset(n:Node, c:Node, across:Bool, free:Float):Float {
		var s = n.style, rtl = n.rtl();
		// (a grid's: its self-alignment, else the grid's for its items, across and along; stretched at the start)
		if (s.display == Grid) {
			var cs = c.style;
			var a = across ? (cs.justifySelf == Auto ? s.justifyItems : cs.justifySelf) : (cs.alignSelf == Auto ? s.alignItems : cs.alignSelf);
			var k = switch a {
				case End: 1.0;
				case Center: 0.5;
				case _: 0.0;
			}
			return free * (across && rtl ? 1 - k : k);
		}
		var row = s.direction == Row || s.direction == RowReverse, reverse = s.direction == RowReverse || s.direction == ColumnReverse;
		var main = across == row, k:Float;
		if (main) {
			k = switch s.justify {
				case End: 1;
				case Center | SpaceAround | SpaceEvenly: 0.5;
				case _: 0;
			}
			// (the main axis's start: the right in a row right to left, the far end reversed)
			if ((row && rtl) != reverse) k = 1 - k;
		} else {
			var a = c.style.alignSelf == Auto ? s.alignItems : c.style.alignSelf;
			k = switch a {
				case End: 1;
				case Center: 0.5;
				case _: 0;
			}
			if (across && rtl) k = 1 - k;
		}
		return free * k;
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
		if (contribution && known(w)) return Math.max(clamp(w, minW, maxW), edgesH(s));
		// (an intrinsic width's min-content contribution: max-content's, the others' min-content)
		if (contribution && s.width == DimValue.MaxContent) return Math.max(clamp(intrinsicWidth(n, s.width, parentW, Math.NaN), minW, maxW), edgesH(s));
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
				var cw = clamp(minContentWidth(c, Math.NaN, true), min(cs.minWidth, Math.NaN), max(cs.maxWidth, Math.NaN));
				// (a row's item with a flex-basis: as contribution() has it, its base size when its factor is 0,
				// no less than its automatic minimum)
				var b = cs.basis.resolve(Math.NaN);
				if (row && known(b)) {
					if (cw > b && cs.grow == 0 || cw < b && cs.shrink == 0) cw = b;
					if (cs.minWidth == DimValue.Auto && cs.overflow == Visible) {
						var content = minContentWidth(c, Math.NaN, false), given = cs.width.resolve(Math.NaN);
						var least = known(given) ? Math.min(content, given) : content;
						if (cw < least) cw = least;
					}
					cw = clamp(cw, Math.max(min(cs.minWidth, Math.NaN), edgesH(cs)), max(cs.maxWidth, Math.NaN));
				}
				cw += mz(m.left) + mz(m.right);
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
	// an item's size along a container's indefinite main axis: its
	// hypothetical size, except that a row's item with a flex-basis set gives
	// its max-content contribution (its width or content, within its min and
	// max) when its grow factor (wider) or shrink factor (narrower) would take
	// it there, else its base size, then within its min (the automatic one
	// too) and max, as Chromium sizes rows
	function contribution(it:Item, row:Bool, innerW:Float, innerH:Float):Float {
		var cs = it.node.style;
		if (!row || cs.basis == DimValue.Auto) return it.hypo;
		var w = cs.width == DimValue.MinContent ? minContentWidth(it.node, innerW, false) : cs.width.resolve(innerW);
		if (!known(w)) {
			size(it.node, Math.NaN, known(it.styleCross) ? it.styleCross : Math.NaN, innerW, innerH, Math.NaN, Math.NaN, false);
			w = rw;
		}
		var c = clamp(w, it.minMain, it.maxMain), b = it.basis;
		// (a percentage basis of the container's indefinite width: its width's or content's, as auto's)
		if (!known(cs.basis.resolve(innerW))) b = Math.max(w, it.edges);
		var stays = c > b && cs.grow == 0 || c < b && cs.shrink == 0;
		return clamp(stays ? b : c, it.minMain, it.maxMain);
	}

	static function resolveFlexible(l:Line, mainSize:Float, gap:Float) {
		var start = l.start, end = l.end;
		var gaps = gap * (end - start - 1);
		var hypo = gaps;
		for (i in start...end) {
			var it = items[i];
			hypo += it.hypo + it.mMainStart + it.mMainEnd;
		}
		var growing = hypo < mainSize;
		var open = false;
		for (i in start...end) {
			var it = items[i];
			var factor = growing ? it.node.style.grow : it.node.style.shrink;
			it.frozen = factor == 0 || (growing && it.basis > it.hypo) || (!growing && it.basis < it.hypo);
			it.main = it.frozen ? it.hypo : it.basis;
			if (!it.frozen) open = true;
		}
		// (the free space: the frozen items' sizes, the others' bases)
		var initial = mainSize - gaps;
		for (i in start...end) {
			var it = items[i];
			initial -= (it.frozen ? it.main : it.basis) + it.mMainStart + it.mMainEnd;
		}
		var guard = end - start + 1;
		while (open && guard-- > 0) {
			var remaining = mainSize - gaps;
			var factors = 0.0, scaled = 0.0;
			for (i in start...end) {
				var it = items[i];
				remaining -= (it.frozen ? it.main : it.basis) + it.mMainStart + it.mMainEnd;
				if (!it.frozen) {
					factors += growing ? it.node.style.grow : it.node.style.shrink;
					scaled += it.node.style.shrink * inner(it);
				}
			}
			if (factors < 1 && Math.abs(initial * factors) < Math.abs(remaining)) remaining = initial * factors;
			var violation = 0.0;
			for (i in start...end) {
				var it = items[i];
				if (!it.frozen) {
					// (its share as Chromium adds it: rounded to a 64th of a pixel, its LayoutUnit)
					var target = it.basis;
					if (growing) target += Math.fround(remaining * it.node.style.grow / factors * 64) / 64;
					else if (scaled > 0) target += Math.fround(remaining * (it.node.style.shrink * inner(it)) / scaled * 64) / 64;
					var c = clamp(target, it.minMain, it.maxMain);
					if (c < 0) c = 0;
					it.violation = c - target;
					violation += it.violation;
					it.main = c;
				}
			}
			open = false;
			for (i in start...end) {
				var it = items[i];
				if (!it.frozen && (violation == 0 || (violation > 0 && it.violation > 0) || (violation < 0 && it.violation < 0)))
					it.frozen = true;
				if (!it.frozen) open = true;
			}
		}
	}

	// an item for c from the pool
	// (whether a node's item has a basis of its own)
	static function basisItems(n:Node):Bool {
		for (c in n.children)
			if (c.style.basis != DimValue.Auto && c.style.display != None && c.style.position != Absolute) return true;
		return false;
	}

	// (whether a row's item has a width or basis that is a percentage of the row's)
	static function percentItems(n:Node):Bool {
		for (c in n.children) {
			var cs = c.style;
			if (cs.display == None || cs.position == Absolute) continue;
			if (percent(cs.basis) || percent(cs.width) || percent(cs.minWidth) || percent(cs.maxWidth)) return true;
		}
		return false;
	}

	// (whether a node is a flex column's item, its height that column's to share)
	static function columnItem(n:Node):Bool {
		var p = n.parent;
		if (p == null || n.style.position == Absolute) return false;
		var ps = p.style;
		return ps.display != Grid && (ps.direction == Column || ps.direction == ColumnReverse);
	}

	// (a wrapping column whose width Chromium finds with its height left indefinite: no height of
	// its own, no min or max that is a percentage, nor its items' heights)
	static function looseColumns(n:Node):Bool {
		var s = n.style;
		return s.wrap && (s.direction == Column || s.direction == ColumnReverse) && !s.height.match(DimValue.Px(_)) && !percent(s.height)
			&& !percent(s.minHeight) && !percent(s.maxHeight) && !percentHeights(n);
	}

	// (whether a column's item has a height or basis that is a percentage of the column's)
	static function percentHeights(n:Node):Bool {
		for (c in n.children) {
			var cs = c.style;
			if (cs.display == None || cs.position == Absolute) continue;
			if (percent(cs.basis) || percent(cs.height) || percent(cs.minHeight) || percent(cs.maxHeight)) return true;
		}
		return false;
	}

	static function percent(d:Dim):Bool
		return switch (d : DimValue) {
			case Percent(_) | Calc(_, _): true;
			case _: false;
		}

	static function takeItem(c:Node):Item {
		if (itemTop == items.length) items.push(new Item());
		var it = items[itemTop++];
		it.reset(c);
		return it;
	}

	// a line from the pool, its items from first on
	static function takeLine(first:Int):Line {
		if (lineTop == lines.length) lines.push(new Line());
		var l = lines[lineTop++];
		l.start = l.end = first;
		l.cross = l.baseline = 0;
		return l;
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
	static function round(n:Node, parentAbsX:Float, parentAbsY:Float, parentRoundX:Float, parentRoundY:Float, scrollers:Null<Array<Node>>) {
		var ax = parentAbsX + n.lx, ay = parentAbsY + n.ly;
		if (!n.relaid && ax == n.rawX && ay == n.rawY && n.lw == n.rawW && n.lh == n.rawH) return;
		n.relaid = false;
		n.rawX = ax;
		n.rawY = ay;
		n.rawW = n.lw;
		n.rawH = n.lh;
		var x0 = Math.fround(ax), y0 = Math.fround(ay), x1 = Math.fround(ax + n.lw), y1 = Math.fround(ay + n.lh);
		@:privateAccess n.setLayout(x0 - parentRoundX, y0 - parentRoundY, x1 - x0, y1 - y0, x0, y0, n.contentWidth, n.contentHeight);
		if (scrollers != null && n.style.overflow == Scroll) scrollers.push(n);
		// (scrolled children: the scroll offset moves them when drawn and hit, not here)
		for (c in n.children)
			round(c, ax, ay, x0, y0, scrollers);
		n.measureInk();
	}

	function lookup(n:Node, w:Float, h:Float, aw:Float, ah:Float, bare:Int):Bool {
		var c = n.cache;
		if (c == null) return false;
		var i = 1, end = 1 + Std.int(c[0]);
		while (i < end) {
			if (same(c[i], w) && same(c[i + 1], h) && c[i + 4] == bare && fits(c[i + 2], c[i + 5], aw) && fits(c[i + 3], c[i + 6], ah)) {
				rw = c[i + 5];
				rh = c[i + 6];
				return true;
			}
			i += ENTRY;
		}
		return false;
	}

	// (the cache: its length in slot 0, then up to CACHE entries; the oldest
	// dropped. Room for one at first, twice as many when full: most nodes
	// are measured once or twice)
	static function store(n:Node, w:Float, h:Float, aw:Float, ah:Float, bare:Int, rw:Float, rh:Float) {
		var c = n.cache;
		if (c == null) c = n.cache = new haxe.ds.Vector(1 + ENTRY, 0.0);
		var at = 1 + Std.int(c[0]);
		if (at >= c.length && c.length < 1 + CACHE * ENTRY) {
			var g = new haxe.ds.Vector(Std.int(Math.min(2 * c.length - 1, 1 + CACHE * ENTRY)), 0.0);
			haxe.ds.Vector.blit(c, 0, g, 0, c.length);
			c = n.cache = g;
		}
		if (at >= 1 + CACHE * ENTRY) {
			for (i in 1...at - ENTRY)
				c[i] = c[i + ENTRY];
			at -= ENTRY;
		}
		c[at] = w;
		c[at + 1] = h;
		c[at + 2] = aw;
		c[at + 3] = ah;
		c[at + 4] = bare;
		c[at + 5] = rw;
		c[at + 6] = rh;
		c[0] = at + ENTRY - 1;
	}

	// (a share of free space as Chromium's LayoutUnit divides it: to a 64th of a pixel, toward zero)
	static inline function lu(v:Float):Float
		return v >= 0 ? Math.ffloor(v * 64) / 64 : Math.fceil(v * 64) / 64;

	static inline function known(v:Float):Bool
		return !Math.isNaN(v);

	static inline function same(a:Float, b:Float):Bool
		return a == b || (Math.isNaN(a) && Math.isNaN(b));

	// (a size measured in the room `was` is `got` in the room `now` too: the
	// same room, or neither room bounded it, as Yoga reuses its measurements)
	static inline function fits(was:Float, got:Float, now:Float):Bool
		return same(was, now) || ((Math.isNaN(was) || got < was) && (Math.isNaN(now) || got <= now));

	// the width CSS's min-content, max-content or fit-content gives n (room: what
	// fit-content fits in; NaN: none, its max-content), its own width, min and max left out
	function intrinsicWidth(n:Node, d:Dim, parentW:Float, room:Float):Float {
		if (d == DimValue.MinContent) return minContentWidth(n, parentW, false);
		bareW = true;
		size(n, Math.NaN, Math.NaN, parentW, Math.NaN, Math.NaN, Math.NaN, false);
		var widest = rw;
		return d == DimValue.MaxContent || !known(room) ? widest : Math.min(widest, Math.max(minContentWidth(n, parentW, false), room));
	}

	// a min or max width, an intrinsic one too
	inline function minWidthOf(n:Node, d:Dim, base:Float, room:Float):Float
		return d.intrinsic() ? intrinsicWidth(n, d, base, room) : min(d, base);

	inline function maxWidthOf(n:Node, d:Dim, base:Float, room:Float):Float
		return d.intrinsic() ? intrinsicWidth(n, d, base, room) : max(d, base);

	// a margin: auto (NaN) as 0
	static inline function mz(v:Float):Float
		return Math.isNaN(v) ? 0 : v;

	// an item's base size inside its padding and border: what its shrink factor scales, as Chromium
	static inline function inner(it:Item):Float
		return Math.max(0, it.basis - it.edges);

	// NaN stays NaN
	static inline function clamp(v:Float, lo:Float, hi:Float):Float
		return Math.isNaN(v) ? v : v > hi ? (hi < lo ? lo : hi) : v < lo ? lo : v;

	// a box's padding and border across and down: the least its border box can be
	static inline function edgesH(s:Style):Float
		return s.padding.left + s.padding.right + s.borderEdges.left + s.borderEdges.right;

	static inline function edgesV(s:Style):Float
		return s.padding.top + s.padding.bottom + s.borderEdges.top + s.borderEdges.bottom;

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
	public var node:Null<Node> = null;
	// (its place from a reversed line's near side: Layout.flex's)
	public var near = 0.0;
	public var mMainStart = 0.0;
	public var mMainEnd = 0.0;
	public var mCrossStart = 0.0;
	public var mCrossEnd = 0.0;
	// its auto margins: 1 at the start, 2 at the end
	public var autoMain = 0;
	public var autoCross = 0;
	public var minMain = 0.0;
	public var maxMain = 0.0;
	public var minCross = 0.0;
	public var maxCross = 0.0;
	public var align:Align = Stretch;
	public var styleCross = 0.0;
	public var basis = 0.0;
	public var edges = 0.0;
	public var hypo = 0.0;
	public var main = 0.0;
	public var cross = 0.0;
	public var frozen = false;
	public var violation = 0.0;
	// (on its baseline: that below its outer start)
	public var baseline = 0.0;

	public function new() {}

	public function reset(node:Node) {
		this.node = node;
		mMainStart = mMainEnd = mCrossStart = mCrossEnd = 0;
		autoMain = autoCross = 0;
		minMain = maxMain = minCross = maxCross = 0;
		align = Stretch;
		styleCross = basis = edges = hypo = main = cross = violation = baseline = 0;
		frozen = false;
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

	public function new(node:Node)
		this.node = node;
}

// items[start...end] (Layout.items)
private class Line {
	public var start = 0;
	public var end = 0;
	public var cross = 0.0;
	// its items' baseline below its start, those aligned on it
	public var baseline = 0.0;

	public function new() {}
}
