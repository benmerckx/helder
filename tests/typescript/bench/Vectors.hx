// vectors.ts in Haxe (bench.mjs: TypeScript against Haxe)
class Vec {
	public var x:Float;
	public var y:Float;

	public function new(x, y) {
		this.x = x;
		this.y = y;
	}

	public function add(o:Vec):Vec
		return new Vec(x + o.x, y + o.y);

	public function scale(k:Float):Vec
		return new Vec(x * k, y * k);

	public function dot(o:Vec):Float
		return x * o.x + y * o.y;
}

class Particle {
	public var at:Vec;
	public var velocity:Vec;

	public function new(at, velocity) {
		this.at = at;
		this.velocity = velocity;
	}

	public function step(dt:Float, gravity:Vec) {
		velocity = velocity.add(gravity.scale(dt));
		at = at.add(velocity.scale(dt));
		if (at.y < 0) velocity = new Vec(velocity.x, -velocity.y * 0.9);
	}
}

class Vectors {
	static function main() {
		var particles = [];
		for (i in 0...1000) particles.push(new Particle(new Vec(i, 100 + i % 7), new Vec(1, 0)));
		var gravity = new Vec(0, -9.81);
		for (t in 0...2000) for (p in particles) p.step(0.001, gravity);
		var energy = 0.0;
		for (p in particles) energy += p.velocity.dot(p.velocity);
		Sys.println(Fixed.of(energy, 6));
	}
}
