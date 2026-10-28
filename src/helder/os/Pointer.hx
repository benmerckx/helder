package helder.os;

// A pointer: the mouse, a finger or a pen (type), one of Pointers' slots,
// preallocated and refilled (copy what must outlive a frame). Its id is the
// slot: small and dense (0 the mouse, touches and pens from 1), stable from
// its press to its release, and given to another one after it. Positions in
// the window's pixels from its top left, sub-pixel where the system has them.
// Pointer events (Event.pointer: PointerDown, PointerMove, PointerUp,
// PointerCancel) carry it, already updated; Pointers answers per frame.
class Pointer {
	// coalesced samples kept per slot (the latest)
	public static inline var SAMPLES = 8;

	public final id:Int;
	public var type(default, null):PointerType = Mouse;
	// the window it went down in (the mouse: the last one it moved over)
	public var window(default, null):Null<Window> = null;
	// its last change
	public var phase(default, null):PointerPhase = None;
	// down now (between its PointerDown and its PointerUp or PointerCancel)
	public var down(default, null) = false;
	// the first touch down while no other was (or the mouse): what a
	// single-pointer program follows
	public var primary(default, null) = false;
	public var x(default, null) = 0.0;
	public var y(default, null) = 0.0;
	// where its press began
	public var startX(default, null) = 0.0;
	public var startY(default, null) = 0.0;
	// its motion since the last frame (Pointers.step)
	public var dx(default, null) = 0.0;
	public var dy(default, null) = 0.0;
	// 0 to 1: a finger's or a pen's force where the system measures it (1
	// where it does not), the mouse's 0.5 while a button is down, else 0
	public var pressure(default, null) = 0.0;
	// a pen's tilt from the screen's normal, degrees (-90 to 90; 0 for the others)
	public var tiltX(default, null) = 0.0;
	public var tiltY(default, null) = 0.0;
	// the mouse's (a pen's) buttons held: bit 0 left, 1 right, 2 middle
	// (the DOM's buttons); a finger down: 1
	public var buttons(default, null) = 0;
	// its last change's time (ms, the system's clock: only differences count)
	public var time(default, null) = 0.0;
	// its press's number (counted across the slots): a press and its release
	// within one step still tell a reader polling once a step that one came
	public var press(default, null) = 0;
	// who has it (cleared at each press): ui, a game control, nobody yet
	public var owner:PointerOwner = None;
	// the samples the system batched since the last event of this pointer
	// (Android's history, iOS's coalesced touches, the browser's coalesced
	// events), oldest first, the last one its position; at most SAMPLES
	public var samples(default, null) = 0;

	// (the system's own id while down: an Android pointer id, a UITouch's
	// address, the browser's pointerId)
	@:allow(helder.os) var key = -1;
	// (the samples' ring and its first; the next sample starts a new batch)
	final sx:Array<Float> = [for (_ in 0...SAMPLES) 0.0];
	final sy:Array<Float> = [for (_ in 0...SAMPLES) 0.0];
	final st:Array<Float> = [for (_ in 0...SAMPLES) 0.0];
	var first = 0;
	var batched = true;

	@:allow(helder.os) function new(id:Int) {
		this.id = id;
	}

	// sample i (0: the oldest) of the last event's
	public inline function sampleX(i:Int):Float
		return sx[(first + i) % SAMPLES];

	public inline function sampleY(i:Int):Float
		return sy[(first + i) % SAMPLES];

	public inline function sampleTime(i:Int):Float
		return st[(first + i) % SAMPLES];

	// (a batched sample on the way to the next event)
	@:allow(helder.os) function sample(x:Float, y:Float, time:Float) {
		if (batched) {
			batched = false;
			samples = 0;
			first = 0;
		}
		var i = (first + samples) % SAMPLES;
		if (samples == SAMPLES) first = (first + 1) % SAMPLES else samples++;
		sx[i] = x;
		sy[i] = y;
		st[i] = time;
	}

	@:allow(helder.os) function pressAt(window:Window, type:PointerType, x:Float, y:Float, pressure:Float, buttons:Int, time:Float, primary:Bool, press:Int) {
		this.window = window;
		this.type = type;
		this.primary = primary;
		this.press = press;
		owner = None;
		phase = Down;
		down = true;
		startX = this.x = x;
		startY = this.y = y;
		this.pressure = pressure;
		this.buttons = buttons;
		this.time = time;
		tiltX = tiltY = 0;
		batched = true;
		sample(x, y, time);
		batched = true;
	}

	@:allow(helder.os) function moveTo(x:Float, y:Float, pressure:Float, time:Float) {
		sample(x, y, time);
		batched = true;
		dx += x - this.x;
		dy += y - this.y;
		this.x = x;
		this.y = y;
		this.pressure = pressure;
		this.time = time;
		phase = Move;
	}

	@:allow(helder.os) function lift(cancelled:Bool, time:Float) {
		phase = cancelled ? Cancel : Up;
		down = false;
		pressure = 0;
		buttons = 0;
		this.time = time;
		key = -1;
	}

	@:allow(helder.os) function tilt(x:Float, y:Float) {
		tiltX = x;
		tiltY = y;
	}

	@:allow(helder.os) function setButtons(b:Int, pressure:Float) {
		buttons = b;
		this.pressure = pressure;
	}

	@:allow(helder.os) function setWindow(w:Window)
		window = w;

	@:allow(helder.os) inline function frame() {
		dx = dy = 0;
	}
}
