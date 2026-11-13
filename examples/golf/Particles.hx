import helder.scene.Node;
import helder.scene.World;
import helder.scene.render.InstancedMesh;
import helder.scene.render.Mesh;

// A pool of particles drawn as one InstancedMesh (one instanced draw):
// each a position, a velocity, a size that shrinks over its life, a colour,
// gravity and drag, a spin (confetti tumbling). Those alive are the first
// count instances: one that dies is swapped with the last. Flat arrays of
// floats: nothing allocated per particle or per frame.
class Particles {
	public final instances:InstancedMesh;
	public final node:Node;
	final capacity:Int;
	var count = 0;
	// per particle, FIELDS floats: x, y, z, vx, vy, vz, age, life, size, gravity, drag, r, g, b, spin, flat
	static inline var FIELDS = 16;
	final f:Array<Float>;
	// (a fixed noise for spreads: the view's, no need to be the same on every run)
	var seed = 7;

	public function new(world:World, mesh:Mesh, capacity:Int, name:String) {
		this.capacity = capacity;
		instances = new InstancedMesh(mesh, capacity, 0);
		instances.castShadows = false;
		node = world.node(name);
		InstancedMesh.attach(node, instances);
		f = [for (_ in 0...capacity * FIELDS) 0.0];
	}

	public inline function random():Float {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff;
		return seed / 0x7fffffff;
	}

	// one particle; flat: drawn flattened (confetti), spin its tumbling speed
	public function emit(x:Float, y:Float, z:Float, vx:Float, vy:Float, vz:Float, life:Float, size:Float, gravity:Float, drag:Float, color:Int, spin = 0.0,
			flat = false) {
		if (count >= capacity) return;
		var o = count * FIELDS;
		f[o] = x;
		f[o + 1] = y;
		f[o + 2] = z;
		f[o + 3] = vx;
		f[o + 4] = vy;
		f[o + 5] = vz;
		f[o + 6] = 0;
		f[o + 7] = life;
		f[o + 8] = size;
		f[o + 9] = gravity;
		f[o + 10] = drag;
		var c = Kit.rgb(color);
		f[o + 11] = c.x;
		f[o + 12] = c.y;
		f[o + 13] = c.z;
		f[o + 14] = spin;
		f[o + 15] = flat ? 1 : 0;
		instances.setColor(count, c.x, c.y, c.z);
		count++;
	}

	// n particles from a point, spread round it: out sideways, up, each a little different
	public function burst(n:Int, x:Float, y:Float, z:Float, out:Float, up:Float, life:Float, size:Float, gravity:Float, drag:Float, color:Int) {
		for (i in 0...n) {
			var a = random() * Math.PI * 2, s = out * (0.5 + 0.5 * random());
			emit(x, y, z, Math.cos(a) * s, up * (0.6 + 0.4 * random()), Math.sin(a) * s, life * (0.7 + 0.3 * random()), size * (0.7 + 0.6 * random()), gravity,
				drag, color);
		}
	}

	public function clear() {
		count = 0;
		instances.count = 0;
	}

	public function update(dt:Float, time:Float) {
		var i = 0;
		while (i < count) {
			var o = i * FIELDS;
			var age = f[o + 6] + dt, life = f[o + 7];
			if (age >= life) {
				// (dead: the last one in its place)
				count--;
				if (i < count) {
					var l = count * FIELDS;
					for (k in 0...FIELDS)
						f[o + k] = f[l + k];
					instances.setColor(i, f[o + 11], f[o + 12], f[o + 13]);
				}
				continue;
			}
			f[o + 6] = age;
			var drag = 1 - f[o + 10] * dt;
			f[o + 3] *= drag;
			f[o + 5] *= drag;
			f[o + 4] = f[o + 4] * drag - f[o + 9] * dt;
			f[o] += f[o + 3] * dt;
			f[o + 1] += f[o + 4] * dt;
			f[o + 2] += f[o + 5] * dt;
			// (grows in fast, shrinks out)
			var k = age / life;
			var s = f[o + 8] * (k < 0.15 ? k / 0.15 : 1 - (k - 0.15) / 0.85 * (k - 0.15) / 0.85);
			var spin = f[o + 14];
			if (spin != 0) {
				// (tumbling: about an axis of its own, from its index's spread)
				var a = (time + i * 0.37) * spin, h = a * 0.5;
				var sh = Math.sin(h), ch = Math.cos(h);
				var ax = Math.sin(i * 2.1), az = Math.cos(i * 1.3), al = Math.sqrt(ax * ax + 1 + az * az);
				instances.setTransform(i, f[o], f[o + 1], f[o + 2], ax / al * sh, 1 / al * sh, az / al * sh, ch, s);
			} else
				instances.setTransform(i, f[o], f[o + 1], f[o + 2], 0, 0, 0, 1, s);
			i++;
		}
		instances.count = count;
		instances.changed();
	}
}
