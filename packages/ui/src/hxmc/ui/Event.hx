package hxmc.ui;

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
	// TextInput: the characters typed (an IME's composed text, too);
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

	public function new(type:EventType, target:Node, x:Float, y:Float) {
		this.type = type;
		this.target = target;
		this.x = x;
		this.y = y;
		current = target;
	}

	// the pointer relative to current's border box (Node.localX: through scrolling and transforms)
	public var localX(get, never):Float;
	public var localY(get, never):Float;

	function get_localX()
		return current.localX(x, y);

	function get_localY()
		return current.localY(x, y);

	public inline function stop()
		stopped = true;

	public inline function preventDefault()
		defaultPrevented = true;

	@:allow(hxmc.ui.Ui) function at(n:Node):Event {
		current = n;
		return this;
	}
}
