package helder.scene.input;

import helder.os.Pointer;

// An on-screen stick (Unity's OnScreenStick; a mobile game's floating
// stick): a finger pressed in its zone holds it, its offset from the
// stick's centre (radius points at full tilt) the stick's x and y, -1 to
// 1 (x right, y up), past a dead zone (rescaled to 0..1, as a pad's). A
// floating stick's centre is where the finger came down; a fixed one's
// its zone's centre. Let go or cancelled: back to 0 (the player stops).
// Bound as an axis: Stick(stick, 0) and Stick(stick, 1) (Binding); drawn
// by helder.scene.view's <Stick>, from centerX, centerY, knobX, knobY.
//
//   final move = new VirtualStick({zone: Zone.rect(0, 0.4, 0.5, 1), radius: 60});
//   actions.bind("moveX", Stick(move, 0)).bind("moveX", KeyAxis(0x61, 0x64));
class VirtualStick extends TouchControl {
	public var x(default, null) = 0.0;
	public var y(default, null) = 0.0;
	public var floating:Bool;
	// full tilt's distance (points), the travel taken as rest (0 to 1)
	public var radius:Float;
	public var deadZone:Float;
	// held by a finger
	public var active(get, never):Bool;
	// its centre and its knob (pixels, the window's), while active
	public var centerX(default, null) = 0.0;
	public var centerY(default, null) = 0.0;
	public var knobX(default, null) = 0.0;
	public var knobY(default, null) = 0.0;

	public function new(o:{zone:Zone, ?floating:Bool, ?radius:Float, ?deadZone:Float}) {
		super(o.zone);
		floating = o.floating ?? true;
		radius = o.radius ?? 60;
		deadZone = o.deadZone ?? 0.1;
	}

	inline function get_active():Bool
		return pointer >= 0;

	override function take(p:Pointer, width:Float, height:Float, scale:Float) {
		super.take(p, width, height, scale);
		centerX = floating ? p.startX : zone.centerX(width);
		centerY = floating ? p.startY : zone.centerY(height);
		follow(p, scale);
	}

	override function follow(p:Pointer, scale:Float) {
		var r = radius * scale, ox = p.x - centerX, oy = p.y - centerY;
		var l = Math.sqrt(ox * ox + oy * oy);
		if (l > r) {
			ox *= r / l;
			oy *= r / l;
			l = r;
		}
		var nx = 0.0, ny = 0.0, m = r > 0 ? l / r : 0;
		if (m > deadZone) {
			var k = (m - deadZone) / (1 - deadZone) / m;
			nx = ox / r * k;
			ny = -oy / r * k;
		}
		if (nx == x && ny == y && knobX == centerX + ox && knobY == centerY + oy) return;
		x = nx;
		y = ny;
		knobX = centerX + ox;
		knobY = centerY + oy;
		tell();
	}

	override function lift(p:Pointer, cancelled:Bool) {
		if (pointer != p.id) return;
		super.lift(p, cancelled);
		x = y = 0;
		knobX = centerX;
		knobY = centerY;
		tell();
	}
}
