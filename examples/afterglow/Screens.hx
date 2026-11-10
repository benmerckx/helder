// The three screens, as data: the stone that stays, the pieces that move
// (each a few fixed states), the glyphs that move them, where the larva
// starts and where its home is. Puzzle plays them, Ruins builds them.
// Coordinates are the world's (x right, y up, z towards the eye); the
// larva walks along walks (x0, x1, y, z), the moth flies in front of it all.
typedef Stone = {
	var box:Array<Float>; // x0, y0, z0, x1, y1, z1
	var ?wear:Float;
	var ?fallen:Float; // how much of its top has come down (low: a flat top to walk on)
	var ?under:Float; // how far it steps back under its lip (1)
}

typedef Piece = {
	var name:String;
	var ?stones:Array<Stone>;
	// the poses it rests in: dx, dy and a turn (radians) about pivot, from as built
	var states:Array<Array<Float>>;
	var ?start:Int;
	var ?pivot:Array<Float>;
	var ?walks:Array<Array<Float>>;
	// it moves with the larva on it (else it waits for it to step off)
	var ?carries:Bool;
	// open (its state 1) only while all these eyes are lit together
	var ?holds:Array<String>;
	// where it bars the way while shut (x0, x1, y0, y1 as built)
	var ?blocks:Array<Float>;
	// a lantern (x, y, z as built), dark until the moth's light wakes it;
	// hung from another piece's point, upright as that piece turns
	var ?lantern:Array<Float>;
	var ?hang:{piece:String, at:Array<Float>};
	var ?time:Float; // seconds a move takes
}

typedef Glyph = {
	var name:String;
	var at:Array<Float>; // on a face looking at the eye
	var ?drives:Array<String>; // each lighting moves these to their next state
	var ?eye:Bool; // one of a pair a piece holds
}

typedef Screen = {
	var name:String;
	var stones:Array<Stone>;
	var walks:Array<Array<Float>>;
	var pieces:Array<Piece>;
	var glyphs:Array<Glyph>;
	var larva:Array<Float>;
	var ?asleep:Bool;
	var home:Array<Float>; // x, y (the ground), z (the face its door is in)
	var moth:Array<Float>; // where the moth comes in
	// growth: caps (x, y, z, spread, count, size, acid), sprouts (x, y, z, spread, count), shelves (x, y)
	var ?caps:Array<Array<Float>>;
	var ?sprouts:Array<Array<Float>>;
	var ?shelves:Array<Array<Float>>;
}

class Screens {
	// 1. First light: light wakes; a lit glyph moves its stone. Wake the
	// larva, slide out the two halves of the bridge, lead it home.
	public static final first:Screen = {
		name: "First light",
		stones: [
			{box: [-5.6, -1.2, -4.1, 0.15, 0.8, -1.9], fallen: 1},
			{box: [-5.6, 0.55, -4.1, 0.45, 1.0, -1.5], wear: 0.7, fallen: 0.15},
			{box: [-7, -1.2, -6.5, -1.9, 4.35, -3.7], fallen: 1},
			{box: [-7.5, 4.2, -6.8, -1.4, 4.85, -3.3], fallen: 1},
			{box: [1.35, -1.2, -3.6, 3.8, 1.0, -1.6], wear: 0.7, fallen: 0.1},
			{box: [1.5, 0.9, -4.6, 3.6, 3.3, -3.6], fallen: 1}
		],
		walks: [[-5.6, 0.45, 1.0, -2.3], [1.35, 3.8, 1.0, -2.3], [-7.5, -1.4, 4.85, -3.9]],
		pieces: [
			{name: "left", stones: [{box: [-0.55, 0.74, -2.9, 0.2, 0.98, -1.9], wear: 0.3, fallen: 0}], walks: [[-0.55, 0.2, 1.0, -2.3]], states: [[0, 0, 0], [0.7, 0, 0]]},
			{name: "right", stones: [{box: [1.6, 0.74, -2.9, 2.35, 0.98, -1.9], wear: 0.3, fallen: 0}], walks: [[1.6, 2.35, 1.0, -2.3]], states: [[0, 0, 0], [-0.7, 0, 0]]}
		],
		glyphs: [
			{name: "a", at: [-2.25, 1.85, -3.7], drives: ["left"]},
			{name: "b", at: [1.95, 2.45, -3.6], drives: ["right"]}
		],
		larva: [-0.9, 1.0, -2.3],
		asleep: true,
		home: [2.4, 1.0, -3.6],
		moth: [-2.0, 4.85, -3.3],
		caps: [[-3.9, 1.0, -2.5, 0.5, 7, 0.13, 0]],
		sprouts: [[-2.0, 1.0, -2.0, 0.45, 9], [-4.6, 4.85, -3.6, 0.5, 8]],
		shelves: [[-2.6, 2.95], [-2.3, 3.45], [-2.9, 2.45]]
	};

	// 2. Two lights: a gate opens only while both its eyes are lit; the
	// moth has one light, a lantern can keep the other. Wake the lantern,
	// turn its arm to the left eye, light the right one, lead the larva home.
	public static final second:Screen = {
		name: "Two lights",
		stones: [
			{box: [-5.6, -1.2, -3.6, 3.8, 1.0, -1.5], wear: 0.7, fallen: 0.1},
			{box: [-5.6, -1.2, -5.2, -0.5, 4.6, -3.4], fallen: 1},
			{box: [1.2, -1.2, -5.2, 3.8, 3.8, -3.4], fallen: 1},
			{box: [-0.55, 0.9, -3.5, -0.1, 3.4, -2.1], wear: 0.4, fallen: 0.3},
			{box: [0.8, 0.9, -3.5, 1.25, 3.4, -2.1], wear: 0.4, fallen: 0.3},
			{box: [-0.75, 3.2, -3.6, 1.45, 3.75, -2.0], wear: 0.5, fallen: 0.4},
			{box: [-1.9, 4.3, -3.6, -1.3, 4.9, -3.0], wear: 0.3, fallen: 0}
		],
		walks: [[-5.6, 3.8, 1.0, -1.95]],
		pieces: [
			{
				name: "gate",
				stones: [{box: [-0.12, 1.0, -3.0, 0.82, 3.2, -2.4], wear: 0.3, fallen: 0}],
				states: [[0, 0, 0], [0, 2.1, 0]],
				holds: ["left eye", "right eye"],
				blocks: [-0.12, 0.82, 1.0, 3.2],
				time: 0.9
			},
			{name: "arm", stones: [{box: [-1.6, 4.47, -3.0, 0.15, 4.73, -2.6], wear: 0.2, fallen: 0}], pivot: [-1.6, 4.6], states: [[0, 0, 1.745], [0, 0, -1.396]], time: 1.6},
			{name: "lantern", lantern: [0.0, 4.05, -2.2], hang: {piece: "arm", at: [0.0, 4.6]}, states: [[0, 0, 0]]}
		],
		glyphs: [
			{name: "turn", at: [-2.5, 3.4, -3.4], drives: ["arm"]},
			{name: "left eye", at: [-1.9, 1.9, -3.4], eye: true},
			{name: "right eye", at: [1.6, 2.3, -3.4], eye: true}
		],
		larva: [-2.3, 1.0, -1.95],
		home: [2.3, 1.0, -3.4],
		moth: [2.0, 1.0, -1.35],
		caps: [[-3.8, 1.0, -2.6, 0.6, 6, 0.14, 0], [2.9, 3.8, -4.2, 0.5, 5, 0.16, 1]],
		sprouts: [[1.6, 1.0, -2.0, 0.4, 7]],
		shelves: [[-3.3, 4.1]]
	};

	// 3. The lift: a stone that carries the larva; the order matters.
	// Lower the lift, let the larva climb on, raise it with the larva on
	// it, slide out the bridge, lead the larva home.
	public static final third:Screen = {
		name: "The lift",
		stones: [
			{box: [-5.6, -1.2, -3.0, -0.55, 1.0, -1.4], wear: 0.7, fallen: 0.1},
			{box: [-5.6, -1.2, -5.8, -0.7, 5.8, -3.6], fallen: 1},
			{box: [-5.6, 3.0, -4.4, -1.3, 3.6, -2.2], wear: 0.6, fallen: 0.1},
			{box: [0.95, -1.2, -3.6, 3.8, 2.6, -1.6], wear: 0.8, fallen: 0.7}
		],
		walks: [[-5.6, -0.55, 1.0, -2.2], [-5.6, -1.3, 3.6, -3.0]],
		pieces: [
			{
				name: "lift",
				stones: [{box: [-0.5, -3.0, -3.3, 0.9, 1.0, -1.7], wear: 0.6, fallen: 0}],
				walks: [[-0.5, 0.9, 1.0, -2.4]],
				states: [[0, 0, 0], [0, 2.6, 0]],
				start: 1,
				carries: true,
				time: 2.2
			},
			{name: "bridge", stones: [{box: [-2.25, 3.34, -3.3, -1.35, 3.58, -2.4], wear: 0.3, fallen: 0}], walks: [[-2.25, -1.35, 3.6, -3.0]], states: [[0, 0, 0], [0.85, 0, 0]]}
		],
		glyphs: [
			{name: "lift", at: [1.75, 1.75, -1.6], drives: ["lift"]},
			{name: "bridge", at: [-1.1, 4.9, -3.6], drives: ["bridge"]}
		],
		larva: [-2.2, 1.0, -2.2],
		home: [-2.75, 3.6, -3.6],
		moth: [-1.6, 1.0, -1.6],
		caps: [[-3.9, 1.0, -2.0, 0.5, 6, 0.13, 0], [-4.2, 3.6, -3.2, 0.6, 5, 0.15, 1]],
		sprouts: [[2.2, 2.6, -2.4, 0.5, 6]],
		shelves: [[-1.6, 2.4]]
	};

	public static final all = [first, second, third];
}
