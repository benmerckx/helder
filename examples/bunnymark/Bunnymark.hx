// title: Bunnymark
// summary: The classic 2D sprite benchmark on helder.sprite's SpriteBatch: bunnies bouncing under gravity, one textured quad each, every one in a single draw; press and hold to add more, the overlay showing how many still run at 60 fps
// tags: 2d, sprites, performance
// demo: canvas 640x480 1x
import haxe.io.Bytes;
import helder.gfx.*;
import helder.image.Image;
import helder.os.*;
import helder.scene.debug.FrameStats;
import helder.scene.debug.Overlay;
import helder.sprite.SpriteBatch;

// Bunnymark as PixiJS's, after Iain Lobb's: each bunny a position and a
// velocity, pulled down each frame, bouncing off the floor (sometimes
// jumping high) and the sides; drawn as one quad of a sheet of five
// bunnies (drawn here in code: no file), all of them one run of one
// texture, so one draw however many there are. Hold a press (a finger,
// the mouse, Space) to add 500 a frame; the count at 60 fps is the most
// bunnies drawn while the last second's median frame stayed under
// 17.5 ms. Nothing is allocated a frame: the bunnies are four float
// arrays, the batch's buffers grow once.
//
//   bun run helder examples/bunnymark/Bunnymark.hx [bunnies]   (--target web: in a page)
class Bunnymark {
	static inline var W = 26;
	static inline var H = 37;
	static inline var KINDS = 5;
	static inline var GRAVITY = 0.5;

	final device:Device;
	final batch:SpriteBatch;
	final sheet:SpriteTexture;
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0.93, 0.95, 0.97)}]};
	var x:Array<Float> = [];
	var y:Array<Float> = [];
	var vx:Array<Float> = [];
	var vy:Array<Float> = [];
	var kind:Array<Int> = [];
	public var count(default, null) = 0;
	// the most bunnies drawn while the frames held 60 a second
	public var at60 = 0;
	var seed = 7;

	public function new(device:Device, start = 2000) {
		this.device = device;
		batch = new SpriteBatch(device);
		sheet = batch.add(bunnies());
		add(start, 0, 0);
	}

	inline function rand():Float {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff;
		return seed / 0x7fffffff;
	}

	// n more bunnies at x0, y0 (points), thrown right and up
	public function add(n:Int, x0:Float, y0:Float) {
		for (_ in 0...n) {
			x.push(x0);
			y.push(y0);
			vx.push(rand() * 10);
			vy.push(rand() * 10 - 5);
			kind.push(count % KINDS);
			count++;
		}
	}

	// a frame: each bunny moved, bounced and drawn into a target of w x h points
	public function frame(enc:Encoder, w:Float, h:Float) {
		var maxX = w - W, maxY = h - H;
		batch.begin(w, h);
		for (i in 0...count) {
			var px = x[i] + vx[i], py = y[i] + vy[i], sy = vy[i] + GRAVITY;
			if (px > maxX) {
				vx[i] = -vx[i];
				px = maxX;
			} else if (px < 0) {
				vx[i] = -vx[i];
				px = 0;
			}
			if (py > maxY) {
				sy = -sy * 0.85;
				py = maxY;
				if (rand() > 0.5) sy -= rand() * 6;
			} else if (py < 0) {
				sy = 0;
				py = 0;
			}
			x[i] = px;
			y[i] = py;
			vy[i] = sy;
			batch.image(sheet, kind[i] * W, 0, W, H, px, py, W, H);
		}
		enc.beginPass(pass);
		batch.flush(enc);
		enc.endPass();
	}

	// the sheet: five bunnies side by side (white, grey, pink, tan, blue),
	// long ears, a round body, an eye, a soft edge
	static function bunnies():Image {
		var px = Bytes.alloc(W * KINDS * H * 4);
		var fur = [[255, 255, 255], [190, 196, 205], [255, 196, 214], [226, 196, 150], [170, 205, 255]];
		for (k in 0...KINDS)
			for (j in 0...H)
				for (i in 0...W) {
					var cx = i + 0.5, cy = j + 0.5;
					// (coverage: the body, the head, two ears; 0 to 1 at the edge)
					var body = 1 - ell(cx, cy, 13, 28, 10.5, 8.5);
					var head = 1 - ell(cx, cy, 13, 17, 7.5, 6.5);
					var ear1 = 1 - ell(cx, cy, 9.5, 7, 2.6, 7);
					var ear2 = 1 - ell(cx, cy, 16.5, 7, 2.6, 7);
					var a = Math.max(Math.max(body, head), Math.max(ear1, ear2));
					a = Math.max(0, Math.min(1, a * 6));
					var c = fur[k], r = c[0] * 1.0, g = c[1] * 1.0, b = c[2] * 1.0;
					// (inner ears pink, an eye, a darker outline)
					if (ell(cx, cy, 9.5, 7.5, 1.1, 4.5) < 1 || ell(cx, cy, 16.5, 7.5, 1.1, 4.5) < 1) {
						r = 250;
						g = 150;
						b = 175;
					}
					if (ell(cx, cy, 16, 16, 1.4, 1.6) < 1) r = g = b = 30;
					if (a < 1) {
						r *= 0.5;
						g *= 0.5;
						b *= 0.5;
					}
					var o = 4 * (j * W * KINDS + k * W + i);
					px.set(o, Std.int(r));
					px.set(o + 1, Std.int(g));
					px.set(o + 2, Std.int(b));
					px.set(o + 3, Std.int(a * 255));
				}
		return new Image(W * KINDS, H, px);
	}

	// (x, y's distance from an ellipse's centre in its radii: 1 on its edge)
	static inline function ell(x:Float, y:Float, cx:Float, cy:Float, rx:Float, ry:Float):Float {
		var dx = (x - cx) / rx, dy = (y - cy) / ry;
		return Math.sqrt(dx * dx + dy * dy);
	}

	static function main() {
		var begun = Sys.time(), firstFrame = -1.0, printed = 0.0;
		var window = new Window("Bunnymark", 640, 480);
		var device = Device.create(window.surface);
		// (an argument: the bunnies to start with, 2000 by default)
		var start = Std.parseInt(Sys.args()[0] ?? "");
		var mark = new Bunnymark(device, start != null && start > 0 ? start : 2000);
		var overlay = new Overlay(device), stats = new FrameStats(60);
		overlay.detail = true;
		var holding = false, px = 0.0, py = 0.0, last = Sys.time(), frames = 0;
		App.run(() -> {
			var now = Sys.time(), s = window.scale;
			overlay.scale = s;
			var w = device.width / s, h = device.height / s;
			if (holding) mark.add(500, px, py);
			// (a second of frames under 17.5 ms at the median: the count holds 60 fps)
			if (stats.count == stats.capacity && stats.percentile(0.5) < 0.0175 && mark.count > mark.at60) mark.at60 = mark.count;
			var enc = device.beginFrame();
			if (enc == null) return;
			mark.frame(enc, w, h);
			stats.draws = 1;
			overlay.lines.resize(0);
			overlay.lines.push('BUNNIES ${mark.count}');
			overlay.lines.push('AT 60 FPS ${mark.at60}');
			overlay.lines.push('HOLD TO ADD');
			overlay.draw(enc, stats);
			var cpu = Sys.time() - now;
			device.endFrame();
			// (the first frames, the page's start among them, left out)
			if (++frames > 3) stats.add(now - last, cpu);
			// (the site's numbers: site/numbers.mjs reads the last stats line)
			if (firstFrame < 0) firstFrame = Sys.time() - begun;
			if (now - printed > 0.5 && stats.count > 10) {
				printed = now;
				Sys.println(stats.report(firstFrame, 0, device.textureBytes));
			}
			last = now;
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case KeyDown if (e.key == 0x20): holding = true;
			case KeyUp if (e.key == 0x20): holding = false;
			case PointerDown | PointerMove:
				px = e.x / window.scale;
				py = e.y / window.scale;
				if (e.kind == PointerDown) holding = true;
			case PointerUp | PointerCancel: holding = false;
			case _:
		});
	}
}
