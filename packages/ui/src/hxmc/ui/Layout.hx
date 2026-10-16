package hxmc.ui;

// Flexbox layout of a Node tree, after CSS Flexible Box Layout (section 9)
// with Yoga's simplifications: min sizes default to 0 (no automatic minimum
// from the content), margins are pixels (no auto margins), no baseline
// alignment. Sizes are border boxes; padding and borderWidth are inside.
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
	public static function run(root:Node, width:Float, height:Float, text:TextEngine) {
		var l = new Layout(text);
		if (root.dirty || root.lw != width || root.lh != height) l.size(root, width, height, width, height, width, height, true);
		root.lx = 0;
		root.ly = 0;
		round(root, 0, 0, 0, 0);
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
		var pad = s.padding, bw = s.borderWidth;
		var padL = pad.left + bw, padT = pad.top + bw, padH = pad.left + pad.right + 2 * bw, padV = pad.top + pad.bottom + 2 * bw;
		if (n.hasContent() && n.children.length == 0) {
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
			}
		} else flex(n, w, h, availW, availH, minW, maxW, minH, maxH, padL, padT, padH, padV, perform);
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
			case Start:
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
				case Start:
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

		// absolute children, in the padding box
		var pbW = bw - 2 * s.borderWidth, pbH = bh - 2 * s.borderWidth;
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
			var ax = known(l) ? l + m.left : known(r) ? pbW - r - aw - m.right : padL - s.borderWidth + m.left;
			var ay = known(t) ? t + m.top : known(b) ? pbH - b - ah - m.bottom : padT - s.borderWidth + m.top;
			c.lx = s.borderWidth + ax;
			c.ly = s.borderWidth + ay;
			size(c, aw, ah, pbW, pbH, aw, ah, true);
			c.lw = aw;
			c.lh = ah;
		}
		n.lw = bw;
		n.lh = bh;
		@:privateAccess n.contentWidth = cw;
		@:privateAccess n.contentHeight = ch;
		n.dirty = false;
		rw = bw;
		rh = bh;
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
		for (c in n.children)
			hide(c);
	}

	// rounds each box's edges in window coordinates
	static function round(n:Node, parentAbsX:Float, parentAbsY:Float, parentRoundX:Float, parentRoundY:Float) {
		var ax = parentAbsX + n.lx, ay = parentAbsY + n.ly;
		var x0 = Math.fround(ax), y0 = Math.fround(ay), x1 = Math.fround(ax + n.lw), y1 = Math.fround(ay + n.lh);
		@:privateAccess n.setLayout(x0 - parentRoundX, y0 - parentRoundY, x1 - x0, y1 - y0, x0, y0, n.contentWidth, n.contentHeight);
		// (scrolled children: the scroll offset moves them when drawn and hit, not here)
		for (c in n.children)
			round(c, ax, ay, x0, y0);
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

private class Line {
	public final items:Array<Item> = [];
	public var cross = 0.0;

	public function new() {}
}
