import haxe.io.Bytes;
import helder.canvas.Canvas;
import helder.canvas.Filter;
import helder.canvas.Gradient;
import helder.canvas.Paint;
import helder.canvas.Path;
import helder.canvas.Stroke;
import helder.canvas.SvgPath;
import helder.gfx.shader.Vec4;
import helder.image.Image;

// The gallery's canvas piece: a neon sign drawn with helder.canvas's
// filters on the CPU (Filter: a layer blurred for the glow, twice, the
// tube's core over it, the hue turned by a colour matrix) into an image ui
// shows. Its knobs: the glow's reach, the hue, the flicker, the wall's
// light. Drawn again only when what it shows changes (a knob, the box's
// size, the flicker's state, a tenth of a second at a time).
class Neon extends helder.ui.Node {
	public var knobs = new Vec4(0.5, 0.5, 0.5, 0.5);
	public var time = 0.0;

	var canvas:Null<Canvas> = null;
	var image:Null<Image> = null;
	var drawn = "";
	final shape = new Path();
	final ring = new Path();

	public function new() {
		super("neon");
		// (a bolt in a ring, in a box of 100)
		SvgPath.parse("M56 10 L30 54 H48 L40 90 L72 40 H54 L66 10 Z", shape);
		ring.arc(50, 50, 44, 0, Math.PI * 2);
	}

	// the knobs from a slider's values
	public function setKnobs(v:Array<Float>) {
		knobs = new Vec4(v[0], v[1], v[2], v[3]);
		if (ui != null) ui.requestFrame();
	}

	override public function hasContent():Bool
		return true;

	// (on, or flickered off, at t: a few short dips)
	function lit(t:Float):Float {
		var step = Std.int(t * 10), h = (step * 1103515245 + 12345) & 0x7fffffff;
		return h % 100 < Std.int(knobs.z * 30) ? 0.35 : 1.0;
	}

	function render(w:Int, h:Int, on:Float) {
		if (canvas == null || canvas.width != w || canvas.height != h) {
			canvas = new Canvas(w, h);
			image = new Image(w, h, Bytes.alloc(w * h * 4));
			image.retain = true;
		}
		var c = canvas;
		var wall = new LinearGradient(0, 0, 0, h);
		var lightness = Std.int(10 + knobs.w * 26);
		wall.addStop(0, 0xff000000 | (lightness << 16) | (lightness << 8) | (lightness + 8)).addStop(1, 0xff050507);
		c.resetTransform();
		c.fillRect(0, 0, w, h, Paint.shaded(wall));
		var s = Math.min(w, h) / 130;
		var p = new Path(), r = new Path();
		p.addPath(shape);
		r.addPath(ring);
		c.save();
		c.translate(w / 2 - 50 * s, h / 2 - 50 * s);
		c.scale(s, s);
		var hue = ColorMatrix.hueRotate(knobs.y * 360);
		var reach = 2 + knobs.x * 14;
		var tube = 0xff3ee0ff, glow = Paint.solid(tube);
		glow.alpha = on;
		// (the glow: the tube wide and blurred, then narrower and less)
		c.saveLayer(1, null, null, new FilterChain([new Blur(reach), hue]));
		var wide = new Stroke(9);
		c.stroke(p, wide, glow);
		c.stroke(r, wide, glow);
		c.restore();
		c.saveLayer(1, null, null, new FilterChain([new Blur(reach * 0.3), hue]));
		var mid = new Stroke(4.5);
		c.stroke(p, mid, glow);
		c.stroke(r, mid, glow);
		c.restore();
		// (the core: nearly white)
		var core = Paint.solid(0xffeaffff);
		core.alpha = 0.4 + 0.6 * on;
		var thin = new Stroke(1.8);
		c.stroke(p, thin, core);
		c.stroke(r, thin, core);
		c.restore();
		c.readPixels(image.pixels, 0, 0, w, h);
		image.changed();
	}

	override public function paintContent(g:helder.ui.Canvas, x:Float, y:Float, width:Float, height:Float) {
		var r = Std.downcast(g, helder.ui.draw.Renderer);
		var scale = r == null ? 1.0 : r.scale;
		var w = Std.int(Math.max(8, Math.round(width * scale))), h = Std.int(Math.max(8, Math.round(height * scale)));
		var on = lit(time);
		var key = '$w $h $on ${knobs.x} ${knobs.y} ${knobs.z} ${knobs.w}';
		if (key != drawn) {
			drawn = key;
			render(w, h, on);
		}
		g.image(image, x, y, width, height, 0, 0, 1, 1, style.radius);
	}
}
