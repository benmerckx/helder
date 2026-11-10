import Puzzle;

// The game: the screens in turn, the moth led by the pointer, the puzzle
// stepped at its fixed rate (the same steps whatever the frame rate: the
// same play for the same input), and the passing from one screen to the
// next (a pause once the larva is home, a fade into the mist and out).
class Game {
	public var index(default, null) = 0;
	public var puzzle(default, null):Puzzle;
	public var moth(default, null):Flight;
	// 1: all mist, 0: clear
	public var fade(default, null) = 1.0;
	public var eye:Vec;
	// what happens printed as it does (the playtests' check: -- --log)
	public var log = false;
	var clock = 0.0;
	var steps = 0;
	var home = -1.0;
	var leaving = false;

	public function new(eye:Vec) {
		this.eye = eye;
		start(0);
	}

	public function start(k:Int) {
		index = k;
		var s = Screens.all[k];
		puzzle = new Puzzle(s, eye);
		moth = new Flight(s.moth[0], s.moth[1] + Flight.FEET, s.moth[2]);
		home = -1;
		leaving = false;
	}

	// a press, a drag, a release: x, y on the moth's plane
	public function press(x:Float, y:Float) {
		moth.held = true;
		moth.lead(x, y);
	}

	public function drag(x:Float, y:Float)
		if (moth.held) moth.lead(x, y);

	public function release()
		moth.held = false;

	// to the time t (seconds)
	public function update(t:Float) {
		while (clock + Puzzle.STEP <= t) {
			clock += Puzzle.STEP;
			step();
		}
	}

	function step() {
		var dt = Puzzle.STEP;
		puzzle.eye = eye;
		moth.step(dt, puzzle);
		puzzle.step({x: moth.x, y: moth.y, z: moth.z});
		if (log)
			for (e in puzzle.events)
				Sys.println('afterglow: screen ${index + 1}: $e at ${Math.round(clock * 10) / 10} s');
		puzzle.events.resize(0);
		if (puzzle.solved && home < 0) home = clock;
		var last = index == Screens.all.length - 1;
		if (home >= 0 && !last && clock - home > 3.2) leaving = true;
		if (leaving) {
			fade = Math.min(1, fade + dt / 1.4);
			if (fade >= 1) start(index + 1);
		} else fade = Math.max(0, fade - dt / 1.6);
	}
}
