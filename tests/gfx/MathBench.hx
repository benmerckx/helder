import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.gfx.shader.ShaderMath.*;

// The math types in CPU code (Vec3, Vec4, Mat4: @:hxmc.struct values on
// hxmc's targets): about a million vector operations of each kind, where
// Haxe's inline constructors cannot remove the objects (a value kept across
// iterations, passed to and returned by functions, stored in objects). Run
// with RT_STATS=1 for what was allocated:
//   haxe bin/MathBench -cp src -cp tests/gfx -main MathBench -cp bin/hxmc/std --custom-target hxmc
//   RT_STATS=1 bin/MathBench
class Particle {
	public var pos:Vec3;
	public var vel:Vec3;

	public function new(i:Int) {
		pos = vec3(i, 0, -i);
		vel = vec3(1, i % 7, 0.5);
	}
}

class MathBench {
	// (not inlined: values in and out of a call)
	static function towards(a:Vec3, b:Vec3, t:Float):Vec3
		return mix(a, b, t);

	static function kernels(n:Int):{a:Float, b:Float, c:Float, d:Float} {
		// a running value: a = a * k + d, n times
		var acc = vec3(0, 0, 0);
		var d = vec3(1, 2, 3);
		for (i in 0...n)
			acc = acc * 0.999 + d;
		// through a function
		var p = vec3(1, 1, 1);
		var q = vec3(-2, 4, 8);
		for (i in 0...n)
			p = normalize(towards(p, q, 0.25) + vec3(0, 0.001 * (i & 7), 0));
		// objects' fields: n / 1000 steps of 1000 particles
		var ps = [for (i in 0...1000) new Particle(i)];
		var g = vec3(0, -9.8, 0), dt = 1 / 60;
		for (step in 0...Std.int(n / 1000))
			for (o in ps) {
				o.vel = o.vel + g * dt;
				o.pos = o.pos + o.vel * dt;
			}
		var sum = vec3(0, 0, 0);
		for (o in ps)
			sum = sum + o.pos;
		// matrices: n / 10 compositions, each transforming a vector
		var m = Mat4.identity();
		var v = vec4(0, 0, 0, 0);
		var r = Mat4.rotationY(0.001);
		for (i in 0...Std.int(n / 10)) {
			m = r * m;
			v = v + m * vec4(1, 2, 3, 1);
		}
		return {a: acc.x + acc.y + acc.z, b: p.x + p.y + p.z, c: sum.x + sum.y + sum.z, d: v.x + v.y + v.z + v.w};
	}

	static function main() {
		var n = 1000000;
		kernels(1000); // (warm)
		var t0 = haxe.Timer.stamp();
		var r = kernels(n);
		var t1 = haxe.Timer.stamp();
		Sys.println('MathBench: ${Math.round((t1 - t0) * 1000)} ms ' + [r.a, r.b, r.c, r.d].map(x -> Math.round(x * 1000) / 1000).join(" "));
	}
}
