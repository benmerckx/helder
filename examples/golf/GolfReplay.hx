import Course.Hole;

// Recorded rounds replayed on the simulation alone (no window, no GPU):
// each shot a direction and a speed, played when the ball rests, the
// steps as the game takes them (Sim.DT). The physics has no trigonometry
// or transcendental functions in a step, so the same shots give the same
// result natively and as wasm32-wasi: the examples lane runs this on both
// and each listed hole must be holed in its strokes.
//
//   GolfReplay            the recorded rounds: a line each, exit 1 on a miss
//   GolfReplay tune       how far a shot rolls on a flat green, by speed
//   GolfReplay search N   shots that hole hole N (1-based) in one or two
class GolfReplay {
	// per hole: its index, then its shots (dx, dz, speed), holed in that many strokes
	public static final rounds:Array<{hole:Int, shots:Array<Array<Float>>}> = [
		{hole: 0, shots: [[0, -1, 4.4]]},
		{hole: 1, shots: [[0, -1, 3.55], [0.9944, 0.1059, 3.55]]},
		{hole: 3, shots: [[-0.6724, -0.7402, 7]]},
		{hole: 5, shots: [[-0.3074, -0.9516, 5.2]]},
		{hole: 7, shots: [[-0.0998, -0.995, 5.2]]},
		{hole: 8, shots: [[0.2588, -0.9659, 6.95], [0.9963, 0.0862, 4.8]]}
	];

	static function main() {
		var args = Sys.args();
		if (args[0] == "tune") return tune();
		if (args[0] == "search") return search(Std.parseInt(args[1]) - 1, args.length > 2 ? Std.parseInt(args[2]) : 1);
		var failed = 0;
		for (r in rounds) {
			var res = replay(Course.holes[r.hole], r.shots);
			var ok = res.sim.sunk && res.sim.strokes == r.shots.length;
			Sys.println('${ok ? "ok  " : "FAIL"} hole ${r.hole + 1} (${Course.holes[r.hole].name}): ${res.sim.sunk ? "holed" : "not holed"} in ${res.sim.strokes}, ${res.sim.steps} steps, ball at ${fmt(res.sim.ball.position.x)} ${fmt(res.sim.ball.position.y)} ${fmt(res.sim.ball.position.z)}, ${res.bytes} bytes allocated in ${res.allocating} steps (the buffers growing)');
			if (!ok) failed++;
			// (only while the buffers grow: a few steps, a little)
			if (res.allocating > 4 || res.bytes > 4096) {
				Sys.println('FAIL hole ${r.hole + 1}: its steps allocated more than the buffers growing');
				failed++;
			}
		}
		Sys.println(failed == 0 ? 'GolfReplay: ${rounds.length} holes holed' : 'GolfReplay: $failed of ${rounds.length} missed');
		if (failed > 0) Sys.exit(1);
	}

	static function fmt(f:Float):String
		return Std.string(Math.round(f * 10000) / 10000);

	// the shots played in turn, each when the ball rests; at most 20 s a shot
	public static function replay(hole:Hole, shots:Array<Array<Float>>):{sim:Sim, bytes:Float, allocating:Int} {
		var sim = new Sim(hole);
		var bytes = 0.0, allocating = 0;
		for (s in shots) {
			if (sim.sunk) break;
			sim.shoot(s[0], s[1], s[2]);
			var n = 0;
			// (the physics' buffers grow to the hole's size: its bodies at the
			// first step, the contacts and pairs at the most there have been)
			while (!sim.resting && !sim.sunk && n < 20 * 120) {
				var before = hxmc.GcStats.bytesAllocated();
				sim.step();
				var d = hxmc.GcStats.bytesAllocated() - before;
				if (d > 0 && Sys.getEnv("GOLF_TRACE") != null) Sys.println('  step ${sim.steps}: $d bytes, ${sim.physics.contacts} contacts');
				if (d > 0) allocating++;
				bytes += d;
				n++;
			}
		}
		return {sim: sim, bytes: bytes, allocating: allocating};
	}

	static function tune() {
		var hole:Hole = {name: "flat", par: 1, tee: {x: 0, y: 0, z: 0}, cup: {x: 100, y: 0, z: 100}, pieces: [Course.Piece.Flat(0, -15, 4, 40, 0)]};
		var speed = 0.6;
		while (speed <= 7.01) {
			var sim = new Sim(hole);
			sim.shoot(0, -1, speed);
			var n = 0;
			while (!sim.resting && n++ < 30 * 120)
				sim.step();
			Sys.println('speed ${fmt(speed)}: ${fmt(-sim.ball.position.z)} m in ${fmt(n / 120)} s');
			speed += 0.4;
		}
	}

	// a grid of directions and speeds from the tee; the shots that hole it in one, else the best two-shot pairs
	static function search(index:Int, depth:Int) {
		var hole = Course.holes[index];
		var found = 0;
		var t = hole.tee, c = hole.cup;
		var base = Math.atan2(c.x - t.x, -(c.z - t.z));
		for (ai in 0...121) {
			var a = base + (ai - 60) * 0.0125;
			for (si in 0...33) {
				var speed = 0.8 + si * 0.2;
				var dx = Math.round(Math.sin(a) * 10000) / 10000, dz = Math.round(-Math.cos(a) * 10000) / 10000;
				var res = replay(hole, [[dx, dz, speed]]);
				if (res.sim.sunk) {
					Sys.println('[$dx, $dz, $speed]');
					if (++found > 12) return;
				}
			}
		}
		if (found == 0) Sys.println("none in one");
		if (found > 0 || depth < 2) return;
		// (two: a first shot round the compass, then at the cup from where it stopped)
		var pairs = 0, misses = 0;
		for (ai in 0...72) {
			var a = ai * Math.PI * 2 / 72;
			var dx = Math.round(Math.sin(a) * 10000) / 10000, dz = Math.round(-Math.cos(a) * 10000) / 10000;
			for (si in 0...8) {
				var first = [dx, dz, 1.0 + si * 0.85];
				var res = replay(hole, [first]);
				if (res.sim.sunk || res.sim.strokes > 1) continue;
				var p = res.sim.ball.position;
				var b = Math.atan2(c.x - p.x, -(c.z - p.z));
				for (bi in 0...21) {
					var a2 = b + (bi - 10) * 0.025;
					for (s2 in 0...26) {
						var second = [Math.round(Math.sin(a2) * 10000) / 10000, Math.round(-Math.cos(a2) * 10000) / 10000, 0.8 + s2 * 0.25];
						var r2 = replay(hole, [first, second]);
						if (r2.sim.sunk && r2.sim.strokes == 2) {
							Sys.println('[$first, $second]');
							if (++pairs >= 6) return;
							break;
						}
					}
				}
			}
		}
		if (pairs == 0) Sys.println("none in two");
	}
}
