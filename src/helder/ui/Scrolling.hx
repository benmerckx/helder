package helder.ui;

// Ui's scrolling: the wheel's (the nearest Overflow Scroll ancestor that
// can move that way), the keys' (eased: scrollBy), scrollIntoView, and the
// scrollbars' geometry and their thumbs dragged (a click on a track pages).
// A scroller's offsets run from scrollStart (0, or right to left sideways
// less maxScroll) over maxScroll.
@:allow(helder.ui)
@:access(helder.ui.Ui)
class Scrolling {
	// the wheel's scroll from target: its nearest scroller that can move that way
	static function wheel(ui:Ui, target:Node, deltaX:Float, deltaY:Float, eased = false) {
		var n = target;
		while (n != null) {
			if (n.style.overflow == Scroll && (canScroll(n, deltaX, true) || canScroll(n, deltaY, false))) {
				// (a mouse's notch: glided to, slowing, from where a glide is heading)
				if (eased) {
					scrollBy(ui, n, deltaX, deltaY, true);
					return;
				}
				ui.scrolls.remove(n);
				n.scrollX += deltaX;
				n.scrollY += deltaY;
				clamp(n);
				if (n.onScroll != null) n.onScroll();
				ui.requestFrame();
				return;
			}
			n = n.parent;
		}
	}

	// whether a wheel on n by deltaX, deltaY would scroll something: a
	// scroller at n or around it (the innermost first) not at its end that way
	static function scrollsAt(ui:Ui, n:Null<Node>, deltaX:Float, deltaY:Float):Bool {
		while (n != null) {
			if (n.style.overflow == Scroll && (canScroll(n, deltaX, true) || canScroll(n, deltaY, false))) return true;
			n = n.parent;
		}
		return false;
	}

	// keys that scroll, when the focus took none of them (as a browser's):
	// the arrows by 40 pixels, Page Up and Down and Space (Shift: up) by
	// seven eighths of the view, Home and End to the ends; the nearest
	// scroller that can move that way around the focus, else the pointer
	static inline var ARROW_STEP = 40;

	static function keyScroll(ui:Ui, key:Int, mods:Int):Bool {
		if (mods & (Key.MOD_CONTROL | Key.MOD_META | Key.MOD_ALT) != 0) return false;
		if (ui.focus != null && ui.focus.takesText()) return false;
		var x = key == Key.LEFT || key == Key.RIGHT;
		var back = key == Key.UP || key == Key.LEFT || key == Key.PAGE_UP || key == Key.HOME || key == Key.SPACE && mods & Key.MOD_SHIFT != 0;
		var page = key == Key.PAGE_UP || key == Key.PAGE_DOWN || key == Key.SPACE, edge = key == Key.HOME || key == Key.END;
		if (!(x || page || edge || key == Key.UP || key == Key.DOWN)) return false;
		var n = ui.focus != null ? ui.focus : ui.hover;
		while (n != null) {
			if (n.style.overflow == Scroll) {
				var s = n.style, view = (x ? n.width : n.height) - (x ? s.borderEdges.horizontal + s.padding.horizontal : s.borderEdges.vertical + s.padding.vertical);
				var d = edge ? maxScroll(n, x) + 1 : page ? Math.max(1, view * 0.875) : ARROW_STEP;
				if (back) d = -d;
				if (canScroll(n, d, x)) {
					scrollBy(ui, n, x ? d : 0, x ? 0 : d);
					return true;
				}
			}
			n = n.parent;
		}
		return false;
	}

	// scrolls by dx, dy eased over Ui.scrollDuration (a scroll easing already: from where it is, to its end moved on)
	static function scrollBy(ui:Ui, n:Node, dx:Float, dy:Float, out = false) {
		var a = ui.scrolls.get(n);
		var tx = (a != null ? a[2] : n.scrollX) + dx, ty = (a != null ? a[3] : n.scrollY) + dy;
		tx = clampTo(n, true, tx);
		ty = clampTo(n, false, ty);
		if (ui.scrollDuration <= 0) {
			ui.scrollTo(n, tx, ty);
			return;
		}
		// (a wheel's notch: ScrollGlide's curve, from rest or from its speed; keys': in and out)
		// (its start the first tick's: Clock.now is the last tick's, long ago when the window was idle)
		ui.scrolls.set(n, [n.scrollX, n.scrollY, tx, ty, -1, out ? (a == null ? 2 : 1) : 0]);
		ui.requestFrame();
		if (a != null) return;
		Clock.addTo(ui.context, t -> {
			var a = ui.scrolls.get(n);
			if (a == null) return false;
			if (a[4] < 0) a[4] = t;
			var k = Math.min(1, Math.max(0, (t - a[4]) / (a[5] > 0 ? ScrollGlide.DURATION : ui.scrollDuration)));
			var e = ScrollGlide.ease(k, a[5] != 1);
			setScroll(ui, n, true, a[0] + (a[2] - a[0]) * e);
			setScroll(ui, n, false, a[1] + (a[3] - a[1]) * e);
			if (k < 1) return true;
			ui.scrolls.remove(n);
			return false;
		});
	}

	static function canScroll(n:Node, d:Float, x:Bool):Bool {
		if (d == 0 || (x ? n.style.overflowX : n.style.overflowY) != Scroll) return false;
		var lo = scrollStart(n, x), v = x ? n.scrollX : n.scrollY;
		return d > 0 ? v < lo + maxScroll(n, x) : v > lo;
	}

	// how far n scrolls on the axis (from scrollStart)
	static function maxScroll(n:Node, x:Bool):Float {
		var s = n.style, inset = x ? s.borderEdges.horizontal + s.padding.horizontal : s.borderEdges.vertical + s.padding.vertical;
		var view = (x ? n.width : n.height) - inset;
		// (less than half a pixel over: none, the box being rounded and the content not, as Chromium snaps scrollHeight)
		var over = (x ? n.contentWidth : n.contentHeight) - view;
		return over < 0.5 ? 0 : over;
	}

	// its least offset on the axis: 0, but right to left, sideways, its
	// content overflows to the left: scrolled from 0 (its right end) down to
	// less maxScroll, as Chromium's scrollLeft
	static function scrollStart(n:Node, x:Bool):Float
		return x && n.rtl() ? -maxScroll(n, true) : 0;

	static inline function clampTo(n:Node, x:Bool, v:Float):Float {
		var lo = scrollStart(n, x);
		return Math.max(lo, Math.min(v, lo + maxScroll(n, x)));
	}

	// a scroller's offsets back within its extent
	static function clamp(n:Node) {
		var x = clampTo(n, true, n.scrollX), y = clampTo(n, false, n.scrollY);
		if (x != n.scrollX || y != n.scrollY) {
			n.scrollX = x;
			n.scrollY = y;
			if (n.onScroll != null) n.onScroll();
		}
	}

	// scrolls n's scrolling ancestors, nearest first, as little as brings it
	// into each one's view (its far edge at the view's, unless it is larger)
	static function scrollIntoView(ui:Ui, n:Node) {
		var p = n.parent, shiftX = 0.0, shiftY = 0.0;
		while (p != null) {
			if (p.style.overflow == Scroll) {
				for (x in [false, true]) {
					var s = p.style, inset = x ? s.borderEdges.left + s.padding.left : s.borderEdges.top + s.padding.top;
					var start = (x ? n.absX - p.absX - shiftX : n.absY - p.absY - shiftY) - inset, end = start + (x ? n.width : n.height);
					var view = viewSize(p, x), cur = x ? p.scrollX : p.scrollY;
					if (start < cur) setScroll(ui, p, x, start) else if (end > cur + view) setScroll(ui, p, x, Math.min(start, end - view));
				}
				shiftX += p.scrollX;
				shiftY += p.scrollY;
			}
			p = p.parent;
		}
	}

	static function viewSize(n:Node, x:Bool):Float {
		var s = n.style;
		return (x ? n.width : n.height) - (x ? s.borderEdges.horizontal + s.padding.horizontal : s.borderEdges.vertical + s.padding.vertical);
	}

	// a scrollbar's track on axis x (horizontal) or y: its start and length
	// along the axis (absolute), its offset across it; right to left, the
	// vertical one on the left, as Chromium has it
	static function track(n:Node, x:Bool):Array<Float> {
		var be = n.style.borderEdges, i = Ui.SCROLLBAR_INSET, rtl = n.rtl(), b = barSize(n);
		// (the other axis's bar, if any, takes the corner)
		var corner = maxScroll(n, !x) > 0 ? b + i : 0;
		return x ? [n.absX + be.left + i + (rtl ? corner : 0), n.width - be.horizontal - 2 * i - corner, n.absY + n.height - be.bottom - i - b] : [
			n.absY + be.top + i, n.height - be.vertical - 2 * i - corner, rtl ? n.absX + be.left + i : n.absX + n.width - be.right - i - b];
	}

	// (a scroller's scrollbar thickness: its style's, 0 for none)
	static function barSize(n:Node):Float
		return switch n.style.scrollbarWidth {
			case None: 0;
			case Thin: Ui.SCROLLBAR * 2 / 3;
			case _: Ui.SCROLLBAR;
		}

	// (the scrollbar colours n inherits: its track's or its thumb's; null: none given)
	static function inheritedBar(n:Node, track:Bool):Null<Color> {
		var p = n;
		while (p != null) {
			var c = track ? p.style.scrollbarTrackColor : p.style.scrollbarColor;
			if (c != null) return c;
			p = p.parent;
		}
		return null;
	}

	static function thumbLength(trackLength:Float, view:Float, content:Float):Float
		return Math.min(trackLength, Math.max(Ui.MIN_THUMB, trackLength * view / content));

	// the thumb's rectangle (x, y, w, h: absolute, unscrolled), or null when n
	// does not overflow on the axis
	static function thumb(n:Node, x:Bool):Null<Array<Float>> {
		if ((x ? n.style.overflowX : n.style.overflowY) != Scroll) return null;
		var max = maxScroll(n, x);
		if (max <= 0) return null;
		if (barSize(n) <= 0) return null;
		var t = track(n, x);
		if (t[1] <= 0) return null;
		var len = thumbLength(t[1], viewSize(n, x), x ? n.contentWidth : n.contentHeight);
		var at = t[0] + (t[1] - len) * ((x ? n.scrollX : n.scrollY) - scrollStart(n, x)) / max;
		var b = barSize(n);
		return x ? [at, t[2], len, b] : [t[2], at, b, len];
	}

	// a node's offset from window to its own (unscrolled) coordinates: its
	// ancestors' scrolling
	static function scrolled(n:Node, x:Bool):Float {
		var d = 0.0, p = n.parent;
		while (p != null) {
			if (p.style.overflow == Scroll) d += x ? p.scrollX : p.scrollY;
			p = p.parent;
		}
		return d;
	}

	// a press on a scrollbar of target or an ancestor: starts dragging its
	// thumb, or pages towards the press on its track
	static function scrollbarDown(ui:Ui, target:Node, px:Float, py:Float):Bool {
		var n = target;
		while (n != null) {
			if (n.style.overflow == Scroll)
				for (x in [false, true]) {
					var t = thumb(n, x);
					if (t == null) continue;
					var tr = track(n, x);
					var lx = px + scrolled(n, true), ly = py + scrolled(n, false);
					var along = x ? lx : ly, across = x ? ly : lx;
					if (across < tr[2] - Ui.SCROLLBAR_INSET || across > tr[2] + barSize(n) + Ui.SCROLLBAR_INSET || along < tr[0] || along > tr[0] + tr[1]) continue;
					var start = x ? t[0] : t[1], len = x ? t[2] : t[3];
					if (along >= start && along <= start + len) {
						ui.drag = n;
						ui.dragX = x;
						ui.dragFrom = x ? px : py;
						ui.dragScroll = x ? n.scrollX : n.scrollY;
						ui.requestFrame();
					} else {
						var page = viewSize(n, x) * (along < start ? -1 : 1);
						setScroll(ui, n, x, (x ? n.scrollX : n.scrollY) + page);
					}
					return true;
				}
			n = n.parent;
		}
		return false;
	}

	static function setScroll(ui:Ui, n:Node, x:Bool, v:Float) {
		v = clampTo(n, x, v);
		if (v == (x ? n.scrollX : n.scrollY)) return;
		if (x) n.scrollX = v; else n.scrollY = v;
		if (n.onScroll != null) n.onScroll();
		ui.requestFrame();
	}
}
