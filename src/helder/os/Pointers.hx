package helder.os;

import helder.os.Event;

// Every pointer, one stream for the mouse, fingers and pens (the DOM's
// Pointer Events): a Pointer per slot, preallocated (MAX), events that
// carry one (PointerDown, PointerMove, PointerUp, PointerCancel: Event.pointer,
// already updated), and per frame what is down and what changed, with
// nothing allocated:
//
//   App.run(frame, e -> switch e.kind {
//     case PointerDown if (e.pointer.type == Touch): grab(e.pointer.id);
//     case PointerCancel: release(e.pointer.id);
//     case _:
//   });
//   for (i in 0...Pointers.count) {           // in a frame: the pointers down
//     var p = Pointers.at(i);
//     if (Pointers.justDown(p)) ...; look(p.dx, p.dy);
//   }
//
// Slot 0 is the mouse (its moves too, a button down or not: the desktop's,
// the browser's), touches and pens take the lowest free slot from 1 on.
// Back ends: Android's MotionEvents (every pointer, their history as
// samples), iOS's UITouches (every finger, coalesced touches as samples),
// the browser's Pointer Events (coalesced events as samples); the mouse on
// X11, Windows and macOS (no touch screens there yet: WM_POINTER and
// XInput2 come later). The mouse keeps its Mouse* events too (sent first),
// and a touch its compatibility events while emulate is on: the first
// finger's tap a click and its drag Scrolls (helder.os.TouchDrag, as before
// there were pointers; with Mods.TOUCH, so that the mouse's pointer is not
// made of them). A program that follows the pointers itself turns emulate
// off (helder.ui's windows do).
class Pointers {
	public static inline var MAX = 16;

	static final slots:Array<Pointer> = [for (i in 0...MAX) new Pointer(i)];
	// the slots down, in the order they went down
	static final order:Array<Int> = [for (_ in 0...MAX) 0];
	// the presses since the last step, and the ends (up or cancelled)
	static final downs:Array<Bool> = [for (_ in 0...MAX) false];
	static final ups:Array<Bool> = [for (_ in 0...MAX) false];
	static var presses = 0;
	// (the event the mouse's pointer events are sent with: the back end's own stays as it is)
	static final event = new Event();

	// how many are down now
	public static var count(default, null) = 0;

	// whether a touch also sends what it did before pointers (a tap's
	// MouseMove, MouseDown and MouseUp, a drag's Scrolls: TouchDrag), for
	// the first finger: on by default
	// (the browser's side decides a tap's click itself: CanvasWindow tells it before each frame's events)
	public static var emulate = true;

	// the pointer of slot id (0 the mouse)
	public static inline function get(id:Int):Pointer
		return slots[id];

	// the i-th pointer down now, by the order they went down
	public static inline function at(i:Int):Pointer
		return slots[order[i]];

	// a frame begins (App.run's turns, before the events): dx and dy start
	// again, and what justDown, justUp and cancelled answer
	public static function step() {
		for (i in 0...MAX) {
			slots[i].frame();
			downs[i] = ups[i] = false;
		}
	}

	// went down since the last step (also when it is up again)
	public static inline function justDown(p:Pointer):Bool
		return downs[p.id];

	// went up or was cancelled since the last step
	public static inline function justUp(p:Pointer):Bool
		return ups[p.id];

	// its last press was cancelled (the system took it)
	public static inline function cancelled(p:Pointer):Bool
		return p.phase == Cancel;

	// --- the back ends' side

	// the pointer down whose system id is key (null: none)
	@:allow(helder.os) static function find(key:Int, type:PointerType):Null<Pointer> {
		for (i in 1...MAX) {
			var p = slots[i];
			if (p.down && p.key == key && p.type == type) return p;
		}
		return null;
	}

	// a touch or a pen down: its slot (null: every slot taken, ignored)
	@:allow(helder.os) static function press(window:Window, key:Int, type:PointerType, x:Float, y:Float, pressure:Float, time:Float):Null<Pointer> {
		var stale = find(key, type);
		if (stale != null) lift(stale, true, time);
		for (i in 1...MAX) {
			var p = slots[i];
			if (p.down) continue;
			var primary = true;
			for (j in 1...MAX)
				if (slots[j].down) primary = false;
			p.pressAt(window, type, x, y, pressure, 1, time, primary, ++presses);
			p.key = key;
			pressed(p);
			return p;
		}
		return null;
	}

	@:allow(helder.os) static function lift(p:Pointer, cancelled:Bool, time:Float) {
		if (!p.down) return;
		p.lift(cancelled, time);
		ups[p.id] = true;
		var k = order.indexOf(p.id);
		if (k >= 0 && k < count) {
			for (j in k...count - 1)
				order[j] = order[j + 1];
			count--;
		}
	}

	static function pressed(p:Pointer) {
		downs[p.id] = true;
		order[count++] = p.id;
	}

	// e as one of p's events
	@:allow(helder.os) static function fill(e:Event, kind:EventKind, p:Pointer, button = 0, mods = 0) {
		e.kind = kind;
		e.window = p.window;
		e.pointer = p;
		e.x = Math.round(p.x);
		e.y = Math.round(p.y);
		e.button = button;
		e.mods = mods;
		e.deltaX = e.deltaY = 0;
		e.text = "";
		e.key = 0;
	}

	// the event loop's callback with the mouse's pointer events after its
	// Mouse* events (App.run's: one closure for the run)
	@:allow(helder.os) static function relay(onEvent:Event->Void):Event->Void
		return e -> {
			onEvent(e);
			if ((e.kind == MouseMove || e.kind == MouseDown || e.kind == MouseUp) && e.mods & Mods.TOUCH == 0 && mouse(e))
				onEvent(event);
		};

	// the mouse's pointer (slot 0) after one of its events: whether event is
	// its pointer event to send (a press of the first button down, the release
	// of the last, a move)
	@:allow(helder.os) static function mouse(e:Event):Bool {
		var p = slots[0], time = haxe.Timer.stamp() * 1000;
		// (the DOM's buttons: left 1, right 2, middle 4)
		var bit = e.button == 1 ? 1 : e.button == 3 ? 2 : e.button == 2 ? 4 : 0;
		var kind:EventKind = None;
		switch e.kind {
			case MouseDown:
				if (bit == 0) return false;
				if (!p.down) {
					p.pressAt(e.window, Mouse, e.x, e.y, 0.5, bit, time, true, ++presses);
					p.key = 0;
					pressed(p);
					kind = PointerDown;
				} else {
					// (another button: a move with its buttons changed, as the DOM's chords)
					p.setButtons(p.buttons | bit, 0.5);
					p.moveTo(e.x, e.y, 0.5, time);
					kind = PointerMove;
				}
			case MouseUp:
				if (!p.down || p.buttons & bit == 0) return false;
				p.setButtons(p.buttons & ~bit, 0.5);
				p.moveTo(e.x, e.y, 0.5, time);
				if (p.buttons == 0) {
					lift(p, false, time);
					kind = PointerUp;
				} else kind = PointerMove;
			case _:
				p.setWindow(e.window);
				p.moveTo(e.x, e.y, p.down ? 0.5 : 0, time);
				kind = PointerMove;
		}
		fill(event, kind, p, e.kind == MouseMove ? 0 : e.button, e.mods);
		return true;
	}

	// every pointer of window let go (its touches cancelled: the app went to
	// the background, the window closed); their PointerCancels sent
	@:allow(helder.os) static function cancelAll(window:Null<Window>, e:Event, onEvent:Null<Event->Void>) {
		for (i in 1...MAX) {
			var p = slots[i];
			if (!p.down || (window != null && p.window != window)) continue;
			lift(p, true, p.time);
			if (onEvent == null) continue;
			fill(e, PointerCancel, p);
			onEvent(e);
		}
	}

	// (tests: every slot up, nothing pressed)
	@:allow(helder.os) static function reset() {
		for (p in slots) {
			if (p.down) lift(p, true, p.time);
			p.frame();
		}
		step();
	}
}
