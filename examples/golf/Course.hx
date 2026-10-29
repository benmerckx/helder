// The course: holes as data, each a list of kit pieces (Piece) placed in
// metres (x right, y up, z toward the camera at the tee; a hole runs to
// -z), a tee, a cup and a par. Sim builds the bodies from it, GolfScene the
// meshes, so a new hole is a new entry here and nothing else.
//
//   {name: "Straight", par: 2, tee: p(0, 0), cup: p(0, -5), pieces: [
//     Flat(0, -2.5, 1.6, 7),          // a slab of green, its top at y = 0
//     ...rails(-0.8, 1, 0.8, -6)      // a rail round its edge
//   ]}
enum Piece {
	// a slab of green: its centre's x and z, its width (x) and depth (z), its top's height
	Flat(x:Float, z:Float, w:Float, d:Float, y:Float);
	// green sloping from height y0 at z0 to y1 at z1 (along z), w wide, centred on x
	RampZ(x:Float, z0:Float, z1:Float, w:Float, y0:Float, y1:Float);
	// the same along x, d deep, centred on z
	RampX(z:Float, x0:Float, x1:Float, d:Float, y0:Float, y1:Float);
	// a rail or a bumper wall: a box from x0, z0 to x1, z1 (one of them thin), standing on y
	Wall(x0:Float, z0:Float, x1:Float, z1:Float, y:Float);
	// a round bumper post (kicks the ball back off)
	Post(x:Float, z:Float, r:Float, y:Float);
	// a block sliding from (x, z) to (x + dx, z + dz) and back, period seconds a round trip (phase 0 to 1)
	Mover(x:Float, z:Float, w:Float, d:Float, y:Float, dx:Float, dz:Float, period:Float, phase:Float);
}

typedef Point = {x:Float, y:Float, z:Float};

typedef Hole = {
	name:String,
	par:Int,
	tee:Point,
	cup:Point,
	pieces:Array<Piece>
}

class Course {
	public static inline var RAIL = 0.12;

	static inline function p(x:Float, z:Float, y = 0.0):Point
		return {x: x, y: y, z: z};

	// rails round the rectangle x0..x1, z0..z1 (on its edge, inside it), at
	// height y; sides: which ones ("n" the -z one, "s" +z, "e" +x, "w" -x)
	public static function rails(x0:Float, z0:Float, x1:Float, z1:Float, y = 0.0, sides = "nsew"):Array<Piece> {
		var lx = Math.min(x0, x1), hx = Math.max(x0, x1), lz = Math.min(z0, z1), hz = Math.max(z0, z1), t = RAIL;
		var out = [];
		if (sides.indexOf("n") >= 0) out.push(Wall(lx, lz, hx, lz + t, y));
		if (sides.indexOf("s") >= 0) out.push(Wall(lx, hz - t, hx, hz, y));
		if (sides.indexOf("w") >= 0) out.push(Wall(lx, lz, lx + t, hz, y));
		if (sides.indexOf("e") >= 0) out.push(Wall(hx - t, lz, hx, hz, y));
		return out;
	}

	public static final holes:Array<Hole> = [
		// 1: a straight lane, rails all round
		{
			name: "First Putt",
			par: 2,
			tee: p(0, 0),
			cup: p(0, -5.4),
			pieces: [Flat(0, -2.6, 1.6, 7.2, 0)].concat(rails(-0.8, 1, 0.8, -6.2))
		}
	];
}
