// The course: three islands of six holes each, every hole data: a list of
// kit pieces (Piece) placed in metres (x right, y up, z toward the camera
// at the tee; a hole runs to -z), a tee, a cup and a par. Sim builds the
// bodies from it, Game the meshes, so a new hole is a new entry here and
// nothing else.
//
//   {name: "Straight", world: 0, par: 2, tee: p(0, 0), cup: p(0, -5), pieces: [
//     Flat(0, -2.5, 1.6, 7, 0),        // a slab of green, its top at y = 0
//     ...rails(-0.8, 1, 0.8, -6)       // a rail round its edge
//   ]}
//
// Each island brings its own pieces in, one a hole, then twists them:
// Meadowdrift the slopes, bumpers and sand; Copperwind Cliffs what moves
// (sliders, turnstiles, wind, boosters, lifts, one-way gates); Lanternwater
// the puzzles (water, portals, switches and their gates, crumbling tiles).
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
	// a round post (the ball bounces off it)
	Post(x:Float, z:Float, r:Float, y:Float);
	// a block sliding from (x, z) to (x + dx, z + dz) and back, period seconds a round trip (phase 0 to 1)
	Mover(x:Float, z:Float, w:Float, d:Float, y:Float, dx:Float, dz:Float, period:Float, phase:Float);
	// a round bumper that kicks the ball off it at Sim.KICK at least
	Bumper(x:Float, z:Float, r:Float, y:Float);
	// a bar len long turning about its middle at speed (radians a second, counter-clockwise from above), from angle start
	Spinner(x:Float, z:Float, len:Float, y:Float, speed:Float, start:Float);
	// a platform w by d whose top rises from y0 to y1 and back, period seconds a round trip
	Lift(x:Float, z:Float, w:Float, d:Float, y0:Float, y1:Float, period:Float, phase:Float);
	// a pad on the green speeding a ball rolling over it along (ax, az), in m/s²
	Boost(x:Float, z:Float, w:Float, d:Float, y:Float, ax:Float, az:Float);
	// a gust over the area (up to 1.5 m above y), pushing the ball along (ax, az) in m/s², in the air too
	Wind(x:Float, z:Float, w:Float, d:Float, y:Float, ax:Float, az:Float);
	// a sand patch on a green (slow going)
	Sand(x:Float, z:Float, w:Float, d:Float, y:Float);
	// a sheet of ice on a green (hardly slows)
	Ice(x:Float, z:Float, w:Float, d:Float, y:Float);
	// a pool, its surface at y: the ball in it is put back, a stroke more
	Water(x:Float, z:Float, w:Float, d:Float, y:Float);
	// a portal on the green at (x, y, z): the ball rolling onto it comes out at (tx, ty, tz) heading (dx, dz), its speed kept
	Portal(x:Float, z:Float, y:Float, tx:Float, tz:Float, ty:Float, dx:Float, dz:Float);
	// a plate that, rolled over, swaps the gates of its group (open ones close, closed ones open)
	Switch(x:Float, z:Float, y:Float, group:Int);
	// a gate from x0, z0 to x1, z1 on y, of a group, open (sunk into the green) or closed at the start
	Gate(x0:Float, z0:Float, x1:Float, z1:Float, y:Float, group:Int, open:Bool);
	// a line from x0, z0 to x1, z1 the ball crosses only heading along (dx, dz)
	OneWay(x0:Float, z0:Float, x1:Float, z1:Float, y:Float, dx:Float, dz:Float);
	// green that falls away once the ball has rolled off it (back when the ball is put back)
	Crumble(x:Float, z:Float, w:Float, d:Float, y:Float);
}

typedef Point = {x:Float, y:Float, z:Float};

typedef Hole = {
	name:String,
	world:Int,
	par:Int,
	tee:Point,
	cup:Point,
	pieces:Array<Piece>,
	// what the hole brings in, said on its card ("" nothing new)
	?tip:String
}

// an island of holes: its name and look (colours as sRGB hex; the sun's
// direction toward it, its colour and strength)
typedef World = {
	name:String,
	blurb:String,
	sky:Array<String>,
	grass:Int,
	grassDark:Int,
	rock:Int,
	rockDark:Int,
	rail:Int,
	accent:Int,
	// the accent dark enough for text on white
	deep:Int,
	sun:Array<Float>,
	sunColor:Int,
	sunPower:Float,
	ambientSky:Int,
	ambientGround:Int,
	fog:Int,
	exposure:Float,
	// fireflies and lanterns (the dusk's)
	night:Bool,
	// the diorama's light: a cool fill from across the sun (its colour, strength),
	// the cloud sea's lit and shaded tints, the contact shadows' tint
	fill:Int,
	fillPower:Float,
	cloud:Int,
	cloudShade:Int,
	shade:Int,
	// the grade (PostProcess): saturation, contrast, vignette, lift (rgb, added to
	// the shadows: cool) and gain (rgb: warm)
	grade:Array<Float>,
	lift:Array<Float>,
	gain:Array<Float>
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

	public static final worlds:Array<World> = [
		{
			name: "Meadowdrift",
			blurb: "Soft greens on a spring breeze",
			sky: ["#8ec9ff", "#cfe6ff", "#ffe3ef"],
			grass: 0x6fd27a,
			grassDark: 0x5fc46c,
			rock: 0xf0cfa8,
			rockDark: 0xc9a8de,
			rail: 0xfff6e8,
			accent: 0xff6b6b,
			deep: 0xe0484f,
			sun: [0.45, 0.8, 0.4],
			sunColor: 0xfff1dc,
			sunPower: 2.6,
			ambientSky: 0x8fa6d6,
			ambientGround: 0x6d5a4a,
			fog: 0xd8e8ff,
			exposure: 0.95,
			night: false,
			fill: 0x9db8ff,
			fillPower: 0.5,
			cloud: 0xfdfbff,
			cloudShade: 0xdcd2f0,
			shade: 0x2c3a6e,
			grade: [0.95, 1.03, 0.12],
			lift: [0.006, 0.012, 0.03],
			gain: [1.02, 1.0, 0.97]
		},
		{
			name: "Copperwind Cliffs",
			blurb: "Gears, gusts and golden light",
			sky: ["#ffb27a", "#ffd9a8", "#ffeede"],
			grass: 0xa9cf5a,
			grassDark: 0x97c04c,
			rock: 0xe39a6c,
			rockDark: 0xc4705a,
			rail: 0xfff1de,
			accent: 0x2a9d8f,
			deep: 0x1f8a7e,
			sun: [-0.55, 0.55, 0.35],
			sunColor: 0xffd2a0,
			sunPower: 3.0,
			ambientSky: 0xb09ac0,
			ambientGround: 0x7a4a3a,
			fog: 0xffd8b8,
			exposure: 0.95,
			night: false,
			fill: 0x9aa6e8,
			fillPower: 0.45,
			cloud: 0xfff0e4,
			cloudShade: 0xe0a6a8,
			shade: 0x4a2c52,
			grade: [0.94, 1.03, 0.14],
			lift: [0.01, 0.008, 0.028],
			gain: [1.03, 0.99, 0.95]
		},
		{
			name: "Lanternwater",
			blurb: "Moonlit pools and puzzling doors",
			sky: ["#1f2350", "#4a3f7a", "#c77fa8"],
			grass: 0x3fb59a,
			grassDark: 0x35a38a,
			rock: 0x8a7fc4,
			rockDark: 0x6a5fa8,
			rail: 0xe8e4ff,
			accent: 0xffc857,
			deep: 0xc98a12,
			sun: [0.35, 0.75, -0.5],
			sunColor: 0xc8d4ff,
			sunPower: 1.7,
			ambientSky: 0x5a62a8,
			ambientGround: 0x3a2f5a,
			fog: 0x6a5a9a,
			exposure: 1.05,
			night: true,
			fill: 0x7d8cff,
			fillPower: 0.55,
			cloud: 0xe7c4dc,
			cloudShade: 0x9c6c9e,
			shade: 0x1a1640,
			grade: [0.96, 1.04, 0.2],
			lift: [0.012, 0.01, 0.035],
			gain: [1.02, 0.98, 1.0]
		}
	];

	public static final holes:Array<Hole> = [
		// --- Meadowdrift

		// 1: a straight lane, rails all round
		{
			name: "First Putt",
			world: 0,
			par: 2,
			tee: p(0, 0),
			cup: p(0, -5.4),
			pieces: [Flat(0, -2.6, 1.6, 7.2, 0)].concat(rails(-0.8, 1, 0.8, -6.2)),
			tip: "Drag back from the ball, let go to shoot"
		},
		// 2: a corner, banked off the far rail
		{
			name: "The Bend",
			world: 0,
			par: 2,
			tee: p(0, 0.2),
			cup: p(4.0, -3.6),
			pieces: [
				Flat(0, -1.7, 1.6, 5.4, 0), Flat(2.8, -3.6, 4, 1.6, 0), Wall(-0.8, -4.4, -0.68, 1, 0), Wall(-0.8, 0.88, 0.8, 1, 0), Wall(0.68, -2.8, 0.8, 1, 0),
				Wall(-0.8, -4.4, 4.8, -4.28, 0), Wall(0.68, -2.92, 4.8, -2.8, 0), Wall(4.68, -4.4, 4.8, -2.8, 0)
			],
			tip: "Bank it off the far rail"
		},
		// 3: up a ramp to a higher green: too soft and it rolls back down
		{
			name: "Uphill",
			world: 0,
			par: 2,
			tee: p(0, 0.2),
			cup: p(0, -6.0, 0.6),
			pieces: [
				Flat(0, -0.25, 1.6, 2.5, 0), RampZ(0, -1.5, -3.5, 1.6, 0, 0.6), Flat(0, -5.25, 1.6, 3.5, 0.6),
				Block(-0.8, -1.5, -0.68, -3.5, 0, 0.8), Block(0.68, -1.5, 0.8, -3.5, 0, 0.8)
			].concat(rails(-0.8, 1, 0.8, -1.5, 0, "swe")).concat(rails(-0.8, -3.5, 0.8, -7, 0.6, "nwe")),
			tip: "Slopes pull the ball back: hit it firmly"
		},
		// 4: bumpers between the tee and the cup, kicking the ball away
		{
			name: "Pinball",
			world: 0,
			par: 2,
			tee: p(0, 0.2),
			cup: p(0, -5.2),
			pieces: [
				Flat(0, -2.5, 3.2, 7, 0), Bumper(-0.7, -2.0, 0.2, 0), Bumper(0.7, -2.0, 0.2, 0), Bumper(0, -3.3, 0.22, 0), Bumper(-1.0, -4.4, 0.18, 0),
				Bumper(1.0, -4.4, 0.18, 0)
			].concat(rails(-1.6, 1, 1.6, -6)),
			tip: "Bumpers kick the ball away"
		},
		// 5: the straight line runs through sand; round by the lane on the left is longer but quick
		{
			name: "Sandy Shortcut",
			world: 0,
			par: 2,
			tee: p(0.7, 0.3),
			cup: p(0.5, -6.6),
			pieces: [
				Flat(0, -3.4, 3.2, 8.8, 0), Sand(0.4, -3.4, 2.4, 2.6, 0), Post(-0.8, -2.1, 0.1, 0), Post(-0.8, -4.7, 0.1, 0)
			].concat(rails(-1.6, 1, 1.6, -7.8)),
			tip: "Sand slows the ball right down"
		},
		// 6: off a kicker over a gap to the green beyond
		{
			name: "The Leap",
			world: 0,
			par: 2,
			tee: p(0, 0.4),
			cup: p(0, -7.6),
			pieces: [
				Flat(0, -0.9, 1.6, 3.8, 0), RampZ(0, -2.8, -3.8, 1.6, 0, 0.4), Flat(0, -7.0, 2.4, 4.2, 0), Bumper(-0.6, -6.6, 0.16, 0),
				Bumper(0.6, -6.6, 0.16, 0)
			].concat(rails(-0.8, 1, 0.8, -2.8, 0, "swe")).concat(rails(-1.2, -4.9, 1.2, -9.1, 0, "nwe")),
			tip: "A ramp's lip throws the ball: mind the gap"
		},

		// --- Copperwind Cliffs

		// 7: two blocks sliding across the lane
		{
			name: "Sliders",
			world: 1,
			par: 2,
			tee: p(0, 0.2),
			cup: p(0, -7),
			pieces: [
				Flat(0, -3.5, 1.8, 9, 0), Mover(-0.45, -3.2, 0.7, 0.45, 0, 0.9, 0, 3.2, 0), Mover(0.45, -5.4, 0.7, 0.45, 0, -0.9, 0, 2.6, 0.5)
			].concat(rails(-0.9, 1, 0.9, -8)),
			tip: "Blocks slide to and fro: time your shot"
		},
		// 8: a turnstile across the lane, then a second turning the other way
		{
			name: "Turnstile",
			world: 1,
			par: 2,
			tee: p(0, 0.3),
			cup: p(0, -7.2),
			pieces: [
				Flat(0, -3.6, 2, 9.2, 0), Spinner(0, -2.8, 1.6, 0, 1.4, 0), Spinner(0, -5.2, 1.6, 0, -1.9, 0.8)
			].concat(rails(-1, 1, 1, -8.2)),
			tip: "Turnstiles knock the ball aside: go through the gap"
		},
		// 9: a gusty bridge without rails: aim into the wind
		{
			name: "Crosswind",
			world: 1,
			par: 2,
			tee: p(0, 0.3),
			cup: p(0, -7.4),
			pieces: [
				Flat(0, -0.5, 1.8, 3, 0), Flat(0, -4, 1.0, 4, 0), Flat(0, -7.4, 2.4, 2.8, 0), Wind(0, -4, 7, 4, 0, 1.6, 0)
			].concat(rails(-0.9, 1, 0.9, -2, 0, "swe")).concat(rails(-1.2, -6, 1.2, -8.8, 0, "nwe")),
			tip: "Wind pushes the ball, in the air too: aim into it"
		},
		// 10: boosters up a slope too steep for a putt alone
		{
			name: "Booster Run",
			world: 1,
			par: 2,
			tee: p(0, 0.4),
			cup: p(0, -9.4, 1.6),
			pieces: [
				Flat(0, -0.6, 1.6, 3.2, 0), Boost(0, -1.4, 1.2, 0.9, 0, 0, -16), RampZ(0, -2.2, -6.2, 1.6, 0, 1.6), Boost(0, -4.2, 1.2, 0.9, 0.8, 0, -16),
				Flat(0, -8.4, 2.4, 4.4, 1.6), Block(-0.8, -2.2, -0.68, -6.2, 0, 1.8), Block(0.68, -2.2, 0.8, -6.2, 0, 1.8)
			].concat(rails(-0.8, 1, 0.8, -2.2, 0, "swe")).concat(rails(-1.2, -6.2, 1.2, -10.6, 1.6, "nwe")),
			tip: "Boosters speed up a ball rolling over them"
		},
		// 11: a lift up to the ledge with the cup: stop on it, ride up, shoot off
		{
			name: "Lift Off",
			world: 1,
			par: 3,
			tee: p(0, 0.3),
			cup: p(0, -7.6, 1.2),
			pieces: [
				Flat(0, -1, 2, 4, 0), Lift(0, -3.65, 1.2, 1.2, 0, 1.2, 8, 0), Flat(0, -6.6, 2.4, 3.8, 1.2),
				Block(-1.2, -4.7, 1.2, -4.3, -0.3, 1.2), Block(-0.72, -3.05, -0.6, -4.3, 0, 1.4), Block(0.6, -3.05, 0.72, -4.3, 0, 1.4)
			].concat(rails(-1, 1, 1, -3, 0, "swe")).concat([Wall(-1, -3.12, -0.6, -3, 0), Wall(0.6, -3.12, 1, -3, 0)])
				.concat(rails(-1.2, -4.7, 1.2, -8.5, 1.2, "nwe")),
			tip: "Stop on the lift and ride it up"
		},
		// 12: the cup in a pen whose only door opens inward from the far side
		{
			name: "Roundabout",
			world: 1,
			par: 3,
			tee: p(0, 0.4),
			cup: p(0, -3.6),
			pieces: [
				Flat(0, -2.75, 5, 7.5, 0), Wall(-1, -2.4, 1, -2.28, 0), Wall(-1, -4.8, -1.08 + 0.2, -2.28, 0), Wall(1.08 - 0.2, -4.8, 1, -2.28, 0),
				Wall(-1, -4.92, -0.4, -4.8, 0), Wall(0.4, -4.92, 1, -4.8, 0), OneWay(-0.4, -4.86, 0.4, -4.86, 0, 0, 1), Bumper(0, -5.9, 0.16, 0)
			].concat(rails(-2.5, 1, 2.5, -6.5)),
			tip: "Arrows mark a one-way gate"
		},

		// --- Lanternwater

		// 13: over the pool off a kicker, or down round it by the narrow ramps at its sides
		{
			name: "Skipping Stone",
			world: 2,
			par: 2,
			tee: p(0, 0.5),
			cup: p(0, -6.6, -0.25),
			pieces: [
				Flat(0, -0.4, 4, 2.8, 0), RampZ(0, -1.8, -3, 1.0, 0, 0.45), RampZ(-1.7, -1.8, -4.3, 0.6, 0, -0.25), RampZ(1.7, -1.8, -4.3, 0.6, 0, -0.25),
				Water(0, -3.05, 2.8, 2.5, -0.4), Flat(0, -6.15, 4, 3.7, -0.25)
			].concat(rails(-2, 1, 2, -1.8, 0, "swe")).concat(rails(-2, -4.3, 2, -8, -0.25, "nwe")),
			tip: "Water costs a stroke"
		},
		// 14: the cup's island has no bridge: the portal goes there
		{
			name: "Wormhole",
			world: 2,
			par: 2,
			tee: p(0, 0.3),
			cup: p(4.6, -7.6),
			pieces: [
				Flat(0, -1.4, 2, 4.8, 0), Portal(0, -3, 0, 4.6, -5.0, 0, 0, -1), Flat(4.6, -6.6, 2.2, 3.6, 0), Bumper(4.0, -7.0, 0.14, 0)
			].concat(rails(-1, 1, 1, -3.8)).concat(rails(3.5, -4.8, 5.7, -8.4)),
			tip: "Portals keep the ball's speed"
		},
		// 15: a closed gate across the lane; the switch is in the bay beside it
		{
			name: "Flip Switch",
			world: 2,
			par: 3,
			tee: p(0, 0.3),
			cup: p(0, -7.0),
			pieces: [
				Flat(0, -3.6, 2, 9.2, 0), Flat(-1.6, -2.7, 1.2, 1.6, 0), Switch(-1.65, -2.7, 0, 0), Gate(-1, -4.6, 1, -4.48, 0, 0, false)
			].concat(rails(-1, 1, 1, -8.2, 0, "nse")).concat([Wall(-1, -1.9, -0.88, 1, 0), Wall(-1, -8.2, -0.88, -3.5, 0)])
				.concat(rails(-2.2, -1.9, -1, -3.5, 0, "nsw")),
			tip: "Roll over a switch to open its gates"
		},
		// 16: over a crumbling bridge to the switch; back by the portal through the gate it opened
		{
			name: "Brittle Bridge",
			world: 2,
			par: 4,
			tee: p(-0.4, 0.4),
			cup: p(4.2, -1.4),
			pieces: [
				Flat(0, -0.6, 2.4, 3.2, 0), Water(0, -3.2, 2.4, 2, -0.3), Crumble(0, -2.7, 0.7, 1.0, 0), Crumble(0, -3.7, 0.7, 1.0, 0),
				Flat(0, -5.4, 2.4, 2.4, 0), Switch(0, -5.0, 0, 0), Portal(0.75, -5.9, 0, 0.3, -0.6, 0, 1, 0), Flat(2.2, -0.6, 2.0, 1.0, 0),
				Gate(1.3, -1.1, 1.42, -0.1, 0, 0, false), Flat(4.2, -1.0, 2.0, 2.4, 0)
			].concat(rails(-1.2, 1, 1.2, -2.2, 0, "sw")).concat([Wall(-1.2, -2.2, -0.35, -2.08, 0), Wall(0.35, -2.2, 1.2, -2.08, 0)])
				.concat([Wall(1.08, 1, 1.2, -0.1, 0), Wall(1.08, -1.1, 1.2, -2.2, 0)])
				.concat(rails(-1.2, -4.2, 1.2, -6.6, 0, "new")).concat([Wall(-1.2, -4.32, -0.35, -4.2, 0), Wall(0.35, -4.32, 1.2, -4.2, 0)])
				.concat(rails(1.2, -0.1, 3.2, -1.1, 0, "ns")).concat(rails(3.2, 0.2, 5.2, -2.2, 0, "nse")),
			tip: "Cracked tiles fall once the ball has crossed"
		},
		// 17: two doors on one switch group: as one opens the other shuts, a plate between them
		{
			name: "Two Doors",
			world: 2,
			par: 3,
			tee: p(0, 0.3),
			cup: p(0, -8.4),
			pieces: [
				Flat(0, -4.2, 2, 10.4, 0), Gate(-1, -3.0, 1, -2.88, 0, 0, false), Gate(-1, -6.0, 1, -5.88, 0, 0, true), Flat(-1.6, -1.6, 1.2, 1.6, 0),
				Switch(-1.65, -1.6, 0, 0), Switch(0, -4.5, 0, 0), Post(-0.6, -4.5, 0.1, 0), Post(0.6, -4.5, 0.1, 0)
			].concat(rails(-1, 1, 1, -9.4, 0, "nse")).concat([Wall(-1, 1, -0.88, -0.8, 0), Wall(-1, -2.4, -0.88, -9.4, 0)])
				.concat(rails(-2.2, -0.8, -1, -2.4, 0, "nsw")),
			tip: "One switch can open a gate and close another"
		},
		// 18: up by the portal to the moonlit plateau, past the turnstile to the switch, into the pen
		{
			name: "Moonrise",
			world: 2,
			par: 4,
			tee: p(0, 0.3),
			cup: p(3.1, -7.2, 0.8),
			pieces: [
				Flat(0, -1, 2.4, 4, 0), Portal(0, -2.4, 0, -0.4, -4.8, 0.8, 0, -1), Flat(1.2, -6.2, 5.2, 3.6, 0.8),
				Spinner(-0.4, -6.4, 1.3, 0.8, 1.5, 0), Switch(-0.4, -7.5, 0.8, 0), Wall(2.4, -6.0, 2.52, -7.88, 0.8), Gate(2.52, -6.06, 3.68, -6.06, 0.8, 0, false),
				Bumper(0.9, -5.4, 0.15, 0.8)
			].concat(rails(-1.2, 1, 1.2, -3, 0, "swe")).concat(rails(-1.4, -4.4, 3.8, -8, 0.8)),
			tip: "Everything you have learned, together"
		}
	];
}
