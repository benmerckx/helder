package helder.ui.gesture;

import helder.os.PointerType;

// A gesture recogniser on a node (Node.addGesture; markup's onTap, onPan,
// onPinch and onScale make them): a state machine fed the pointers pressed
// on its node or inside it, competing for each pointer in an arena
// (Flutter's model; Ui keeps one per pointer). At a press Ui collects the
// recognisers from the node pressed up to the root, the innermost first (a
// scroller's own drag last, for the first finger); the first to accept
// (past its slop, a second finger for a pinch) wins the pointer and the
// others lose it; at the release a Tap still in it wins. A click is a
// press no other gesture won (Ui). The handler (onGesture) gets the
// recogniser itself, reused (use-gesture's state): its fields are the
// gesture's now, copy what must outlive the call. Positions in its node's
// coordinates (Node.localX: through scrolling and transforms), distances in
// points, speeds in points a second, angles in radians (clockwise: y down).
class Gesture {
	// the pointers one follows at most
	public static inline var MAX = 10;
	// a press moved this far (points) is no longer a tap (Android's 8 dp,
	// helder.os.TouchDrag's; iOS's about 10, Flutter's 18)
	public static inline var SLOP = 8.0;

	public var node(default, null):Null<Node> = null;
	public var state(default, null):GestureState = Possible;
	public var onGesture:Null<Gesture->Void> = null;
	public var enabled = true;
	public var slop = SLOP;
	// the focus (its pointers' centroid), node-local
	public var x(default, null) = 0.0;
	public var y(default, null) = 0.0;
	// the focus's motion since the last call, since it began, its speed
	public var dx(default, null) = 0.0;
	public var dy(default, null) = 0.0;
	public var tx(default, null) = 0.0;
	public var ty(default, null) = 0.0;
	public var vx(default, null) = 0.0;
	public var vy(default, null) = 0.0;
	// the pointers' spread from the focus against when it began (Scale), and since the last call
	public var scale(default, null) = 1.0;
	public var dscale(default, null) = 1.0;
	// the turn of its first two pointers since it began, and since the last call
	public var angle(default, null) = 0.0;
	public var dangle(default, null) = 0.0;
	// how many pointers it follows now
	public var pointers(default, null) = 0;
	public var pointerType(default, null):PointerType = Touch;
	// the mouse's button that pressed (1 for a finger or a pen)
	public var button(default, null) = 1;
	// a Tap's taps (1)
	public var taps(default, null) = 0;

	// (the pointers followed: their ids and positions in the window's points)
	final ids:Array<Int> = [for (_ in 0...MAX) -1];
	final px:Array<Float> = [for (_ in 0...MAX) 0.0];
	final py:Array<Float> = [for (_ in 0...MAX) 0.0];
	// (the focus, the spread and the angle now; as of the last move or a
	// change of the pointers: what a move adds up from, so that a finger
	// put down or lifted makes no jump)
	var fx = 0.0;
	var fy = 0.0;
	var span = 0.0;
	var turn = 0.0;
	var lastFx = 0.0;
	var lastFy = 0.0;
	var lastSpan = 0.0;
	var lastTurn = 0.0;
	// (the motion since the press, and not yet reported)
	var travelX = 0.0;
	var travelY = 0.0;
	var pendX = 0.0;
	var pendY = 0.0;
	var pendScale = 1.0;
	var pendTurn = 0.0;
	var time = 0.0;

	public function new() {}

	// the id of its i-th pointer (0 the mouse, else a finger's or a pen's slot)
	public inline function pointerAt(i:Int):Int
		return ids[i];

	// whether it is under way (Began or Changed)
	public var active(get, never):Bool;

	inline function get_active():Bool
		return state == Began || state == Changed;

	// gives up: its pointers back to their arenas (the others may still win
	// them); under way, it ends Cancelled
	public function cancel() {
		var u = owner();
		if (active) report(Cancelled);
		if (u != null) @:privateAccess u.leaveGesture(this);
		clear();
	}

	// --- what a recogniser decides (Tap, Pan, Scale)

	// whether it joins the arena of a pointer pressed on its node
	function wants(type:PointerType, button:Int):Bool
		return enabled && pointers < MAX;

	// its pointers moved (the focus, the spread and the angle updated)
	function moved() {}

	// one of its pointers lifted (or was cancelled), still counted
	function lifted(cancelled:Bool) {}

	// a pointer was put down, already counted
	function added() {}

	// a pointer went to another recogniser, no longer counted
	function lost() {}

	// claims every pointer it follows: whether it has them all now (none
	// won by another before)
	function accept():Bool {
		var u = owner();
		return u == null || @:privateAccess u.acceptGesture(this);
	}

	// (the Ui whose arenas it is in)
	function owner():Null<Ui>
		return node == null ? null : node.ui;

	// leaves every arena it is in (Failed while Possible)
	function fail() {
		if (state == Possible) state = Failed;
		cancel();
	}

	// state now, the handler told
	function report(s:GestureState) {
		state = s;
		var n = node;
		x = n == null ? fx : n.localX(fx, fy);
		y = n == null ? fy : n.localY(fx, fy);
		dx = pendX;
		dy = pendY;
		dscale = pendScale;
		dangle = pendTurn;
		if (s == Began) {
			tx = ty = angle = 0;
			scale = 1;
		}
		tx += dx;
		ty += dy;
		scale *= dscale;
		angle += dangle;
		pendX = pendY = pendTurn = 0;
		pendScale = 1;
		if (onGesture != null) onGesture(this);
	}

	// how far the focus went since the press
	inline function travel():Float
		return Math.sqrt(travelX * travelX + travelY * travelY);

	// --- the arena's side (Ui)

	@:allow(helder.ui) function attachTo(n:Null<Node>) {
		if (n != node && pointers > 0) cancel();
		node = n;
	}

	@:allow(helder.ui) function follows(id:Int):Bool
		return ids.indexOf(id) >= 0 && ids.indexOf(id) < pointers;

	@:allow(helder.ui) function join(id:Int, type:PointerType, button:Int):Bool {
		if (follows(id) || !wants(type, button)) return false;
		if (state == Failed || state == Ended || state == Cancelled) state = Possible;
		if (pointers == 0) {
			pointerType = type;
			this.button = button;
			travelX = travelY = pendX = pendY = pendTurn = 0;
			pendScale = 1;
			vx = vy = 0;
			taps = 0;
		}
		ids[pointers++] = id;
		return true;
	}

	@:allow(helder.ui) function down(id:Int, x:Float, y:Float, time:Float) {
		var i = ids.indexOf(id);
		if (i < 0 || i >= pointers) return;
		px[i] = x;
		py[i] = y;
		this.time = time;
		measure();
		rebase();
		added();
	}

	@:allow(helder.ui) function move(id:Int, x:Float, y:Float, time:Float) {
		var i = ids.indexOf(id);
		if (i < 0 || i >= pointers || (px[i] == x && py[i] == y)) return;
		px[i] = x;
		py[i] = y;
		measure();
		var mx = fx - lastFx, my = fy - lastFy, dt = time - this.time;
		travelX += mx;
		travelY += my;
		pendX += mx;
		pendY += my;
		if (lastSpan > 0 && span > 0) pendScale *= span / lastSpan;
		if (pointers > 1) {
			var a = turn - lastTurn;
			// (the shorter way round)
			if (a > Math.PI) a -= 2 * Math.PI else if (a < -Math.PI) a += 2 * Math.PI;
			pendTurn += a;
		}
		if (dt > 0) {
			vx = 0.8 * (mx / dt) + 0.2 * vx;
			vy = 0.8 * (my / dt) + 0.2 * vy;
		}
		this.time = time;
		rebase();
		moved();
	}

	@:allow(helder.ui) function up(id:Int, time:Float, cancelled:Bool) {
		var i = ids.indexOf(id);
		if (i < 0 || i >= pointers) return;
		this.time = time;
		lifted(cancelled);
		remove(i);
	}

	@:allow(helder.ui) function lose(id:Int) {
		var i = ids.indexOf(id);
		if (i < 0 || i >= pointers) return;
		remove(i);
		lost();
	}

	function remove(i:Int) {
		for (j in i...pointers - 1) {
			ids[j] = ids[j + 1];
			px[j] = px[j + 1];
			py[j] = py[j + 1];
		}
		ids[--pointers] = -1;
		if (pointers > 0) {
			measure();
			rebase();
		} else if (state != Possible && !active) state = Possible;
	}

	function clear() {
		for (i in 0...pointers)
			ids[i] = -1;
		pointers = 0;
		if (!active) state = Possible;
	}

	// (the focus, the spread from it, the angle from the first pointer to the second)
	function measure() {
		var sx = 0.0, sy = 0.0;
		for (i in 0...pointers) {
			sx += px[i];
			sy += py[i];
		}
		fx = sx / pointers;
		fy = sy / pointers;
		var s = 0.0;
		for (i in 0...pointers)
			s += Math.sqrt((px[i] - fx) * (px[i] - fx) + (py[i] - fy) * (py[i] - fy));
		span = s / pointers;
		turn = pointers > 1 ? Math.atan2(py[1] - py[0], px[1] - px[0]) : 0;
	}

	inline function rebase() {
		lastFx = fx;
		lastFy = fy;
		lastSpan = span;
		lastTurn = turn;
	}
}
