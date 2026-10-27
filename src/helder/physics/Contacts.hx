package helder.physics;

import helder.gfx.shader.Vec3;

// A step's contacts as Collide finds them, struct-of-arrays: the bodies,
// then STRIDE floats each (the normal from a to b, the point, the depth,
// the solver's impulses so far and the bounce). Kept from step to step:
// cleared, not reallocated, so a step allocates nothing once it has had
// as many contacts before. (A cleared slot keeps its bodies referenced
// until it is used again.)
@:allow(helder.physics)
class Contacts {
	static inline var STRIDE = 11;
	static inline var POINT = 3;
	static inline var DEPTH = 6;
	static inline var NORMAL_IMPULSE = 7;
	static inline var TANGENT_IMPULSE1 = 8;
	static inline var TANGENT_IMPULSE2 = 9;
	static inline var BOUNCE = 10;

	public var length(default, null) = 0;

	final a:Array<Body> = [];
	final b:Array<Body> = [];
	final f:Array<Float> = [];

	public function new() {}

	public inline function clear()
		length = 0;

	public function add(a:Body, b:Body, normal:Vec3, point:Vec3, depth:Float) {
		var i = length++;
		if (i == this.a.length) {
			this.a.push(a);
			this.b.push(b);
			for (_ in 0...STRIDE)
				f.push(0);
		} else {
			this.a[i] = a;
			this.b[i] = b;
		}
		var o = i * STRIDE;
		f[o] = normal.x;
		f[o + 1] = normal.y;
		f[o + 2] = normal.z;
		f[o + POINT] = point.x;
		f[o + POINT + 1] = point.y;
		f[o + POINT + 2] = point.z;
		f[o + DEPTH] = depth;
		f[o + NORMAL_IMPULSE] = 0;
		f[o + TANGENT_IMPULSE1] = 0;
		f[o + TANGENT_IMPULSE2] = 0;
		f[o + BOUNCE] = 0;
	}

	// the contacts from index from on, turned around (a and b swapped)
	function flip(from:Int) {
		for (i in from...length) {
			var t = a[i];
			a[i] = b[i];
			b[i] = t;
			var o = i * STRIDE;
			f[o] = f[o] * -1;
			f[o + 1] = f[o + 1] * -1;
			f[o + 2] = f[o + 2] * -1;
		}
	}

	inline function normal(i:Int):Vec3 {
		var o = i * STRIDE;
		return new Vec3(f[o], f[o + 1], f[o + 2]);
	}

	inline function point(i:Int):Vec3 {
		var o = i * STRIDE + POINT;
		return new Vec3(f[o], f[o + 1], f[o + 2]);
	}

	inline function get(i:Int, field:Int):Float
		return f[i * STRIDE + field];

	inline function set(i:Int, field:Int, v:Float)
		f[i * STRIDE + field] = v;

	// contact i as a Contact (Collide.test's)
	function contact(i:Int):Contact
		return new Contact(a[i], b[i], normal(i), point(i), get(i, DEPTH));
}
