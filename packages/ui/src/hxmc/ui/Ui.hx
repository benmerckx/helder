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
// ancestor.
class Ui {
	public final root:Node;
	public var text:TextEngine;
	public var width(default, null):Float;
	public var height(default, null):Float;
	public var focus(default, null):Null<Node>;
	public var hover(default, null):Null<Node>;
	// the node a button went down on (gets the pointer until it is up)
	public var capture(default, null):Null<Node>;
	public var needsFrame(default, null) = true;
	// the last pointer position
	public var pointerX(default, null) = 0.0;
	public var pointerY(default, null) = 0.0;

	public function new(text:TextEngine, width:Float, height:Float) {
		this.text = text;
		this.width = width;
		this.height = height;
		root = new Node("root");
		root.attach(this);
	}

	public function resize(width:Float, height:Float) {
		if (width == this.width && height == this.height) return;
		this.width = width;
		this.height = height;
		root.markDirty();
	}

	public function requestFrame()
		needsFrame = true;

	// lays the tree out if it changed
	public function update() {
		Layout.run(root, width, height, text);
		clampScroll(root);
	}

	// draws the tree (after update)
	public function paint(canvas:Canvas) {
		needsFrame = false;
		paintNode(root, canvas);
	}

	function paintNode(n:Node, canvas:Canvas) {
		var s = n.style;
		if (s.display == None || n.width <= 0 && n.height <= 0 && n.children.length == 0) return;
		if (s.opacity <= 0) return;
		if (s.opacity < 1) canvas.pushOpacity(s.opacity);
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
		if (s.opacity < 1) canvas.popOpacity();
	}

	// --- pointer ---

	public function pointerMove(x:Float, y:Float) {
		pointerX = x;
		pointerY = y;
		var target = root.hitTest(x, y);
		setHover(target);
		var to = capture != null ? capture : target;
		if (to != null) bubble(new Event(PointerMove, to, x, y));
	}

	public function pointerDown(x:Float, y:Float, button:Int) {
		pointerX = x;
		pointerY = y;
		var target = root.hitTest(x, y);
		setHover(target);
		if (target == null) {
			setFocus(null);
			return;
		}
		capture = target;
		setPressed(target, true);
		var e = new Event(PointerDown, target, x, y);
		e.button = button;
		bubble(e);
		if (!e.defaultPrevented) {
			var f = target;
			while (f != null && !f.focusable)
				f = f.parent;
			setFocus(f);
		}
	}

	public function pointerUp(x:Float, y:Float, button:Int) {
		pointerX = x;
		pointerY = y;
		var target = root.hitTest(x, y);
		var pressed = capture;
		capture = null;
		var to = pressed != null ? pressed : target;
		if (to == null) return;
		if (pressed != null) setPressed(pressed, false);
		var e = new Event(PointerUp, to, x, y);
		e.button = button;
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
		var target = root.hitTest(x, y);
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
				requestFrame();
				return;
			}
			n = n.parent;
		}
	}

	// --- keyboard ---

	public function keyDown(key:Int, mods:Int) {
		var e = new Event(KeyDown, focus != null ? focus : root, pointerX, pointerY);
		e.key = key;
		e.mods = mods;
		bubble(e);
		if (!e.defaultPrevented && key == Key.TAB) moveFocus(mods & Key.MOD_SHIFT != 0 ? -1 : 1);
	}

	public function keyUp(key:Int, mods:Int) {
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

	// --- focus ---

	public function setFocus(n:Null<Node>) {
		if (n == focus) return;
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
		collect(root);
		if (all.length == 0) return;
		var i = focus == null ? (dir > 0 ? -1 : 0) : all.indexOf(focus);
		setFocus(all[(i + dir + all.length) % all.length]);
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
			n.scrollX = Math.max(0, Math.min(n.scrollX, maxScroll(n, true)));
			n.scrollY = Math.max(0, Math.min(n.scrollY, maxScroll(n, false)));
		}
		for (c in n.children)
			clampScroll(c);
	}

	// a node left the tree: it no longer hovers, captures or has the focus
	@:allow(hxmc.ui.Node) function detached(n:Node) {
		if (hover != null && contains(n, hover)) hover = null;
		if (capture != null && contains(n, capture)) capture = null;
		if (focus != null && contains(n, focus)) focus = null;
	}
}
