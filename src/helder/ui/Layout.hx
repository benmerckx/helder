package helder.ui;

// Flexbox layout of a Node tree, after CSS Flexible Box Layout (section 9),
// and CSS grid for a Display Grid container (GridLayout):
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
// laid out with the same constraints as last time; a node changed whose
// parent's measures of it come out as they were is laid out again in place,
// its ancestors not (inPlace). At the end the boxes are
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
	// (known: the next size() measures its node's content's height, its aspect ratio left out, a wrapping
	// column's lines broken at this height, the ratio's)
	var noRatio = Math.NaN;
	// flex items and lines, kept from layout to layout: a container's are
	// taken from the top and given back when it is done (its children's
	// taken above them meanwhile)
	static final items:Array<Item> = [];
	static var itemTop = 0;
	static final lines:Array<Line> = [];
	static var lineTop = 0;

	static inline var CACHE = 4; // measured results kept per node
	static inline var ENTRY = 9; // knownW, knownH, availW, availH, bare (1: its width, 2: its height), width, height, parentW, parentH
	static inline var CHANGES = 64; // nodes changed at most for inPlace to try (else from the root)
	// (inPlace's: a node's measures as they were; contain's: the nodes laid out in place)
	static final was:Array<Float> = [];
	static final tops:Array<Node> = [];
	// (the nodes laid out in place so far: a test's)
	@:noCompletion public static var inPlaces = 0;

	public function new(text:TextEngine)
		this.text = text;

	// lays out the tree in a viewport of width x height
	// whether anything was laid out again (a clean tree of the same size: nothing done);
	// the scrollers rounded again (their extents may have changed) are added to scrollers
	public static function run(root:Node, width:Float, height:Float, text:TextEngine, ?scrollers:Array<Node>):Bool {
		if (!root.dirty && root.lw == width && root.lh == height && !root.relaid) return false;
		var l = new Layout(text);
		itemTop = lineTop = 0;
		if (!(root.lw == width && root.lh == height && l.contain(root))) l.size(root, width, height, width, height, width, height, true);
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
		if (perform) {
			n.performed = !bareW && !bareH;
			n.pKW = knownW;
			n.pKH = knownH;
			n.pPW = parentW;
			n.pPH = parentH;
			n.pAW = availW;
			n.pAH = availH;
			n.pLoose = looseH;
		}
		// the style's own size, clamped
		// (bare on an axis where the node has no size, min or max of its own: as measured normally, cached alike)
		var bw = bareW && (s.width != DimValue.Auto || s.minWidth != DimValue.Auto || s.maxWidth != DimValue.Auto);
		var bh = bareH && (s.height != DimValue.Auto || s.minHeight != DimValue.Auto || s.maxHeight != DimValue.Auto);
		var bare = (bw ? 1 : 0) | (bh ? 2 : 0), baseW = bareW, base = bareH;
		bareW = bareH = false;
		var nrBreak = noRatio, nr = known(nrBreak);
		noRatio = Math.NaN;
		// (measured bare, a column still breaks its lines at its own height within its max-height, in pixels)
		var bareBreak = bh && s.height.match(DimValue.Px(_)) ? s.height.resolve(parentH) : Math.NaN;
		if (bh && s.maxHeight.match(DimValue.Px(_))) {
			var most = s.maxHeight.resolve(parentH);
			if (!known(bareBreak) || most < bareBreak) bareBreak = most;
		}
		// (cached by how bare it was measured; not when that height, of its parent's, breaks it)
		var cached = !known(bareBreak) && !nr;
		// (its height definite for its children: given so, or its own)
		var defH = !looseH || known(s.height.resolve(parentH));
		looseH = false;
		var minW = Math.max(bw ? 0.0 : minWidthOf(n, s.minWidth, parentW, availW), edgesH(s)), maxW = bw ? Math.POSITIVE_INFINITY : maxWidthOf(n, s.maxWidth, parentW, availW);
		var minH = Math.max(bh ? 0.0 : min(s.minHeight, parentH), edgesV(s)), maxH = bh ? Math.POSITIVE_INFINITY : max(s.maxHeight, parentH);
		var w = known(knownW) ? knownW : bw ? Math.NaN : clamp(s.width.intrinsic() ? intrinsicWidth(n, s.width, parentW, availW) : s.width.resolve(parentW), minW, maxW);
		var h = known(knownH) ? knownH : bh ? Math.NaN : clamp(s.height.resolve(parentH), minH, maxH);
		var ar = nr ? 0 : s.aspectRatio;
		if (ar > 0) {
			if (!known(w) && known(h)) {
				w = clamp(h * ar, minW, maxW);
				// (no narrower than its content's min-content width)
				if (!baseW && s.width == DimValue.Auto && s.minWidth == DimValue.Auto && s.overflow == Visible)
					w = Math.max(w, Math.min(minContentWidth(n, parentW, false), maxW));
			} else if (known(w) && !known(h)) {
				h = clamp(w / ar, minH, maxH);
				// (no less than its content's height, within its max-height, its height and min-height auto (not a percentage
				// behaving as auto) and its overflow visible: CSS's automatic minimum size of a box with an aspect ratio; a
				// flex base size not, flex's own minimum then)
				if (!base && s.height == DimValue.Auto && s.minHeight == DimValue.Auto && s.overflow == Visible && (n.children.length > 0 || n.hasContent())) {
					noRatio = h;
					size(n, w, Math.NaN, parentW, parentH, availW, availH, false);
					if (rh > h) h = Math.min(rh, maxH);
				}
			}
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
		} else if (!cached) n.lossy = true else if (lookup(n, w, defH ? h : -1 - h, availW, availH, bare, parentW, parentH)) return;
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
		} else if (s.display == Grid) {
			// (a grid measured bare: its content's height still within its own min-height, as Chromium's)
			var least = bh ? Math.max(min(s.minHeight, parentH), edgesV(s)) : minH;
			GridLayout.grid(this, n, w, h, availW, availH, minW, maxW, minH, maxH, padL, padT, padH, padV, perform, least, defH);
		}
		else {
			breakH = nr ? nrBreak : bareBreak;
			flex(n, w, h, availW, availH, minW, maxW, minH, maxH, padL, padT, padH, padV, perform, defH);
		}
		if (!perform && cached) store(n, w, defH ? h : -1 - h, availW, availH, bare, rw, rh, parentW, parentH);
	}

	// --- laid out in place ---

	// the changed nodes (Ui.changes) each laid out in place, it or the
	// nearest ancestor that can be (inPlace), their ancestors as they were
	// but rounded again; whether all could be (else the root is laid out)
	function contain(root:Node):Bool {
		var u = root.ui;
		if (u == null || u.changes.length == 0 || u.changes.length > CHANGES) return false;
		tops.resize(0);
		for (c in u.changes) {
			if (!c.dirty) continue;
			var top = c;
			while (top.parent != null)
				top = top.parent;
			if (top != root) continue;
			var b = c;
			while (b != root && !inPlace(b))
				b = b.parent;
			if (b == root) return false;
			tops.push(b);
			inPlaces++;
		}
		for (b in tops) {
			var a = b.parent;
			while (a != null && a.dirty) {
				a.dirty = false;
				a.relaid = true;
				// (its measures kept, unless some were not)
				if (a.cacheWas >= 0) {
					if (a.cache != null) a.cache[0] = a.cacheWas;
					a.minContent = a.minContentWas;
				} else a.lossy = true;
				a = a.parent;
			}
		}
		return true;
	}

	// a changed node laid out again in place when its parent's layout of it
	// stays as it was: each measure its parent made of it (its cache when it
	// changed, all kept) and its min-content come out the same, it is not
	// on its baseline (its parent reads that), and laid out with what it was
	// given last time its size and overflow are its own as they were
	function inPlace(n:Node):Bool {
		var p = n.parent, s = n.style;
		if (p == null || !n.performed || n.cacheWas < 0 || s.display == None) return false;
		if ((s.alignSelf == Auto ? p.style.alignItems : s.alignSelf) == Baseline) return false;
		was.resize(0);
		for (i in 1...n.cacheWas + 1)
			was.push(n.cache[i]);
		var mc = n.minContentWas, i = 0;
		while (i < was.length) {
			// (as measured: bare, its height loose when kept negative)
			var hk = was[i + 1], bare = Std.int(was[i + 4]);
			bareW = bare & 1 != 0;
			bareH = bare & 2 != 0;
			looseH = hk < 0;
			size(n, was[i], hk < 0 ? -1 - hk : hk, was[i + 7], was[i + 8], was[i + 2], was[i + 3], false);
			if (!same(rw, was[i + 5]) || !same(rh, was[i + 6])) return false;
			i += ENTRY;
		}
		if (known(mc) && !same(minContentWidth(n, Math.NaN, false), mc)) return false;
		var lw = n.lw, lh = n.lh, cw = n.contentWidth, ch = n.contentHeight;
		looseH = n.pLoose;
		size(n, n.pKW, n.pKH, n.pPW, n.pPH, n.pAW, n.pAH, true);
		return same(rw, lw) && same(rh, lh) && same(n.contentWidth, cw) && same(n.contentHeight, ch);
	}

	// --- a flex container ---

	function flex(n:Node, w:Float, h:Float, availW:Float, availH:Float, minW:Float, maxW:Float, minH:Float, maxH:Float, padL:Float, padT:Float,
			padH:Float, padV:Float, perform:Bool, defH:Bool) {
		var s = n.style;
		var bareBreak = breakH;
		breakH = Math.NaN;
		// (a block: a column, its items at their own sizes; a row its own
		// direction made, a widget's, a flex row's)
		var block = s.display == Block && s.direction == Column;
		var row = !block && (s.direction == Row || s.direction == RowReverse);
		var reverse = !block && (s.direction == RowReverse || s.direction == ColumnReverse);
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
		var multi = !block && s.wrap;

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
			// (a legend first: a fieldset's rendered legend, outside the flex container in CSS, so no gap after it)
			if (c.legend && !row && itemTop == first + 1) it.mMainEnd -= gapMain;
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
				// (a row's: its min-content width, no less than its definite height's through its aspect ratio)
				if (row) content = cs.aspectRatio > 0 && known(it.styleCross) ? Math.max(minContentWidth(c, innerW, false), it.styleCross * cs.aspectRatio)
					: minContentWidth(c, innerW, false) else if (contentBasis && !(cs.aspectRatio > 0)) content = b else {
					var kc = it.styleCross;
					if (!known(kc) && it.align == Stretch && !multi && known(innerCross))
						kc = clamp(Math.max(0, innerCross - it.mCrossStart - it.mCrossEnd), it.minCross, it.maxCross);
					var ac = known(kc) ? kc : known(availCross) ? Math.max(0, availCross - it.mCrossStart - it.mCrossEnd) : Math.NaN;
					if (contentBasis && !known(kc)) content = b else {
						// (its content's height: not its own, CSS's content size suggestion; a wrapping
						// column's lines broken at its own definite height, its tallest line's, as Chromium's)
						bareH = true;
						size(c, kc, Math.NaN, innerW, pctH, ac, Math.NaN, false);
						content = rh;
						// (with an aspect ratio and a definite width: the height that width gives, its content's when
						// more, within its max across through the ratio; its height auto, not a percentage behaving as auto)
						if (cs.aspectRatio > 0 && known(kc) && cs.height == DimValue.Auto) {
							noRatio = rh;
							bareH = true;
							size(c, kc, Math.NaN, innerW, pctH, ac, Math.NaN, false);
							content = Math.max(content, Math.min(rh, it.maxCross / cs.aspectRatio));
						}
					}
				}
				// (with an aspect ratio: no less than its min across through the ratio, CSS's content size
				// suggestion; its max across not, its content wider, as Chromium has it)
				if (cs.aspectRatio > 0) content = Math.max(content, it.minCross * (row ? cs.aspectRatio : 1 / cs.aspectRatio));
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
			if (block) for (i in l.start...l.end) items[i].main = items[i].hypo else resolveFlexible(l, mainSize, gapMain);
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
							// flexed height, only its own height, as Chromium has it; in lines of a known width, its flexed height's)
							var given = oneLine || ics.aspectRatio > 0 && it.align == Stretch && !known(innerCross) ? Math.NaN : it.main;
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
			// (a column whose items have aspect ratios: laid out again at the width found, its items
			// stretched to it before their heights are, as Chromium finds a width before the heights)
			if (!row && aspectItems(n)) {
				itemTop = first;
				lineTop = firstLine;
				breakH = bareBreak;
				flex(n, crossSize + padH, h, availW, availH, minW, maxW, minH, maxH, padL, padT, padH, padV, perform, defH);
				return;
			}
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
		if (n.hasContent() && (n.children.length == 0 || n.contentOwnsChildren())) inner = n.minContentWidth(text) else if (s.display == Grid) inner = GridLayout.minContent(this, n) else {
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
	// (whether a node's item has an aspect ratio)
	static function aspectItems(n:Node):Bool {
		for (c in n.children)
			if (c.style.aspectRatio > 0 && c.style.display != None && c.style.position != Absolute) return true;
		return false;
	}

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
		n.performed = false;
		n.relaid = true;
		for (c in n.children)
			hide(c);
	}

	// rounds each box's edges in window coordinates (a subtree neither laid
	// out again nor moved is as it was), then its ink's bounds
	static function round(n:Node, parentAbsX:Float, parentAbsY:Float, parentRoundX:Float, parentRoundY:Float, scrollers:Null<Array<Node>>) {
		var ax = parentAbsX + n.lx, ay = parentAbsY + n.ly;
		// (where it is in its parent too: the parent moved and it not, it moved in its parent)
		if (!n.relaid && ax == n.rawX && ay == n.rawY && n.lw == n.rawW && n.lh == n.rawH && n.x == Math.fround(ax) - parentRoundX
			&& n.y == Math.fround(ay) - parentRoundY) return;
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

	// (pw, ph: its parent's box, compared when its own size is relative to it: relative())
	function lookup(n:Node, w:Float, h:Float, aw:Float, ah:Float, bare:Int, pw:Float, ph:Float):Bool {
		var c = n.cache;
		if (c == null) return false;
		var rel = relative(n.style);
		var i = 1, end = 1 + Std.int(c[0]);
		while (i < end) {
			if (same(c[i], w) && same(c[i + 1], h) && c[i + 4] == bare && fits(c[i + 2], c[i + 5], aw) && fits(c[i + 3], c[i + 6], ah) && (!rel || same(c[i + 7], pw)
				&& same(c[i + 8], ph))) {
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
	static function store(n:Node, w:Float, h:Float, aw:Float, ah:Float, bare:Int, rw:Float, rh:Float, pw:Float, ph:Float) {
		// (measured again since it changed: its measures as they were gone)
		if (n.dirty) n.cacheWas = -1;
		var c = n.cache;
		if (c == null) c = n.cache = new haxe.ds.Vector(1 + ENTRY, 0.0);
		var at = 1 + Std.int(c[0]);
		if (at >= c.length && c.length < 1 + CACHE * ENTRY) {
			var g = new haxe.ds.Vector(Std.int(Math.min(2 * c.length - 1, 1 + CACHE * ENTRY)), 0.0);
			for (i in 0...c.length)
				g[i] = c[i];
			c = n.cache = g;
		}
		if (at >= 1 + CACHE * ENTRY) {
			for (i in 1...at - ENTRY)
				c[i] = c[i + ENTRY];
			at -= ENTRY;
			n.lossy = true;
		}
		c[at] = w;
		c[at + 1] = h;
		c[at + 2] = aw;
		c[at + 3] = ah;
		c[at + 4] = bare;
		c[at + 5] = rw;
		c[at + 6] = rh;
		c[at + 7] = pw;
		c[at + 8] = ph;
		c[0] = at + ENTRY - 1;
	}

	// (whether a node's own size is relative to its parent's box: a percentage of it)
	static function relative(s:Style):Bool {
		inline function of(d:Dim):Bool
			return d.match(DimValue.Percent(_) | DimValue.Calc(_, _));
		return of(s.width) || of(s.height) || of(s.minWidth) || of(s.maxWidth) || of(s.minHeight) || of(s.maxHeight);
	}

	// (a share of free space as Chromium's LayoutUnit divides it: to a 64th of a pixel, toward zero)
	static inline function lu(v:Float):Float
		return v >= 0 ? Math.ffloor(v * 64) / 64 : Math.fceil(v * 64) / 64;

	static inline function known(v:Float):Bool
		return !Math.isNaN(v);

	static inline function same(a:Float, b:Float):Bool
		return a == b || (Math.isNaN(a) && Math.isNaN(b));

	// (a size measured in the room `was` is `got` in the room `now` too: the
	// same room, an unbounded one's size fitting, or a narrower room it still
	// fits, as Yoga reuses its measurements; not a wider one: what wrapped
	// in `was` may not in `now`)
	static inline function fits(was:Float, got:Float, now:Float):Bool
		return same(was, now) || got <= now && (Math.isNaN(was) || now < was);

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

// items[start...end] (Layout.items)
private class Line {
	public var start = 0;
	public var end = 0;
	public var cross = 0.0;
	// its items' baseline below its start, those aligned on it
	public var baseline = 0.0;

	public function new() {}
}
