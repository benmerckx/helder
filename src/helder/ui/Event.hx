package helder.ui;

enum abstract EventType(Int) {
	var PointerDown;
	var PointerUp;
	var PointerMove;
	var PointerEnter;
	var PointerLeave;
	var Click;
	var Wheel;
	var KeyDown;
	var KeyUp;
	var TextInput;
	var Composition;
	var Focus;
	var Blur;
	// drag and drop (Node.dragData): the source's start and end, a target's
	// over (preventDefault accepts the drop), leave and drop
	var DragStart;
	var DragOver;
	var DragLeave;
	var Drop;
	var DragEnd;
	// the focus came into a node or its subtree, or left it: as Focus and
	// Blur, but bubbling (the DOM's focusin, focusout)
	var FocusIn;
	var FocusOut;
	// a text field's text changed by its user (text: its text now), as the DOM's input
	var Input;
}

// An event as Ui dispatches it: to the target, then (unless stopped) to
// each ancestor (current), except PointerEnter, PointerLeave, Focus and
// Blur, which each node gets for itself.
class Event {
	public final type:EventType;
	public final target:Node;
	// the node whose handler runs
	public var current(default, null):Node;
	// the pointer in window pixels (pointer events; else where it was last)
	public final x:Float;
	public final y:Float;
	// pointer buttons: 1 left, 2 middle, 3 right
	public var button = 0;
	// KeyDown, KeyUp: the key (Key) and the modifiers (Key.MOD_*)
	public var key = 0;
	public var mods = 0;
	// TextInput: the characters typed (an IME's composed text, too); Input: the field's text;
	// Composition: an input method's text not committed yet (empty: none)
	public var text = "";
	// Composition: the caret in text (UTF-16)
	public var caret = 0;
	// Wheel: the scroll in pixels (down and right positive)
	// drag and drop: what is dragged (the source's dragData); DragEnd: whether it was dropped
	public var data:Dynamic = null;
	public var dropped = false;
	public var deltaX = 0.0;
	public var deltaY = 0.0;
	public var stopped(default, null) = false;
	// the default action (Tab moving the focus, the wheel scrolling) is not taken
	public var defaultPrevented(default, null) = false;

	// (made by of: a page's code using an event's fields keeps its class,
	// its constructor with it, and so none of a Node's methods)
	function new(type:EventType, target:Node, x:Float, y:Float) {
		this.type = type;
		this.target = target;
		this.x = x;
		this.y = y;
	}

	// an event of type at target, the pointer at x, y in the window's coordinates
	public static function of(type:EventType, target:Node, x:Float, y:Float):Event
		return new Event(type, target, x, y).at(target);

	// the pointer relative to current's border box (Node.localX: through
	// scrolling and transforms; fields, so that a handler's untyped event
	// reads them too)
	public var localX(default, null) = 0.0;
	public var localY(default, null) = 0.0;

	public inline function stop()
		stopped = true;

	public inline function preventDefault()
		defaultPrevented = true;

	@:allow(helder.ui.Ui) function at(n:Node):Event {
		current = n;
		localX = n.localX(x, y);
		localY = n.localY(x, y);
		return this;
	}
}
