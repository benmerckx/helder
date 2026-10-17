import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.os.*;
import hxmc.ui.*;
import hxmc.ui.draw.*;

// Boxes drawn by hxmc.ui.draw headless (make ui-draw-check): boxes.json's
// (corners with their own radii, borders with their own sides' widths, a
// clip to a padding box's rounded corners; box shadows, several, inset; turned, scaled, skewed, about
// other origins, nested) against boxes.png, Chromium drawing the same
// (box-ref.mjs). Edges are anti-aliased differently (Skia's
// coverage against our signed distance), so the shapes must agree: a
// small mean difference, few pixels far apart. And a text under scale(2)
// must come out as the same text at twice the size (its glyphs
// rasterized at the scaled size, on the pixel grid), and turned, drawn
// where the turn puts it.
//   BoxTest <boxes.png> <out.png> [<turned.png>: the turned text]
class BoxTest {
	static inline var W = 320;
	static inline var H = 320;
	static inline var MEAN = 1.5;
	static inline var FAR = 64;
	static inline var MAX_FAR = 0.002;

	static function box(b:Dynamic):Node {
		var n = new Node("box");
		n.style.set({position: Absolute, left: (b.left : Float), top: (b.top : Float), width: (b.width : Float), height: (b.height : Float),
			background: Color.parse(b.background)});
		// (one value, or each corner's and each side's)
		if (Std.isOfType(b.radius, String)) n.style.corners = CornersValue.parse(b.radius) else if (b.radius != null) n.style.radius = b.radius;
		if (b.border != null) {
			if (Std.isOfType(b.border, String)) n.style.borders = [for (p in (b.border : String).split(" ")) Std.parseFloat(p)] else n.style.borderWidth = b.border;
			n.style.borderColor = Color.parse(b.borderColor);
		}
		if (b.overflow == "hidden") n.style.overflow = Hidden;
		if (b.shadow != null) n.style.shadow = Shadow.parse(b.shadow);
		if (b.transform != null) n.style.transform = Transform.parse(b.transform);
		if (b.origin != null) n.style.transformOrigin = Transform.origin(b.origin);
		if (b.children != null) for (c in (b.children : Array<Dynamic>))
			n.append(box(c));
		return n;
	}

	static function draw(device:Device, r:Renderer, ui:Ui):Bytes {
		ui.update();
		var pixels = Bytes.alloc(W * H * 4);
		var enc = device.beginFrame();
		var pass:PassDesc = {colors: [{load: Clear, clear: new hxmc.gfx.Color(1, 1, 1)}]};
		enc.beginPass(pass);
		r.begin(W, H);
		ui.paint(r);
		r.end(enc);
		enc.endPass();
		device.readPixels(pixels);
		device.endFrame();
		return pixels;
	}

	// a text at (10.25, 10.5): at a size, under a transform about its top left
	static function text(size:Float, ?transform:String):Ui {
		var ui = new Ui(new DrawText(), W, H);
		var t = new TextNode("Transformed");
		t.style.set({position: Absolute, left: 10.25, top: 10.5, fontSize: size, color: Color.rgb(0x111111)});
		if (transform != null) {
			t.style.transform = Transform.parse(transform);
			t.style.transformOrigin = Transform.origin("left top");
		}
		ui.root.append(t);
		return ui;
	}

	static function main() {
		var args = Sys.args();
		var dir = haxe.io.Path.directory(args[0]);
		var boxes:Array<Dynamic> = haxe.Json.parse(sys.io.File.getContent(dir + "/boxes.json"));
		var ui = new Ui(new DrawText(), W, H);
		for (b in boxes)
			ui.root.append(box(b));
		var device = Device.create(Surface.headless(W, H));
		var r = new Renderer(device);
		var pixels = draw(device, r, ui);
		sys.io.File.saveBytes(args[1], Png.encode(pixels, W, H));
		// (the texts: scaled against the larger size, turned)
		var scaled = draw(device, r, text(12, "scale(2)")), large = draw(device, r, text(24));
		var turned = draw(device, r, text(16, "translate(30px, 0) rotate(90deg)"));
		device.dispose();
		if (args.length > 2) sys.io.File.saveBytes(args[2], Png.encode(turned, W, H));
		var apart = 0, inked = 0, turnedInk = 0, outside = 0;
		for (i in 0...W * H) {
			if (Math.abs(scaled.get(4 * i) - large.get(4 * i)) > 64) apart++;
			if (large.get(4 * i) < 128) inked++;
			// (moved 30 right, turned a quarter about (10.25, 10.5): down from there, to its left)
			if (turned.get(4 * i) < 128) {
				turnedInk++;
				if (i % W > 41 || Std.int(i / W) < 9) outside++;
			}
		}
		var textOk = inked > 200 && apart <= inked / 50 && turnedInk > 100 && outside == 0;
		Sys.println('BoxTest: text ${textOk ? "ok" : "FAILED"} ($apart of $inked inked pixels apart scaled; turned: $turnedInk inked, $outside outside)');
		var want = PngDecoder.decode(sys.io.File.getBytes(args[0]));
		var total = 0.0, far = 0;
		for (i in 0...W * H) {
			var d = 0;
			for (c in 0...3) {
				var v = Std.int(Math.abs(pixels.get(4 * i + c) - want.rgba.get(4 * i + c)));
				if (v > d) d = v;
			}
			total += d;
			if (d > FAR) far++;
		}
		var mean = total / (W * H);
		var ok = mean < MEAN && far <= MAX_FAR * W * H;
		Sys.println('BoxTest: boxes ${ok ? "ok" : "FAILED"} (mean ${Math.round(mean * 100) / 100}, $far pixels off by more than $FAR)');
		Sys.exit(ok && textOk ? 0 : 1);
	}
}
