import helder.os.audio.Sfx;

// The game's sounds, made here procedurally (no files): a putter's tock, a
// knock off a rail, a thud on landing, a bumper's boing, a portal's warp, a
// switch's click and its gates' rumble, a crumbling tile, a splash, a
// whoosh for a fall, the cup's rattle and plunk and a chime on a hole-in,
// mixed by helder.os's Sfx (desktop and the web: no audio back end on
// phones yet, where they are silent). Kept soft: a little under each
// event, never a wall of noise.
class Sounds {
	static var sfx:Null<Sfx>;
	static var tock = -1;
	static var knock = -1;
	static var thud = -1;
	static var plunk = -1;
	static var whoosh = -1;
	static var chime = -1;
	static var boingId = -1;
	static var warpId = -1;
	static var clickId = -1;
	static var rumbleId = -1;
	static var crumbleId = -1;
	static var splashId = -1;
	static var seed = 12345;
	// (the last time each was played: the same one not again within a few hundredths of a second)
	static var last = [for (_ in 0...16) -1.0];

	// the sounds made and the output opened (before the first is played: a few milliseconds)
	public static function start() {
		if (sfx != null) return;
		var s = Sfx.open();
		sfx = s;
		if (!s.playing) return;
		var tau = 2 * Math.PI;
		tock = s.add(make(0.12, t -> 0.7 * Math.sin(tau * 1150 * t) * Math.exp(-t * 60) + 0.35 * noise() * Math.exp(-t * 400)));
		knock = s.add(make(0.1, t -> 0.6 * Math.sin(tau * 520 * t) * Math.exp(-t * 55) + 0.2 * noise() * Math.exp(-t * 300)));
		var lp = 0.0;
		thud = s.add(make(0.18, t -> {
			lp += (noise() - lp) * 0.08;
			0.8 * Math.sin(tau * (140 - 200 * t) * t) * Math.exp(-t * 28) + 0.6 * lp * Math.exp(-t * 40);
		}));
		plunk = s.add(make(0.5, t -> {
			// (two rattles on the rim, then the drop)
			var r = (t < 0.05 ? Math.exp(-t * 200) : t < 0.11 ? 0.6 * Math.exp(-(t - 0.07) * 200) : 0) * noise() * 0.4;
			var d = t > 0.12 ? 0.8 * Math.sin(tau * (330 - 160 * (t - 0.12)) * (t - 0.12)) * Math.exp(-(t - 0.12) * 9) : 0;
			r + d;
		}));
		var low = 0.0;
		whoosh = s.add(make(0.6, t -> {
			low += (noise() - low) * (0.02 + 0.1 * t);
			low * 1.6 * Math.sin(Math.PI * t / 0.6);
		}));
		chime = s.add(make(1.4, t -> {
			var v = 0.0;
			var notes = [523.25, 659.25, 783.99, 1046.5];
			for (k in 0...4) {
				var at = t - k * 0.08;
				if (at > 0) v += 0.22 * (Math.sin(tau * notes[k] * at) + 0.3 * Math.sin(tau * notes[k] * 2 * at)) * Math.exp(-at * 3.0);
			}
			v;
		}));
		// (a spring: a pitch bending down, wobbling)
		var ph = 0.0;
		boingId = s.add(make(0.32, t -> {
			ph += tau * (380 + 260 * Math.exp(-t * 14) + 30 * Math.sin(t * 60)) / Sfx.RATE;
			0.55 * Math.sin(ph) * Math.exp(-t * 11);
		}));
		// (a portal: a rising sweep through a shimmer)
		var pw = 0.0;
		warpId = s.add(make(0.5, t -> {
			pw += tau * (220 + 1400 * t * t) / Sfx.RATE;
			var env = Math.sin(Math.PI * t / 0.5);
			0.3 * env * (Math.sin(pw) + 0.5 * Math.sin(pw * 1.5 + Math.sin(t * 90)));
		}));
		clickId = s.add(make(0.08, t -> 0.5 * Math.sin(tau * 1800 * t) * Math.exp(-t * 90) + 0.3 * noise() * Math.exp(-t * 500)));
		var rl = 0.0;
		rumbleId = s.add(make(0.45, t -> {
			rl += (noise() - rl) * 0.03;
			2.2 * rl * Math.sin(Math.PI * t / 0.45) + 0.15 * Math.sin(tau * 70 * t) * Math.sin(Math.PI * t / 0.45);
		}));
		crumbleId = s.add(make(0.5, t -> {
			// (cracks: bursts of noise, fewer as it falls away)
			var grain = Math.sin(t * 160) > 0.3 - t ? 1 : 0.2;
			0.45 * noise() * grain * Math.exp(-t * 6);
		}));
		var sl = 0.0;
		splashId = s.add(make(0.7, t -> {
			sl += (noise() - sl) * (0.25 - 0.3 * t);
			var bloop = t < 0.15 ? 0.4 * Math.sin(tau * (600 - 2000 * t) * t) * Math.exp(-t * 20) : 0;
			0.9 * sl * Math.exp(-t * 5) + bloop;
		}));
	}

	static function make(seconds:Float, f:Float->Float):Array<Float>
		return [for (i in 0...Std.int(seconds * Sfx.RATE)) f(i / Sfx.RATE)];

	// (a fixed noise: -1 to 1)
	static function noise():Float {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff;
		return seed / 0x3fffffff - 1;
	}

	static function play(id:Int, gain:Float, rate = 1.0) {
		start();
		var s = sfx;
		if (s == null || id < 0) return;
		var now = helder.ui.Ui.now();
		if (id < last.length) {
			if (now - last[id] < 0.04) return;
			last[id] = now;
		}
		s.play(id, gain, rate);
	}

	public static function hit(power:Float)
		play(tock, 0.35 + 0.65 * power, 0.9 + 0.25 * power);

	public static function bounce(strength:Float)
		play(knock, 0.15 + 0.7 * strength, 0.85 + 0.3 * strength);

	public static function land(strength:Float)
		play(thud, 0.25 + 0.6 * strength, 0.9 + 0.2 * strength);

	public static function boing()
		play(boingId, 0.55, 0.95 + 0.1 * (seed & 7) / 7);

	public static function warp()
		play(warpId, 0.6);

	public static function click()
		play(clickId, 0.6);

	public static function rumble()
		play(rumbleId, 0.7);

	public static function crumble()
		play(crumbleId, 0.6);

	public static function cup() {
		play(plunk, 0.9);
		play(chime, 0.7);
	}

	public static function splash()
		play(splashId, 0.8);

	public static function fall()
		play(whoosh, 0.8);
}
