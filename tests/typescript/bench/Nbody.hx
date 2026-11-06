// nbody.ts in Haxe (bench.mjs: TypeScript against Haxe)
class Body {
	public var x:Float;
	public var y:Float;
	public var z:Float;
	public var vx:Float;
	public var vy:Float;
	public var vz:Float;
	public var mass:Float;

	public function new(x, y, z, vx, vy, vz, mass) {
		this.x = x;
		this.y = y;
		this.z = z;
		this.vx = vx;
		this.vy = vy;
		this.vz = vz;
		this.mass = mass;
	}
}

class Nbody {
	static function advance(bodies:Array<Body>, dt:Float) {
		for (i in 0...bodies.length) {
			var a = bodies[i];
			for (j in i + 1...bodies.length) {
				var b = bodies[j];
				var dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
				var d2 = dx * dx + dy * dy + dz * dz;
				var mag = dt / (d2 * Math.sqrt(d2));
				a.vx -= dx * b.mass * mag;
				a.vy -= dy * b.mass * mag;
				a.vz -= dz * b.mass * mag;
				b.vx += dx * a.mass * mag;
				b.vy += dy * a.mass * mag;
				b.vz += dz * a.mass * mag;
			}
		}
		for (b in bodies) {
			b.x += dt * b.vx;
			b.y += dt * b.vy;
			b.z += dt * b.vz;
		}
	}

	static function energy(bodies:Array<Body>):Float {
		var e = 0.0;
		for (i in 0...bodies.length) {
			var a = bodies[i];
			e += 0.5 * a.mass * (a.vx * a.vx + a.vy * a.vy + a.vz * a.vz);
			for (j in i + 1...bodies.length) {
				var b = bodies[j];
				var dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
				e -= a.mass * b.mass / Math.sqrt(dx * dx + dy * dy + dz * dz);
			}
		}
		return e;
	}

	static function main() {
		var bodies = [
			new Body(0, 0, 0, 0, 0, 0, 39.47), new Body(4.84, -1.16, -0.10, 0.60, 2.81, -0.02, 0.037), new Body(8.34, 4.12, -0.40, -1.01, 1.82, 0.008, 0.011),
			new Body(12.89, -15.11, -0.22, 1.08, 0.86, -0.01, 0.0017), new Body(15.37, -25.91, 0.17, 0.97, 0.59, -0.03, 0.002)
		];
		Sys.println(Fixed.of(energy(bodies), 9));
		for (i in 0...1000000) advance(bodies, 0.01);
		Sys.println(Fixed.of(energy(bodies), 9));
	}
}
