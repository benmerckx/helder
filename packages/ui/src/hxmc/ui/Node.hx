package hxmc.ui;

import hxmc.ui.Event;

// A node of the UI tree: a box laid out by its parent's flexbox (Layout),
// drawn by a renderer (Canvas) and receiving events (Ui). Its children are
// in drawing order (the last on top). x, y, width and height are the
// layout's result in pixels, relative to the parent's border box (rounded
// to whole pixels: absX, absY are the window's), valid after Ui.update. A
// change to the tree or to a layout property of the style marks the node
// and its ancestors for layout; a paint property asks only for a frame.
// Subclasses with content (TextNode) measure it (measureContent) and draw it
// (paintContent).
class Node {
	public final style:Style;
	public var parent(default, null):Null<Node>;
	public final children:Array<Node> = [];
	// a name for debugging and markup (the element's name)
	public var tag:String;
	// the Ui this node's tree is attached to (null: detached)
	public var ui(default, null):Null<Ui>;

	// the layout's result (Layout): relative to the parent, then absolute; rounded
	public var x(default, null) = 0.0;
	public var y(default, null) = 0.0;
	public var width(default, null) = 0.0;
	public var height(default, null) = 0.0;
	public var absX(default, null) = 0.0;
	public var absY(default, null) = 0.0;
	// the extent of the children past the padding box's origin (scrolling)
	public var contentWidth(default, null) = 0.0;
	public var contentHeight(default, null) = 0.0;
	// Overflow Scroll: the children's offset (clamped by Ui to the content)
	public var scrollX = 0.0;
	public var scrollY = 0.0;

	// events (Ui dispatches them; Event.stop() ends bubbling to the ancestors)
	public var onPointerDown:Null<Event->Void>;
	public var onPointerUp:Null<Event->Void>;
	public var onPointerMove:Null<Event->Void>;
	public var onPointerEnter:Null<Event->Void>;
	public var onPointerLeave:Null<Event->Void>;
	public var onClick:Null<Event->Void>;
	public var onWheel:Null<Event->Void>;
	public var onKeyDown:Null<Event->Void>;
	public var onKeyUp:Null<Event->Void>;
	public var onTextInput:Null<Event->Void>;
	// Overflow Scroll: its scrollX or scrollY changed (the wheel, a thumb, clamping)
	public var onScroll:Null<Void->Void>;
	public var onComposition:Null<Event->Void>;
	public var onFocus:Null<Event->Void>;
	public var onBlur:Null<Event->Void>;
	// drag and drop: dragData makes it draggable (what its drag carries);
	// the handlers of a source (start, end) and of a target (over: call
	// preventDefault to accept; leave; drop)
	public var dragData:Dynamic = null;
	public var onDragStart:Null<Event->Void>;
	public var onDragOver:Null<Event->Void>;
	public var onDragLeave:Null<Event->Void>;
	public var onDrop:Null<Event->Void>;
	public var onDragEnd:Null<Event->Void>;
	// takes the keyboard focus when clicked or tabbed to
	public var focusable = false;
	// what it is to assistive technology (hxmc.ui.access.AccessTree)
	public var semantics:Null<hxmc.ui.access.Semantics> = null;
	// its id in the accessibility tree (0: none yet)
	@:allow(hxmc.ui.access) var accessId = 0;
	// the pointer is over it (or a descendant), the button is down on it, it has the focus
	public var hovered(default, null) = false;
	public var pressed(default, null) = false;
	public var focused(default, null) = false;

	// layout state (Layout): unrounded results, the measure cache, dirty
	@:allow(hxmc.ui.Layout) var lx = 0.0;
	@:allow(hxmc.ui.Layout) var ly = 0.0;
	@:allow(hxmc.ui.Layout) var lw = 0.0;
	@:allow(hxmc.ui.Layout) var lh = 0.0;
	@:allow(hxmc.ui.Layout) var cache:Array<Float> = [];
	@:allow(hxmc.ui.Layout) var dirty = true;
	@:allow(hxmc.ui.Layout) var minContent = Math.NaN;

	public function new(?tag:String) {
		this.tag = tag == null ? "view" : tag;
		style = new Style(this);
	}

	// --- the tree ---

	public function append(child:Node):Node
		return insert(child, children.length);

	// child at index (moved if it is already a child of this node)
	public function insert(child:Node, index:Int):Node {
		if (child == this) throw "Node: a node is not its own child";
		var p:Node = this;
		while (p != null) {
			if (p == child) throw "Node: a node is not inside itself";
			p = p.parent;
		}
		if (child.parent == this) {
			var i = indexOf(child);
			children.splice(i, 1);
			if (i < index) index--;
		} else if (child.parent != null) child.parent.remove(child);
		if (index < 0 || index > children.length) index = children.length;
		children.insert(index, child);
		child.parent = this;
		child.attach(ui);
		markDirty();
		return child;
	}

	// the index of a child (-1: not one), looked for from the end, where
	// anchors and new children usually are
	public function indexOf(child:Node):Int {
		if (child.parent != this) return -1;
		var i = children.length;
		while (--i >= 0)
			if (children[i] == child) return i;
		return -1;
	}

	// puts nodes, all children of this node and as many as the children from
	// start, in that order from start (a keyed list's rows, reordered at once)
	public function reorder(start:Int, nodes:Array<Node>) {
		if (start < 0 || start + nodes.length > children.length) throw "Node.reorder: out of range";
		var changed = false;
		for (k in 0...nodes.length) {
			var n = nodes[k];
			if (n.parent != this) throw "Node.reorder: not a child";
			if (children[start + k] != n) {
				children[start + k] = n;
				changed = true;
			}
		}
		if (changed) markDirty();
	}

	public function remove(child:Node) {
		if (child.parent != this) return;
		children.remove(child);
		child.parent = null;
		child.attach(null);
		markDirty();
	}

	public function removeChildren() {
		for (c in children) {
			c.parent = null;
			c.attach(null);
		}
		children.resize(0);
		markDirty();
	}

	@:allow(hxmc.ui.Ui) function attach(u:Null<Ui>) {
		if (ui == u) return;
		if (ui != null) ui.detached(this);
		ui = u;
		for (c in children)
			c.attach(u);
	}

	// --- changes ---

	// the layout of this node (and so of its ancestors) must be redone
	public function markDirty() {
		var n = this;
		while (n != null && !(n.dirty && n.cache.length == 0 && Math.isNaN(n.minContent))) {
			n.dirty = true;
			n.cache.resize(0);
			n.minContent = Math.NaN;
			n = n.parent;
		}
		if (ui != null) ui.requestFrame();
	}

	@:allow(hxmc.ui.Style) function styleChanged(layout:Bool) {
		if (layout) {
			markDirty();
			// (an inherited text property: the descendants' text changes too)
			for (c in children)
				c.inheritedChanged();
		} else if (ui != null) ui.requestFrame();
	}

	function inheritedChanged() {
		if (hasContent()) markDirty();
		for (c in children)
			c.inheritedChanged();
	}

	// --- inherited text properties ---

	public function font():Font {
		var family:Null<String> = null, size:Null<Float> = null, weight:Null<Int> = null, italic:Null<Bool> = null, lh:Null<Float> = null;
		var n = this;
		while (n != null) {
			var s = n.style;
			if (family == null) family = s.fontFamily;
			if (size == null) size = s.fontSize;
			if (weight == null) weight = s.fontWeight;
			if (italic == null) italic = s.italic;
			if (lh == null) lh = s.lineHeight;
			n = n.parent;
		}
		return new Font(family == null ? Style.DEFAULT_FAMILY : family, size == null ? Style.DEFAULT_SIZE : size,
			weight == null ? Style.DEFAULT_WEIGHT : weight, italic == true, lh == null ? Style.DEFAULT_LINE_HEIGHT : lh);
	}

	public function textColor():Color {
		var n = this;
		while (n != null) {
			if (n.style.color != null) return n.style.color;
			n = n.parent;
		}
		return Style.DEFAULT_COLOR;
	}

	public function textAlign():TextAlign {
		var n = this;
		while (n != null) {
			if (n.style.textAlign != null) return n.style.textAlign;
			n = n.parent;
		}
		return Left;
	}

	// a window position in this node's coordinates (from its border box's
	// top left), its ancestors' scrolling taken into account
	public function localX(windowX:Float):Float
		return windowX + scrolled(true) - absX;

	public function localY(windowY:Float):Float
		return windowY + scrolled(false) - absY;

	function scrolled(x:Bool):Float {
		var d = 0.0, p = parent;
		while (p != null) {
			if (p.style.overflow == Scroll) d += x ? p.scrollX : p.scrollY;
			p = p.parent;
		}
		return d;
	}

	// --- content (subclasses) ---

	public function hasContent():Bool
		return false;

	// the content's size for the given content-box constraints (NaN: unknown
	// or unbounded)
	public function measureContent(text:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):Size
		return Size.ZERO;

	// assistive technology sets its value (a text input's text): false when it has none
	public function accessSetValue(value:String):Bool
		return false;

	// where text is typed into it (its caret, window pixels, after a paint):
	// an input method's place; null: it takes no text
	public function textInputArea():Null<{x:Float, y:Float, width:Float, height:Float}>
		return null;

	// its background gradient drawn at its size in the window's pixels (kept until either changes)
	var gradientImage:Null<Image> = null;
	var gradientKey = "";
	var gradientOf:Null<Gradient> = null;

	public function backgroundImage(scale:Float):Image {
		var g = style.backgroundImage, w = Std.int(Math.max(1, Math.round(width * scale))), h = Std.int(Math.max(1, Math.round(height * scale)));
		var key = w + "x" + h + "@" + scale;
		if (gradientImage == null || gradientOf != g || gradientKey != key) {
			gradientImage = g.render(w, h, scale);
			gradientOf = g;
			gradientKey = key;
		}
		return gradientImage;
	}

	// whether it takes typed text while focused (a text field): keys that type are its, not shortcuts
	public function takesText():Bool
		return false;

	// whether its children are part of its content (a TextNode's spans), not boxes laid out
	public function contentOwnsChildren():Bool
		return false;

	// the content's min-content width (its widest unbreakable part)
	public function minContentWidth(text:TextEngine):Float
		return measureContent(text, Math.NaN, Math.NaN, 0, Math.NaN).width;

	// draws the content in its content box at (x, y), in window pixels
	public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {}

	// --- queries ---

	// the topmost node under (px, py) in window pixels, among this subtree
	// (clipped by Overflow), or null
	public function hitTest(px:Float, py:Float):Null<Node> {
		if (style.display == None) return null;
		var inside = px >= absX && py >= absY && px < absX + width && py < absY + height;
		if (!inside && style.overflow != Visible) return null;
		var i = children.length;
		while (--i >= 0) {
			var c = children[i].hitTest(px + (style.overflow == Scroll ? scrollX : 0), py + (style.overflow == Scroll ? scrollY : 0));
			if (c != null) return c;
		}
		return inside ? this : null;
	}

	// the first descendant (or this) with the tag, depth first
	public function find(tag:String):Null<Node> {
		if (this.tag == tag) return this;
		for (c in children) {
			var f = c.find(tag);
			if (f != null) return f;
		}
		return null;
	}

	public function toString():String
		return '$tag(${x},${y} ${width}x${height})';

	// --- set by Layout and Ui ---

	@:allow(hxmc.ui.Layout) function setLayout(x:Float, y:Float, w:Float, h:Float, ax:Float, ay:Float, cw:Float, ch:Float) {
		this.x = x;
		this.y = y;
		width = w;
		height = h;
		absX = ax;
		absY = ay;
		contentWidth = cw;
		contentHeight = ch;
	}

	@:allow(hxmc.ui.Ui) function setState(hovered:Bool, pressed:Bool, focused:Bool) {
		var changed = hovered != this.hovered || pressed != this.pressed || focused != this.focused;
		this.hovered = hovered;
		this.pressed = pressed;
		this.focused = focused;
		if (changed && ui != null) ui.requestFrame();
	}
}
