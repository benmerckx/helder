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
	public var focusVisible(default, set) = false;
	// the window's theme (StyleSheet: its rules for the nodes with a slot,
	// its colours; a subtree's own wins, Node.theme), and whether the dark
	// colours and the rules for "dark" apply
	public var theme(default, set):Null<StyleSheet> = null;
	public var dark(default, set) = false;

	function set_focusVisible(v:Bool):Bool {
		if (v == focusVisible) return v;
		focusVisible = v;
		// (the focused node's rules for focus-visible)
		if (focus != null) @:privateAccess focus.restyleLater();
		return v;
	}

	// (the nodes whose rules apply again at the next update: Node.restyleLater)
	var restyles:Array<Node> = [];

	// applies the rules of the nodes waiting for it (update does, before layout)
	public function flushRestyles() {
		while (restyles.length > 0) {
			var list = restyles;
			restyles = [];
			for (n in list) {
				@:privateAccess n.restylePending = false;
				Rules.restyle(n);
			}
		}
	}

	function set_theme(v:Null<StyleSheet>):Null<StyleSheet> {
		if (v == theme) return v;
		theme = v;
		Rules.restyleTree(root);
		requestFrame();
		return v;
	}

	function set_dark(v:Bool):Bool {
		if (v == dark) return v;
		dark = v;
		Rules.restyleTree(root);
		requestFrame();
		return v;
	}
	// where widgets copy and paste text (UiWindow: the system's)
	// the window's pixels to the UI's (a Retina display's 2): what drawings are rasterized at
	public var scale = 1.0;
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

	// lays the tree out if it changed (a tree that did not: nothing done)
	public function update() {
		flushRestyles();
		Layout.run(root, width, height, text, rounded);
		if (root.inkStale) refreshInk(root);
		if (overlay.children.length > 0) {
			Layout.run(overlay, width, height, text, rounded);
			// (placed from their sizes: laid out again when one moved)
			if (placePopups()) Layout.run(overlay, width, height, text, rounded);
			if (overlay.inkStale) refreshInk(overlay);
		}
		// (the scrollers whose extents may have changed)
		for (n in rounded)
			clampScroll(n);
		rounded.resize(0);
	}

	// the ink bounds that a transform's change left stale, measured again
	static function refreshInk(n:Node) {
		if (!n.inkStale) return;
		for (c in n.children)
			refreshInk(c);
		n.measureInk();
	}

	// draws the tree (after update): subtrees whose ink misses what can be
	// seen (the window, the scrollers' padding boxes) left out
	public function paint(canvas:Canvas) {
		needsFrame = false;
		cullX0 = cullY0 = 0;
		cullX1 = width;
		cullY1 = height;
		paintNode(root, canvas);
		if (overlay.children.length > 0) paintNode(overlay, canvas);
	}

	// the farthest any shadow drawn reaches outside its box (Style.shadow)
	public static var shadowReach = 0.0;
	// (what can be seen, in the coordinates of the node being drawn)
	var cullX0 = 0.0;
	var cullY0 = 0.0;
	var cullX1 = 0.0;
	var cullY1 = 0.0;
	// (the node being drawn is hidden: Style.visibility, inherited)
	var hidden = false;

	function paintNode(n:Node, canvas:Canvas) {
		var s = n.style;
		if (s.display == None || n.width <= 0 && n.height <= 0 && n.children.length == 0) return;
		if (!@:privateAccess s.drawn) {
			@:privateAccess s.drawn = true;
			if (@:privateAccess s.starting) @:privateAccess n.restyleLater();
		}
		if (s.opacity <= 0) return;
		var m = n.transformMatrix();
		// (its ink, widened by what rings, shadows and glyphs' overhang add, out of sight: left out)
		if (m == null && !n.inkAll) {
			var e = focusRingOffset + focusRingWidth + shadowReach + 8;
			if (n.inkX1 + e <= cullX0 || n.inkX0 - e >= cullX1 || n.inkY1 + e <= cullY0 || n.inkY0 - e >= cullY1) return;
		}
		var c0 = cullX0, c1 = cullY0, c2 = cullX1, c3 = cullY1;
		if (m != null) {
			canvas.pushTransform(m[0], m[1], m[2], m[3], m[4], m[5]);
			// (under a transform: everything drawn)
			cullX0 = cullY0 = -1e9;
			cullX1 = cullY1 = 1e9;
		}
		if (s.opacity < 1) canvas.pushOpacity(s.opacity);
		var wasHidden = hidden;
		if (s.visibility != null) hidden = s.visibility == Hidden;
		// (each corner's radius and each side's border, when the style gives them)
		var cs = s.corners != null ? s.cornerRadii() : null, sides = s.borders != null ? s.borderEdges : null;
		var be = s.borderEdges, bordered = be.top + be.right + be.bottom + be.left > 0 && s.borderColor.a > 0;
		// (the padding box's corners: each less the wider side meeting there)
		var padR = Math.max(0, s.radius - s.borderWidth), padC:Null<Corners> = null;
		if (cs != null || sides != null) {
			var c = s.cornerRadii();
			padC = new Corners(Math.max(0, c.topLeft - Math.max(be.left, be.top)), Math.max(0, c.topRight - Math.max(be.top, be.right)),
				Math.max(0, c.bottomRight - Math.max(be.right, be.bottom)), Math.max(0, c.bottomLeft - Math.max(be.bottom, be.left)));
		}
		// (the shadows outside: the last one first, under the others; not
		// under the box, as CSS clips them, unless its background hides them)
		var shadows = s.shadow == null || hidden ? null : s.shadow.painted();
		var opaque = s.background.a == 255 && s.backgroundImage == null;
		if (shadows != null)
			for (sh in shadows) {
				if (sh.inset) continue;
				var o = sh.spread;
				canvas.shadow(n.absX + sh.x - o, n.absY + sh.y - o, n.width + 2 * o, n.height + 2 * o, s.radius > 0 ? Math.max(0, s.radius + o) : 0, sh.color,
					sh.blur, cs == null ? null : new Corners(cs.topLeft > 0 ? Math.max(0, cs.topLeft + o) : 0, cs.topRight > 0 ? Math.max(0, cs.topRight + o) : 0,
						cs.bottomRight > 0 ? Math.max(0, cs.bottomRight + o) : 0, cs.bottomLeft > 0 ? Math.max(0, cs.bottomLeft + o) : 0), opaque ? null : [sh.x, sh.y, o]);
			}
		if (hidden) {
			// (nothing of its own)
		} else if (s.backgroundImage != null && n.width > 0 && n.height > 0) {
			// (the colour, the gradient over it, then the border over both)
			if (s.background.a > 0) canvas.rect(n.absX, n.absY, n.width, n.height, s.radius, s.background, 0, 0, cs);
			canvas.image(n.backgroundImage(scale), n.absX, n.absY, n.width, n.height, 0, 0, 1, 1, s.radius, cs);
			if (bordered) canvas.rect(n.absX, n.absY, n.width, n.height, s.radius, Color.TRANSPARENT, s.borderWidth, s.borderColor, cs, sides);
		} else if (s.background.a > 0 || bordered)
			canvas.rect(n.absX, n.absY, n.width, n.height, s.radius, s.background, s.borderWidth, s.borderColor, cs, sides);
		// (the shadows inside: in the padding box, over the background)
		if (shadows != null)
			for (sh in shadows)
				if (sh.inset)
					canvas.insetShadow(n.absX + be.left, n.absY + be.top, n.width - be.horizontal, n.height - be.vertical, padR, sh.color, sh.blur, sh.x, sh.y,
						sh.spread, padC);
		var pad = s.padding;
		if (n.hasContent() && !hidden)
			n.paintContent(canvas, n.absX + be.left + pad.left, n.absY + be.top + pad.top, Math.max(0, n.width - be.left - be.right - pad.left - pad.right),
				Math.max(0, n.height - be.top - be.bottom - pad.top - pad.bottom));
		var clip = s.overflow != Visible;
		// (the padding box: its corners' radii less the wider side meeting there)
		if (clip) {
			canvas.pushClip(n.absX + be.left, n.absY + be.top, n.width - be.horizontal, n.height - be.vertical, padR, padC);
			cullX0 = Math.max(cullX0, n.absX + be.left);
			cullY0 = Math.max(cullY0, n.absY + be.top);
			cullX1 = Math.min(cullX1, n.absX + n.width - be.right);
			cullY1 = Math.min(cullY1, n.absY + n.height - be.bottom);
		}
		var scroll = s.overflow == Scroll && (n.scrollX != 0 || n.scrollY != 0);
		if (scroll) {
			canvas.translate(-n.scrollX, -n.scrollY);
			cullX0 += n.scrollX;
			cullX1 += n.scrollX;
			cullY0 += n.scrollY;
			cullY1 += n.scrollY;
		}
		// (absolute and sticky children over the others, in their order, as CSS paints positioned boxes)
		var order = n.paintOrder();
		if (order != null) for (c in order) paintNode(c, canvas) else {
			var positioned = false;
			for (c in n.children)
				if (c.style.position != Relative) positioned = true else paintNode(c, canvas);
			if (positioned)
				for (c in n.children)
					if (c.style.position != Relative) paintNode(c, canvas);
		}
		if (scroll) canvas.translate(n.scrollX, n.scrollY);
		if (clip) canvas.popClip();
		cullX0 = c0;
		cullY0 = c1;
		cullX1 = c2;
		cullY1 = c3;
		if (s.overflow == Scroll && !hidden) {
			for (x in [false, true]) {
				var t = thumb(n, x);
				if (t != null) canvas.rect(t[0], t[1], t[2], t[3], SCROLLBAR / 2, drag == n && dragX == x ? scrollbarActiveColor : scrollbarColor, 0, 0);
			}
		}
		// (its outline over its content, the focus ring over that)
		if (s.outlineWidth > 0 && !hidden) {
			var o = s.outlineOffset + s.outlineWidth;
			canvas.rect(n.absX - o, n.absY - o, n.width + 2 * o, n.height + 2 * o, s.radius > 0 ? Math.max(0, s.radius + o) : 0, Color.TRANSPARENT,
				s.outlineWidth, s.outlineColor ?? n.textColor(), cs == null ? null : new Corners(cs.topLeft > 0 ? Math.max(0, cs.topLeft + o) : 0,
					cs.topRight > 0 ? Math.max(0, cs.topRight + o) : 0, cs.bottomRight > 0 ? Math.max(0, cs.bottomRight + o) : 0,
					cs.bottomLeft > 0 ? Math.max(0, cs.bottomLeft + o) : 0));
		}
		if (n == focus && focusVisible && focusRingWidth > 0 && !hidden) {
			var o = focusRingOffset + focusRingWidth;
			canvas.rect(n.absX - o, n.absY - o, n.width + 2 * o, n.height + 2 * o, s.radius > 0 ? s.radius + o : 0, Color.TRANSPARENT, focusRingWidth,
				focusRingColor, cs == null ? null : new Corners(cs.topLeft > 0 ? cs.topLeft + o : 0, cs.topRight > 0 ? cs.topRight + o : 0,
					cs.bottomRight > 0 ? cs.bottomRight + o : 0, cs.bottomLeft > 0 ? cs.bottomLeft + o : 0));
		}
		hidden = wasHidden;
		if (s.opacity < 1) canvas.popOpacity();
		if (m != null) canvas.popTransform();
	}

	// --- pointer ---

	public function pointerMove(x:Float, y:Float) {
		pointerX = x;
		pointerY = y;
		if (selecting && textSelection != null) {
			var c = textSelection.node.textIndexAt(x, y);
			if (c != textSelection.caret) {
				textSelection.caret = c;
				requestFrame();
			}
		}
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
		// (a press focuses without the ring: hidden before the focus moves)
		if (focusVisible) {
			focusVisible = false;
			requestFrame();
		}
		selectAt(target, x, y, button);
		setHover(target);
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
		selecting = false;
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
			c.mods = mods;
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
				scrolls.remove(n);
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

	// the text selected in a selectable TextNode (null: none), anchor to
	// caret (UTF-16 indices of its whole text); a press elsewhere drops it
	public var textSelection(default, null):Null<{node:TextNode, anchor:Int, caret:Int}> = null;
	// what a selection is painted with
	public var selectionColor:Color = Color.rgba(0x3b82f6, 0.3);
	// (a drag selecting; the clicks in a row and the last one's time and place)
	var selecting = false;
	var selClicks = 0;
	var selAt = -1e9;
	var selX = 0.0;
	var selY = 0.0;
	// the time (seconds; tests replace it)
	public static var now:Void->Float = haxe.Timer.stamp;

	// the selected text (empty: none)
	public function selectedText():String {
		var s = textSelection;
		if (s == null || s.anchor == s.caret) return "";
		return s.node.allText().substring(Std.int(Math.min(s.anchor, s.caret)), Std.int(Math.max(s.anchor, s.caret)));
	}

	// a press on a selectable text (or a span of one): the selection starts,
	// a word on a double click, all of it on a triple; elsewhere it is dropped
	function selectAt(target:Null<Node>, x:Float, y:Float, button:Int) {
		var t:Null<TextNode> = null, n = target;
		while (n != null) {
			if (Std.isOfType(n, TextNode) && (cast n : TextNode).selectable) t = cast n;
			n = n.parent;
		}
		if (t == null || button != 1) {
			if (textSelection != null) {
				textSelection = null;
				requestFrame();
			}
			return;
		}
		var i = t.textIndexAt(x, y), time = now();
		selClicks = time - selAt < 0.45 && Math.abs(x - selX) < 5 && Math.abs(y - selY) < 5 ? selClicks + 1 : 1;
		selAt = time;
		selX = x;
		selY = y;
		var text = t.allText();
		if (selClicks == 2) {
			// (a word: letters, digits and marks around the index; else the one character)
			inline function word(c:Int):Bool
				return c == "_".code || (c >= "0".code && c <= "9".code) || (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c > 0x7F
					&& c != 0xA0 && c != 0x3000;
			var a = i, b = i;
			while (a > 0 && word(StringTools.fastCodeAt(text, a - 1)))
				a--;
			while (b < text.length && word(StringTools.fastCodeAt(text, b)))
				b++;
			if (a == b && b < text.length) b++;
			textSelection = {node: t, anchor: a, caret: b};
		} else if (selClicks >= 3) textSelection = {node: t, anchor: 0, caret: text.length};
		else textSelection = {node: t, anchor: i, caret: i};
		selecting = selClicks == 1;
		requestFrame();
	}

	// the shortcuts, the latest first to match
	final shortcuts:Array<{keys:Shortcut, action:Void->Void, scope:Null<Node>}> = [];

	// runs action when keys (Shortcut.parse: "Mod+S") are pressed and the focused node's handlers
	// neither stopped the key nor prevented its default: anywhere, or while
	// the focus is inside scope (in this Ui). Under a modal popup only a
	// scope inside it counts; keys without Control, Alt or Command that
	// type (a character) not while the focus takes text. The latest added
	// wins. Returns what removes it.
	public function shortcut(keys:String, action:Void->Void, ?scope:Node):Void->Void {
		var s = {keys: Shortcut.parse(keys), action: action, scope: scope};
		shortcuts.push(s);
		return () -> shortcuts.remove(s);
	}

	// the shortcut a key press is (run): true when one was
	function runShortcut(key:Int, mods:Int):Bool {
		var typing = focus != null && focus.takesText();
		if (typing && mods & (Key.MOD_CONTROL | Key.MOD_ALT | Key.MOD_META) == 0 && key < 0xFF00) return false;
		var top = modal();
		var i = shortcuts.length;
		while (--i >= 0) {
			var s = shortcuts[i];
			if (!s.keys.matches(key, mods)) continue;
			if (s.scope != null && (s.scope.ui != this || focus == null || !contains(s.scope, focus))) continue;
			if (top != null && (s.scope == null || !contains(top, s.scope))) continue;
			s.action();
			return true;
		}
		return false;
	}

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
					return;
				}
			}
		}
		if (!e.defaultPrevented && !e.stopped && runShortcut(key, mods)) return;
		if (!e.defaultPrevented && !e.stopped && keyScroll(key, mods)) return;
		// (Control or Command and C: the selected text copied, when the focus took no such key)
		if (!e.defaultPrevented && !e.stopped && (key == "c".code || key == "C".code) && mods & (Key.MOD_CONTROL | Key.MOD_META) != 0 && selectedText() != "") {
			clipboard.write(selectedText());
			return;
		}
		if (!e.defaultPrevented && key == Key.TAB) {
			// (shown before the focus moves: its handlers see it)
			focusVisible = true;
			moveFocus(mods & Key.MOD_SHIFT != 0 ? -1 : 1);
			focusVisible = focus != null;
			requestFrame();
		}
	}

	// how long a scroll by the keys eases (seconds; 0: at once)
	public var scrollDuration = 0.15;
	// (the scrolls easing: from x, y to x, y, since)
	final scrolls = new Map<Node, Array<Float>>();
	// the scrollers rounded by the last layouts, clamped after them
	final rounded:Array<Node> = [];

	// keys that scroll, when the focus took none of them (as a browser's):
	// the arrows by 40 pixels, Page Up and Down and Space (Shift: up) by
	// seven eighths of the view, Home and End to the ends; the nearest
	// scroller that can move that way around the focus, else the pointer
	static inline var ARROW_STEP = 40;

	function keyScroll(key:Int, mods:Int):Bool {
		if (mods & (Key.MOD_CONTROL | Key.MOD_META | Key.MOD_ALT) != 0) return false;
		if (focus != null && focus.takesText()) return false;
		var x = key == Key.LEFT || key == Key.RIGHT;
		var back = key == Key.UP || key == Key.LEFT || key == Key.PAGE_UP || key == Key.HOME || key == Key.SPACE && mods & Key.MOD_SHIFT != 0;
		var page = key == Key.PAGE_UP || key == Key.PAGE_DOWN || key == Key.SPACE, edge = key == Key.HOME || key == Key.END;
		if (!(x || page || edge || key == Key.UP || key == Key.DOWN)) return false;
		var n = focus != null ? focus : hover;
		while (n != null) {
			if (n.style.overflow == Scroll) {
				var s = n.style, view = (x ? n.width : n.height) - (x ? s.borderEdges.horizontal + s.padding.horizontal : s.borderEdges.vertical + s.padding.vertical);
				var d = edge ? maxScroll(n, x) + 1 : page ? Math.max(1, view * 0.875) : ARROW_STEP;
				if (back) d = -d;
				if (canScroll(n, d, x)) {
					scrollBy(n, x ? d : 0, x ? 0 : d);
					return true;
				}
			}
			n = n.parent;
		}
		return false;
	}

	// scrolls by dx, dy eased over scrollDuration (a scroll easing already: from where it is, to its end moved on)
	public function scrollBy(n:Node, dx:Float, dy:Float) {
		var a = scrolls.get(n);
		var tx = (a != null ? a[2] : n.scrollX) + dx, ty = (a != null ? a[3] : n.scrollY) + dy;
		tx = clampTo(n, true, tx);
		ty = clampTo(n, false, ty);
		if (scrollDuration <= 0) {
			scrollTo(n, tx, ty);
			return;
		}
		scrolls.set(n, [n.scrollX, n.scrollY, tx, ty, Clock.now]);
		requestFrame();
		if (a != null) return;
		Clock.add(t -> {
			var a = scrolls.get(n);
			if (a == null) return false;
			var k = Math.min(1, Math.max(0, (t - a[4]) / scrollDuration));
			// (ease in and out)
			var e = k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
			setScroll(n, true, a[0] + (a[2] - a[0]) * e);
			setScroll(n, false, a[1] + (a[3] - a[1]) * e);
			if (k < 1) return true;
			scrolls.remove(n);
			return false;
		});
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
		accessEpoch++;
		if (scroll && n != null) scrollIntoView(n);
		var old = focus;
		focus = n;
		if (old != null) {
			@:privateAccess old.setState(old.hovered, old.pressed, false);
			if (old.onBlur != null) old.onBlur(new Event(Blur, old, pointerX, pointerY));
			bubble(new Event(FocusOut, old, pointerX, pointerY));
		}
		if (n != null) {
			@:privateAccess n.setState(n.hovered, n.pressed, true);
			if (n.onFocus != null) n.onFocus(new Event(Focus, n, pointerX, pointerY));
			bubble(new Event(FocusIn, n, pointerX, pointerY));
		}
	}

	// the next (1) or previous (-1) focusable node in tree order, wrapping
	public function moveFocus(dir:Int) {
		var all:Array<Node> = [];
		function collect(n:Node) {
			if (n.style.display == None) return;
			if (n.focusable && n.visible()) all.push(n);
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
		if (n.focusable && n.visible()) return n;
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
			} else if (p.placement == TopLeft || p.placement == TopRight || p.placement == BottomLeft || p.placement == BottomRight) {
				x = p.placement == TopLeft || p.placement == BottomLeft ? p.gap : width - w - p.gap;
				y = p.placement == TopLeft || p.placement == TopRight ? p.gap : height - h - p.gap;
			} else if (p.placement == Center || p.anchor == null || p.anchor.ui != this) {
				if (p.placement != Center && p.anchor != null) continue;
				x = (width - w) / 2;
				y = (height - h) / 2;
			} else {
				// the anchor where it is drawn: its ancestors' scrolling taken off, through transforms
				var a = p.anchor.windowBounds(), ax = a.x, ay = a.y;
				var g = p.gap;
				switch p.placement {
					case Below | Above:
						// (right to left: their right edges lined up)
						x = p.anchor.rtl() ? ax + a.width - w : ax;
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
				case FocusIn: n.onFocusIn;
				case FocusOut: n.onFocusOut;
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
		var lo = scrollStart(n, x), v = x ? n.scrollX : n.scrollY;
		return d > 0 ? v < lo + maxScroll(n, x) : v > lo;
	}

	// how far n scrolls on the axis (from scrollStart)
	static function maxScroll(n:Node, x:Bool):Float {
		var s = n.style, inset = x ? s.borderEdges.horizontal + s.padding.horizontal : s.borderEdges.vertical + s.padding.vertical;
		var view = (x ? n.width : n.height) - inset;
		return Math.max(0, (x ? n.contentWidth : n.contentHeight) - view);
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
	function clampScroll(n:Node) {
		var x = clampTo(n, true, n.scrollX), y = clampTo(n, false, n.scrollY);
		if (x != n.scrollX || y != n.scrollY) {
			n.scrollX = x;
			n.scrollY = y;
			if (n.onScroll != null) n.onScroll();
		}
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
	// (built again only when something it reads changed: accessEpoch)
	public function accessTree():hxmc.ui.access.AccessTree {
		if (lastAccess != null && accessBuilt == accessEpoch) return lastAccess;
		accessBuilt = accessEpoch;
		return lastAccess = hxmc.ui.access.AccessTree.build(this);
	}

	// bumped by every change an accessibility tree reads (layout, scrolling,
	// the focus, semantics, focusability, transforms, opacity to 0 and back)
	public static var accessEpoch = 0;
	var accessBuilt = -1;

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
				focusVisible = true;
				setFocus(n);
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
					var s = p.style, inset = x ? s.borderEdges.left + s.padding.left : s.borderEdges.top + s.padding.top;
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
		return (x ? n.width : n.height) - (x ? s.borderEdges.horizontal + s.padding.horizontal : s.borderEdges.vertical + s.padding.vertical);
	}

	// a scrollbar's track on axis x (horizontal) or y: its start and length
	// along the axis (absolute), its offset across it; right to left, the
	// vertical one on the left, as Chromium has it
	static function track(n:Node, x:Bool):Array<Float> {
		var be = n.style.borderEdges, i = SCROLLBAR_INSET, rtl = n.rtl();
		// (the other axis's bar, if any, takes the corner)
		var corner = maxScroll(n, !x) > 0 ? SCROLLBAR + i : 0;
		return x ? [n.absX + be.left + i + (rtl ? corner : 0), n.width - be.horizontal - 2 * i - corner, n.absY + n.height - be.bottom - i - SCROLLBAR] : [
			n.absY + be.top + i, n.height - be.vertical - 2 * i - corner, rtl ? n.absX + be.left + i : n.absX + n.width - be.right - i - SCROLLBAR];
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
		var at = t[0] + (t[1] - len) * ((x ? n.scrollX : n.scrollY) - scrollStart(n, x)) / max;
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

	// scrolls n (an overflow: scroll node) to x, y (clamped to what it can scroll)
	public function scrollTo(n:Node, x:Float, y:Float) {
		scrolls.remove(n);
		setScroll(n, true, x);
		setScroll(n, false, y);
	}

	function setScroll(n:Node, x:Bool, v:Float) {
		v = clampTo(n, x, v);
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
