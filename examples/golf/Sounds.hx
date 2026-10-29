import helder.os.audio.Sfx;

// The game's sounds, made here procedurally (no files): a putter's tock, a
// knock off a rail, the cup's rattle and plunk, a whoosh for a fall and a
// chime on a hole-in, mixed by helder.os's Sfx (desktop and the web: no
// audio back end on phones yet, where they are silent).
class Sounds {
	static var sfx:Null<Sfx>;
	static var tock = -1;
	static var knock = -1;
	static var plunk = -1;
	static var whoosh = -1;
	static var chime = -1;
	static var seed = 12345;

	// the sounds made and the output opened (before the first is played: a few milliseconds)
	public static function start() {
		if (sfx != null) return;
		var s = Sfx.open();
		sfx = s;
		if (!s.playing) return;
		tock = s.add(make(0.12, t -> 0.7 * Math.sin(2 * Math.PI * 1150 * t) * Math.exp(-t * 60) + 0.35 * noise() * Math.exp(-t * 400)));
		knock = s.add(make(0.1, t -> 0.6 * Math.sin(2 * Math.PI * 520 * t) * Math.exp(-t * 55) + 0.2 * noise() * Math.exp(-t * 300)));
		plunk = s.add(make(0.5, t -> {
			// (two rattles on the rim, then the drop)
			var r = (t < 0.05 ? Math.exp(-t * 200) : t < 0.11 ? 0.6 * Math.exp(-(t - 0.07) * 200) : 0) * noise() * 0.4;
			var d = t > 0.12 ? 0.8 * Math.sin(2 * Math.PI * (330 - 160 * (t - 0.12)) * (t - 0.12)) * Math.exp(-(t - 0.12) * 9) : 0;
			r + d;
		}));
		var low = 0.0;
		whoosh = s.add(make(0.6, t -> {
			low += (noise() - low) * (0.02 + 0.1 * t);
			low * 1.6 * Math.sin(Math.PI * t / 0.6);
		}));
		chime = s.add(make(1.2, t -> {
			var v = 0.0;
			for (k in 0...3) {
				var at = t - k * 0.09;
				if (at > 0) v += 0.28 * Math.sin(2 * Math.PI * [523.25, 659.25, 783.99][k] * at) * Math.exp(-at * 3.2);
			}
			v;
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
		if (sfx != null) sfx.play(id, gain, rate);
	}

	public static function hit(power:Float)
		play(tock, 0.35 + 0.65 * power, 0.9 + 0.25 * power);

	public static function bounce(strength:Float)
		play(knock, 0.15 + 0.7 * strength, 0.85 + 0.3 * strength);

	public static function cup() {
		play(plunk, 0.9);
		play(chime, 0.7);
	}

	public static function splash()
		play(whoosh, 0.8);
}
