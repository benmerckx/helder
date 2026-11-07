package helder.ui.motion;

// How a track moves to a new target: an analytic spring of a perceptual
// duration and a bounce (SwiftUI's Spring(duration:bounce:): ω = 2π /
// duration, ζ = 1 − bounce, or 1 / (1 + bounce) below 0, mass 1), a tween
// (a duration along a cubic Bézier, CSS's), a decay (a fling's: its rate, the
// target where it comes to rest) or none (instant). A curve may name a token
// of the palette (Curve.TOKENS; a theme's own, StyleSheet.motion, over
// them): "snappy", "default", "calm", "lead", "fade"..., resolved where it
// is used (resolve).
class Curve {
	public static inline var INSTANT_KIND = 0;
	public static inline var SPRING_KIND = 1;
	public static inline var TWEEN_KIND = 2;
	public static inline var DECAY_KIND = 3;

	public final kind:Int;
	// seconds (a spring's perceptual duration, a tween's length)
	public final duration:Float;
	// a spring's: -1 < bounce < 1 (0 critically damped, above it overshoots)
	public final bounce:Float;
	// a tween's: a cubic Bézier (x1, y1, x2, y2), as Transition's
	public final easing:Null<Array<Float>>;
	// a decay's rate (1/s)
	public final rate:Float;
	// the palette's name it stands for (null: its own values)
	public final token:Null<String>;

	function new(kind:Int, duration:Float, bounce:Float, easing:Null<Array<Float>>, rate:Float, token:Null<String>) {
		this.kind = kind;
		this.duration = duration;
		this.bounce = bounce;
		this.easing = easing;
		this.rate = rate;
		this.token = token;
	}

	public static final INSTANT = new Curve(INSTANT_KIND, 0, 0, null, 0, null);

	public static function spring(duration:Float, bounce = 0.0):Curve {
		if (!(duration > 0)) throw 'Curve.spring: duration $duration, above 0';
		if (!(bounce > -1 && bounce < 1)) throw 'Curve.spring: bounce $bounce, between -1 and 1';
		return new Curve(SPRING_KIND, duration, bounce, null, 0, null);
	}

	public static function tween(duration:Float, ?easing:Array<Float>):Curve
		return duration <= 0 ? INSTANT : new Curve(TWEEN_KIND, duration, 0, easing ?? EASE_IN_OUT, 0, null);

	// iOS's rates: normal 2 (UIScrollView's 0.998 a millisecond), fast 10
	public static function decay(rate = 2.0):Curve
		return new Curve(DECAY_KIND, 0, 0, null, rate, null);

	// a token of the palette, its values the built-in ones (resolve: a theme's over them)
	public static function named(token:String):Curve {
		var c = TOKENS.get(token);
		if (c == null) throw 'Curve: no motion token $token (${[for (k in TOKENS.keys()) k].join(", ")})';
		return new Curve(c.kind, c.duration, c.bounce, c.easing, c.rate, token);
	}

	public static final EASE_IN_OUT = [0.42, 0.0, 0.58, 1.0];

	// the palette: snappy .25/0, default .3/0, calm .4/0, a .2/0 lead, a .15 fade
	public static final TOKENS:Map<String, Curve> = [
		"instant" => INSTANT,
		"snappy" => spring(0.25),
		"default" => spring(0.3),
		"calm" => spring(0.4),
		"lead" => spring(0.2),
		"fade" => tween(0.15),
		"bouncy" => spring(0.4, 0.25),
		"morph" => spring(0.3, 0.16),
		"glide" => spring(0.32),
		"drift" => spring(0.85)
	];

	// reduced motion's fade (opacity, presence and colours): 0.15 s, ease in and out
	public static final REDUCED_FADE = tween(0.15);

	// the same curve with its duration times k (a text colour leading: 0.5)
	public function scaled(k:Float):Curve
		return kind == SPRING_KIND || kind == TWEEN_KIND ? new Curve(kind, duration * k, bounce, easing, rate, null) : this;

	// an exit's: 20% shorter, half the bounce (exits run shorter than entrances)
	public function exit():Curve
		return kind == SPRING_KIND ? new Curve(kind, duration * 0.8, bounce * 0.5, null, 0, null) : kind == TWEEN_KIND ? scaled(0.8) : this;

	// this curve, its token a theme's when the nearest sheet over n has one (StyleSheet.motion)
	public function resolve(n:Null<Node>):Curve {
		if (token == null || n == null) return this;
		var s = n.sheet();
		var m = s == null ? null : s.motion;
		var own = m == null ? null : m.get(token);
		return own == null ? this : own;
	}

	// SwiftUI's ω and ζ
	public inline function omega():Float
		return 2 * Math.PI / duration;

	public inline function zeta():Float
		return bounce >= 0 ? 1 - bounce : 1 / (1 + bounce);

	// what markup writes: a token ("snappy"), "none" or "instant", seconds
	// and a bounce ("0.3", "0.3 0.15", "0.3s"), a tween ("ease-out 0.2s"), a
	// structure {duration, bounce} ({duration, easing}: a tween), or a Curve
	public static function of(v:Dynamic):Null<Curve> {
		if (v == null || v == false) return null;
		if (Std.isOfType(v, Curve)) return v;
		if (Std.isOfType(v, String)) return parse(v);
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return spring((v : Float));
		var d:Null<Float> = Reflect.field(v, "duration"), b:Null<Float> = Reflect.field(v, "bounce"), e:Dynamic = Reflect.field(v, "easing");
		if (d == null) throw 'Curve: $v has no duration';
		if (e != null) return tween(d, Std.isOfType(e, String) ? Transition.easingOf(e) : e);
		return spring(d, b ?? 0.0);
	}

	public static function parse(s:String):Curve {
		var t = StringTools.trim(s).toLowerCase();
		if (t == "" || t == "none" || t == "instant" || t == "true") return t == "true" ? named("default") : INSTANT;
		if (TOKENS.exists(t)) return named(t);
		var easing:Null<Array<Float>> = null, nums = [];
		for (w in t.split(" ")) {
			if (w == "") continue;
			var e = Transition.easingOf(w);
			if (e != null) {
				easing = e;
				continue;
			}
			var ms = StringTools.endsWith(w, "ms"), f = Std.parseFloat(ms ? w.substr(0, w.length - 2) : StringTools.endsWith(w, "s") ? w.substr(0, w.length - 1) : w);
			if (Math.isNaN(f)) throw 'Curve: "$s" is not a motion: a token (${[for (k in TOKENS.keys()) k].join(", ")}), a duration and a bounce, or a tween';
			nums.push(ms ? f / 1000 : f);
		}
		if (nums.length == 0) throw 'Curve: "$s" has no duration';
		return easing != null ? tween(nums[0], easing) : spring(nums[0], nums.length > 1 ? nums[1] : 0);
	}

	public function toString():String
		return token != null ? token : switch kind {
			case SPRING_KIND: 'spring($duration, $bounce)';
			case TWEEN_KIND: 'tween($duration)';
			case DECAY_KIND: 'decay($rate)';
			case _: "instant";
		}
}
