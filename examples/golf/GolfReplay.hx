import Course.Hole;

// Recorded rounds replayed on the simulation alone (no window, no GPU):
// each shot a direction, a speed and how long to wait once the ball rests
// (steps of Sim.DT; 60 when left out: the game's demo waits as long), the
// steps as the game takes them. The physics has no trigonometry or
// transcendental functions in a step, so the same shots give the same
// result natively and as wasm32-wasi: the examples lane runs this on both
// and every hole must be holed in its strokes.
//
//   GolfReplay                        the recorded rounds: a line each, exit 1 on a miss
//   GolfReplay tune                   how far a shot rolls on a flat green, by speed
//   GolfReplay search N [shots] [x z] [wide]
//                                     after the shots given (JSON), the next shots that hole
//                                     hole N (1-based); else those ending nearest x, z (the cup)
class GolfReplay {
	public static inline var WAIT = 60;

	// per hole: its index, then its shots (dx, dz, speed[, wait]), holed in that many strokes
	public static final rounds:Array<{hole:Int, shots:Array<Array<Float>>}> = [
		{hole: 0, shots: [[0, -1, 4.4]]},
		{hole: 1, shots: [[0, -1, 3.55], [0.9944, 0.1059, 3.55]]},
		{hole: 2, shots: [[-0.3074, -0.9516, 6.88]]},
		{hole: 3, shots: [[-0.6631, -0.7485, 5.36]]},
		{hole: 4, shots: [[-0.4719, -0.8816, 6.88], [0.994, 0.1097, 3.46]]},
		{hole: 5, shots: [[-0.0749, -0.9972, 6.88]]},
		{hole: 6, shots: [[-0.2836, -0.959, 6.69]]},
		{hole: 7, shots: [[-0.512, -0.859, 6.5]]},
		{hole: 8, shots: [[-0.1741, -0.9847, 6.31]]},
		{hole: 9, shots: [[0, -1, 6.88], [-0.6816, -0.7317, 0.99]]},
		{hole: 10, shots: [[0, -1, 4.41, 0], [-0.6816, -0.7317, 6.5]]},
		{hole: 11, shots: [[-0.6052, -0.7961, 6.88], [0.8165, 0.5773, 2.7]]},
		{hole: 12, shots: [[-0.0749, -0.9972, 6.5]]},
		{hole: 13, shots: [[-0.0976, -0.9952, 4.6]]},
		{hole: 14, shots: [[-0.3456, -0.9384, 5.55], [0.6954, -0.7187, 4.98]]},
		{hole: 15, shots: [[0.1658, -0.9862, 4.6], [0.4326, 0.9016, 6.88], [-0.5261, -0.8504, 1.18]]},
		{hole: 16, shots: [[-0.5249, -0.8512, 3.65], [0.7606, -0.6492, 6.88], [-0.6395, -0.7688, 3.84]]},
		{hole: 17, shots: [[0.0311, -0.9995, 4.98], [0.1353, -0.9908, 6.88], [0.6912, 0.7227, 6.88], [0.1045, -0.9945, 2.51]]}
	];

	static function main() {
		var args = Sys.args();
		if (args[0] == "tune") return tune();
		if (args[0] == "search") return search(args.slice(1));
		if (args[0] == "trace") return follow(Std.parseInt(args[1]) - 1, haxe.Json.parse(args[2]));
		var failed = 0;
		var seen = [for (_ in Course.holes) false];
		for (r in rounds) {
			seen[r.hole] = true;
			var res = replay(Course.holes[r.hole], r.shots);
			var ok = res.sim.sunk && res.sim.strokes == r.shots.length;
			Sys.println('${ok ? "ok  " : "FAIL"} hole ${r.hole + 1} (${Course.holes[r.hole].name}): ${res.sim.sunk ? "holed" : "not holed"} in ${res.sim.strokes} (par ${Course.holes[r.hole].par}), ${res.sim.steps} steps, ball at ${fmt(res.sim.ball.position.x)} ${fmt(res.sim.ball.position.y)} ${fmt(res.sim.ball.position.z)}, ${res.bytes} bytes allocated in ${res.allocating} steps (the buffers growing)');
			if (!ok) failed++;
			// (only while the buffers grow: a few steps, a little)
			if (res.allocating > 6 || res.bytes > 4096) {
				Sys.println('FAIL hole ${r.hole + 1}: its steps allocated more than the buffers growing');
				failed++;
			}
		}
		for (i in 0...seen.length)
			if (!seen[i]) {
				Sys.println('FAIL hole ${i + 1} (${Course.holes[i].name}): no recorded round');
				failed++;
			}
		Sys.println(failed == 0 ? 'GolfReplay: ${rounds.length} holes holed' : 'GolfReplay: $failed failed');
		if (failed > 0) Sys.exit(1);
	}

	static function fmt(f:Float):String
		return Std.string(Math.round(f * 10000) / 10000);

	// the shots played in turn, each when the ball has rested its wait; at most 20 s a shot
	public static function replay(hole:Hole, shots:Array<Array<Float>>):{sim:Sim, bytes:Float, allocating:Int} {
		var sim = new Sim(hole);
		var bytes = 0.0, allocating = 0;
		function run(limit:Int) {
			var n = 0;
			// (the physics' buffers grow to the hole's size: its bodies at the
			// first step, the contacts and pairs at the most there have been)
			while (!sim.sunk && n < limit) {
				var before = hxmc.GcStats.bytesAllocated();
				sim.step();
				var d = hxmc.GcStats.bytesAllocated() - before;
				if (d > 0 && Sys.getEnv("GOLF_TRACE") != null) Sys.println('  step ${sim.steps}: $d bytes, ${sim.physics.contacts} contacts');
				if (d > 0) allocating++;
				bytes += d;
				n++;
				if (limit > 1000 && sim.resting) break;
			}
		}
		for (s in shots) {
			if (sim.sunk) break;
			// (resting: its wait, then the shot)
			run(s.length > 3 ? Std.int(s[3]) : WAIT);
			if (!sim.resting) run(20 * 120);
			sim.shoot(s[0], s[1], s[2]);
			run(20 * 120);
		}
		return {sim: sim, bytes: bytes, allocating: allocating};
	}

	static function tune() {
		var hole:Hole = {name: "flat", world: 0, par: 1, tee: {x: 0, y: 0, z: 0}, cup: {x: 100, y: 0, z: 100}, pieces: [Course.Piece.Flat(0, -15, 4, 40, 0)]};
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

	// the ball's way through the shots given, every quarter second
	static function follow(index:Int, shots:Array<Array<Float>>) {
		var hole = Course.holes[index];
		for (n in 0...shots.length + 1) {
			var sim = replay(hole, shots.slice(0, n)).sim;
			var p = sim.ball.position;
			Sys.println('after ${n}: ${fmt(p.x)} ${fmt(p.y)} ${fmt(p.z)}, ${sim.strokes} strokes, step ${sim.steps}${sim.sunk ? ", holed" : ""}, gates ${sim.gateOpen}');
		}
		var sim = new Sim(hole);
		var k = 0;
		for (s in shots) {
			var w = s.length > 3 ? Std.int(s[3]) : WAIT;
			for (_ in 0...w) sim.step();
			while (!sim.resting) sim.step();
			sim.shoot(s[0], s[1], s[2]);
			var n = 0;
			while (!sim.sunk && n < 20 * 120 && !(n > 2 && sim.resting)) {
				sim.step();
				if (n % 30 == 0) {
					var p = sim.ball.position, v = sim.ball.velocity;
					Sys.println('  shot $k t ${fmt(n / 120)}: ${fmt(p.x)} ${fmt(p.y)} ${fmt(p.z)} v ${fmt(v.x)} ${fmt(v.y)} ${fmt(v.z)}${sim.grounded ? " ground" : ""} area ${sim.area}');
				}
				n++;
			}
			k++;
		}
	}

	// a grid of directions and speeds after the shots given: those that hole it, else the nearest to a point
	static function search(args:Array<String>) {
		var index = Std.parseInt(args[0]) - 1;
		var hole = Course.holes[index];
		var prefix:Array<Array<Float>> = args.length > 1 && args[1] != "" ? haxe.Json.parse(args[1]) : [];
		var tx = args.length > 3 ? Std.parseFloat(args[2]) : hole.cup.x, tz = args.length > 3 ? Std.parseFloat(args[3]) : hole.cup.z;
		var wide = args.indexOf("wide") >= 0;
		var start = replay(hole, prefix).sim;
		var p = start.ball.position;
		Sys.println('from ${fmt(p.x)} ${fmt(p.y)} ${fmt(p.z)}, ${start.strokes} strokes${start.sunk ? ", holed" : ""}');
		var base = Math.atan2(tx - p.x, -(tz - p.z));
		var found = 0;
		var best:Array<{d:Float, s:String}> = [];
		var angles = wide ? 240 : 121;
		var waits = [for (w in (Sys.getEnv("WAITS") ?? "60").split(",")) Std.parseInt(w)];
		for (wait in waits)
		for (ai in 0...angles) {
			var a = wide ? ai * Math.PI * 2 / angles : base + (ai - 60) * 0.0125;
			for (si in 0...33) {
				var speed = Math.round((0.8 + si * 0.19) * 100) / 100;
				var dx = Math.round(Math.sin(a) * 10000) / 10000, dz = Math.round(-Math.cos(a) * 10000) / 10000;
				var shot = wait == WAIT ? [dx, dz, speed] : [dx, dz, speed, wait];
				var res = replay(hole, prefix.concat([shot]));
				var s = haxe.Json.stringify(shot);
				if (res.sim.sunk && res.sim.strokes == prefix.length + 1) {
					Sys.println('holed: $s');
					if (++found > 10) return;
				} else if (res.sim.strokes == prefix.length + 1) {
					var q = res.sim.ball.position;
					var d = Math.sqrt((q.x - tx) * (q.x - tx) + (q.z - tz) * (q.z - tz));
					best.push({d: d, s: '$s -> ${fmt(q.x)} ${fmt(q.y)} ${fmt(q.z)}'});
				}
			}
		}
		if (found > 0) return;
		best.sort((a, b) -> a.d < b.d ? -1 : a.d > b.d ? 1 : 0);
		Sys.println("none holed; nearest:");
		for (i in 0...Std.int(Math.min(10, best.length)))
			Sys.println('  ${fmt(best[i].d)} m: ${best[i].s}');
	}
}
