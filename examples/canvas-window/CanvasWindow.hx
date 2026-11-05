// title: Canvas in a window
// summary: helder.canvas drawn on the GPU into a desktop window: paths, gradients, strokes, a clip and a layer, animated
// tags: canvas, gfx, 2d
import helder.canvas.*;
import helder.canvas.Gradient;
import helder.canvas.Stroke;
import helder.canvas.gpu.GpuCanvas;
import helder.os.*;

// helder.canvas's GPU back end on a window's device: each frame the
// canvas drawn (a gradient sky, a turning star, dashed orbits, a clipped
// layer at half opacity), then presented (close it, or press Escape):
//
//   haxe -cp src -cp examples -main CanvasWindow --custom-target hxmc=canvas-window -D hxmc.libc=glibc
class CanvasWindow {
	static inline var W = 640;
	static inline var H = 480;

	final canvas:GpuCanvas;
	final star = new Path();
	final orbit = new Path();
	final sky = new LinearGradient(0, 0, 0, H);
	final glow = new RadialGradient(0, 0, 0, 0, 0, 90);
	final line = new Stroke(3);
	var t = 0.0;

	function new(device:helder.gfx.Device) {
		canvas = new GpuCanvas(W, H, device);
		sky.addStop(0, 0xFF0F172A).addStop(1, 0xFF7C3AED);
		glow.addStop(0, 0xFFFDE68A).addStop(1, 0x00F97316);
		for (i in 0...10) {
			var a = -Math.PI / 2 + i * Math.PI / 5, r = i % 2 == 0 ? 80 : 34;
			if (i == 0) star.moveTo(r * Math.cos(a), r * Math.sin(a)) else star.lineTo(r * Math.cos(a), r * Math.sin(a));
		}
		star.close();
		line.dash = new Dash([12, 8]);
		line.cap = Cap.round;
	}

	function frame() {
		t += 1 / 60;
		var c = canvas;
		c.resetTransform();
		c.fillRect(0, 0, W, H, Paint.shaded(sky));
		for (k in 1...4) {
			orbit.clear();
			orbit.ellipse(W / 2, H / 2, 70 * k, 40 * k, 0.3, 0, Math.PI * 2);
			line.dash.offset = t * 30 * k;
			c.stroke(orbit, line, Paint.solid(0x80FFFFFF));
		}
		c.save();
		c.translate(W / 2, H / 2);
		c.rotate(t);
		c.fill(star, Paint.shaded(glow));
		c.restore();
		c.save();
		var clip = new Path();
		clip.roundRect(40, 40, 160, 100, 20);
		c.clip(clip);
		c.saveLayer(0.5);
		c.fillRect(0, 0, W, H, Paint.solid(0xFF22C55E));
		c.restore();
		c.restore();
		c.present();
		frames++;
		// (--shot <file>: the 30th frame's pixels as a PNG, then closed: the gfx lane's check)
		if (shot != null && frames == 30) {
			sys.io.File.saveBytes(shot, helder.image.PngEncoder.encode(c.snapshot().straight(), W, H));
			window.close();
		}
	}

	var frames = 0;
	static var shot:Null<String> = null;
	static var window:Window;

	static function main() {
		var args = Sys.args();
		if (args.length > 1 && args[0] == "--shot") shot = args[1];
		window = new Window("Canvas", W, H);
		var app = new CanvasWindow(helder.gfx.Device.create(window.surface));
		App.run(app.frame, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case _:
		});
	}
}
