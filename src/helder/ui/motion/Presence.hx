package helder.ui.motion;

// How a node enters and leaves (a Transition's presence: transition="fade",
// "scale", "slide-up", "fade scale", "slide-left(24) fade"): from absent
// (presence 0) to present (1) it fades in (always: a node removed always
// fades out), grows from scale, slides from (dx, dy) away; blur is asked
// for but drawn as a fade (the renderer has no blur). Played after the
// first frame when a node is inserted into a drawn parent, and when it is
// removed: it is drawn where it was until its exit settles, and revived
// from where it is if it comes back meanwhile (Node.insert of the same
// node, helder.view's keyed For).
class Presence {
	// the scale it enters from and leaves to (1: none)
	public final scale:Float;
	// where it enters from and leaves to, from its place (pixels)
	public final dx:Float;
	public final dy:Float;
	public final blur:Float;

	public function new(scale = 1.0, dx = 0.0, dy = 0.0, blur = 0.0) {
		this.scale = scale;
		this.dx = dx;
		this.dy = dy;
		this.blur = blur;
	}

	public static final FADE = new Presence();

	// whether w is one of presence's words (Transition.parse)
	public static function word(w:String):Bool {
		var k = w.indexOf("(");
		var name = (k < 0 ? w : w.substr(0, k)).toLowerCase();
		return switch name {
			case "fade" | "scale" | "slide-up" | "slide-down" | "slide-left" | "slide-right" | "blur" | "pop": true;
			case _: false;
		}
	}

	// the effects of words (each Presence.word): combined
	public static function of(words:Array<String>):Presence {
		var scale = 1.0, dx = 0.0, dy = 0.0, blur = 0.0;
		for (w in words) {
			var k = w.indexOf("("), name = (k < 0 ? w : w.substr(0, k)).toLowerCase();
			var arg = k < 0 ? Math.NaN : Std.parseFloat(StringTools.replace(w.substring(k + 1, w.lastIndexOf(")")), "px", ""));
			inline function or(d:Float):Float
				return Math.isNaN(arg) ? d : arg;
			switch name {
				case "scale": scale = or(0.96);
				case "pop": scale = or(0.9);
				case "slide-up": dy = or(16);
				case "slide-down": dy = -or(16);
				case "slide-left": dx = or(16);
				case "slide-right": dx = -or(16);
				case "blur": blur = or(4);
				case _:
			}
		}
		return new Presence(scale, dx, dy, blur);
	}

	public function toString():String
		return 'Presence(scale $scale, $dx, $dy${blur > 0 ? ', blur $blur' : ""})';
}
