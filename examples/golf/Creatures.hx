import helder.gfx.shader.Vec3;
import helder.scene.Node;
import helder.scene.World;
import helder.scene.math.Quat;
import helder.scene.render.InstancedMesh;
import helder.scene.render.MeshRenderer;

// The islands' creatures, scenery that answers the play but never touches
// it: driven by the view's clock and a random stream of their own (never
// the simulation's, which they only read: where the ball is, how fast),
// so a recorded round plays the same, bit for bit, with them or without.
//
//   perched birds  on rails, bumper caps, posts and lanterns: they sit,
//                  turn and peck; a ball coming fast or close scatters
//                  them up and away in arcs, and each lands again on
//                  another perch far from the ball (Meadowdrift's finches
//                  and tits, Copperwind's gulls)
//   low flyers     round the course beside it, through the sharp band:
//                  swallows swooping (Meadowdrift), gulls gliding on still
//                  wings (Copperwind); pushed up and off the aim's line
//                  while the player aims
//   far flock      small and high across the sky, a loose group (swallows,
//                  Copperwind's swifts)
//   bats           at dusk, jinking out past the edges, low against the
//                  afterglow (Lanternwater)
//   moths          round each lantern, lit by it
//   the heron      Lanternwater's: stands on a rail, turns its head,
//                  lifts off slowly when the ball comes near and lands
//                  on another rail
//
// A bird is a body and two bent wings (an inner panel and a swept tip, so
// a wingtip can be darker), each drawn instanced: four draws for all the
// birds, bats and moths (InstancedMesh), the heron its own nodes. Flat
// arrays of floats; nothing allocated a frame.
class Creatures {
	final world:World;
	final kit:Kit;
	final bodies:InstancedMesh;
	final wings:InstancedMesh;
	final tips:InstancedMesh;
	final moths:InstancedMesh;
	// the heron's nodes
	final heron:Node;
	final heronNeck:Node;
	// (its own random stream: a hole's creatures the same each time it is played)
	var seed = 1;

	// --- the birds: FIELDS floats each
	// kind, state, x, y, z, yaw, pitch, flap phase, timer, from x y z, to x y z, mid x y z, t, duration, perch, size, look, a, b
	static inline var FIELDS = 28;
	final b:Array<Float>;
	var count = 0;
	static inline var MAX = 24;
	// kinds
	static inline var FINCH = 0;
	static inline var TIT = 1;
	static inline var GULL = 2;
	static inline var SWALLOW = 3;
	static inline var GLIDER = 4;
	static inline var FAR = 5;
	static inline var SWIFT = 6;
	static inline var BAT = 7;
	static inline var HERON = 8;
	// states
	static inline var SIT = 0;
	static inline var FLY = 1;
	static inline var AWAY = 2;
	static inline var CIRCLE = 3;

	// --- perches: x, y, z, yaw, taken
	final perches:Array<Float> = [];
	// --- moths: per lantern its head's x, y, z
	final lamps:Array<Float> = [];
	// the hole's middle and reach
	var cx = 0.0;
	var cz = 0.0;
	var cy = 0.0;
	var rx = 3.0;
	var rz = 3.0;
	var time = 0.0;
	var used = 0;
	var wingUsed = 0;
	var mothUsed = 0;
	public var visible = true;

	public function new(world:World, kit:Kit) {
		this.world = world;
		this.kit = kit;
		bodies = new InstancedMesh(kit.birdBody, MAX + 2, 0);
		wings = new InstancedMesh(kit.wingIn, MAX * 2 + 4, 0);
		tips = new InstancedMesh(kit.wingTip, MAX * 2 + 4, 0);
		moths = new InstancedMesh(kit.moth, 16, 0);
		for (m in [bodies, wings, tips, moths]) {
			m.castShadows = false;
			InstancedMesh.attach(world.node("creatures"), m);
		}
		b = [for (_ in 0...MAX * FIELDS) 0.0];
		heron = world.node("heron");
		var body = world.node("body", heron);
		MeshRenderer.attach(body, kit.heronBody);
		var legs = world.node("legs", heron);
		MeshRenderer.attach(legs, kit.heronLegs);
		heronNeck = world.node("neck", heron);
		heronNeck.position = new Vec3(0, 0.7, -0.14);
		var head = world.node("head", heronNeck);
		MeshRenderer.attach(head, kit.heronNeck);
		var beak = world.node("beak", heronNeck);
		MeshRenderer.attach(beak, kit.heronBeak);
		heron.visible = false;
	}

	inline function random():Float {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff;
		return seed / 0x7fffffff;
	}

	// --- a hole's creatures

	// perch: a place a bird may sit (x, y its top, z; yaw its facing)
	public function perch(x:Float, y:Float, z:Float, yaw:Float) {
		for (v in [x, y, z, yaw, 0])
			perches.push(v);
	}

	// a lantern's head, for its moths
	public function lamp(x:Float, y:Float, z:Float) {
		for (v in [x, y, z])
			lamps.push(v);
	}

	// the hole's perches and lamps cleared (before they are given again)
	public function clear() {
		perches.resize(0);
		lamps.resize(0);
		count = 0;
		heron.visible = false;
	}

	// the hole's creatures, once its perches and lamps are given: per island
	public function populate(hole:Int, island:Int, minX:Float, maxX:Float, minZ:Float, maxZ:Float, y:Float, tee:Vec3, cup:Vec3) {
		seed = 1 + hole * 7919;
		cx = (minX + maxX) / 2;
		cz = (minZ + maxZ) / 2;
		cy = y;
		rx = (maxX - minX) / 2;
		rz = (maxZ - minZ) / 2;
		// (no perch by the tee or the cup: the shot's ends left clear)
		var k = 0;
		while (k < perches.length) {
			var dx = perches[k] - tee.x, dz = perches[k + 2] - tee.z, ex = perches[k] - cup.x, ez = perches[k + 2] - cup.z;
			if (dx * dx + dz * dz < 0.7 * 0.7 || ex * ex + ez * ez < 0.6 * 0.6) perches[k + 4] = 1;
			k += 5;
		}
		switch island {
			case 0:
				// (finches and tits on the rails, swallows hawking round, a far flock)
				var n = 2 + Std.int(random() * 2);
				for (i in 0...n)
					sitter(i % 2 == 0 ? FINCH : TIT, tee);
				for (i in 0...4)
					add(SWALLOW, CIRCLE, i);
				for (i in 0...6)
					add(FAR, CIRCLE, i);
			case 1:
				// (gulls on the rails and gliding round the cliffs, swifts high)
				for (i in 0...2)
					sitter(GULL, tee);
				for (i in 0...3)
					add(GLIDER, CIRCLE, i);
				for (i in 0...7)
					add(SWIFT, CIRCLE, i);
			case _:
				// (the heron on a rail, bats out past the edges, moths at the lanterns)
				sitter(HERON, tee);
				for (i in 0...5)
					add(BAT, CIRCLE, i);
		}
		time = 0;
	}

	// (a bird of kind at a free perch: on the rail side away from the tee if it can)
	function sitter(kind:Int, tee:Vec3) {
		var p = freePerch(tee.x, tee.z, kind == HERON ? 1.4 : 1.0);
		if (p < 0) return;
		var i = add(kind, SIT, 0);
		if (i < 0) return;
		land(i, p);
	}

	function add(kind:Int, state:Int, index:Int):Int {
		if (count >= MAX) return -1;
		var o = count * FIELDS;
		for (k in 0...FIELDS)
			b[o + k] = 0;
		b[o] = kind;
		b[o + 1] = state;
		b[o + 7] = random() * 6.283;
		b[o + 8] = 1 + random() * 3;
		b[o + 23] = index;
		b[o + 24] = random();
		b[o + 25] = random();
		b[o + 21] = -1;
		return count++;
	}

	// (a free perch at least `away` from x, z, chosen at random among them; -1: none)
	function freePerch(x:Float, z:Float, away:Float):Int {
		var n = Std.int(perches.length / 5);
		if (n == 0) return -1;
		var start = Std.int(random() * n);
		for (j in 0...n) {
			var k = ((start + j) % n) * 5;
			if (perches[k + 4] != 0) continue;
			var dx = perches[k] - x, dz = perches[k + 2] - z;
			if (dx * dx + dz * dz < away * away) continue;
			return k;
		}
		return -1;
	}

	// (bird i set down on perch p)
	function land(i:Int, p:Int) {
		var o = i * FIELDS;
		perches[p + 4] = 1;
		b[o + 21] = p;
		b[o + 1] = SIT;
		b[o + 2] = perches[p];
		b[o + 3] = perches[p + 1];
		b[o + 4] = perches[p + 2];
		b[o + 5] = perches[p + 3] + (random() - 0.5) * 0.8;
		b[o + 6] = 0;
		b[o + 8] = 1 + random() * 3;
	}

	// (bird i off its perch: in an arc to x, y, z over the time given, up by lift at the arc's top)
	function fly(i:Int, x:Float, y:Float, z:Float, duration:Float, lift:Float, sideways:Float) {
		var o = i * FIELDS;
		var p = Std.int(b[o + 21]);
		if (p >= 0) perches[p + 4] = 0;
		b[o + 21] = -1;
		b[o + 1] = FLY;
		b[o + 9] = b[o + 2];
		b[o + 10] = b[o + 3];
		b[o + 11] = b[o + 4];
		b[o + 12] = x;
		b[o + 13] = y;
		b[o + 14] = z;
		// (the arc's middle: above the way, bent sideways)
		var dx = x - b[o + 2], dz = z - b[o + 4];
		b[o + 15] = (b[o + 2] + x) / 2 - dz * sideways;
		b[o + 16] = Math.max(b[o + 3], y) + lift;
		b[o + 17] = (b[o + 4] + z) / 2 + dx * sideways;
		b[o + 18] = 0;
		b[o + 19] = duration;
	}

	// --- the frame

	// dt: the view's (seconds); the ball where it is and its speed; aiming: the
	// aim's line from the ball along (ax, az) for len metres
	public function update(dt:Float, ball:Vec3, speed:Float, aiming:Bool, ax:Float, az:Float, len:Float) {
		time += dt;
		used = 0;
		wingUsed = 0;
		mothUsed = 0;
		heron.visible = false;
		for (i in 0...count) {
			var o = i * FIELDS, kind = Std.int(b[o]);
			switch Std.int(b[o + 1]) {
				case SIT:
					sit(i, o, kind, dt, ball, speed);
				case FLY:
					flight(i, o, kind, dt);
				case AWAY:
					b[o + 8] -= dt;
					if (b[o + 8] <= 0) {
						// (back: to a perch far from the ball, in from where it waited)
						var p = freePerch(ball.x, ball.z, 1.6);
						if (p >= 0) {
							b[o + 21] = -1;
							fly(i, perches[p], perches[p + 1], perches[p + 2], kind == HERON ? 4.5 : 2.6 + random(), kind == HERON ? 0.6 : 0.5, 0.15);
							b[o + 22] = p;
							perches[p + 4] = 1;
						} else
							b[o + 8] = 2;
					}
				case _:
					circle(i, o, kind, dt, aiming, ball, ax, az, len);
			}
		}
		// (the moths: five a lantern, round its head)
		var l = 0;
		while (l < lamps.length && mothUsed < moths.capacity) {
			for (m in 0...5) {
				if (mothUsed >= moths.capacity) break;
				var ph = m * 1.2566 + l, sp = 1.6 + (m % 3) * 0.7;
				var a = time * sp + ph, r = 0.12 + 0.07 * Math.sin(time * 1.3 + m * 2.1);
				var x = lamps[l] + Math.cos(a) * r, z = lamps[l + 2] + Math.sin(a) * r;
				var y = lamps[l + 1] + 0.02 + Math.sin(time * 2.7 + m * 1.7) * 0.07;
				var q = Quat.axisAngle(new Vec3(0, 1, 0), -a) * Quat.axisAngle(new Vec3(0, 0, 1), Math.sin(time * 38 + m) * 0.5);
				moths.setTransform(mothUsed, x, y, z, q.x, q.y, q.z, q.w, 0.035);
				mothUsed++;
			}
			l += 3;
		}
		bodies.count = visible ? used : 0;
		wings.count = tips.count = visible ? wingUsed : 0;
		moths.count = visible ? mothUsed : 0;
		if (!visible) heron.visible = false;
		bodies.changed();
		wings.changed();
		tips.changed();
		moths.changed();
	}

	// (perched: turning and pecking now and then; off when the ball comes fast or close)
	function sit(i:Int, o:Int, kind:Int, dt:Float, ball:Vec3, speed:Float) {
		var x = b[o + 2], y = b[o + 3], z = b[o + 4];
		var dx = x - ball.x, dz = z - ball.z, d = Math.sqrt(dx * dx + dz * dz);
		var near = kind == HERON ? 1.1 : 0.75;
		if ((d < near && speed > 0.5) || d < near * 0.5 || (d < near * 1.6 && speed > 3)) {
			// (away from the ball, up and out past the edge, then back later)
			var l = d > 1e-4 ? d : 1;
			var ux = dx / l, uz = dz / l;
			var out = (kind == HERON ? 2.5 : 2.2) + random() * 1.5;
			var tx = x + ux * out + (random() - 0.5) * 1.2, tz = z + uz * out + (random() - 0.5) * 1.2;
			fly(i, tx, y + (kind == HERON ? 1.4 : 1.6) + random(), tz, kind == HERON ? 3.2 : 1.1 + random() * 0.5, kind == HERON ? 0.5 : 0.35,
				(random() - 0.5) * 0.6);
			b[o + 22] = -2;
			return;
		}
		b[o + 8] -= dt;
		if (b[o + 8] <= 0) {
			// (a turn, or a peck)
			b[o + 8] = 1.2 + random() * 3;
			if (random() < 0.6) b[o + 5] += (random() - 0.5) * 1.6 else b[o + 6] = 1;
		}
		b[o + 6] = Math.max(0, b[o + 6] - dt * 3);
		var peck = b[o + 6] > 0 ? Math.sin(b[o + 6] * Math.PI) * 0.5 : 0;
		if (kind == HERON) {
			heronAt(x, y, z, b[o + 5], Math.sin(time * 0.6 + b[o + 24] * 6) * 0.7 + (b[o + 6] > 0 ? 0.4 : 0), 0, false, 0);
			return;
		}
		var q = Quat.axisAngle(new Vec3(0, 1, 0), b[o + 5]) * Quat.axisAngle(new Vec3(1, 0, 0), 0.25 - peck);
		bird(kind, x, y + size(kind) * 0.12, z, q, 0, true);
	}

	// (on its way: along the arc, flapping; there, landed or waiting away)
	function flight(i:Int, o:Int, kind:Int, dt:Float) {
		var t = b[o + 18] = Math.min(1, b[o + 18] + dt / b[o + 19]);
		var u = t * t * (3 - 2 * t);
		var s = 1 - u;
		var x = s * s * b[o + 9] + 2 * s * u * b[o + 15] + u * u * b[o + 12];
		var y = s * s * b[o + 10] + 2 * s * u * b[o + 16] + u * u * b[o + 13];
		var z = s * s * b[o + 11] + 2 * s * u * b[o + 17] + u * u * b[o + 14];
		var vx = x - b[o + 2], vy = y - b[o + 3], vz = z - b[o + 4];
		b[o + 2] = x;
		b[o + 3] = y;
		b[o + 4] = z;
		var h = Math.sqrt(vx * vx + vz * vz);
		if (h > 1e-5) b[o + 5] = Math.atan2(-vx, -vz);
		var pitch = h > 1e-5 ? Math.max(-0.6, Math.min(0.6, Math.atan2(vy, h))) : 0;
		if (t >= 1) {
			var p = Std.int(b[o + 22]);
			if (p >= 0) {
				perches[p + 4] = 0;
				land(i, p);
			} else {
				// (scattered: out of the way a while)
				b[o + 1] = AWAY;
				b[o + 8] = kind == HERON ? 6 + random() * 4 : 3 + random() * 4;
			}
		}
		if (kind == HERON) {
			heronAt(x, y, z, b[o + 5], 0, pitch, true, time);
			return;
		}
		// (flapping fast off the perch, gliding in to land)
		b[o + 7] += dt * (t < 0.7 ? 22 : 12);
		var flap = Math.sin(b[o + 7]) * (t > 0.85 ? 0.25 : 0.7);
		var q = Quat.axisAngle(new Vec3(0, 1, 0), b[o + 5]) * Quat.axisAngle(new Vec3(1, 0, 0), pitch);
		bird(kind, x, y, z, q, flap, false);
	}

	// (flyers on their rounds)
	function circle(i:Int, o:Int, kind:Int, dt:Float, aiming:Bool, ball:Vec3, ax:Float, az:Float, len:Float) {
		var k = b[o + 23], r0 = b[o + 24], r1 = b[o + 25];
		var x = 0.0, y = 0.0, z = 0.0, bank = 0.0, flap = 0.0;
		switch kind {
			case SWALLOW | GLIDER:
				// (round the course beside it, a loose group: one way round, swooping)
				var glide = kind == GLIDER;
				var w = glide ? 0.16 : 0.32;
				var a = time * w - k * (glide ? 0.9 : 0.22) + r0 * 0.15;
				var ex = rx + (glide ? 2.2 : 1.1) + Math.sin(time * 0.7 + k) * 0.35, ez = rz + (glide ? 2.2 : 1.1) + Math.cos(time * 0.5 + k) * 0.35;
				x = cx + Math.cos(a) * ex;
				z = cz + Math.sin(a) * ez;
				y = cy + (glide ? 1.6 + k * 0.35 : 0.8 + Math.sin(a * 3 + k) * 0.35 + r1 * 0.3);
				bank = glide ? 0.35 : 0.5 + 0.3 * Math.sin(a * 3 + k);
				flap = glide ? Math.sin(time * 1.3 + k) * 0.08 : Math.sin(time * 16 + k * 1.7) * 0.6 * (0.5 + 0.5 * Math.sin(time * 1.9 + k));
			case FAR | SWIFT:
				// (a loose flock across the sky, far and high, coming round again)
				var period = 46.0;
				var u = ((time + 9) / period) % 1;
				var side = -18 + u * 36;
				x = cx + side + Math.sin(k * 2.3) * 0.9;
				z = cz - Math.max(rz, 4) - 12 + Math.cos(k * 1.7) * 0.8 + Math.sin(time * 0.4 + k) * 0.3;
				y = cy + 5.5 + Math.sin(k * 1.1) * 0.6 + Math.sin(time * 0.9 + k) * 0.15;
				flap = Math.sin(time * (kind == SWIFT ? 20 : 13) + k * 2.1) * 0.7;
				b[o + 5] = -Math.PI / 2;
				bank = 0;
			case _:
				// (bats: round past the edges, low, their heading jinking)
				var a = time * 0.45 + k * 1.3;
				var j = Math.sin(time * 5.3 + k * 2.7) * 0.25 + Math.sin(time * 8.9 + k) * 0.12;
				x = cx + Math.cos(a + j * 0.4) * (rx + 2.0 + r0);
				z = cz + Math.sin(a + j * 0.4) * (rz + 2.0 + r0);
				y = cy + 0.2 + r1 * 1.4 + Math.sin(time * 3.1 + k) * 0.2;
				bank = j * 2;
				flap = Math.sin(time * 26 + k * 1.3) * 0.8;
		}
		// (off the aim's line: pushed aside and up)
		if (aiming && len > 0) {
			var px = x - ball.x, pz = z - ball.z;
			var along = Math.max(0, Math.min(len, px * ax + pz * az));
			var qx = px - ax * along, qz = pz - az * along, d = Math.sqrt(qx * qx + qz * qz);
			if (d < 1.4) {
				var push = (1.4 - d) / 1.4;
				var l = d > 1e-4 ? d : 1;
				x += (d > 1e-4 ? qx / l : -az) * push * 1.4;
				z += (d > 1e-4 ? qz / l : ax) * push * 1.4;
				y += push * 1.2;
			}
		}
		var vx = x - b[o + 2], vz = z - b[o + 4];
		b[o + 2] = x;
		b[o + 3] = y;
		b[o + 4] = z;
		if (vx * vx + vz * vz > 1e-8) b[o + 5] = Math.atan2(-vx, -vz);
		var q = Quat.axisAngle(new Vec3(0, 1, 0), b[o + 5]) * Quat.axisAngle(new Vec3(0, 0, 1), bank);
		bird(kind, x, y, z, q, flap, false);
	}

	// (a kind's body length, metres)
	static inline function size(kind:Int):Float
		return switch kind {
			case FINCH | TIT: 0.2;
			case GULL: 0.3;
			case GLIDER: 0.2;
			case SWALLOW: 0.13;
			case FAR: 0.14;
			case SWIFT: 0.12;
			case BAT: 0.08;
			case _: 0.12;
		}

	// (a bird drawn: its body, its wings flapping by flap or folded along its back)
	function bird(kind:Int, x:Float, y:Float, z:Float, q:Quat, flap:Float, folded:Bool) {
		if (used >= bodies.capacity || wingUsed + 2 > wings.capacity) return;
		var len = size(kind);
		var span = switch kind {
			case GULL: 0.34;
			case GLIDER: 0.26;
			case FINCH | TIT: 0.17;
			case SWALLOW: 0.17;
			case SWIFT: 0.17;
			case BAT: 0.12;
			case FAR: 0.17;
			case _: 0.1;
		}
		bodies.setTransform(used, x, y, z, q.x, q.y, q.z, q.w, len);
		var body = 0x2b2d42, wing = 0x2b2d42, tip = 0x2b2d42;
		switch kind {
			case FINCH:
				body = 0xe9b949;
				wing = 0x6b6a52;
				tip = 0x2f3040;
			case TIT:
				body = 0xf1ede0;
				wing = 0x3d4c78;
				tip = 0x22263c;
			case GULL | GLIDER:
				body = 0xf7f6f4;
				wing = 0xb4b9c9;
				tip = 0x2b2d42;
			case SWALLOW:
				body = 0x2f3d6e;
				wing = 0x2a3462;
				tip = 0x1b2042;
			case FAR:
				body = 0x4a5070;
				wing = 0x4a5070;
				tip = 0x3a3f5c;
			case SWIFT:
				body = 0x4a3036;
				wing = 0x43292f;
				tip = 0x2e1c20;
			case BAT:
				body = 0x1d1838;
				wing = 0x25204a;
				tip = 0x17132e;
		}
		color(bodies, used, body);
		used++;
		for (side in 0...2) {
			var w = if (folded) {
				// (folded: along its back, a little out)
				side == 0 ? q * Quat.axisAngle(new Vec3(0, 1, 0), -1.4) : q * Quat.axisAngle(new Vec3(0, 1, 0), 1.4) * Quat.axisAngle(new Vec3(0, 0, 1), Math.PI);
			} else
				side == 0 ? q * Quat.axisAngle(new Vec3(0, 0, 1), flap) : q * Quat.axisAngle(new Vec3(0, 0, 1), Math.PI - flap);
			var s = folded ? span * 0.75 : span;
			var wy = folded ? y + len * 0.1 : y + len * 0.06;
			wings.setTransform(wingUsed, x, wy, z, w.x, w.y, w.z, w.w, s);
			tips.setTransform(wingUsed, x, wy, z, w.x, w.y, w.z, w.w, s);
			color(wings, wingUsed, wing);
			color(tips, wingUsed, tip);
			wingUsed++;
		}
	}

	static inline function color(m:InstancedMesh, i:Int, hex:Int) {
		var c = Kit.rgb(hex);
		m.setColor(i, c.x, c.y, c.z);
	}

	// (the heron at x, y, z facing yaw: its head turned by look; flying: wings out and beating slowly)
	function heronAt(x:Float, y:Float, z:Float, yaw:Float, look:Float, pitch:Float, flying:Bool, t:Float) {
		var s = 0.55;
		heron.visible = visible;
		heron.position = new Vec3(x, y, z);
		var q = Quat.axisAngle(new Vec3(0, 1, 0), yaw) * Quat.axisAngle(new Vec3(1, 0, 0), flying ? pitch * 0.5 - 0.25 : 0);
		heron.rotation = q;
		heron.scale = new Vec3(s, s, s);
		heronNeck.rotation = Quat.axisAngle(new Vec3(0, 1, 0), look) * Quat.axisAngle(new Vec3(1, 0, 0), flying ? -0.6 : 0);
		if (!flying || wingUsed + 2 > wings.capacity) return;
		var flap = Math.sin(t * 5) * 0.55;
		// (the wings from its shoulders)
		var at = q.rotate(new Vec3(0, 0.68 * s, 0));
		for (side in 0...2) {
			var w = side == 0 ? q * Quat.axisAngle(new Vec3(0, 0, 1), flap) : q * Quat.axisAngle(new Vec3(0, 0, 1), Math.PI - flap);
			wings.setTransform(wingUsed, x + at.x, y + at.y, z + at.z, w.x, w.y, w.z, w.w, 0.42);
			tips.setTransform(wingUsed, x + at.x, y + at.y, z + at.z, w.x, w.y, w.z, w.w, 0.42);
			color(wings, wingUsed, 0x8392ba);
			color(tips, wingUsed, 0x3a3f60);
			wingUsed++;
		}
	}
}
