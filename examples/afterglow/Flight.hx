import Puzzle;

// The moth's flight: it flies to where it is led (a finger held down
// drags it along; a tap sends it), beating its wings and facing where it
// goes; when it stops it drops to the ground below and stands there, the
// pose it rests in, riding what it stands on. Where there is nothing
// below it hovers. Stepped with the puzzle, at its rate.
class Flight {
	// the moth's feet below its middle (its quad's 0.6 of Ruins.MOTH)
	public static inline var FEET = 0.6 * 0.45 + 0.03;
	static inline var SPEED = 5.0;

	public var x:Float;
	public var y:Float;
	public var z:Float;
	public var facing = 1;
	// 0 standing, 1 flying; the wings' beat; a lean into the climb or dive
	public var fly = 0.0;
	public var phase = 0.0;
	public var tilt = 0.0;
	public var perched(default, null) = false;
	public var held = false;
	var vx = 0.0;
	var vy = 0.0;
	var tx:Float;
	var ty:Float;
	var landing:Null<Vec> = null;
	var settled = 0.0;

	public function new(x:Float, y:Float, z:Float) {
		this.x = tx = x;
		this.y = ty = y;
		this.z = z;
		perched = true;
	}

	// led to (x, y) on the moth's plane
	public function lead(x:Float, y:Float) {
		tx = clamp(x, -3.4, 3.2);
		ty = clamp(y, 0.35, 8.5);
		landing = null;
		perched = false;
		settled = 0;
	}

	public function step(dt:Float, puzzle:Puzzle) {
		phase += dt * (perched ? 0 : 6 + 10 * fly);
		if (perched) {
			// (riding what it stands on; off when that slides from under it)
			var g = puzzle.ground(puzzle.flat(x, y, z).x, puzzle.flat(x, y, z).y + 0.15);
			if (g == null || Math.abs(g.y + FEET - y) > 0.3) {
				lead(puzzle.flat(x, y, z).x, puzzle.flat(x, y, z).y + 0.4);
				return;
			}
			y = g.y + FEET;
			fly = Math.max(0, fly - dt * 4);
			tilt *= 0.9;
			return;
		}
		// (towards the plane it flies in, or down to where it lands)
		var gx = tx, gy = ty, gz = Puzzle.FLY;
		if (landing != null) {
			gx = landing.x;
			gy = landing.y + FEET;
			gz = landing.z;
		}
		var dx = gx - x, dy = gy - y;
		var d = Math.sqrt(dx * dx + dy * dy);
		var want = Math.min(SPEED, d * (landing != null ? 3.5 : 4.5));
		var wx = d > 0.0001 ? dx / d * want : 0, wy = d > 0.0001 ? dy / d * want : 0;
		var k = 1 - Math.exp(-dt * 9);
		vx += (wx - vx) * k;
		vy += (wy - vy) * k;
		x += vx * dt;
		y += vy * dt;
		z += (gz - z) * (1 - Math.exp(-dt * 6));
		if (Math.abs(vx) > 0.25) facing = vx > 0 ? 1 : -1;
		var speed = Math.sqrt(vx * vx + vy * vy);
		fly = Math.min(1, fly + dt * 5);
		tilt += (clamp(vy * 0.12, -0.35, 0.35) - tilt) * k;
		// (hovering still, a little bob)
		y += Math.sin(phase * 0.25) * 0.002 * (1 - Math.min(speed, 1));
		if (landing != null) {
			if (d < 0.02 && Math.abs(gz - z) < 0.05) {
				x = gx;
				y = gy;
				z = gz;
				vx = vy = 0;
				perched = true;
				landing = null;
			}
			return;
		}
		if (held || d > 0.1 || speed > 0.35) {
			settled = 0;
			return;
		}
		settled += dt;
		// (hovering a moment first: long enough to wake what it stopped by)
		if (settled > 0.9) landing = puzzle.ground(x, y);
	}

	static inline function clamp(v:Float, a:Float, b:Float):Float
		return v < a ? a : v > b ? b : v;
}
