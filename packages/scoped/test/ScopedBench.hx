import haxe.Timer;
import hxmc.scoped.*;

@:build(hxmc.scoped.Struct.build())
abstract Particle(Addr) {
	var x:Float;
	var y:Float;
	var vx:Float;
	var vy:Float;
	var life:Int;
}

@:build(hxmc.scoped.Struct.build())
abstract Node(Addr) {
	var left:Int;
	var right:Int;
}

class GcParticle {
	public var x:Float;
	public var y:Float;
	public var vx:Float;
	public var vy:Float;
	public var life:Int;

	public function new(seed:Int) {
		x = 0;
		y = 0;
		vx = (seed % 17) * 0.1;
		vy = (seed % 13) * 0.1;
		life = 50 + seed % 100;
	}
}

class GcNode {
	public var left:GcNode;
	public var right:GcNode;

	public function new(l, r) {
		left = l;
		right = r;
	}
}

// Scoped memory against GC objects on whatever target this is built for: the
// same work, the same checksums. Particles: updated in place, the dead ones
// respawned (a new object each in the GC version), a temporary list of the
// visible ones each frame. Trees: binary trees built and walked, each in a
// scope of its own (GC: dropped for the collector).
//   haxe -cp packages/scoped/src -cp packages/scoped/test -main ScopedBench <target>
// (make scoped-bench: this machine's targets)
@:build(hxmc.scoped.Scoped.build())
class ScopedBench {
	static inline var PARTICLES = 100000;
	static inline var FRAMES = 200;
	static inline var DEPTH = 16;
	static inline var TREES = 40;

	static function main() {
		run("particles scoped", particlesScoped);
		run("particles gc", particlesGc);
		run("particles flat", particlesFlat);
		run("trees scoped", treesScoped);
		run("trees gc", treesGc);
	}

	static function run(name:String, f:() -> Float) {
		f(); // warm up
		var t = Timer.stamp();
		var check = f();
		var ms = Std.int((Timer.stamp() - t) * 1000);
		println('$name: $ms ms (check $check)');
	}

	static function println(s:String) {
		#if js
		js.Syntax.code("console.log({0})", s);
		#elseif sys
		Sys.println(s);
		#else
		trace(s);
		#end
	}

	@:scoped static function particlesScoped():Float {
		var ps = Scope.slice(Particle, PARTICLES);
		for (i in 0...PARTICLES)
			spawn(ps[i], i);
		var visible = 0;
		for (frame in 0...FRAMES) {
			var shown = Scope.grow(Int);
			for (i in 0...ps.length) {
				var p = ps[i];
				p.x += p.vx;
				p.y += p.vy;
				if (--p.life <= 0)
					spawn(p, i + frame);
				if (p.x < 100)
					shown.push(i);
			}
			visible += shown.length;
		}
		var sum = 0.0;
		for (p in ps)
			sum += p.x;
		return Math.round(sum) + visible;
	}

	static inline function spawn(p:Particle, seed:Int) {
		p.x = 0;
		p.y = 0;
		p.vx = (seed % 17) * 0.1;
		p.vy = (seed % 13) * 0.1;
		p.life = 50 + seed % 100;
	}

	static function particlesGc():Float {
		var ps = [for (i in 0...PARTICLES) new GcParticle(i)];
		var visible = 0;
		for (frame in 0...FRAMES) {
			var shown = [];
			for (i in 0...PARTICLES) {
				var p = ps[i];
				p.x += p.vx;
				p.y += p.vy;
				if (--p.life <= 0)
					ps[i] = p = new GcParticle(i + frame);
				if (p.x < 100)
					shown.push(i);
			}
			visible += shown.length;
		}
		var sum = 0.0;
		for (p in ps)
			sum += p.x;
		return Math.round(sum) + visible;
	}

	// the same work in flat arrays, a Vector per field: what each target does
	// at best with plain Haxe (the scoped version's goal)
	static function particlesFlat():Float {
		var x = new haxe.ds.Vector<Float>(PARTICLES), y = new haxe.ds.Vector<Float>(PARTICLES);
		var vx = new haxe.ds.Vector<Float>(PARTICLES), vy = new haxe.ds.Vector<Float>(PARTICLES);
		var life = new haxe.ds.Vector<Int>(PARTICLES);
		inline function respawn(i:Int, seed:Int) {
			x[i] = 0;
			y[i] = 0;
			vx[i] = (seed % 17) * 0.1;
			vy[i] = (seed % 13) * 0.1;
			life[i] = 50 + seed % 100;
		}
		for (i in 0...PARTICLES)
			respawn(i, i);
		var visible = 0;
		var shown = new haxe.ds.Vector<Int>(PARTICLES);
		for (frame in 0...FRAMES) {
			var n = 0;
			for (i in 0...PARTICLES) {
				x[i] += vx[i];
				y[i] += vy[i];
				if (--life[i] <= 0)
					respawn(i, i + frame);
				if (x[i] < 100)
					shown[n++] = i;
			}
			visible += n;
		}
		var sum = 0.0;
		for (i in 0...PARTICLES)
			sum += x[i];
		return Math.round(sum) + visible;
	}

	@:scoped static function treesScoped():Float {
		var total = 0;
		for (t in 0...TREES)
			total += count(build(DEPTH));
		return total;
	}

	// a tree of depth d in the caller's scope (its result: scoped memory)
	static function build(d:Int):Node {
		var n = new Node();
		if (d > 0) {
			n.left = cast build(d - 1);
			n.right = cast build(d - 1);
		}
		return n;
	}

	static function count(n:Node):Int {
		var l:Int = n.left;
		return l == 0 ? 1 : 1 + count(cast l) + count(cast(n.right : Int));
	}

	static function treesGc():Float {
		var total = 0;
		for (t in 0...TREES)
			total += countGc(buildGc(DEPTH));
		return total;
	}

	static function buildGc(d:Int):GcNode
		return d == 0 ? new GcNode(null, null) : new GcNode(buildGc(d - 1), buildGc(d - 1));

	static function countGc(n:GcNode):Int
		return n.left == null ? 1 : 1 + countGc(n.left) + countGc(n.right);
}
