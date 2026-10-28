package helder.ui;

import helder.os.PointerType;
import helder.ui.Event;
import helder.ui.gesture.Gesture;
import helder.ui.gesture.Tap;
import helder.ui.gesture.TouchScroll;

// The host of a UI tree: its viewport, its TextEngine, layout (update),
// drawing (paint) and input. A window's loop (helder.ui.draw.Window, or a
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
//
// Fingers and pens (helder.os's pointers but the mouse: their slots as
// ids, 1 to POINTERS - 1) are pointers of their own, each captured by the
// node it went down on (Node.capture moves it, releaseCapture lets it go;
// a node leaving the tree gets PointerCancel), with pointerId,
// pointerType, pressure and isPrimary on their events. Each pointer has
// an arena (helder.ui.gesture.Gesture): the recognisers on the nodes it
// went down in compete for it, the innermost first, and for the first
// finger a drag that scrolls what is under where it started (TouchScroll,
// as helder.os.TouchDrag did: Wheel events, a glide), last; a recogniser
// that wins it other than a Tap takes the click, and the scroll cancels
// the press (PointerCancel). A press released within the slop on the node
// it went down on clicks. The mouse's presses feed the arena too, its
// clicks as before.
class Ui {
	public final root:Node;
	// the layers above the tree (Popup nodes, the last on top)
	public final overlay:Node;
	// the page's body: the node of slot "body", whose text properties the layers inherit (as a page's popups its body's)
	public var body(default, null):Null<Node> = null;
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
		if (focus != null) {
			@:privateAccess focus.restyleLater();
			focus.statesChanged();
		}
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
	// the safe area: the insets from each edge, in UI pixels, that a phone's
	// bars, notch or cutout leave clear (UiWindow: the window's, each frame;
	// 0 elsewhere). Markup's env(safe-area-inset-*) reads the main window's
	// (SafeArea); a layout of its own reads this
	public var safeArea:Edges = Edges.ZERO;
	// the platform's own views where a window has them (PlatformViews), and
	// which kinds of widget are native where the tree leaves it Auto (Host):
	// "text-field" and "text-area" (the plan's defaults: native everywhere)
	public var platform:Null<PlatformViews> = null;
	public var policy:Map<String, Host> = ["text-field" => Native, "text-area" => Native, "context-menu" => Native, "menubar" => Native];
	public var clipboard:ClipboardHost = new ClipboardHost.MemoryClipboard();
	public var focusRingColor:Color = 0xFF3B82F6;
	public var focusRingWidth = 2.0;
	// the ring's gap outside the node
	public var focusRingOffset = 2.0;
	public var scrollbarColor:Color = 0x59000000;
	public var scrollbarActiveColor:Color = 0x8C000000;

	// --- the pointers other than the mouse (fingers, pens: helder.os's slots)
	public static inline var POINTERS = 16;

	// per pointer: down; its events' target (the node it went down on, or
	// the one that captured it; null: what is under it); its type; where
	// it went down and is; whether its press is still the nodes' (not
	// cancelled: a scroll took it) and its release may click; the first one
	final pDown:Array<Bool> = [for (_ in 0...POINTERS) false];
	final pTarget:Array<Null<Node>> = [for (_ in 0...POINTERS) null];
	final pType:Array<PointerType> = [for (_ in 0...POINTERS) Touch];
	final pStartX:Array<Float> = [for (_ in 0...POINTERS) 0.0];
	final pStartY:Array<Float> = [for (_ in 0...POINTERS) 0.0];
	final pLive:Array<Bool> = [for (_ in 0...POINTERS) false];
	final pClick:Array<Bool> = [for (_ in 0...POINTERS) false];
	final pPrimary:Array<Bool> = [for (_ in 0...POINTERS) false];
	// the arenas (the mouse's 0): the recognisers competing for each
	// pointer, the innermost first; the one that won it
	final arenas:Array<Array<Gesture>> = [for (_ in 0...POINTERS) []];
	final winners:Array<Null<Gesture>> = [for (_ in 0...POINTERS) null];
	final scratch:Array<Array<Gesture>> = [for (_ in 0...POINTERS) []];
	// the first finger's drag (a scroller's)
	final touchScroll:TouchScroll;
	// the pointer whose event is being dispatched (Node.capture's)
	var dispatching = -1;

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
		touchScroll = @:privateAccess new TouchScroll(this);
		#if hxmc.dev
		DevTree.add(this);
		#end
	}

	public function resize(width:Float, height:Float) {
		if (width == this.width && height == this.height) return;
		var was = breakpoint(this.width);
		this.width = width;
		this.height = height;
		root.markDirty();
		overlay.markDirty();
		// (across a breakpoint: the rules for sm, md... hold or not)
		if (breakpoint(width) != was) {
			Rules.restyleTree(root);
			Rules.restyleTree(overlay);
		}
	}

	// Tailwind's breakpoints (sm, md, lg, xl, 2xl: the window at least so wide, in pixels)
	public static final BREAKPOINTS = ["sm" => 640.0, "md" => 768.0, "lg" => 1024.0, "xl" => 1280.0, "2xl" => 1536.0];

	// (their widths: iterated without the map's iterator)
	static final WIDTHS = [for (b in BREAKPOINTS) b];

	// (how many of them a width reaches)
	static function breakpoint(w:Float):Int {
		var k = 0;
		for (b in WIDTHS)
			if (w >= b) k++;
		return k;
	}

	public function requestFrame()
		needsFrame = true;

	// lays the tree out if it changed (a tree that did not: nothing done);
	// the platform's views' events first, their nodes kept in step after
	public function update() {
		if (platform != null) platform.poll();
		// (a touch's scroll let go moving: its glide's since the last)
		if (touchScroll.gliding) @:privateAccess touchScroll.glide(now() * 1000);
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
		changes.resize(0);
		for (n in natives.copy())
			n.syncNative();
	}

	// the nodes that may be native (EditableText: they join while in the tree)
	var natives:Array<Node> = [];

	// what draws n, a widget of that kind (Ui.policy's names): its own host,
	// else its nearest ancestor's not Auto, else the policy's; Native only
	// where the window has the platform's views
	public function hostOf(n:Node, kind:String):Host {
		var h:Host = Auto, p = n;
		while (p != null && h == Auto) {
			h = p.host;
			p = p.parent;
		}
		if (h == Auto) h = policy.exists(kind) ? policy[kind] : Drawn;
		return h == Native && platform != null ? Native : Drawn;
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
		// (a glide's next step: another frame)
		needsFrame = touchScroll.gliding;
		paintFrame++;
		cullX0 = cullY0 = 0;
		cullX1 = width;
		cullY1 = height;
		paintNode(root, canvas);
		if (overlay.children.length > 0) paintNode(overlay, canvas);
	}

	// (the paints so far: a node drawn in the last one has its number, Node.drawnAt)
	var paintFrame = 0;

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
		if (!n.inkAll) {
			var e = focusRingOffset + focusRingWidth + shadowReach + 8;
			if (n.inkX1 + e <= cullX0 || n.inkX0 - e >= cullX1 || n.inkY1 + e <= cullY0 || n.inkY0 - e >= cullY1) return;
		}
		@:privateAccess n.drawnAt = paintFrame;
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
		var shadows = hidden ? null : s.paintedShadows();
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
		} else if (s.background.a > 0 && s.borderColor.a < 255 && be.top + be.right + be.bottom + be.left > 0) {
			// (the background under the border too, as CSS's background-clip: border-box, seen through a translucent one)
			canvas.rect(n.absX, n.absY, n.width, n.height, s.radius, s.background, 0, 0, cs);
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
				if (t == null) continue;
				var b = barSize(n), track = inheritedBar(n, true), own = inheritedBar(n, false);
				if (track != null && track.a > 0) {
					var tr = Ui.track(n, x);
					if (x) canvas.rect(tr[0], tr[2], tr[1], b, b / 2, track, 0, 0) else canvas.rect(tr[2], tr[0], b, tr[1], b / 2, track, 0, 0);
				}
				canvas.rect(t[0], t[1], t[2], t[3], b / 2, own != null ? own : drag == n && dragX == x ? scrollbarActiveColor : scrollbarColor, 0, 0);
			}
		}
		// (its outline over its content, the focus ring over that)
		if (s.outlineWidth > 0 && !hidden && s.outlineStyle != None) {
			var o = s.outlineOffset + s.outlineWidth;
			canvas.rect(n.absX - o, n.absY - o, n.width + 2 * o, n.height + 2 * o, s.radius > 0 ? Math.max(0, s.radius + o) : 0, Color.TRANSPARENT,
				s.outlineWidth, s.outlineColor ?? n.textColor(), cs == null ? null : new Corners(cs.topLeft > 0 ? Math.max(0, cs.topLeft + o) : 0,
					cs.topRight > 0 ? Math.max(0, cs.topRight + o) : 0, cs.bottomRight > 0 ? Math.max(0, cs.bottomRight + o) : 0,
					cs.bottomLeft > 0 ? Math.max(0, cs.bottomLeft + o) : 0));
		}
		if (n == focus && focusVisible && focusRingWidth > 0 && !hidden && (s.outlineStyle == null || s.outlineStyle == Auto)) {
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

	// the mouse moved (id 0), or a finger or a pen (id: its slot) to x, y
	public function pointerMove(x:Float, y:Float, id = 0, pressure = 1.0) {
		if (id != 0) return touchMove(id, x, y, pressure);
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
			var e = Event.of(DragStart, s, x, y);
			e.data = s.dragData;
			bubble(e);
			if (!e.defaultPrevented) {
				setPressed(capture, false);
				capture = null;
				closeArena(0, true);
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
		if (to != null) dispatch(Event.of(PointerMove, to, x, y), 0);
		if (capture != null) moveArena(0, x, y);
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
				var e = Event.of(DragOver, target, x, y);
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
		var e = Event.of(DragLeave, t, x, y);
		e.data = dragging.data;
		t.onDragLeave(e.at(t));
	}

	// the drag ended: dropped on its target (Drop) or not, the source told (DragEnd)
	function endDrag(drop:Bool, x:Float, y:Float) {
		var d = dragging, t = dropTarget;
		dragging = null;
		dropTarget = null;
		if (t != null && !drop && t.onDragLeave != null) {
			var e = Event.of(DragLeave, t, x, y);
			e.data = d.data;
			t.onDragLeave(e.at(t));
		}
		var dropped = drop && t != null;
		if (dropped && t.onDrop != null) {
			var e = Event.of(Drop, t, x, y);
			e.data = d.data;
			t.onDrop(e.at(t));
		}
		var e = Event.of(DragEnd, d.source, x, y);
		e.data = d.data;
		e.dropped = dropped;
		bubble(e);
		requestFrame();
	}

	// a press of the mouse (id 0: button 1 left, 2 middle, 3 right), or a
	// finger or a pen down (id: its slot; button 1): whether a node took it,
	// one that is the ui's own (Node.ownsPointer: not the root, the body, nor
	// a box drawing a world under the ui), so that the game's controls leave
	// it alone (helder.os's Pointer.owner, UiWindow's)
	public function pointerDown(x:Float, y:Float, button:Int, id = 0, type:PointerType = Mouse, pressure = 1.0):Bool {
		if (id != 0) return touchDown(id, type, x, y, pressure);
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
			return false;
		}
		if (scrollbarDown(target, x, y)) return true;
		capture = target;
		dragSource = target;
		while (dragSource != null && dragSource.dragData == null)
			dragSource = dragSource.parent;
		dragFromX = x;
		dragFromY = y;
		setPressed(target, true);
		var e = Event.of(PointerDown, target, x, y);
		e.button = button;
		e.mods = mods;
		e.pressure = 0.5;
		dispatch(e, 0);
		if (!e.defaultPrevented) {
			var f = target;
			while (f != null && !f.focusable)
				f = f.parent;
			setFocus(f, false);
		}
		if (capture != null) openArena(0, target, Mouse, button, x, y, false);
		return owns(target);
	}

	// the mouse's button released (id 0), or a finger or a pen lifted
	public function pointerUp(x:Float, y:Float, button:Int, id = 0) {
		if (id != 0) return touchUp(id, x, y);
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
		var e = Event.of(PointerUp, to, x, y);
		e.button = button;
		e.mods = mods;
		dispatch(e, 0);
		if (arenas[0].length > 0) {
			moveArena(0, x, y);
			closeArena(0, false);
		}
		if (pressed != null) lose(pressed, 0, x, y);
		// a click: released over the node it went down on (or inside it)
		if (pressed != null && target != null && contains(pressed, target)) {
			var c = Event.of(Click, pressed, x, y);
			c.button = button;
			c.mods = mods;
			bubble(c);
		}
		setHover(target);
	}

	// a finger or a pen cancelled (the system took it: no click; id 0: the
	// mouse's press let go of the same way)
	public function pointerCancel(id:Int) {
		if (id == 0) {
			var pressed = capture;
			capture = null;
			closeArena(0, true);
			if (pressed == null) return;
			setPressed(pressed, false);
			dispatch(Event.of(PointerCancel, pressed, pointerX, pointerY), 0);
			lose(pressed, 0, pointerX, pointerY);
			return;
		}
		if (id < 0 || id >= POINTERS || !pDown[id]) return;
		pDown[id] = false;
		cancelPress(id);
		closeArena(id, true);
	}

	// the node pointer id's events go to now (the mouse's: capture; null: what is under it)
	public function captureOf(id:Int):Null<Node>
		return id == 0 ? capture : id > 0 && id < POINTERS && pDown[id] ? pTarget[id] : null;

	function touchDown(id:Int, type:PointerType, x:Float, y:Float, pressure:Float):Bool {
		if (id < 0 || id >= POINTERS) return false;
		if (pDown[id]) pointerCancel(id);
		var primary = true;
		for (i in 1...POINTERS)
			if (pDown[i]) primary = false;
		// (a new touch stops a glide)
		@:privateAccess touchScroll.stop();
		var target = hit(x, y);
		dismissOutside(target);
		if (focusVisible) {
			focusVisible = false;
			requestFrame();
		}
		// (a press elsewhere drops a selection; a finger's drag scrolls, it selects nothing)
		if (primary) {
			selectAt(target, x, y, 1);
			selecting = false;
		}
		if (target == null) {
			if (primary) setFocus(null);
			return false;
		}
		pDown[id] = pLive[id] = pClick[id] = true;
		pPrimary[id] = primary;
		pTarget[id] = target;
		pType[id] = type;
		pStartX[id] = x;
		pStartY[id] = y;
		setPressed(target, true);
		var e = touchEvent(PointerDown, target, id, x, y, pressure);
		e.button = 1;
		dispatch(e, id);
		if (!e.defaultPrevented && primary) {
			var f = target;
			while (f != null && !f.focusable)
				f = f.parent;
			setFocus(f, false);
		}
		if (pDown[id]) openArena(id, target, type, 1, x, y, primary && type != Mouse);
		return owns(target);
	}

	function touchMove(id:Int, x:Float, y:Float, pressure:Float) {
		if (id < 0 || id >= POINTERS || !pDown[id]) return;
		if (pLive[id]) {
			var to = pTarget[id] ?? hit(x, y);
			if (to != null) dispatch(touchEvent(PointerMove, to, id, x, y, pressure), id);
		}
		moveArena(id, x, y);
	}

	function touchUp(id:Int, x:Float, y:Float) {
		if (id < 0 || id >= POINTERS || !pDown[id]) return;
		pDown[id] = false;
		var target = hit(x, y), pressed = pTarget[id], live = pLive[id];
		pLive[id] = false;
		pTarget[id] = null;
		if (live) {
			if (pressed != null) setPressed(pressed, false);
			var to = pressed ?? target;
			if (to != null) {
				var e = touchEvent(PointerUp, to, id, x, y, 0);
				e.button = 1;
				dispatch(e, id);
			}
		}
		moveArena(id, x, y);
		var won = winners[id];
		closeArena(id, false);
		if (!live) return;
		if (pressed != null) lose(pressed, id, x, y);
		// a click: a tap (released within the slop, no other gesture won it) on the node it went down on
		var dx = x - pStartX[id], dy = y - pStartY[id];
		if (pClick[id] && pressed != null && target != null && contains(pressed, target) && (won == null || Std.isOfType(won, Tap))
			&& Math.sqrt(dx * dx + dy * dy) <= Gesture.SLOP) {
			var c = touchEvent(Click, pressed, id, x, y, 0);
			c.button = 1;
			dispatch(c, id);
		}
	}

	// a touch's press taken from its node: PointerCancel, the capture lost
	function cancelPress(id:Int) {
		var pressed = pTarget[id], live = pLive[id];
		pLive[id] = pClick[id] = false;
		pTarget[id] = null;
		if (!live || pressed == null) return;
		setPressed(pressed, false);
		dispatch(touchEvent(PointerCancel, pressed, id, pStartX[id], pStartY[id], 0), id);
		lose(pressed, id, pStartX[id], pStartY[id]);
	}

	function touchEvent(type:EventType, target:Node, id:Int, x:Float, y:Float, pressure:Float):Event {
		var e = Event.of(type, target, x, y);
		e.pointerId = id;
		e.pointerType = pType[id];
		e.pressure = pressure;
		e.isPrimary = pPrimary[id];
		e.mods = mods;
		return e;
	}

	// e bubbled, as pointer id's (Node.capture's)
	function dispatch(e:Event, id:Int) {
		var was = dispatching;
		dispatching = id;
		bubble(e);
		dispatching = was;
	}

	// (n no longer has pointer id: LostPointerCapture)
	function lose(n:Node, id:Int, x:Float, y:Float) {
		if (n.onLostPointerCapture == null) return;
		var e = id == 0 ? Event.of(LostPointerCapture, n, x, y) : touchEvent(LostPointerCapture, n, id, x, y, 0);
		n.onLostPointerCapture(e.at(n));
	}

	// (Node.capture: the pointer being dispatched, n's from now on)
	function captureBy(n:Node) {
		var id = dispatching;
		if (id <= 0) {
			// (the mouse: while pressed)
			if (capture != null) capture = n;
			return;
		}
		if (id >= POINTERS || !pDown[id] || !pLive[id]) return;
		var old = pTarget[id];
		pTarget[id] = n;
		if (old != null && old != n) lose(old, id, pStartX[id], pStartY[id]);
	}

	// (Node.releaseCapture: its pointers go to what is under them)
	function releaseBy(n:Node) {
		if (capture == n) capture = null;
		for (id in 1...POINTERS)
			if (pDown[id] && pTarget[id] == n) {
				pTarget[id] = null;
				lose(n, id, pStartX[id], pStartY[id]);
			}
	}

	// whether target is the ui's own (pointerDown's answer)
	function owns(target:Null<Node>):Bool
		return target != null && target != root && target != body && target != overlay && target.ownsPointer();

	// --- the arenas (helder.ui.gesture.Gesture)

	// pointer id's arena opened at its press on target: the recognisers from
	// it up (innermost first), then the first finger's scroll
	function openArena(id:Int, target:Node, type:PointerType, button:Int, x:Float, y:Float, scroll:Bool) {
		var a = arenas[id];
		if (a.length > 0) closeArena(id, true);
		winners[id] = null;
		var n = target;
		while (n != null) {
			var gs = n.gestures;
			if (gs != null)
				for (g in gs)
					if (@:privateAccess g.join(id, type, button)) a.push(g);
			n = n.parent;
		}
		if (scroll && @:privateAccess touchScroll.join(id, type, button)) a.push(touchScroll);
		if (a.length == 0) return;
		var t = now(), list = snapshot(id);
		for (g in list)
			if (a.indexOf(g) >= 0) @:privateAccess g.down(id, x, y, t);
	}

	function moveArena(id:Int, x:Float, y:Float) {
		var a = arenas[id];
		if (a.length == 0) return;
		var t = now(), list = snapshot(id);
		for (g in list)
			if (a.indexOf(g) >= 0) @:privateAccess g.move(id, x, y, t);
	}

	// its pointer lifted (or cancelled): each recogniser told, the arena emptied
	function closeArena(id:Int, cancelled:Bool) {
		var a = arenas[id];
		if (a.length == 0) {
			winners[id] = null;
			return;
		}
		var t = now(), list = snapshot(id);
		for (g in list)
			if (a.indexOf(g) >= 0) @:privateAccess g.up(id, t, cancelled);
		a.resize(0);
		winners[id] = null;
	}

	// (an arena's recognisers as they are: callbacks may change it)
	function snapshot(id:Int):Array<Gesture> {
		var list = scratch[id];
		list.resize(0);
		for (g in arenas[id])
			list.push(g);
		return list;
	}

	// (Gesture.accept: g takes every pointer it follows, the others lose
	// them; whether it has them all)
	@:allow(helder.ui.gesture) function acceptGesture(g:Gesture):Bool {
		var all = true;
		for (id in 0...POINTERS) {
			if (!@:privateAccess g.follows(id)) continue;
			var w = winners[id];
			if (w == g) continue;
			if (w != null) {
				all = false;
				continue;
			}
			winners[id] = g;
			// (backwards, without the snapshot: a move's loop holds it)
			var a = arenas[id], i = a.length;
			while (--i >= 0) {
				if (i >= a.length) continue;
				var m = a[i];
				if (m != g && a.remove(m)) @:privateAccess m.lose(id);
			}
			if (!Std.isOfType(g, Tap)) pClick[id] = false;
			// (the scroll takes the press from the nodes)
			if (g == touchScroll && id > 0) cancelPress(id);
		}
		return all;
	}

	// (Gesture.cancel: g out of every arena, its pointers left to the others)
	@:allow(helder.ui.gesture) function leaveGesture(g:Gesture) {
		for (id in 0...POINTERS) {
			if (!arenas[id].remove(g)) continue;
			if (winners[id] == g) winners[id] = null;
		}
	}

	public function wheel(x:Float, y:Float, deltaX:Float, deltaY:Float) {
		var target = hit(x, y);
		if (target == null) return;
		var e = Event.of(Wheel, target, x, y);
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

	// whether a wheel at x, y by deltaX, deltaY would scroll something: a
	// scroller under the point (the innermost first) not at its end that
	// way (a touch drag's question, helder.os's Window.scrollsAt: UiWindow)
	public function scrollsAt(x:Float, y:Float, deltaX:Float, deltaY:Float):Bool {
		var n = hit(x, y);
		while (n != null) {
			if (n.style.overflow == Scroll && (canScroll(n, deltaX, true) || canScroll(n, deltaY, false))) return true;
			n = n.parent;
		}
		return false;
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
		// (a text selectable by its own flag, or by user-select text or all; none: not)
		while (n != null) {
			if (Std.isOfType(n, TextNode)) {
				var u = n.userSelect();
				if (u == Text || u == All || (cast n : TextNode).selectable && n.style.userSelect != None) t = cast n;
			}
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
		} else if (selClicks >= 3 || t.userSelect() == All) textSelection = {node: t, anchor: 0, caret: text.length};
		else textSelection = {node: t, anchor: i, caret: i};
		selecting = selClicks == 1 && t.userSelect() != All;
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
		var e = Event.of(KeyDown, focus != null ? focus : root, pointerX, pointerY);
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

	// the nodes changed since the last update, as far as layout goes (Node.markDirty;
	// more than Layout.CHANGES: all laid out again from the root)
	@:allow(helder.ui.Layout) final changes:Array<Node> = [];

	@:allow(helder.ui.Node) function changed(n:Node)
		if (changes.length <= @:privateAccess Layout.CHANGES) changes.push(n);

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
		var e = Event.of(KeyUp, focus != null ? focus : root, pointerX, pointerY);
		e.key = key;
		e.mods = mods;
		bubble(e);
	}

	public function textInput(text:String) {
		if (text.length == 0) return;
		var e = Event.of(TextInput, focus != null ? focus : root, pointerX, pointerY);
		e.text = text;
		bubble(e);
	}

	// an input method's composition (empty: it ended), caret in it: to the focus
	public function composition(text:String, caret:Int) {
		var e = Event.of(Composition, focus != null ? focus : root, pointerX, pointerY);
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
			if (old.onBlur != null) old.onBlur(Event.of(Blur, old, pointerX, pointerY));
			bubble(Event.of(FocusOut, old, pointerX, pointerY));
		}
		if (n != null) {
			@:privateAccess n.setState(n.hovered, n.pressed, true);
			if (n.onFocus != null) n.onFocus(Event.of(Focus, n, pointerX, pointerY));
			bubble(Event.of(FocusIn, n, pointerX, pointerY));
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
				if (target == p && p.onDismiss != null && p.dismissOnOutside) p.onDismiss();
				break;
			}
			if (target != null && p.anchor != null && contains(p.anchor, target)) break;
			if (p.onDismiss != null && p.dismissOnOutside) p.onDismiss();
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
				case PointerCancel: n.onPointerCancel;
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
			// (a press: after the click, or Enter or Space the key handlers left; a link's Enter only, as a browser's)
			var press = n.onActivate;
			if (press != null && !e.stopped && (e.type == Click || e.type == KeyDown && !e.defaultPrevented
				&& (e.key == Key.ENTER || e.key == Key.SPACE && (n.semantics == null || n.semantics.role != helder.ui.access.Role.Link)))) {
				if (e.type == KeyDown) e.preventDefault();
				press(e.at(n));
			}
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
				if (o.onPointerLeave != null) o.onPointerLeave(Event.of(PointerLeave, o, pointerX, pointerY));
			}
		var i = now.length;
		while (--i >= 0) {
			var o = now[i];
			if (!old.contains(o)) {
				@:privateAccess o.setState(true, o.pressed, o.focused);
				if (o.onPointerEnter != null) o.onPointerEnter(Event.of(PointerEnter, o, pointerX, pointerY));
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

	var lastAccess:Null<helder.ui.access.AccessTree>;

	// the accessibility tree now (after update): what accessAction acts in
	// (built again only when something it reads changed: accessEpoch)
	public function accessTree():helder.ui.access.AccessTree {
		if (lastAccess != null && accessBuilt == accessEpoch) return lastAccess;
		accessBuilt = accessEpoch;
		return lastAccess = helder.ui.access.AccessTree.build(this);
	}

	// bumped by every change an accessibility tree reads (layout, scrolling,
	// the focus, semantics, focusability, transforms, opacity to 0 and back)
	public static var accessEpoch = 0;
	var accessBuilt = -1;

	// assistive technology's request on a node of the last accessTree():
	// false when the node is gone or does not take it
	public function accessAction(id:Int, action:helder.ui.access.AccessAction, ?value:String):Bool {
		var n = lastAccess == null ? null : lastAccess.node(id);
		if (n == null || n.ui != this) return false;
		switch action {
			case Click:
				var x = n.absX + n.width / 2, y = n.absY + n.height / 2;
				bubble(Event.of(Click, n, x, y));
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
		var be = n.style.borderEdges, i = SCROLLBAR_INSET, rtl = n.rtl(), b = barSize(n);
		// (the other axis's bar, if any, takes the corner)
		var corner = maxScroll(n, !x) > 0 ? b + i : 0;
		return x ? [n.absX + be.left + i + (rtl ? corner : 0), n.width - be.horizontal - 2 * i - corner, n.absY + n.height - be.bottom - i - b] : [
			n.absY + be.top + i, n.height - be.vertical - 2 * i - corner, rtl ? n.absX + be.left + i : n.absX + n.width - be.right - i - b];
	}

	// (a scroller's scrollbar thickness: its style's, 0 for none)
	static function barSize(n:Node):Float
		return switch n.style.scrollbarWidth {
			case None: 0;
			case Thin: SCROLLBAR * 2 / 3;
			case _: SCROLLBAR;
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
		return Math.min(trackLength, Math.max(MIN_THUMB, trackLength * view / content));

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
					if (across < tr[2] - SCROLLBAR_INSET || across > tr[2] + barSize(n) + SCROLLBAR_INSET || along < tr[0] || along > tr[0] + tr[1]) continue;
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
	@:allow(helder.ui.Node) function setBody(n:Node) {
		body = n;
		@:privateAccess overlay.inheritedChanged();
	}

	@:allow(helder.ui.Node) function detached(n:Node) {
		if (n == body) {
			body = null;
			@:privateAccess overlay.inheritedChanged();
		}
		if (hover != null && contains(n, hover)) hover = null;
		if (capture != null && contains(n, capture)) capture = null;
		// (its pointers' presses cancelled, its recognisers out of the arenas)
		for (id in 1...POINTERS)
			if (pDown[id] && pTarget[id] != null && contains(n, pTarget[id])) cancelPress(id);
		for (id in 0...POINTERS) {
			if (arenas[id].length == 0) continue;
			for (g in arenas[id].copy())
				if (g.node != null && contains(n, g.node)) g.cancel();
		}
		if (drag != null && contains(n, drag)) drag = null;
		if (focus != null && contains(n, focus)) focus = null;
	}
}
