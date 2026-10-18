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
class Node implements Part {
	public final style:Style;
	public var parent(default, null):Null<Node>;
	// (a leaf's: one empty array shared by all, replaced by its own when a child comes)
	public var children(default, null):Array<Node> = NO_CHILDREN;

	static final NO_CHILDREN:Array<Node> = [];
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
	// the extent of the children past the padding box's origin (scrolling;
	// right to left: from its right edge, what overflows on the left)
	public var contentWidth(default, null) = 0.0;
	public var contentHeight(default, null) = 0.0;
	// Overflow Scroll: the children's offset (clamped by Ui to the content;
	// right to left, scrollX from 0 down: Ui.scrollStart)
	public var scrollX(default, set) = 0.0;
	public var scrollY(default, set) = 0.0;

	// events (Ui dispatches them; Event.stop() ends bubbling to the ancestors;
	// kept in a Handlers made when the first is set: most nodes have none)
	public var onPointerDown(get, set):Null<Event->Void>;
	public var onPointerUp(get, set):Null<Event->Void>;
	public var onPointerMove(get, set):Null<Event->Void>;
	public var onPointerEnter(get, set):Null<Event->Void>;
	public var onPointerLeave(get, set):Null<Event->Void>;
	public var onClick(get, set):Null<Event->Void>;
	// a press: a click, or Enter or Space while it has the focus (after onKeyDown, unless it
	// prevented the default), as a DOM button's click (a link's: Enter, not Space, as a DOM link's)
	public var onActivate(get, set):Null<Event->Void>;
	public var onWheel(get, set):Null<Event->Void>;
	public var onKeyDown(get, set):Null<Event->Void>;
	public var onKeyUp(get, set):Null<Event->Void>;
	public var onTextInput(get, set):Null<Event->Void>;
	// a text field's text changed by its user (Event.text: its text; the DOM's input)
	public var onInput(get, set):Null<Event->Void>;
	// Overflow Scroll: its scrollX or scrollY changed (the wheel, a thumb, clamping)
	public var onScroll(get, set):Null<Void->Void>;
	public var onComposition(get, set):Null<Event->Void>;
	public var onFocus(get, set):Null<Event->Void>;
	public var onBlur(get, set):Null<Event->Void>;
	// (bubbling: the focus coming into this node or one under it, or leaving)
	public var onFocusIn(get, set):Null<Event->Void>;
	public var onFocusOut(get, set):Null<Event->Void>;
	// drag and drop: dragData makes it draggable (what its drag carries);
	// the handlers of a source (start, end) and of a target (over: call
	// preventDefault to accept; leave; drop)
	public var dragData(get, set):Dynamic;
	public var onDragStart(get, set):Null<Event->Void>;
	public var onDragOver(get, set):Null<Event->Void>;
	public var onDragLeave(get, set):Null<Event->Void>;
	public var onDrop(get, set):Null<Event->Void>;
	public var onDragEnd(get, set):Null<Event->Void>;
	// takes the keyboard focus when clicked or tabbed to
	public var focusable(default, set) = false;
	// what it is to assistive technology (hxmc.ui.access.AccessTree)
	public var semantics(default, set):Null<hxmc.ui.access.Semantics> = null;
	// its id in the accessibility tree (0: none yet)
	@:allow(hxmc.ui.access) var accessId = 0;
	// the pointer is over it (or a descendant), the button is down on it, it has the focus
	public var hovered(default, null) = false;
	public var pressed(default, null) = false;
	public var focused(default, null) = false;
	// a legend (a page's legend element): its parent's first, as a fieldset's
	// rendered legend, no flex item (Layout: no gap after it in a column)
	public var legend = false;
	// what a theme styles it as (Rule, StyleSheet): the part of a widget
	// (shadcn's data-slot names: "button", "switch-thumb"), its variant and
	// size ("destructive", "sm"); its attributes, the states rules match
	// ("data-state" "checked", "data-disabled" present: attr, setAttr); and
	// a theme for this subtree (null: the parent's, else the window's)
	public var slot(default, set):Null<String> = null;
	public var variant(default, set):Null<String> = null;
	public var size(default, set):Null<String> = null;
	public var theme(default, set):Null<StyleSheet> = null;
	// what draws the widgets of this subtree (Host: Auto, the parent's; Ui.hostOf)
	public var host:Host = Auto;
	var attrs:Null<Map<String, String>> = null;
	// (what the rules wrote: the properties and their values, Rules; a restyle asked for, done by Ui.update)
	var themedIds:Null<Array<Int>> = null;
	var themedValues:Null<Array<Dynamic>> = null;
	// (the properties whose own values it holds over the rules at any value, its defaults too: Rules.keep)
	var keptIds:Null<Array<Int>> = null;
	var restylePending = false;

	// (asks for its rules to be applied again, at the next update: several changes, one restyle)
	function restyleLater() {
		if (ui == null || restylePending || slot == null && themedIds == null) return;
		restylePending = true;
		@:privateAccess ui.restyles.push(this);
		ui.requestFrame();
	}

	// layout state (Layout): unrounded results, the measure cache, dirty
	@:allow(hxmc.ui.Layout) var lx = 0.0;
	@:allow(hxmc.ui.Layout) var ly = 0.0;
	@:allow(hxmc.ui.Layout) var lw = 0.0;
	@:allow(hxmc.ui.Layout) var lh = 0.0;
	// (made when first stored to)
	@:allow(hxmc.ui.Layout) var cache:Null<haxe.ds.Vector<Float>> = null;
	@:allow(hxmc.ui.Layout) var dirty = true;
	// (laid out since its edges were last rounded; the unrounded box they were rounded from)
	@:allow(hxmc.ui.Layout) var relaid = true;
	@:allow(hxmc.ui.Layout) var rawX = 0.0;
	@:allow(hxmc.ui.Layout) var rawY = 0.0;
	@:allow(hxmc.ui.Layout) var rawW = 0.0;
	@:allow(hxmc.ui.Layout) var rawH = 0.0;
	// the bounds of what it and its subtree draw (measureInk), stale after a transform changed
	@:allow(hxmc.ui) var inkX0 = 0.0;
	@:allow(hxmc.ui) var inkY0 = 0.0;
	@:allow(hxmc.ui) var inkX1 = 0.0;
	@:allow(hxmc.ui) var inkY1 = 0.0;
	@:allow(hxmc.ui) var inkAll = false;
	@:allow(hxmc.ui) var inkStale = false;
	@:allow(hxmc.ui.Layout) var minContent = Math.NaN;
	// (what its last layout was given, to be laid out again in place: Layout.inPlace)
	@:allow(hxmc.ui.Layout) var performed = false;
	@:allow(hxmc.ui.Layout) var pKW = 0.0;
	@:allow(hxmc.ui.Layout) var pKH = 0.0;
	@:allow(hxmc.ui.Layout) var pPW = 0.0;
	@:allow(hxmc.ui.Layout) var pPH = 0.0;
	@:allow(hxmc.ui.Layout) var pAW = 0.0;
	@:allow(hxmc.ui.Layout) var pAH = 0.0;
	@:allow(hxmc.ui.Layout) var pLoose = false;
	// (its measures as they were when it changed: the cache's length then, -1
	// not all of them (some dropped or never kept, or measured again since);
	// its min-content; lossy: some measure since not in the cache)
	@:allow(hxmc.ui.Layout) var cacheWas = -1;
	@:allow(hxmc.ui.Layout) var minContentWas = Math.NaN;
	@:allow(hxmc.ui.Layout) var lossy = false;
	// (a row's items' baseline, those aligned on it, below its top; NaN: none)
	@:allow(hxmc.ui.Layout) var lb = Math.NaN;

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
		var first = children.length > 0 ? children[0] : null, last = children.length > 0 ? children[children.length - 1] : null;
		if (child.parent == this) {
			var i = indexOf(child);
			children.splice(i, 1);
			if (i < index) index--;
		} else if (child.parent != null) child.parent.remove(child);
		if (index < 0 || index > children.length) index = children.length;
		if (children == NO_CHILDREN) children = [];
		children.insert(index, child);
		var moved = child.parent != this;
		child.parent = this;
		child.attach(ui);
		// (under another parent: what it inherits may differ, and the states of nodes around it)
		if (moved) child.inheritedChanged();
		if (moved && ui != null && @:privateAccess Rules.relational != 0) Rules.restyleTree(child);
		Rules.placed(this, child, first, last, index + 1 < children.length ? children[index + 1] : null);
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
		if (changed) {
			Rules.placed(this, null, children[0], children[children.length - 1]);
			markDirty();
		}
	}

	public function remove(child:Node) {
		if (child.parent != this) return;
		var first = children[0], last = children[children.length - 1], i = indexOf(child);
		children.splice(i, 1);
		child.parent = null;
		child.attach(null);
		Rules.placed(this, child, first == child ? null : first, last == child ? null : last, i < children.length ? children[i] : null);
		markDirty();
	}

	public function removeChildren() {
		for (c in children) {
			c.parent = null;
			c.attach(null);
		}
		children.resize(0);
		Rules.placed(this, null, null, null);
		markDirty();
	}

	@:allow(hxmc.ui.Ui) function attach(u:Null<Ui>) {
		if (ui == u) return;
		if (ui != null) ui.detached(this);
		ui = u;
		if (u != null && slot == "body") u.setBody(this);
		// (out of a window: drawn anew when back, its starting rules again)
		if (u == null) @:privateAccess style.drawn = false;
		restyleLater();
		for (c in children)
			c.attach(u);
	}

	// --- changes ---

	// (what the accessibility tree reads: a change builds it again)
	function set_scrollX(v:Float):Float {
		if (v != scrollX) Ui.accessEpoch++;
		return scrollX = v;
	}

	function set_scrollY(v:Float):Float {
		if (v != scrollY) Ui.accessEpoch++;
		return scrollY = v;
	}

	function set_focusable(v:Bool):Bool {
		if (v != focusable) Ui.accessEpoch++;
		return focusable = v;
	}

	function set_semantics(v:Null<hxmc.ui.access.Semantics>):Null<hxmc.ui.access.Semantics> {
		if (v != semantics) Ui.accessEpoch++;
		return semantics = v;
	}

	// --- the handlers ---

	var handlers:Null<Handlers> = null;

	inline function get_onPointerDown():Null<Event->Void>
		return handlers == null ? null : handlers.onPointerDown;

	function set_onPointerDown(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onPointerDown = v;
	}

	inline function get_onPointerUp():Null<Event->Void>
		return handlers == null ? null : handlers.onPointerUp;

	function set_onPointerUp(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onPointerUp = v;
	}

	inline function get_onPointerMove():Null<Event->Void>
		return handlers == null ? null : handlers.onPointerMove;

	function set_onPointerMove(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onPointerMove = v;
	}

	inline function get_onPointerEnter():Null<Event->Void>
		return handlers == null ? null : handlers.onPointerEnter;

	function set_onPointerEnter(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onPointerEnter = v;
	}

	inline function get_onPointerLeave():Null<Event->Void>
		return handlers == null ? null : handlers.onPointerLeave;

	function set_onPointerLeave(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onPointerLeave = v;
	}

	inline function get_onClick():Null<Event->Void>
		return handlers == null ? null : handlers.onClick;

	function set_onClick(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onClick = v;
	}

	inline function get_onActivate():Null<Event->Void>
		return handlers == null ? null : handlers.onActivate;

	function set_onActivate(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onActivate = v;
	}

	inline function get_onWheel():Null<Event->Void>
		return handlers == null ? null : handlers.onWheel;

	function set_onWheel(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onWheel = v;
	}

	inline function get_onKeyDown():Null<Event->Void>
		return handlers == null ? null : handlers.onKeyDown;

	function set_onKeyDown(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onKeyDown = v;
	}

	inline function get_onKeyUp():Null<Event->Void>
		return handlers == null ? null : handlers.onKeyUp;

	function set_onKeyUp(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onKeyUp = v;
	}

	inline function get_onTextInput():Null<Event->Void>
		return handlers == null ? null : handlers.onTextInput;

	function set_onTextInput(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onTextInput = v;
	}

	inline function get_onInput():Null<Event->Void>
		return handlers == null ? null : handlers.onInput;

	function set_onInput(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onInput = v;
	}

	inline function get_onScroll():Null<Void->Void>
		return handlers == null ? null : handlers.onScroll;

	function set_onScroll(v:Null<Void->Void>):Null<Void->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onScroll = v;
	}

	inline function get_onComposition():Null<Event->Void>
		return handlers == null ? null : handlers.onComposition;

	function set_onComposition(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onComposition = v;
	}

	inline function get_onFocus():Null<Event->Void>
		return handlers == null ? null : handlers.onFocus;

	function set_onFocus(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onFocus = v;
	}

	inline function get_onBlur():Null<Event->Void>
		return handlers == null ? null : handlers.onBlur;

	inline function get_onFocusIn():Null<Event->Void>
		return handlers == null ? null : handlers.onFocusIn;

	function set_onFocusIn(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onFocusIn = v;
	}

	inline function get_onFocusOut():Null<Event->Void>
		return handlers == null ? null : handlers.onFocusOut;

	function set_onFocusOut(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onFocusOut = v;
	}

	function set_onBlur(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onBlur = v;
	}

	inline function get_dragData():Dynamic
		return handlers == null ? null : handlers.dragData;

	function set_dragData(v:Dynamic):Dynamic {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.dragData = v;
	}

	inline function get_onDragStart():Null<Event->Void>
		return handlers == null ? null : handlers.onDragStart;

	function set_onDragStart(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onDragStart = v;
	}

	inline function get_onDragOver():Null<Event->Void>
		return handlers == null ? null : handlers.onDragOver;

	function set_onDragOver(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onDragOver = v;
	}

	inline function get_onDragLeave():Null<Event->Void>
		return handlers == null ? null : handlers.onDragLeave;

	function set_onDragLeave(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onDragLeave = v;
	}

	inline function get_onDrop():Null<Event->Void>
		return handlers == null ? null : handlers.onDrop;

	function set_onDrop(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onDrop = v;
	}

	inline function get_onDragEnd():Null<Event->Void>
		return handlers == null ? null : handlers.onDragEnd;

	function set_onDragEnd(v:Null<Event->Void>):Null<Event->Void> {
		if (handlers == null) {
			if (v == null) return v;
			handlers = new Handlers();
		}
		return handlers.onDragEnd = v;
	}

	// (Ui.update's, after the layout, for the nodes that joined Ui.natives: a platform's view kept in step)
	@:allow(hxmc.ui.Ui) function syncNative() {}

	// (the window took the keyboard's focus from its platform view: given back)
	function refocusNative() {}

	// the layout of this node (and so of its ancestors) must be redone
	public function markDirty() {
		Ui.accessEpoch++;
		fontCache = null;
		textBits = -1;
		var n = this;
		while (n != null && !(n.dirty && (n.cache == null || n.cache[0] == 0) && Math.isNaN(n.minContent))) {
			if (!n.dirty) {
				n.cacheWas = n.lossy ? -1 : n.cache == null ? 0 : Std.int(n.cache[0]);
				n.minContentWas = n.minContent;
				n.lossy = false;
			}
			n.dirty = true;
			if (n.cache != null) n.cache[0] = 0;
			n.minContent = Math.NaN;
			n = n.parent;
		}
		if (ui != null) {
			ui.changed(this);
			ui.requestFrame();
		}
	}

	@:allow(hxmc.ui.Style) function styleChanged(layout:Bool) {
		if (layout) {
			markDirty();
			// (its parent's layout reads its style: margins, flex, position...)
			if (parent != null && ui != null) ui.changed(parent);
			// (an inherited text property: the descendants' text changes too, the body's: the layers' too)
			for (c in children)
				c.inheritedChanged();
			if (ui != null && this == ui.body) ui.overlay.inheritedChanged();
		} else if (ui != null) ui.requestFrame();
	}

	// (the direction changed above: the descendants laid out again)
	function dirChanged() {
		for (c in children) {
			c.markDirty();
			c.dirChanged();
		}
		if (ui != null && this == ui.body) ui.overlay.dirChanged();
	}

	function inheritedChanged() {
		fontCache = null;
		textBits = -1;
		if (hasContent()) markDirty();
		for (c in children)
			c.inheritedChanged();
		if (ui != null && this == ui.body) ui.overlay.inheritedChanged();
	}

	// --- inherited text properties ---

	// (what it inherits from: its parent; the overlay's, the page's body (Ui.body), as a popup in a page's
	// body inherits the body's text, not its trigger's)
	inline function inheritsFrom():Null<Node>
		return ui != null && this == ui.overlay && ui.body != null ? ui.body : parent;

	public function font():Font {
		if (fontCache != null) return fontCache;
		// (unset: NaN, -1; no boxes)
		var family:Null<String> = null, size = Math.NaN, weight = -1, italic = -1, lh = Math.NaN, ls = Math.NaN, ws = Math.NaN;
		// (a line height in pixels, made a multiple of this font's size once it is known)
		var lhPx = Math.NaN;
		var ow:Null<OverflowWrap> = null, wb:Null<WordBreak> = null, ff:Null<String> = null, fvn:Null<String> = null;
		var n = this;
		while (n != null) {
			var s = n.style;
			if (family == null) family = s.fontFamily;
			if (Math.isNaN(size) && s.fontSize != null) size = s.fontSize;
			if (weight < 0 && s.fontWeight != null) weight = s.fontWeight;
			if (italic < 0 && s.italic != null) italic = s.italic ? 1 : 0;
			if (Math.isNaN(lh) && Math.isNaN(lhPx)) {
				if (s.lineHeightPx != null) lhPx = s.lineHeightPx else if (s.lineHeight != null) lh = s.lineHeight;
			}
			if (Math.isNaN(ls)) {
				if (s.letterSpacingEm != null) ls = s.letterSpacingEm * n.fontSizeHere() else if (s.letterSpacing != null) ls = s.letterSpacing;
			}
			if (Math.isNaN(ws) && s.wordSpacing != null) ws = s.wordSpacing;
			if (ow == null) ow = s.overflowWrap;
			if (wb == null) wb = s.wordBreak;
			if (ff == null) ff = s.fontFeatureSettings;
			if (fvn == null) fvn = s.fontVariantNumeric;
			n = n.inheritsFrom();
		}
		if (Math.isNaN(size)) size = Style.DEFAULT_SIZE;
		if (!Math.isNaN(lhPx)) lh = size > 0 ? lhPx / size : Style.DEFAULT_LINE_HEIGHT;
		return fontCache = new Font(family == null ? Style.DEFAULT_FAMILY : family, size,
			weight < 0 ? Style.DEFAULT_WEIGHT : weight, italic == 1, Math.isNaN(lh) ? Style.DEFAULT_LINE_HEIGHT : lh, Math.isNaN(ls) ? 0 : ls,
			Math.isNaN(ws) ? 0 : ws, ow == null ? BreakWord : ow, wb == null ? WordBreak.Normal : wb, features(fvn, ff));
	}

	// (the font size here: its own or the nearest ancestor's)
	function fontSizeHere():Float {
		var n = this;
		while (n != null) {
			if (n.style.fontSize != null) return n.style.fontSize;
			n = n.inheritsFrom();
		}
		return Style.DEFAULT_SIZE;
	}

	// (the features asked for: font-variant-numeric's, then font-feature-settings', which win)
	static function features(numeric:Null<String>, settings:Null<String>):String {
		var a = numeric == null ? "" : Style.numericFeatures(numeric), b = settings == null || StringTools.trim(settings) == "normal" ? "" : settings;
		return a == "" ? b : b == "" ? a : a + ", " + b;
	}

	// (the font, until it or an ancestor changes a text property: markDirty clears it)
	var fontCache:Null<Font> = null;

	// the text shadows its text casts (Style.textShadow, inherited; null: none)
	public function textShadow():Null<Shadow> {
		var n = this;
		while (n != null) {
			var sh = n.style.textShadow;
			if (sh != null) return sh == Shadow.NONE ? null : sh;
			n = n.inheritsFrom();
		}
		return null;
	}

	// a paragraph's text shadows (textShadow()), the last first, under where
	// it is drawn at x, y in color (or its spans' colors)
	function paintTextShadows(canvas:Canvas, p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>) {
		var shadows = textShadow();
		if (shadows != null)
			for (sh in shadows.painted())
				canvas.textShadow(p, x + sh.x, y + sh.y, width, align, sh.currentColor ? color : sh.color, sh.blur, sh.currentColor ? colors : null);
	}

	public function textColor():Color {
		var n = this;
		while (n != null) {
			if (n.style.color != null) return n.style.color;
			n = n.inheritsFrom();
		}
		return Style.DEFAULT_COLOR;
	}

	// whether it is seen: its visibility, else its nearest ancestor's (Style.visibility)
	public function visible():Bool {
		var n = this;
		while (n != null) {
			var v = n.style.visibility;
			if (v != null) return v == Visible;
			n = n.parent;
		}
		return true;
	}

	// whether the pointer finds it: seen, and its pointerEvents (else its
	// nearest ancestor's) not None
	public function hittable():Bool {
		var n = this;
		while (n != null) {
			var p = n.style.pointerEvents;
			if (p != null) return p == Auto && visible();
			n = n.parent;
		}
		return visible();
	}

	// whether its text wraps: its textWrap, else its nearest ancestor's (Style.textWrap)
	public inline function wraps():Bool
		return textWrap() != NoWrap;

	// how its text wraps: its textWrap, else its nearest ancestor's
	public function textWrap():TextWrap
		return cast (textInherited() >> 4) & 3;

	// how its text's letters are shown: its textTransform, else its nearest ancestor's
	public function textTransform():TextTransform
		return cast (textInherited() >> 2) & 3;

	// (its direction (0 none set, else Dir + 1), text transform and wrapping,
	// inherited, found in one walk up and kept as bits: -1 not yet; cleared
	// with fontCache, as their setters lay the subtree out again)
	var textBits = -1;

	function textInherited():Int {
		if (textBits >= 0) return textBits;
		var d = -1, t = -1, w = -1, n = this;
		while (n != null && (d < 0 || t < 0 || w < 0)) {
			var s = n.style;
			if (d < 0 && s.dir != null) d = (cast s.dir : Int) + 1;
			if (t < 0 && s.textTransform != null) t = (cast s.textTransform : Int);
			if (w < 0 && s.textWrap != null) w = (cast s.textWrap : Int);
			n = n.inheritsFrom();
		}
		return textBits = (d < 0 ? 0 : d) | (t < 0 ? 0 : t) << 2 | (w < 0 ? 0 : w) << 4;
	}

	public function textAlign():TextAlign {
		var n = this;
		while (n != null) {
			if (n.style.textAlign != null) return n.style.textAlign;
			n = n.inheritsFrom();
		}
		return rtl() ? Right : Left;
	}

	// whether its inline direction is right to left (Style.dir, inherited)
	// its text's user-select as set on it or an ancestor (Auto: none set)
	public function userSelect():UserSelect {
		var n = this;
		while (n != null) {
			var u = n.style.userSelect;
			if (u != null && u != Auto) return u;
			n = n.inheritsFrom();
		}
		return Auto;
	}

	public function rtl():Bool
		return dir() == Rtl;

	// its direction as set on it or an ancestor (null: none set)
	public function dir():Null<Dir> {
		var d = textInherited() & 3;
		return d == 0 ? null : cast d - 1;
	}

	// a window position in this node's coordinates (from its border box's
	// top left), its ancestors' scrolling and transforms (its own too) taken
	// into account
	public function localX(windowX:Float, windowY:Float):Float
		return toLocal(windowX, windowY, true);

	public function localY(windowX:Float, windowY:Float):Float
		return toLocal(windowX, windowY, false);

	function toLocal(px:Float, py:Float, x:Bool):Float {
		var chain = [], n = this;
		while (n != null) {
			chain.push(n);
			n = n.parent;
		}
		var i = chain.length;
		while (--i >= 0) {
			var a = chain[i], m = a.transformMatrix();
			if (m != null) {
				var inv = Transform.invert(m);
				if (inv != null) {
					var tx = inv[0] * px + inv[2] * py + inv[4];
					py = inv[1] * px + inv[3] * py + inv[5];
					px = tx;
				}
			}
			if (i > 0 && a.style.overflow == Scroll) {
				px += a.scrollX;
				py += a.scrollY;
			}
		}
		return x ? px - absX : py - absY;
	}

	// --- a part (Part: what a neutral element's ref gets) ---

	public function focus(visible:Bool = true) {
		if (ui == null) return;
		if (visible) ui.focusVisible = true;
		ui.setFocus(this);
	}

	public function rect():{x:Float, y:Float, width:Float, height:Float}
		return windowBounds();

	public function scrollIntoView()
		if (ui != null) ui.scrollIntoView(this);

	// (a press's pointer: the pressed node's until released (Ui.capture), this one's now)
	public function capture()
		if (ui != null && ui.capture != null) @:privateAccess ui.capture = this;

	// (a text field's: EditableText's)
	public function select(start:Int, end:Int) {}

	public function contains(p:Part):Bool {
		var n:Null<Node> = Std.downcast(p, Node);
		while (n != null && n != this)
			n = n.parent;
		return n != null;
	}

	// the border box where it is drawn, in window pixels: its ancestors'
	// scrolling taken off, through the transforms (its own too; the bounds
	// of the box they turn)
	public function windowBounds():{x:Float, y:Float, width:Float, height:Float} {
		var xs = [absX, absX + width, absX, absX + width], ys = [absY, absY, absY + height, absY + height];
		var a = this;
		while (a != null) {
			if (a != this && a.style.overflow == Scroll)
				for (k in 0...4) {
					xs[k] -= a.scrollX;
					ys[k] -= a.scrollY;
				}
			var m = a.transformMatrix();
			if (m != null)
				for (k in 0...4) {
					var x = xs[k];
					xs[k] = m[0] * x + m[2] * ys[k] + m[4];
					ys[k] = m[1] * x + m[3] * ys[k] + m[5];
				}
			a = a.parent;
		}
		var x0 = Math.min(Math.min(xs[0], xs[1]), Math.min(xs[2], xs[3])), y0 = Math.min(Math.min(ys[0], ys[1]), Math.min(ys[2], ys[3]));
		var x1 = Math.max(Math.max(xs[0], xs[1]), Math.max(xs[2], xs[3])), y1 = Math.max(Math.max(ys[0], ys[1]), Math.max(ys[2], ys[3]));
		return {x: x0, y: y0, width: x1 - x0, height: y1 - y0};
	}

	// the transform (Style.transform about Style.transformOrigin) in window
	// pixels, as Canvas.pushTransform takes it; null: none
	public function transformMatrix():Null<Array<Float>> {
		var t = style.transform;
		// (Sticky: moved where it sticks, then transformed there)
		var sx = 0.0, sy = 0.0;
		if (style.position == Sticky) {
			var s = stickyOffset();
			sx = s[0];
			sy = s[1];
		}
		if (t == null || t.isIdentity()) return sx == 0 && sy == 0 ? null : [1.0, 0, 0, 1, sx, sy];
		var o = style.transformOrigin;
		var ox = o == null ? Math.NaN : o[0].resolve(width), oy = o == null ? Math.NaN : o[1].resolve(height);
		ox = absX + (Math.isNaN(ox) ? width / 2 : ox);
		oy = absY + (Math.isNaN(oy) ? height / 2 : oy);
		var m = t.toMatrix(width, height);
		// (about the origin: moved there, transformed, moved back)
		m[4] += ox - (m[0] * ox + m[2] * oy) + sx;
		m[5] += oy - (m[1] * ox + m[3] * oy) + sy;
		return m;
	}

	// a Sticky node's move from where it was laid out: kept its insets
	// (left, top, right, bottom: those given) inside the content box of the
	// nearest scrolling ancestor as it scrolls, as far as its parent's
	// content box lets it go (its margins inside), as CSS sticks it
	function stickyOffset():Array<Float> {
		var p = parent, sc = parent;
		while (sc != null && sc.style.overflow != Scroll)
			sc = sc.parent;
		if (p == null) return [0, 0];
		var out = [0.0, 0.0];
		for (axis in 0...2) {
			var x = axis == 0, s = style, m = s.margin;
			var pos = x ? absX : absY, size = x ? width : height;
			// (the view: the scroller's content box, scrolled; else the window's)
			var v0 = 0.0, v1 = ui == null ? 1e9 : x ? ui.width : ui.height;
			if (sc != null) {
				var ss = sc.style, be = ss.borderEdges, pad = ss.padding;
				v0 = (x ? sc.absX + be.left + pad.left + sc.scrollX : sc.absY + be.top + pad.top + sc.scrollY);
				v1 = (x ? sc.absX + sc.width - be.right - pad.right + sc.scrollX : sc.absY + sc.height - be.bottom - pad.bottom + sc.scrollY);
			}
			// (the parent's content box, its margins inside)
			var ps = p.style, pbe = ps.borderEdges, ppad = ps.padding;
			// (an auto margin: 0)
			var m0 = x ? m.left : m.top, m1 = x ? m.right : m.bottom;
			var c0 = (x ? p.absX + pbe.left + ppad.left : p.absY + pbe.top + ppad.top) + (Math.isNaN(m0) ? 0 : m0);
			var c1 = (x ? p.absX + p.width - pbe.right - ppad.right : p.absY + p.height - pbe.bottom - ppad.bottom) - (Math.isNaN(m1) ? 0 : m1);
			var start = (x ? s.left : s.top).resolve(v1 - v0), end = (x ? s.right : s.bottom).resolve(v1 - v0);
			var d = 0.0;
			if (!Math.isNaN(start) && pos + d < v0 + start) d = Math.min(v0 + start - pos, Math.max(0, c1 - (pos + size)));
			if (!Math.isNaN(end) && pos + d + size > v1 - end) d = Math.max(v1 - end - (pos + size), Math.min(0, c0 - pos));
			out[axis] = d;
		}
		return out;
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

	// its children in their layout order (Style.order: lower first, ties in
	// the tree's order): the children themselves when none has an order
	@:allow(hxmc.ui) function inOrder():Array<Node> {
		var any = false;
		for (c in children)
			if (c.style.order != 0) {
				any = true;
				break;
			}
		return any ? sorted((a, b) -> a.style.order - b.style.order) : children;
	}

	// its children in the order they paint (Style.zIndex; then positioned ones
	// over those in the flow; then Style.order), hit the other way round; null
	// when that is the tree's order with positioned ones last (the usual case)
	@:allow(hxmc.ui) function paintOrder():Null<Array<Node>> {
		var any = false;
		for (c in children)
			if (c.style.zIndex != 0 || c.style.order != 0) {
				any = true;
				break;
			}
		if (!any) return null;
		inline function tier(n:Node):Int
			return n.style.position != Relative ? 1 : 0;
		return sorted((a, b) -> a.style.zIndex != b.style.zIndex ? a.style.zIndex - b.style.zIndex : tier(a) != tier(b) ? tier(a) - tier(b) : a.style.order - b.style.order);
	}

	// (a stable sort of the children: insertion, children being few)
	function sorted(cmp:(Node, Node) -> Int):Array<Node> {
		var a = children.copy();
		for (i in 1...a.length) {
			var x = a[i], j = i - 1;
			while (j >= 0 && cmp(a[j], x) > 0) {
				a[j + 1] = a[j];
				j--;
			}
			a[j + 1] = x;
		}
		return a;
	}

	// --- queries ---

	// the topmost node under (px, py) in window pixels, among this subtree
	// (clipped by Overflow, through the transforms), or null
	public function hitTest(px:Float, py:Float):Null<Node> {
		if (style.display == None) return null;
		// (nothing of it there)
		if (!inkAll && (px < inkX0 || px >= inkX1 || py < inkY0 || py >= inkY1)) return null;
		var m = transformMatrix();
		if (m != null) {
			var inv = Transform.invert(m);
			if (inv == null) return null;
			var tx = inv[0] * px + inv[2] * py + inv[4];
			py = inv[1] * px + inv[3] * py + inv[5];
			px = tx;
		}
		var inside = px >= absX && py >= absY && px < absX + width && py < absY + height;
		if (!inside && style.overflow != Visible) return null;
		// (absolute and sticky children first: they are drawn over the others)
		var sx = px + (style.overflow == Scroll ? scrollX : 0), sy = py + (style.overflow == Scroll ? scrollY : 0);
		var order = paintOrder();
		if (order != null) {
			var i = order.length;
			while (--i >= 0) {
				var c = order[i].hitTest(sx, sy);
				if (c != null) return c;
			}
			return inside && hittable() ? this : null;
		}
		for (pass in 0...2) {
			var i = children.length;
			while (--i >= 0) {
				if ((children[i].style.position != Relative) != (pass == 0)) continue;
				var c = children[i].hitTest(sx, sy);
				if (c != null) return c;
			}
		}
		return inside && hittable() ? this : null;
	}

	// the bounds of what it and its subtree draw, from its layout (window
	// pixels before scrolling; its children's too unless it clips them;
	// unbounded when it or a child moves by a transform or sticks): paint and
	// hit tests leave out subtrees whose bounds miss them (paint after widening
	// them by what shadows and rings add: Ui.inkMargin)
	@:allow(hxmc.ui) function measureInk() {
		var s = style;
		inkAll = s.transform != null || s.position == Sticky;
		inkX0 = absX;
		inkY0 = absY;
		inkX1 = absX + width;
		inkY1 = absY + height;
		// (content wider or higher than its box: past it on either side, as aligned)
		var c = contentInk();
		if (c != null) {
			var be = s.borderEdges, p = s.padding;
			var ex = c.width - (width - be.horizontal - p.horizontal), ey = c.height - (height - be.vertical - p.vertical);
			if (ex > 0) {
				inkX0 -= ex;
				inkX1 += ex;
			}
			if (ey > 0) inkY1 += ey;
		}
		if (s.overflow == Visible)
			for (k in children) {
				if (k.style.display == None) continue;
				if (k.inkAll) inkAll = true;
				if (k.inkX0 < inkX0) inkX0 = k.inkX0;
				if (k.inkY0 < inkY0) inkY0 = k.inkY0;
				if (k.inkX1 > inkX1) inkX1 = k.inkX1;
				if (k.inkY1 > inkY1) inkY1 = k.inkY1;
			}
		inkStale = false;
	}

	// (a transform or sticking changed: its bounds and its ancestors' measured again at the next update)
	@:allow(hxmc.ui) function inkChanged() {
		var n = this;
		while (n != null && !n.inkStale) {
			n.inkStale = true;
			n = n.parent;
		}
		if (ui != null) ui.requestFrame();
	}

	// what its content draws, from its content box's top left, when it may reach past the box (a text's paragraph)
	// its first baseline below its border box's top, once laid out: a text's
	// first line's, a row's items aligned on theirs, else its first item's
	// (one without any: its bottom edge, as CSS's flexbox synthesizes it);
	// NaN: none (no text, no items)
	public function firstBaseline():Float {
		if (!Math.isNaN(lb)) return lb;
		for (c in inOrder()) {
			var cs = c.style;
			if (cs.display == None || cs.position == Absolute) continue;
			var b = c.firstBaseline();
			return c.ly + (Math.isNaN(b) ? c.lh : b);
		}
		return Math.NaN;
	}

	public function contentInk():Null<Size>
		return null;

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
		if (changed && ui != null) {
			ui.requestFrame();
			restyleLater();
		}
		if (changed) statesChanged();
	}

	// called when its states (hover, press, focus, the focus ring's
	// visibility) or attributes change: hxmc.ui.view.States' signals
	public var onStates:Null<Void->Void> = null;
	// (its States, once made: hxmc.ui.view's)
	@:allow(hxmc.ui.view) var statesOf:Any = null;

	@:allow(hxmc.ui.Ui) function statesChanged() {
		Rules.related(this);
		if (onStates != null) onStates();
	}

	// --- theme ---

	// an attribute (null: not set; "" when it is present without a value)
	public function attr(name:String):Null<String>
		return attrs == null ? null : attrs.get(name);

	// sets an attribute (null: removes it); the rules matching it follow
	public function setAttr(name:String, value:Null<String>) {
		if (attr(name) == value) return;
		if (value == null) attrs.remove(name) else {
			if (attrs == null) attrs = new Map();
			attrs.set(name, value);
		}
		restyleLater();
		// (a group or peer no longer: what its marking styled, again)
		if (value == null && (name == "group" || name == "peer") && parent != null) Rules.restyleTree(parent);
		statesChanged();
	}

	// the theme it is styled by: its own or the nearest ancestor's, else the window's
	public function sheet():Null<StyleSheet> {
		var n = this;
		while (n != null) {
			if (n.theme != null) return n.theme;
			n = n.parent;
		}
		return ui == null ? null : ui.theme;
	}

	function set_slot(v:Null<String>):Null<String> {
		if (v == slot) return v;
		slot = v;
		if (ui != null && v == "body") ui.setBody(this);
		restyleLater();
		return v;
	}

	function set_variant(v:Null<String>):Null<String> {
		if (v == variant) return v;
		variant = v;
		restyleLater();
		return v;
	}

	function set_size(v:Null<String>):Null<String> {
		if (v == size) return v;
		size = v;
		restyleLater();
		return v;
	}

	function set_theme(v:Null<StyleSheet>):Null<StyleSheet> {
		if (v == theme) return v;
		theme = v;
		Rules.restyleTree(this);
		return v;
	}

	// (a theme's colours for its placeholder's text and its selection, null:
	// none; EditableText's)
	function themePseudo(placeholder:Null<Color>, selection:Null<Color>) {}
}

// a node's event handlers (Node.onClick...)
private class Handlers {
	public var onPointerDown:Null<Event->Void> = null;
	public var onPointerUp:Null<Event->Void> = null;
	public var onPointerMove:Null<Event->Void> = null;
	public var onPointerEnter:Null<Event->Void> = null;
	public var onPointerLeave:Null<Event->Void> = null;
	public var onClick:Null<Event->Void> = null;
	public var onActivate:Null<Event->Void> = null;
	public var onWheel:Null<Event->Void> = null;
	public var onKeyDown:Null<Event->Void> = null;
	public var onKeyUp:Null<Event->Void> = null;
	public var onTextInput:Null<Event->Void> = null;
	public var onInput:Null<Event->Void> = null;
	public var onScroll:Null<Void->Void> = null;
	public var onComposition:Null<Event->Void> = null;
	public var onFocus:Null<Event->Void> = null;
	public var onBlur:Null<Event->Void> = null;
	public var onFocusIn:Null<Event->Void> = null;
	public var onFocusOut:Null<Event->Void> = null;
	public var dragData:Dynamic = null;
	public var onDragStart:Null<Event->Void> = null;
	public var onDragOver:Null<Event->Void> = null;
	public var onDragLeave:Null<Event->Void> = null;
	public var onDrop:Null<Event->Void> = null;
	public var onDragEnd:Null<Event->Void> = null;

	public function new() {}
}
