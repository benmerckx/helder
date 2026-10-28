package helder.scene.input;

import helder.gfx.shader.Vec2;
import helder.os.Event;
import helder.os.Gamepads;
import helder.os.Pointer;
import helder.os.Pointers;

// Named actions bound to input (Binding: keys, mouse buttons, screen
// regions, pairs of keys as axes, gamepads, fingers: touch zones, a look
// zone's drag, on-screen sticks and buttons), read once per simulation
// step so that input and the simulation agree (a press and its release
// within one step still count as a press):
//
//   var actions = new Actions();
//   final move = new VirtualStick({zone: Zone.rect(0, 0.4, 0.5, 1), radius: 60});
//   final fire = new VirtualButton({zone: Zone.circle(0.88, 0.8, 40)});
//   actions.bind("jump", Key(0x20)).bind("jump", Region(0.75, 0.6, 1, 1));
//   actions.bind("moveX", KeyAxis(0xFF51, 0xFF53)).bind("moveX", Stick(move, 0)).bind("moveX", PadAxis(0, 1));
//   actions.bind("lookX", TouchDelta(0, Zone.rect(0.5, 0, 1, 1), 0.3)).bind("fire", Button(fire)).bind("fire", PadButton(7));
//   App.run(..., e -> actions.event(e));
//   clock.advance(dt, step -> {
//     actions.step();
//     if (actions.pressed("jump")) ...;
//     player.x += actions.axis("moveX") * speed * step;
//   });
//
// Bindings are data (rebind at run time with unbind and bind). Gamepads:
// PadButton and PadAxis, read at each step from helder.os.Gamepads (which
// Stages.frame polls; Gamepads.set feeds an on-screen stick). Fingers and
// pens: read at each step from helder.os.Pointers, each press taken by
// the first control whose zone it began in (sticks, buttons and Touch
// zones first, then TouchDelta's look zones), if nobody had it (not the
// ui's: a press on a ui button is the ui's, Pointer.owner), and held by it
// until it lifts or is cancelled (a cancel lets go: the player stops). A
// zone shared by bindings is one control (equal zones). Nothing
// is allocated per event or per step.
class Actions {
	final names:Array<String> = [];
	final bindings:Array<Array<Binding>> = [];
	// per action and binding: held (a region, a pad's button, a Button's or a
	// Touch's), and the presses of its control seen
	final bindingHeld:Array<Array<Bool>> = [];
	final bindingSeen:Array<Array<Int>> = [];
	// per action: how many of its bindings are down now; presses and
	// releases since the last step; the last step's view
	final down:Array<Int> = [];
	final pressEvents:Array<Int> = [];
	final releaseEvents:Array<Int> = [];
	final pressedNow:Array<Bool> = [];
	final releasedNow:Array<Bool> = [];
	final heldNow:Array<Bool> = [];
	final axisValue:Array<Float> = [];
	// what is held: keys and mouse buttons
	final keys:Array<Int> = [];
	final buttons:Array<Int> = [];
	var pointerDown = false;
	var px = 0.0;
	var py = 0.0;
	var width = 1.0;
	var height = 1.0;
	// a stick's travel taken as rest (its axes' first 0.15)
	public var deadZone = 0.15;

	// the touch controls: sticks, buttons and Touch zones (taking a press
	// first), then the look zones; the control holding each pointer, the
	// press of it seen
	final controls:Array<TouchControl> = [];
	final looks:Array<LookZone> = [];
	final claims:Array<Null<TouchControl>> = [for (_ in 0...Pointers.MAX) null];
	final seen:Array<Int> = [for (_ in 0...Pointers.MAX) 0];

	public function new() {}

	function index(action:String):Int {
		var k = names.indexOf(action);
		if (k >= 0) return k;
		names.push(action);
		bindings.push([]);
		bindingHeld.push([]);
		bindingSeen.push([]);
		down.push(0);
		pressEvents.push(0);
		releaseEvents.push(0);
		pressedNow.push(false);
		releasedNow.push(false);
		heldNow.push(false);
		axisValue.push(0);
		return names.length - 1;
	}

	public function bind(action:String, b:Binding):Actions {
		var k = index(action);
		bindings[k].push(b);
		bindingHeld[k].push(false);
		bindingSeen[k].push(0);
		// (its control, once: a zone's shared by the bindings naming it)
		switch b {
			case Touch(zone):
				if (touchZone(zone) == null) controls.push(new TouchZone(zone));
			case TouchDelta(_, zone, _):
				if (lookZone(zone) == null) looks.push(new LookZone(zone));
			case Stick(s, _):
				if (controls.indexOf(s) < 0) controls.push(s);
			case Button(c):
				if (controls.indexOf(c) < 0) controls.push(c);
			case _:
		}
		return this;
	}

	// all of an action's bindings removed
	public function unbind(action:String):Actions {
		var k = names.indexOf(action);
		if (k >= 0) {
			bindings[k] = [];
			bindingHeld[k] = [];
			bindingSeen[k] = [];
			down[k] = 0;
		}
		return this;
	}

	// the window's size, for Region bindings (by default the event's window)
	// and the zones of a pointer without a window
	public function setSize(width:Float, height:Float) {
		this.width = width;
		this.height = height;
	}

	// an event from helder.os's loop
	public function event(e:Event) {
		switch e.kind {
			case KeyDown:
				if (keys.indexOf(e.key) < 0) {
					keys.push(e.key);
					keyChanged(e.key, true);
				}
			case KeyUp:
				if (keys.remove(e.key)) keyChanged(e.key, false);
			case MouseDown:
				if (e.window != null) setSize(e.window.width, e.window.height);
				if (buttons.indexOf(e.button) < 0) {
					buttons.push(e.button);
					mouseChanged(e.button, true);
				}
				if (e.button == 1) {
					pointerDown = true;
					pointer(e.x, e.y);
				}
			case MouseUp:
				if (buttons.remove(e.button)) mouseChanged(e.button, false);
				if (e.button == 1) {
					pointerDown = false;
					pointer(e.x, e.y);
				}
			case MouseMove:
				if (pointerDown) pointer(e.x, e.y);
			case _:
		}
		axes();
	}

	// (an action's binding went down or up: its count)
	inline function press(k:Int)
		if (down[k]++ == 0) pressEvents[k]++;

	inline function release(k:Int)
		if (down[k] > 0 && --down[k] == 0) releaseEvents[k]++;

	function keyChanged(key:Int, isDown:Bool) {
		for (k in 0...names.length)
			for (b in bindings[k])
				switch b {
					case Key(n) if (n == key): isDown ? press(k) : release(k);
					case _:
				}
	}

	function mouseChanged(button:Int, isDown:Bool) {
		for (k in 0...names.length)
			for (b in bindings[k])
				switch b {
					case Mouse(n) if (n == button): isDown ? press(k) : release(k);
					case _:
				}
	}

	// the regions under the pointer (held while it is down inside them)
	function pointer(x:Float, y:Float) {
		px = x / width;
		py = y / height;
		for (k in 0...names.length)
			for (i in 0...bindings[k].length)
				switch bindings[k][i] {
					case Region(x0, y0, x1, y1):
						var inside = pointerDown && px >= x0 && px <= x1 && py >= y0 && py <= y1;
						var was = bindingHeld[k][i];
						if (inside && !was) {
							bindingHeld[k][i] = true;
							press(k);
						} else if (!inside && was) {
							bindingHeld[k][i] = false;
							release(k);
						}
					case _:
				}
	}

	// the gamepads' buttons (Gamepads, as last polled: Stages.frame polls),
	// the touch controls' (Button, Touch: their presses since the last step)
	function pads() {
		for (k in 0...names.length)
			for (i in 0...bindings[k].length) {
				var now = false, presses = -1;
				switch bindings[k][i] {
					case PadButton(b):
						for (p in 0...Gamepads.MAX)
							if (Gamepads.button(p, b)) now = true;
					case Button(c):
						now = c.down;
						presses = c.presses;
					case Touch(zone):
						var z = touchZone(zone);
						now = z.held > 0;
						presses = z.presses;
					case _:
						continue;
				}
				var was = bindingHeld[k][i];
				// (a press since the last step, maybe released again: down and up)
				if (presses >= 0 && presses != bindingSeen[k][i]) {
					bindingSeen[k][i] = presses;
					if (!was) {
						press(k);
						was = true;
					}
				}
				if (now && !was) press(k) else if (!now && was) release(k);
				bindingHeld[k][i] = now;
			}
	}

	// the fingers and pens since the last step (helder.os.Pointers): new
	// presses offered to the controls, the held ones followed
	function touches() {
		for (i in 0...Pointers.MAX) {
			var p = Pointers.get(i);
			if (p.type == helder.os.PointerType.Mouse) continue;
			var w = p.window, ww = w == null ? width : w.width, wh = w == null ? height : w.height, s = p.scale;
			if (p.press != seen[i]) {
				// (a new press: the last one's end missed, its control let go)
				seen[i] = p.press;
				var old = claims[i];
				claims[i] = null;
				if (old != null) @:privateAccess old.lift(p, true);
				if (p.owner == helder.os.PointerOwner.None) claims[i] = offer(p, ww, wh, s);
			}
			var c = claims[i];
			if (c == null) continue;
			if (p.down) @:privateAccess c.follow(p, s) else {
				@:privateAccess c.lift(p, p.phase == helder.os.PointerPhase.Cancel);
				claims[i] = null;
			}
		}
	}

	// (the first control that takes p's press: the sticks, buttons and Touch zones, then the look zones)
	function offer(p:Pointer, w:Float, h:Float, s:Float):Null<TouchControl> {
		for (c in controls)
			if (@:privateAccess c.wants(p, w, h, s)) return take(c, p, w, h, s);
		for (c in looks)
			if (@:privateAccess c.wants(p, w, h, s)) return take(c, p, w, h, s);
		return null;
	}

	function take(c:TouchControl, p:Pointer, w:Float, h:Float, s:Float):TouchControl {
		p.owner = helder.os.PointerOwner.Control;
		@:privateAccess c.take(p, w, h, s);
		return c;
	}

	function touchZone(zone:Zone):Null<TouchZone> {
		for (c in controls)
			if (c.zone.equals(zone) && Std.isOfType(c, TouchZone)) return cast c;
		return null;
	}

	function lookZone(zone:Zone):Null<LookZone> {
		for (c in looks)
			if (c.zone.equals(zone)) return c;
		return null;
	}

	function axes() {
		for (k in 0...names.length) {
			var v = 0.0, look = 0.0;
			for (b in bindings[k])
				switch b {
					case KeyAxis(neg, pos):
						if (keys.indexOf(neg) >= 0) v -= 1;
						if (keys.indexOf(pos) >= 0) v += 1;
					case PadAxis(a, scale):
						// (the pad pushed furthest, past the dead zone, rescaled to 0..1)
						var best = 0.0;
						for (p in 0...Gamepads.MAX) {
							var x = Gamepads.axis(p, a);
							if (Math.abs(x) > Math.abs(best)) best = x;
						}
						var m = Math.abs(best);
						if (m > deadZone) v += (best < 0 ? -1 : 1) * (m - deadZone) / (1 - deadZone) * scale;
					case Stick(s, a):
						v += a == 0 ? s.x : s.y;
					case TouchDelta(a, zone, scale):
						var z = lookZone(zone);
						look += (a == 0 ? z.stepX : z.stepY) * scale;
					case _:
				}
			// (a look's drag is a distance, not a tilt: not clamped)
			axisValue[k] = Math.max(-1, Math.min(1, v)) + look;
		}
	}

	// a simulation step begins: what happened since the last one becomes
	// what pressed, released and held answer
	public function step() {
		touches();
		for (l in looks)
			l.close();
		pads();
		axes();
		for (k in 0...names.length) {
			pressedNow[k] = pressEvents[k] > 0;
			releasedNow[k] = releaseEvents[k] > 0;
			heldNow[k] = down[k] > 0;
			pressEvents[k] = releaseEvents[k] = 0;
		}
	}

	// went down since the last step (also when it went up again)
	public function pressed(action:String):Bool {
		var k = names.indexOf(action);
		return k >= 0 && pressedNow[k];
	}

	public function released(action:String):Bool {
		var k = names.indexOf(action);
		return k >= 0 && releasedNow[k];
	}

	// down at the step
	public function held(action:String):Bool {
		var k = names.indexOf(action);
		return k >= 0 && heldNow[k];
	}

	// an axis action's value now: KeyAxis, PadAxis and Stick from -1 to 1,
	// plus TouchDelta's drag over the last step (points times its scale)
	public function axis(action:String):Float {
		var k = names.indexOf(action);
		return k >= 0 ? axisValue[k] : 0;
	}

	// two axes as a vector (x right, y up), of length 1 at most
	public function stick(x:String, y:String):Vec2 {
		var v = new Vec2(axis(x), axis(y));
		var l = Math.sqrt(v.x * v.x + v.y * v.y);
		return l > 1 ? v / l : v;
	}
}

// (Touch(zone)'s control: held while a finger whose press began in it is
// down, wherever it goes; any number of fingers)
private class TouchZone extends TouchControl {
	public var held(default, null) = 0;
	public var presses(default, null) = 0;

	public function new(zone:Zone)
		super(zone);

	override function wants(p:Pointer, width:Float, height:Float, scale:Float):Bool
		return zone.contains(p.startX, p.startY, width, height, scale);

	override function take(p:Pointer, width:Float, height:Float, scale:Float) {
		if (held++ == 0) presses++;
		tell();
	}

	override function lift(p:Pointer, cancelled:Bool) {
		if (held > 0) held--;
		tell();
	}
}

// (TouchDelta's control: the drags of the fingers whose presses began in
// it, in points, added up over a step; any number of fingers)
private class LookZone extends TouchControl {
	final lastX:Array<Float> = [for (_ in 0...Pointers.MAX) 0.0];
	final lastY:Array<Float> = [for (_ in 0...Pointers.MAX) 0.0];
	var sumX = 0.0;
	var sumY = 0.0;
	var scale = 1.0;
	// the last step's drag
	public var stepX(default, null) = 0.0;
	public var stepY(default, null) = 0.0;

	public function new(zone:Zone)
		super(zone);

	override function wants(p:Pointer, width:Float, height:Float, scale:Float):Bool
		return zone.contains(p.startX, p.startY, width, height, scale);

	override function take(p:Pointer, width:Float, height:Float, scale:Float) {
		// (from where it came down: its motion before this step counts)
		lastX[p.id] = p.startX;
		lastY[p.id] = p.startY;
		follow(p, scale);
	}

	override function follow(p:Pointer, scale:Float) {
		this.scale = scale;
		sumX += (p.x - lastX[p.id]) / scale;
		sumY += (p.y - lastY[p.id]) / scale;
		lastX[p.id] = p.x;
		lastY[p.id] = p.y;
	}

	override function lift(p:Pointer, cancelled:Bool)
		if (!cancelled) follow(p, scale);

	// (the step's drag: what axes read)
	public function close() {
		stepX = sumX;
		stepY = sumY;
		sumX = sumY = 0;
	}
}
