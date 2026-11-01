import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.*;
import helder.ui.*;
import helder.ui.draw.*;

// The renderer's pixel grid (Renderer.snap) at a phone's fractional scale,
// 2.8125 device pixels a point: a bordered box and a line of text drawn
// headless (npm test -- ui-draw), then
// - crisp: laid out without a transform, a row across the box has no
//   blended pixels (its edges and its border whole pixels; without
//   snapping its edges fall inside pixels);
// - gliding: under a translation (how things move) nothing is snapped: the
//   box moved by a third of a device pixel draws its edges a third of the
//   way over (blended pixels where they fall), not stepped to the next
//   whole pixel, so a moving thing glides rather than twitching.
class SnapTest {
	static inline var W = 128;
	static inline var H = 64;
	static inline var SCALE = 2.8125;
	static final PW = Std.int(W * SCALE);
	static final PH = Std.int(H * SCALE);

	static var device:Device;
	static var ui:Ui;
	static var group:Node;

	static function main() {
		device = Device.create(Surface.headless(PW, PH));
		ui = new Ui(new DrawText(), W, H);
		ui.scale = SCALE;
		ui.root.style.background = Color.WHITE;
		ui.root.style.fontFamily = "DejaVu Sans";
		ui.root.style.fontSize = 13;
		ui.root.style.color = Color.BLACK;
		group = new Node();
		group.style.set({position: Absolute, left: 0, top: 0, right: 0, bottom: 0});
		ui.root.append(group);
		var b = new Node();
		// (at points whose device pixels are fractions: 10.3 pt is 28.97 px)
		b.style.set({position: Absolute, left: 10, top: 10, width: 41, height: 19, background: Color.BLACK, borderWidth: 1, borderColor: Color.rgb(0xFF0000)});
		group.append(b);
		var t = new TextNode("Hi, fine");
		t.style.set({position: Absolute, left: 61, top: 12});
		group.append(t);
		var ok = true;
		function check(name:String, pass:Bool, detail:String) {
			Sys.println('SnapTest: $name ${pass ? "ok" : "FAILED"} ($detail)');
			if (!pass) ok = false;
		}
		// a row through the box's middle, across its left and right edges
		var y = Std.int(19.5 * SCALE);
		var snapped = draw(0, 0, true), loose = draw(0.37, 0, false);
		var blends = blended(snapped, y, 0, Std.int(56 * SCALE)), looseBlends = blended(loose, y, 0, Std.int(56 * SCALE));
		check("crisp", blends == 0 && looseBlends > 0, '$blends blended pixels across the box snapped, $looseBlends unsnapped');
		var border = run(snapped, y, Std.int(9 * SCALE), 0xFF0000);
		check("border", border == 3, 'its 1 pt border $border pixels wide');
		// (under a transform of no movement at all: as laid out, snapped)
		var still = draw(0, 0, true);
		check("at rest", differ(snapped, still, 0, 0) == 0, "the same pixels");
		var a = draw(0.12, 0, true), b = draw(0.24, 0, true);
		var ba = blended(a, y, 0, Std.int(56 * SCALE)), d = differ(a, b, 0, 0);
		check("gliding", ba > 0 && d > 0, '$ba blended pixels across the box moved by 0.34 px, $d pixels differ moved a third of a pixel more');
		device.dispose();
		Sys.exit(ok ? 0 : 1);
	}

	static function draw(dx:Float, dy:Float, snap:Bool):Bytes {
		group.style.transform = Transform.translate(dx, dy);
		var r = new Renderer(device);
		r.scale = SCALE;
		r.snap = snap;
		var pass:PassDesc = {colors: [{load: Clear, clear: new helder.gfx.Color(1, 1, 1)}]};
		var pixels = Bytes.alloc(PW * PH * 4);
		ui.update();
		var enc = device.beginFrame();
		enc.beginPass(pass);
		r.begin(PW, PH);
		ui.paint(r);
		r.end(enc);
		enc.endPass();
		device.readPixels(pixels);
		device.endFrame();
		return pixels;
	}

	static inline function rgb(p:Bytes, x:Int, y:Int):Int {
		var o = 4 * (y * PW + x);
		return (p.get(o) << 16) | (p.get(o + 1) << 8) | p.get(o + 2);
	}

	// (pixels of row y, x0 to x1, neither white, black nor red)
	static function blended(p:Bytes, y:Int, x0:Int, x1:Int):Int {
		var n = 0;
		for (x in x0...x1) {
			var c = rgb(p, x, y);
			if (c != 0xFFFFFF && c != 0 && c != 0xFF0000) n++;
		}
		return n;
	}

	// (the length of the first run of colour c in row y from x0 on)
	static function run(p:Bytes, y:Int, x0:Int, c:Int):Int {
		var x = x0;
		while (x < PW && rgb(p, x, y) != c)
			x++;
		var n = 0;
		while (x < PW && rgb(p, x, y) == c) {
			n++;
			x++;
		}
		return n;
	}

	// (pixels of a that differ from b's moved by dx, dy)
	static function differ(a:Bytes, b:Bytes, dx:Int, dy:Int):Int {
		var n = 0;
		for (y in 0...PH - dy)
			for (x in 0...PW - dx)
				if (rgb(a, x, y) != rgb(b, x + dx, y + dy)) n++;
		return n;
	}
}
