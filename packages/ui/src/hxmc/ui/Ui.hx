package hxmc.ui;

import hxmc.ui.Event;

// The host of a UI tree: its viewport, its TextEngine, layout (update),
// drawing (paint) and input. A window's loop (hxmc.ui.draw.Window, or a
// test) feeds it pointer, wheel, key and text events in window pixels and
// calls update and paint when needsFrame. Pointer events go to the topmost
// node under the pointer (Node.hitTest), or while a button is down to the
// node it went down on; key and text events to the focused node; all
// bubble to the ancestors. Clicking a focusable node (or a descendant of
// one) focuses it, Tab and Shift+Tab move the focus through the focusable
// nodes in tree order, the wheel scrolls the nearest Overflow Scroll
// ancestor. A node that scrolls shows a scrollbar's thumb over its content
// on each axis it overflows, dragged to scroll (a click on its track pages);
// the focus moved by the keyboard shows a ring around the focused node (as
// CSS's :focus-visible: a click hides it). Popups (open, close) are
// layers over the tree: children of overlay, a second root laid out,
// drawn and hit after it.
class Ui {
	public final root:Node;
	// the layers above the tree (Popup nodes, the last on top)
	public final overlay:Node;
	public var text:TextEngine;
	public var width(default, null):Float;
	public var height(default, null):Float;
	public var focus(default, null):Null<Node>;
	public var hover(default, null):Null<Node>;
	// the node a button went down on (gets the pointer until it is up)
	public var capture(default, null):Null<Node>;
	public var needsFrame(default, null) = true;
	// the modifier keys held (Key.MOD_*: from the key events), which pointer events carry too
	public var mods(default, null) = 0;
	// the last pointer position
	public var pointerX(default, null) = 0.0;
	public var pointerY(default, null) = 0.0;
	// the focus was moved by the keyboard: its ring shows
	public var focusVisible(default, null) = false;
	// where widgets copy and paste text (UiWindow: the system's)
	public var clipboard:ClipboardHost = new ClipboardHost.MemoryClipboard();
	public var focusRingColor:Color = 0xFF3B82F6;
	public var focusRingWidth = 2.0;
	// the ring's gap outside the node
	public var focusRingOffset = 2.0;
	public var scrollbarColor:Color = 0x59000000;
	public var scrollbarActiveColor:Color = 0x8C000000;

	// the thumb being dragged: its node, axis, the pointer and scroll it started at
	var drag:Null<Node> = null;
	// drag and drop: the node a press may drag (its dragData), where it went down; the drag, its target that accepts
	var dragSource:Null<Node> = null;
	var dragFromX = 0.0;
	var dragFromY = 0.0;
	// what is being dragged and where (null: nothing)
	public var dragging(default, null):Null<{source:Node, data:Dynamic, x:Float, y:Float}> = null;
	var dropTarget:Null<Node> = null;
	var dragX = false;
	var dragFrom = 0.0;
	var dragScroll = 0.0;

	// a scrollbar's thickness and its inset from the node's border
	public static inline var SCROLLBAR = 6.0;
	public static inline var SCROLLBAR_INSET = 2.0;
	public static inline var MIN_THUMB = 20.0;

	public function new(text:TextEngine, width:Float, height:Float) {
		this.text = text;
		this.width = width;
		this.height = height;
		root = new Node("root");
		root.attach(this);
		overlay = new Node("overlay");
		overlay.attach(this);
	}

	public function resize(width:Float, height:Float) {
		if (width == this.width && height == this.height) return;
		this.width = width;
		this.height = height;
		root.markDirty();
		overlay.markDirty();
	}

	public function requestFrame()
		needsFrame = true;

	// lays the tree out if it changed
	public function update() {
		Layout.run(root, width, height, text);
		clampScroll(root);
		if (overlay.children.length > 0) {
			Layout.run(overlay, width, height, text);
			// (placed from their sizes: laid out again when one moved)
			if (placePopups()) Layout.run(overlay, width, height, text);
			clampScroll(overlay);
		}
	}

	// draws the tree (after update)
	public function paint(canvas:Canvas) {
		needsFrame = false;
		paintNode(root, canvas);
		if (overlay.children.length > 0) paintNode(overlay, canvas);
	}

	function paintNode(n:Node, canvas:Canvas) {
		var s = n.style;
		if (s.display == None || n.width <= 0 && n.height <= 0 && n.children.length == 0) return;
		if (s.opacity <= 0) return;
		if (s.opacity < 1) canvas.pushOpacity(s.opacity);
		var sh = s.shadow;
		if (sh != null)
			canvas.shadow(n.absX + sh.x - sh.spread, n.absY + sh.y - sh.spread, n.width + 2 * sh.spread, n.height + 2 * sh.spread,
				s.radius > 0 ? s.radius + sh.spread : 0, sh.color, sh.blur);
		if (s.background.a > 0 || (s.borderWidth > 0 && s.borderColor.a > 0))
			canvas.rect(n.absX, n.absY, n.width, n.height, s.radius, s.background, s.borderWidth, s.borderColor);
		var bw = s.borderWidth, pad = s.padding;
		if (n.hasContent())
			n.paintContent(canvas, n.absX + bw + pad.left, n.absY + bw + pad.top, Math.max(0, n.width - 2 * bw - pad.left - pad.right),
				Math.max(0, n.height - 2 * bw - pad.top - pad.bottom));
		var clip = s.overflow != Visible;
		if (clip) canvas.pushClip(n.absX + bw, n.absY + bw, n.width - 2 * bw, n.height - 2 * bw, Math.max(0, s.radius - bw));
		var scroll = s.overflow == Scroll && (n.scrollX != 0 || n.scrollY != 0);
		if (scroll) canvas.translate(-n.scrollX, -n.scrollY);
		for (c in n.children)
			paintNode(c, canvas);
		if (scroll) canvas.translate(n.scrollX, n.scrollY);
		if (clip) canvas.popClip();
		if (s.overflow == Scroll) {
			for (x in [false, true]) {
				var t = thumb(n, x);
				if (t != null) canvas.rect(t[0], t[1], t[2], t[3], SCROLLBAR / 2, drag == n && dragX == x ? scrollbarActiveColor : scrollbarColor, 0, 0);
			}
		}
		if (n == focus && focusVisible && focusRingWidth > 0) {
			var o = focusRingOffset + focusRingWidth;
			canvas.rect(n.absX - o, n.absY - o, n.width + 2 * o, n.height + 2 * o, s.radius > 0 ? s.radius + o : 0, Color.TRANSPARENT, focusRingWidth,
				focusRingColor);
		}
		if (s.opacity < 1) canvas.popOpacity();
	}

	// --- pointer ---

	public function pointerMove(x:Float, y:Float) {
		pointerX = x;
		pointerY = y;
		if (drag != null) {
			var n = drag, t = track(n, dragX), view = viewSize(n, dragX), content = dragX ? n.contentWidth : n.contentHeight;
			var len = thumbLength(t[1], view, content), max = maxScroll(n, dragX);
			var v = dragScroll + ((dragX ? x : y) - dragFrom) * (t[1] > len ? max / (t[1] - len) : 0);
			setScroll(n, dragX, v);
			return;
		}
		// (a press on a draggable moved past 4 pixels: its drag starts)
		if (dragging == null && dragSource != null && capture != null && Math.abs(x - dragFromX) + Math.abs(y - dragFromY) > 4) {
			var s = dragSource;
			dragSource = null;
			var e = new Event(DragStart, s, x, y);
			e.data = s.dragData;
			bubble(e);
			if (!e.defaultPrevented) {
				setPressed(capture, false);
				capture = null;
				dragging = {source: s, data: s.dragData, x: x, y: y};
			}
		}
		var target = hit(x, y);
		setHover(target);
		if (dragging != null) {
			dragging.x = x;
			dragging.y = y;
			dragOver(target, x, y);
			requestFrame();
			return;
		}
		var to = capture != null ? capture : target;
		if (to != null) bubble(new Event(PointerMove, to, x, y));
	}

	// the drag over target: from it up, the first that accepts (DragOver
	// with preventDefault) is the drop target; the one before it hears DragLeave
	function dragOver(target:Null<Node>, x:Float, y:Float) {
		// (left first: the pointer no longer inside the target that accepted, as HTML orders it)
		if (dropTarget != null && (target == null || !contains(dropTarget, target))) {
			leaveDrop(x, y);
			dropTarget = null;
		}
		var accepted:Null<Node> = null;
		var n = target;
		while (n != null && accepted == null) {
			if (n.onDragOver != null) {
				var e = new Event(DragOver, target, x, y);
				e.data = dragging.data;
				n.onDragOver(e.at(n));
				if (e.defaultPrevented) accepted = n;
			}
			n = n.parent;
		}
		if (dropTarget != null && dropTarget != accepted) leaveDrop(x, y);
		dropTarget = accepted;
	}

	function leaveDrop(x:Float, y:Float) {
		var t = dropTarget;
		if (t == null || t.onDragLeave == null) return;
		var e = new Event(DragLeave, t, x, y);
		e.data = dragging.data;
		t.onDragLeave(e.at(t));
	}

	// the drag ended: dropped on its target (Drop) or not, the source told (DragEnd)
	function endDrag(drop:Bool, x:Float, y:Float) {
		var d = dragging, t = dropTarget;
		dragging = null;
		dropTarget = null;
		if (t != null && !drop && t.onDragLeave != null) {
			var e = new Event(DragLeave, t, x, y);
			e.data = d.data;
			t.onDragLeave(e.at(t));
		}
		var dropped = drop && t != null;
		if (dropped && t.onDrop != null) {
			var e = new Event(Drop, t, x, y);
			e.data = d.data;
			t.onDrop(e.at(t));
		}
		var e = new Event(DragEnd, d.source, x, y);
		e.data = d.data;
		e.dropped = dropped;
		bubble(e);
		requestFrame();
	}

	public function pointerDown(x:Float, y:Float, button:Int) {
		pointerX = x;
		pointerY = y;
		var target = hit(x, y);
		dismissOutside(target);
		setHover(target);
		if (focusVisible) {
			focusVisible = false;
			requestFrame();
		}
		if (target == null) {
			setFocus(null);
			return;
		}
		if (scrollbarDown(target, x, y)) return;
		capture = target;
		dragSource = target;
		while (dragSource != null && dragSource.dragData == null)
			dragSource = dragSource.parent;
		dragFromX = x;
		dragFromY = y;
		setPressed(target, true);
		var e = new Event(PointerDown, target, x, y);
		e.button = button;
		e.mods = mods;
		bubble(e);
		if (!e.defaultPrevented) {
			var f = target;
			while (f != null && !f.focusable)
				f = f.parent;
			setFocus(f, false);
		}
	}

	public function pointerUp(x:Float, y:Float, button:Int) {
		pointerX = x;
		pointerY = y;
		if (drag != null) {
			drag = null;
			requestFrame();
			setHover(hit(x, y));
			return;
		}
		dragSource = null;
		if (dragging != null) {
			endDrag(true, x, y);
			setHover(hit(x, y));
			return;
		}
		var target = hit(x, y);
		var pressed = capture;
		capture = null;
		var to = pressed != null ? pressed : target;
		if (to == null) return;
		if (pressed != null) setPressed(pressed, false);
		var e = new Event(PointerUp, to, x, y);
		e.button = button;
		e.mods = mods;
		bubble(e);
		// a click: released over the node it went down on (or inside it)
		if (pressed != null && target != null && contains(pressed, target)) {
			var c = new Event(Click, pressed, x, y);
			c.button = button;
			bubble(c);
		}
		setHover(target);
	}

	public function wheel(x:Float, y:Float, deltaX:Float, deltaY:Float) {
		var target = hit(x, y);
		if (target == null) return;
		var e = new Event(Wheel, target, x, y);
		e.deltaX = deltaX;
		e.deltaY = deltaY;
		bubble(e);
		if (e.defaultPrevented) return;
		var n = target;
		while (n != null) {
			if (n.style.overflow == Scroll && (canScroll(n, deltaX, true) || canScroll(n, deltaY, false))) {
				n.scrollX += deltaX;
				n.scrollY += deltaY;
				clampScroll(n);
				if (n.onScroll != null) n.onScroll();
				requestFrame();
				return;
			}
			n = n.parent;
		}
	}

	// --- keyboard ---

	public function keyDown(key:Int, mods:Int) {
		this.mods = mods | modOf(key);
		// (Escape during a drag: it ends, not dropped)
		if (dragging != null && key == Key.ESCAPE) {
			endDrag(false, pointerX, pointerY);
			return;
		}
		var e = new Event(KeyDown, focus != null ? focus : root, pointerX, pointerY);
		e.key = key;
		e.mods = mods;
		bubble(e);
		if (!e.defaultPrevented && key == Key.ESCAPE) {
			// the topmost popup that can be dismissed
			var i = overlay.children.length;
			while (--i >= 0) {
				var p = popupAt(i);
				if (p != null && p.onDismiss != null) {
					p.onDismiss();
					break;
				}
			}
		}
		if (!e.defaultPrevented && key == Key.TAB) {
			moveFocus(mods & Key.MOD_SHIFT != 0 ? -1 : 1);
			focusVisible = focus != null;
			requestFrame();
		}
	}

	public function keyUp(key:Int, mods:Int) {
		this.mods = mods & ~modOf(key);
		var e = new Event(KeyUp, focus != null ? focus : root, pointerX, pointerY);
		e.key = key;
		e.mods = mods;
		bubble(e);
	}

	public function textInput(text:String) {
		if (text.length == 0) return;
		var e = new Event(TextInput, focus != null ? focus : root, pointerX, pointerY);
		e.text = text;
		bubble(e);
	}

	// an input method's composition (empty: it ended), caret in it: to the focus
	public function composition(text:String, caret:Int) {
		var e = new Event(Composition, focus != null ? focus : root, pointerX, pointerY);
		e.text = text;
		e.caret = caret;
		bubble(e);
	}

	// where text is typed now (the focused node's caret, window pixels): the
	// input method's place; null: the focus takes no text
	public function textInputArea():Null<{x:Float, y:Float, width:Float, height:Float}>
		return focus == null ? null : focus.textInputArea();

	// the modifier a modifier key is (0: none)
	static function modOf(key:Int):Int
		return switch key {
			case Key.SHIFT | 0xFFE2: Key.MOD_SHIFT;
			case Key.CONTROL | 0xFFE4: Key.MOD_CONTROL;
			case Key.ALT | 0xFFEA: Key.MOD_ALT;
			case Key.META | 0xFFE8 | 0xFFEB | 0xFFEC: Key.MOD_META;
			case _: 0;
		}

	// --- focus ---

	// the focus moved to n (null: none); scroll: n brought into view in its
	// scrolling ancestors (not when a press focused it)
	public function setFocus(n:Null<Node>, scroll = true) {
		if (n == focus) return;
		if (scroll && n != null) scrollIntoView(n);
		var old = focus;
		focus = n;
		if (old != null) {
			@:privateAccess old.setState(old.hovered, old.pressed, false);
			if (old.onBlur != null) old.onBlur(new Event(Blur, old, pointerX, pointerY));
		}
		if (n != null) {
			@:privateAccess n.setState(n.hovered, n.pressed, true);
			if (n.onFocus != null) n.onFocus(new Event(Focus, n, pointerX, pointerY));
		}
	}

	// the next (1) or previous (-1) focusable node in tree order, wrapping
	public function moveFocus(dir:Int) {
		var all:Array<Node> = [];
		function collect(n:Node) {
			if (n.style.display == None) return;
			if (n.focusable) all.push(n);
			for (c in n.children)
				collect(c);
		}
		// (in the topmost modal popup only; else the tree, then the popups)
		var m = modal();
		if (m != null) collect(m) else {
			collect(root);
			collect(overlay);
		}
		if (all.length == 0) return;
		var i = focus == null ? (dir > 0 ? -1 : 0) : all.indexOf(focus);
		setFocus(all[(i + dir + all.length) % all.length]);
	}

	// --- popups ---

	// shows a popup over the tree, above those open; a modal one covers the
	// window (its content centred) and takes the focus (its first focusable node)
	public function open(p:Popup) {
		if (p.parent == overlay) return;
		p.returnFocus = focus;
		if (p.modal) {
			p.style.left = 0;
			p.style.top = 0;
			p.style.width = DimValue.Percent(100);
			p.style.height = DimValue.Percent(100);
			p.style.alignItems = Center;
			p.style.justify = Center;
		}
		overlay.append(p);
		if (p.modal) {
			var f = firstFocusable(p);
			setFocus(f);
		}
		requestFrame();
	}

	// removes a popup; the focus, if it was inside, goes back to where it was when it opened
	public function close(p:Popup) {
		if (p.parent != overlay) return;
		var inside = focus != null && contains(p, focus);
		overlay.remove(p);
		if (inside || focus == null) {
			var r = p.returnFocus;
			setFocus(r != null && r.ui == this ? r : null);
		}
		p.returnFocus = null;
		requestFrame();
	}

	function popupAt(i:Int):Null<Popup> {
		var c = overlay.children[i];
		return Std.isOfType(c, Popup) ? cast c : null;
	}

	// the topmost modal popup (null: none)
	function modal():Null<Popup> {
		var i = overlay.children.length;
		while (--i >= 0) {
			var p = popupAt(i);
			if (p != null && p.modal) return p;
		}
		return null;
	}

	static function firstFocusable(n:Node):Null<Node> {
		if (n.style.display == None) return null;
		if (n.focusable) return n;
		for (c in n.children) {
			var f = firstFocusable(c);
			if (f != null) return f;
		}
		return null;
	}

	// the topmost node under a point: in the popups (a modal one stops the
	// search: what is under it is covered), then the tree
	function hit(x:Float, y:Float):Null<Node> {
		var i = overlay.children.length;
		while (--i >= 0) {
			var c = overlay.children[i];
			var h = c.hitTest(x, y);
			if (h != null) return h;
			if (Std.isOfType(c, Popup) && (cast c : Popup).modal) return null;
		}
		return root.hitTest(x, y);
	}

	// a press outside the popups on top (and their anchors) dismisses them;
	// on a modal one's backdrop, it
	function dismissOutside(target:Null<Node>) {
		var i = overlay.children.length;
		while (--i >= 0) {
			if (i >= overlay.children.length) continue;
			var p = popupAt(i);
			if (p == null) continue;
			if (target != null && target != p && contains(p, target)) break;
			if (p.modal) {
				if (target == p && p.onDismiss != null) p.onDismiss();
				break;
			}
			if (target != null && p.anchor != null && contains(p.anchor, target)) break;
			if (p.onDismiss != null) p.onDismiss();
		}
	}

	// the anchored popups placed (their style's left and top): true when one moved
	function placePopups():Bool {
		var moved = false;
		for (c in overlay.children) {
			if (!Std.isOfType(c, Popup)) continue;
			var p:Popup = cast c;
			if (p.modal || p.placement == Manual) continue;
			var w = p.width, h = p.height, x = 0.0, y = 0.0;
			if (p.placement == Point) {
				x = p.atX + w > width && p.atX - w >= 0 ? p.atX - w : p.atX;
				y = p.atY + h > height && p.atY - h >= 0 ? p.atY - h : p.atY;
			} else if (p.placement == Center || p.anchor == null || p.anchor.ui != this) {
				if (p.placement != Center && p.anchor != null) continue;
				x = (width - w) / 2;
				y = (height - h) / 2;
			} else {
				// the anchor where it is drawn: its ancestors' scrolling taken off
				var a = p.anchor, ax = a.absX, ay = a.absY, n = a.parent;
				while (n != null) {
					if (n.style.overflow == Scroll) {
						ax -= n.scrollX;
						ay -= n.scrollY;
					}
					n = n.parent;
				}
				var g = p.gap;
				switch p.placement {
					case Below | Above:
						x = ax;
						var below = ay + a.height + g, above = ay - g - h;
						y = p.placement == Below ? (below + h > height && above >= 0 ? above : below) : (above < 0 && below + h <= height ? below : above);
					case _:
						y = ay;
						var right = ax + a.width + g, left = ax - g - w;
						x = p.placement == Right ? (right + w > width && left >= 0 ? left : right) : (left < 0 && right + w <= width ? right : left);
				}
			}
			x = Math.round(Math.max(0, Math.min(x, width - w)));
			y = Math.round(Math.max(0, Math.min(y, height - h)));
			if (p.style.left.resolve(0) != x || p.style.top.resolve(0) != y) {
				p.style.left = x;
				p.style.top = y;
				moved = true;
			}
		}
		return moved;
	}

	// --- internals ---

	function bubble(e:Event) {
		var n = e.target;
		while (n != null && !e.stopped) {
			var h = switch e.type {
				case PointerDown: n.onPointerDown;
				case PointerUp: n.onPointerUp;
				case PointerMove: n.onPointerMove;
				case Click: n.onClick;
				case Wheel: n.onWheel;
				case KeyDown: n.onKeyDown;
				case KeyUp: n.onKeyUp;
				case TextInput: n.onTextInput;
				case Composition: n.onComposition;
				case DragStart: n.onDragStart;
				case DragEnd: n.onDragEnd;
				case _: null;
			}
			if (h != null) h(e.at(n));
			n = n.parent;
		}
	}

	function setHover(target:Null<Node>) {
		if (target == hover) return;
		// leave the old path up to the common ancestor, enter the new one
		var old:Array<Node> = [], now:Array<Node> = [];
		var n = hover;
		while (n != null) {
			old.push(n);
			n = n.parent;
		}
		n = target;
		while (n != null) {
			now.push(n);
			n = n.parent;
		}
		hover = target;
		for (o in old)
			if (!now.contains(o)) {
				@:privateAccess o.setState(false, o.pressed, o.focused);
				if (o.onPointerLeave != null) o.onPointerLeave(new Event(PointerLeave, o, pointerX, pointerY));
			}
		var i = now.length;
		while (--i >= 0) {
			var o = now[i];
			if (!old.contains(o)) {
				@:privateAccess o.setState(true, o.pressed, o.focused);
				if (o.onPointerEnter != null) o.onPointerEnter(new Event(PointerEnter, o, pointerX, pointerY));
			}
		}
	}

	function setPressed(target:Node, on:Bool) {
		var n = target;
		while (n != null) {
			@:privateAccess n.setState(n.hovered, on, n.focused);
			n = n.parent;
		}
	}

	static function contains(ancestor:Node, n:Node):Bool {
		while (n != null) {
			if (n == ancestor) return true;
			n = n.parent;
		}
		return false;
	}

	static function canScroll(n:Node, d:Float, x:Bool):Bool {
		if (d == 0) return false;
		var max = maxScroll(n, x);
		var v = x ? n.scrollX : n.scrollY;
		return d > 0 ? v < max : v > 0;
	}

	static function maxScroll(n:Node, x:Bool):Float {
		var s = n.style, inset = 2 * s.borderWidth + (x ? s.padding.horizontal : s.padding.vertical);
		var view = (x ? n.width : n.height) - inset;
		return Math.max(0, (x ? n.contentWidth : n.contentHeight) - view);
	}

	function clampScroll(n:Node) {
		if (n.style.overflow == Scroll) {
			var x = Math.max(0, Math.min(n.scrollX, maxScroll(n, true))), y = Math.max(0, Math.min(n.scrollY, maxScroll(n, false)));
			if (x != n.scrollX || y != n.scrollY) {
				n.scrollX = x;
				n.scrollY = y;
				if (n.onScroll != null) n.onScroll();
			}
		}
		for (c in n.children)
			clampScroll(c);
	}

	// the pointer's shape: the style of the node under it (or that has it
	// captured), Auto taking the parent's; Default over a scrollbar's drag
	public function cursor():Cursor {
		if (drag != null) return Default;
		var n = capture != null ? capture : hover;
		while (n != null) {
			if (n.style.cursor != Auto) return n.style.cursor;
			n = n.parent;
		}
		return Default;
	}

	// --- accessibility ---

	var lastAccess:Null<hxmc.ui.access.AccessTree>;

	// the accessibility tree now (after update): what accessAction acts in
	public function accessTree():hxmc.ui.access.AccessTree
		return lastAccess = hxmc.ui.access.AccessTree.build(this);

	// assistive technology's request on a node of the last accessTree():
	// false when the node is gone or does not take it
	public function accessAction(id:Int, action:hxmc.ui.access.AccessAction, ?value:String):Bool {
		var n = lastAccess == null ? null : lastAccess.node(id);
		if (n == null || n.ui != this) return false;
		switch action {
			case Click:
				var x = n.absX + n.width / 2, y = n.absY + n.height / 2;
				bubble(new Event(Click, n, x, y));
			case Focus:
				if (!n.focusable) return false;
				setFocus(n);
				focusVisible = true;
				requestFrame();
			case Increment | Decrement:
				if (n.focusable) setFocus(n);
				keyDown(action == Increment ? Key.RIGHT : Key.LEFT, 0);
			case SetValue:
				if (value == null || !n.accessSetValue(value)) return false;
		}
		return true;
	}

	// scrolls n's scrolling ancestors, nearest first, as little as brings it
	// into each one's view (its far edge at the view's, unless it is larger)
	public function scrollIntoView(n:Node) {
		var p = n.parent, shiftX = 0.0, shiftY = 0.0;
		while (p != null) {
			if (p.style.overflow == Scroll) {
				for (x in [false, true]) {
					var s = p.style, inset = s.borderWidth + (x ? s.padding.left : s.padding.top);
					var start = (x ? n.absX - p.absX - shiftX : n.absY - p.absY - shiftY) - inset, end = start + (x ? n.width : n.height);
					var view = viewSize(p, x), cur = x ? p.scrollX : p.scrollY;
					if (start < cur) setScroll(p, x, start) else if (end > cur + view) setScroll(p, x, Math.min(start, end - view));
				}
				shiftX += p.scrollX;
				shiftY += p.scrollY;
			}
			p = p.parent;
		}
	}

	// --- scrollbars ---

	static function viewSize(n:Node, x:Bool):Float {
		var s = n.style;
		return (x ? n.width : n.height) - 2 * s.borderWidth - (x ? s.padding.horizontal : s.padding.vertical);
	}

	// a scrollbar's track on axis x (horizontal) or y: its start and length
	// along the axis (absolute), its offset across it
	static function track(n:Node, x:Bool):Array<Float> {
		var bw = n.style.borderWidth, i = SCROLLBAR_INSET;
		// (the other axis's bar, if any, takes the corner)
		var corner = maxScroll(n, !x) > 0 ? SCROLLBAR + i : 0;
		return x ? [n.absX + bw + i, n.width - 2 * bw - 2 * i - corner, n.absY + n.height - bw - i - SCROLLBAR] : [n.absY + bw + i,
			n.height - 2 * bw - 2 * i - corner, n.absX + n.width - bw - i - SCROLLBAR];
	}

	static function thumbLength(trackLength:Float, view:Float, content:Float):Float
		return Math.min(trackLength, Math.max(MIN_THUMB, trackLength * view / content));

	// the thumb's rectangle (x, y, w, h: absolute, unscrolled), or null when n
	// does not overflow on the axis
	static function thumb(n:Node, x:Bool):Null<Array<Float>> {
		var max = maxScroll(n, x);
		if (max <= 0) return null;
		var t = track(n, x);
		if (t[1] <= 0) return null;
		var len = thumbLength(t[1], viewSize(n, x), x ? n.contentWidth : n.contentHeight);
		var at = t[0] + (t[1] - len) * (x ? n.scrollX : n.scrollY) / max;
		return x ? [at, t[2], len, SCROLLBAR] : [t[2], at, SCROLLBAR, len];
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
	function scrollbarDown(target:Node, px:Float, py:Float):Bool {
		var n = target;
		while (n != null) {
			if (n.style.overflow == Scroll)
				for (x in [false, true]) {
					var t = thumb(n, x);
					if (t == null) continue;
					var tr = track(n, x);
					var lx = px + scrolled(n, true), ly = py + scrolled(n, false);
					var along = x ? lx : ly, across = x ? ly : lx;
					if (across < tr[2] - SCROLLBAR_INSET || across > tr[2] + SCROLLBAR + SCROLLBAR_INSET || along < tr[0] || along > tr[0] + tr[1]) continue;
					var start = x ? t[0] : t[1], len = x ? t[2] : t[3];
					if (along >= start && along <= start + len) {
						drag = n;
						dragX = x;
						dragFrom = x ? px : py;
						dragScroll = x ? n.scrollX : n.scrollY;
						requestFrame();
					} else {
						var page = viewSize(n, x) * (along < start ? -1 : 1);
						setScroll(n, x, (x ? n.scrollX : n.scrollY) + page);
					}
					return true;
				}
			n = n.parent;
		}
		return false;
	}

	function setScroll(n:Node, x:Bool, v:Float) {
		v = Math.max(0, Math.min(v, maxScroll(n, x)));
		if (v == (x ? n.scrollX : n.scrollY)) return;
		if (x) n.scrollX = v; else n.scrollY = v;
		if (n.onScroll != null) n.onScroll();
		requestFrame();
	}

	// a node left the tree: it no longer hovers, captures or has the focus
	@:allow(hxmc.ui.Node) function detached(n:Node) {
		if (hover != null && contains(n, hover)) hover = null;
		if (capture != null && contains(n, capture)) capture = null;
		if (drag != null && contains(n, drag)) drag = null;
		if (focus != null && contains(n, focus)) focus = null;
	}
}
