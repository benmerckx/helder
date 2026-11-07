import Reel.*;
import Reel.SceneDef;
import haxe.io.Bytes;
import helder.canvas.Blend;
import helder.canvas.Canvas;
import helder.canvas.Paint;
import helder.canvas.Path;
import helder.canvas.Stroke;
import helder.image.Image;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;

// A generative piece on helder.canvas: particles drift through a field of
// sines (each step a short line, all of a colour stroked as one path,
// added with the lighter blend), the canvas dimmed a little each step so
// their paths leave trails; drawn on the CPU each frame into an image ui
// shows. Its steps follow the scene's clock (one per sixtieth of a
// second), so the same frames come out of every run.
class FlowField extends helder.ui.Node {
	static inline var COUNT = 1400;
	static final COLORS = [0xff6d8bff, 0xffa98bff, 0xff3ee0a8, 0xffffbf47, 0xffff6f91];

	final canvas:Canvas;
	final image:Image;
	final w:Int;
	final h:Int;
	final xs = new Array<Float>();
	final ys = new Array<Float>();
	final life = new Array<Int>();
	final paths = [for (_ in 0...5) new Path()];
	final paints:Array<Paint> = [];
	final pen = new Stroke(1.5);
	final dim:Paint;
	var steps = 0;
	var seed = 1;

	// the steps taken to time (s)
	public var time(default, set) = 0.0;

	public function new(w:Int, h:Int) {
		super("flow");
		this.w = w;
		this.h = h;
		canvas = new Canvas(w, h);
		canvas.clear(0xff07080d);
		image = new Image(w, h, Bytes.alloc(w * h * 4));
		image.retain = true;
		for (c in COLORS) {
			var p = Paint.solid((c & 0xffffff) | 0x70000000);
			p.blend = Blend.lighter;
			paints.push(p);
		}
		dim = Paint.solid(0x1207080d);
		for (i in 0...COUNT) {
			xs.push(0);
			ys.push(0);
			life.push(0);
			spawn(i);
		}
	}

	function random():Float {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff;
		return seed / 0x7fffffff;
	}

	function spawn(i:Int) {
		xs[i] = random() * w;
		ys[i] = random() * h;
		life[i] = 60 + Std.int(random() * 240);
	}

	// the field's angle at x, y at step s: sines of sines, slowly turning
	inline function angle(x:Float, y:Float, s:Int):Float {
		var t = s * 0.004, k = 0.0042;
		return 2.2 * (Math.sin(x * k + Math.sin(y * k * 1.3 + t) * 1.6) + Math.cos(y * k * 1.1 - Math.cos(x * k * 0.7 - t) * 1.4));
	}

	function step() {
		for (p in paths)
			p.clear();
		canvas.fillRect(0, 0, w, h, dim);
		for (i in 0...COUNT) {
			var x = xs[i], y = ys[i], a = angle(x, y, steps), v = 2.6;
			var nx = x + Math.cos(a) * v, ny = y + Math.sin(a) * v;
			var p = paths[i % 5];
			p.moveTo(x, y);
			p.lineTo(nx, ny);
			xs[i] = nx;
			ys[i] = ny;
			if (--life[i] <= 0 || nx < -4 || ny < -4 || nx > w + 4 || ny > h + 4) spawn(i);
		}
		for (k in 0...5)
			canvas.stroke(paths[k], pen, paints[k]);
		steps++;
	}

	function set_time(t:Float):Float {
		var want = Std.int(t * 60), n = 0;
		while (steps < want && n++ < 900)
			step();
		if (n > 0) {
			canvas.readPixels(image.pixels, 0, 0, w, h);
			image.changed();
			if (ui != null) ui.requestFrame();
		}
		return time = t;
	}

	override public function hasContent():Bool
		return true;

	override public function paintContent(c:helder.ui.Canvas, x:Float, y:Float, width:Float, height:Float)
		c.image(image, x, y, width, height, 0, 0, 1, 1, 0);
}

class Threads implements Markup {
	public static final scene:SceneDef = {name: "canvas", title: "A generative canvas", duration: 7.0, view: view};

	static function Field(props:{t:Read<Float>}):helder.ui.Node {
		var f = new FlowField(W, H);
		f.style.grow = 1;
		renderEffect(() -> props.t(), t -> f.time = t);
		return f;
	}

	public static function view(t:Read<Float>):View {
		return <view grow={1} background={NIGHT} color={INK} font-family="Inter">
			<Field t={t}/>
			<view position="absolute" left={56} bottom={52} row-gap={10}>
				<Show when={() -> at(t(), 0.8)}>
					<view row-gap={8} transition="fade slide-up(20)">
						<text font-size={14} color={MUTED} font-weight={600} letter-spacing={1.6}>HELDER.CANVAS · ON THE CPU</text>
						<text font-family="Inter Display" font-size={44} font-weight={700} letter-spacing={-1}>Fourteen hundred threads</text>
						<text font-size={16} color={MUTED}>Paths stroked with the lighter blend, a field of sines, every frame.</text>
					</view>
				</Show>
			</view>
		</view>;
	}
}
