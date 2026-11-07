import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

// What the showreel's scenes share: the clock they animate from, easing,
// the palette and the fonts.
//
// Each scene is a function of its own time (a Read<Float>, seconds since
// it began): what it shows at a time is set from that time alone, cues
// (`at(t, 1.2)`: false before 1.2 s, true after) flip state that
// helder.ui.motion then springs to, so a headless run's virtual clock
// records every frame exactly, whatever the machine's speed.
typedef SceneDef = {
	name:String,
	title:String,
	duration:Float,
	view:Read<Float>->helder.view.View
}

class Reel {
	public static inline var W = 1280;
	public static inline var H = 720;

	// the palette: a deep night, ink and five accents
	public static inline var NIGHT = "#07080d";
	public static inline var PANEL = "#10121a";
	public static inline var RAISED = "#171a25";
	public static inline var LINE = "#252a3a";
	public static inline var INK = "#f2f4fb";
	public static inline var MUTED = "#8a91a8";
	public static inline var BLUE = "#6d8bff";
	public static inline var VIOLET = "#a98bff";
	public static inline var MINT = "#3ee0a8";
	public static inline var AMBER = "#ffbf47";
	public static inline var CORAL = "#ff6f91";

	// whether t has reached at (a cue: a state change motion animates)
	public static inline function at(t:Float, at:Float):Bool
		return t >= at;

	// 0 before a, 1 after b, smoothly between
	public static function ramp(t:Float, a:Float, b:Float):Float {
		var x = (t - a) / (b - a);
		x = x < 0 ? 0 : x > 1 ? 1 : x;
		return x * x * (3 - 2 * x);
	}

	// 0 before a, 1 after b, linear
	public static inline function lin(t:Float, a:Float, b:Float):Float {
		var x = (t - a) / (b - a);
		return x < 0 ? 0 : x > 1 ? 1 : x;
	}

	// ease out (cubic)
	public static inline function out(x:Float):Float
		return 1 - (1 - x) * (1 - x) * (1 - x);

	// ease in and out (quintic-ish: a fling's long glide)
	public static function inOut(x:Float):Float
		return x < 0.5 ? 16 * x * x * x * x * x : 1 - Math.pow(-2 * x + 2, 5) / 2;

	public static inline function mix(a:Float, b:Float, k:Float):Float
		return a + (b - a) * k;

	// n with thousands' commas
	public static function thousands(n:Int):String {
		var s = Std.string(n < 0 ? -n : n), out = "";
		while (s.length > 3) {
			out = "," + s.substr(s.length - 3) + out;
			s = s.substr(0, s.length - 3);
		}
		return (n < 0 ? "−" : "") + s + out;
	}

	// a colour #rrggbb with an alpha
	public static function alpha(hex:String, a:Float):String {
		var v = Std.int(Math.max(0, Math.min(255, Math.round(a * 255))));
		return hex + StringTools.hex(v, 2);
	}

	// a hash of an integer (deterministic "randomness")
	public static function hash(i:Int):Int {
		var h = i * 0x45d9f3b;
		h = (h ^ (h >>> 16)) * 0x45d9f3b;
		return (h ^ (h >>> 16)) & 0x7fffffff;
	}

	public static inline function rand(i:Int):Float
		return (hash(i) % 100000) / 100000;

	// a few of lucide's icons (ISC) beyond helder.ui's own: <image src={icon("pause")} color=.../>
	static final icons = new Map<String, helder.ui.Svg>();

	public static function icon(name:String):helder.ui.Svg {
		var s = icons.get(name);
		if (s != null) return s;
		var body = switch name {
			case "pause": '<rect x="14" y="4" width="4" height="16" rx="1"/><rect x="6" y="4" width="4" height="16" rx="1"/>';
			case "play": '<polygon points="6 3 20 12 6 21 6 3"/>';
			case "skip-back": '<polygon points="19 20 9 12 19 4 19 20"/><line x1="5" x2="5" y1="19" y2="5"/>';
			case "skip-forward": '<polygon points="5 4 15 12 5 20 5 4"/><line x1="19" x2="19" y1="5" y2="19"/>';
			case _: helder.ui.widgets.Icons.markup(name);
		}
		s = helder.ui.Svg.parse(helder.ui.widgets.Icons.OPEN + body + "</svg>");
		icons.set(name, s);
		return s;
	}

	// Inter (OFL, rsms/inter), cut to Latin by tests/../fonts' script: the
	// variable font (weights 100 to 900) at text size (Inter) and display
	// size (Inter Display)
	static var loaded = false;

	public static function fonts() {
		if (loaded) return;
		loaded = true;
		var f = helder.text.SystemFonts.get();
		for (b in [
			helder.asset.Asset.embed("fonts/Inter.ttf"),
			helder.asset.Asset.embed("fonts/InterDisplay.ttf"),
			helder.asset.Asset.embed("helder/ui/code/fonts/JetBrainsMono-Regular.ttf")
		])
			try f.add(b) catch (_:Dynamic) {}
	}
}
