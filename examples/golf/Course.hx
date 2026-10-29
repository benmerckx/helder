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
	// a solid block from x0, z0 to x1, z1 and from y0 up to y1 (a ramp's side, a step)
	Block(x0:Float, z0:Float, x1:Float, z1:Float, y0:Float, y1:Float);
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
		},
		// 2: a corner, banked off the far rail
		{
			name: "The Bend",
			par: 2,
			tee: p(0, 0.2),
			cup: p(4.0, -3.6),
			pieces: [
				Flat(0, -1.7, 1.6, 5.4, 0), Flat(2.8, -3.6, 4, 1.6, 0), Wall(-0.8, -4.4, -0.68, 1, 0), Wall(-0.8, 0.88, 0.8, 1, 0), Wall(0.68, -2.8, 0.8, 1, 0),
				Wall(-0.8, -4.4, 4.8, -4.28, 0), Wall(0.68, -2.92, 4.8, -2.8, 0), Wall(4.68, -4.4, 4.8, -2.8, 0)
			]
		},
		// 3: up a ramp to a higher green: too soft and it rolls back down
		{
			name: "Uphill",
			par: 2,
			tee: p(0, 0.2),
			cup: p(0, -6.0, 0.6),
			pieces: [
				Flat(0, -0.25, 1.6, 2.5, 0), RampZ(0, -1.5, -3.5, 1.6, 0, 0.6), Flat(0, -5.25, 1.6, 3.5, 0.6),
				Block(-0.8, -1.5, -0.68, -3.5, 0, 0.8), Block(0.68, -1.5, 0.8, -3.5, 0, 0.8)
			].concat(rails(-0.8, 1, 0.8, -1.5, 0, "swe")).concat(rails(-0.8, -3.5, 0.8, -7, 0.6, "nwe"))
		},
		// 4: bumper posts between the tee and the cup
		{
			name: "Pinball",
			par: 2,
			tee: p(0, 0.2),
			cup: p(0, -5.2),
			pieces: [
				Flat(0, -2.5, 3.2, 7, 0), Post(-0.7, -2.0, 0.18, 0), Post(0.7, -2.0, 0.18, 0), Post(0, -3.3, 0.2, 0), Post(-1.0, -4.4, 0.16, 0),
				Post(1.0, -4.4, 0.16, 0)
			].concat(rails(-1.6, 1, 1.6, -6))
		},
		// 5: off a kicker over a gap to the green beyond
		{
			name: "The Leap",
			par: 2,
			tee: p(0, 0.4),
			cup: p(0, -7.6),
			pieces: [
				Flat(0, -0.9, 1.6, 3.8, 0), RampZ(0, -2.8, -3.8, 1.6, 0, 0.32), Flat(0, -7.2, 2.4, 3.6, 0)
			].concat(rails(-0.8, 1, 0.8, -2.8, 0, "swe")).concat(rails(-1.2, -5.4, 1.2, -9, 0, "nwe"))
		},
		// 6: two blocks sliding across the lane
		{
			name: "Sliders",
			par: 3,
			tee: p(0, 0.2),
			cup: p(0, -7),
			pieces: [
				Flat(0, -3.5, 1.8, 9, 0), Mover(-0.45, -3.2, 0.7, 0.45, 0, 0.9, 0, 3.2, 0), Mover(0.45, -5.4, 0.7, 0.45, 0, -0.9, 0, 2.6, 0.5)
			].concat(rails(-0.9, 1, 0.9, -8))
		},
		// 7: islands joined by narrow bridges, no rails
		{
			name: "Island Hop",
			par: 3,
			tee: p(0, 0.2),
			cup: p(4.4, -4.3),
			pieces: [
				Flat(0, 0, 2, 2, 0), Flat(0, -2, 0.55, 2, 0), Flat(0, -4, 2.4, 2, 0), Flat(2.2, -4, 2, 0.55, 0), Flat(4.2, -4, 2, 2.4, 0),
				Wall(-1.2, -5, 1.2, -4.88, 0), Wall(-1.2, -5, -1.08, -3, 0)
			].concat(rails(3.2, -2.8, 5.2, -5.2, 0, "nse"))
		},
		// 8: a wall with a gate, a block sliding behind it, posts before the cup
		{
			name: "Gatekeeper",
			par: 3,
			tee: p(0, 0.2),
			cup: p(0, -6.8),
			pieces: [
				Flat(0, -3.5, 2.4, 9, 0), Wall(-1.2, -3.56, -0.3, -3.44, 0), Wall(0.3, -3.56, 1.2, -3.44, 0),
				Mover(-0.6, -3.85, 0.62, 0.25, 0, 1.2, 0, 2.6, 0), Post(-0.6, -5.6, 0.15, 0), Post(0.6, -5.6, 0.15, 0)
			].concat(rails(-1.2, 1, 1.2, -8))
		},
		// 9: up to a plateau, over a bridge, past a guard to the summit
		{
			name: "Summit",
			par: 3,
			tee: p(0, 0.2),
			cup: p(4.6, -5.25, 0.7),
			pieces: [
				Flat(0, -0.5, 1.8, 3, 0), RampZ(0, -2, -4, 1.8, 0, 0.7), Block(-0.9, -2, -0.78, -4, 0, 0.9), Block(0.78, -2, 0.9, -4, 0, 0.9),
				Flat(0, -5.25, 2.6, 2.5, 0.7), Post(-0.55, -5.4, 0.16, 0.7), Post(0.45, -5.9, 0.16, 0.7), Flat(2.3, -5.25, 2, 0.6, 0.7),
				Flat(4.3, -5.25, 2, 2.6, 0.7), Mover(3.85, -4.55, 0.3, 0.7, 0.7, 0, -1.3, 3, 0.25)
			].concat(rails(-0.9, 1, 0.9, -2, 0, "swe"))
				.concat([Wall(-1.3, -6.5, 1.3, -6.38, 0.7), Wall(-1.3, -6.5, -1.18, -4, 0.7)])
				.concat(rails(3.3, -3.95, 5.3, -6.55, 0.7, "nse"))
		}
	];
}
