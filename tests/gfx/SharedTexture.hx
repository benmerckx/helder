import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.Surface;
import helder.ui.Color;
import helder.ui.draw.Renderer;

// helder.gfx's shared textures between two processes (the gfx-shared lane;
// helder.story's native preview host shares its frames with the studio so):
// this program starts itself as the producer, which makes a shared texture
// (Device.createShared: an IOSurface on macOS, a DXGI texture with a keyed
// mutex on Windows, a dma-buf on Linux where EGL exports one), draws into it
// (frameInto: a red top-left quarter and a green bottom-right one on blue)
// and prints its handle; the consumer opens it (openShared), draws it into
// its own frame with helder.ui's renderer (gpuTexture) and reads its pixels
// back: each quarter's colour, the right way up. Then the producer draws
// again (the colours swapped) and the consumer's next frame must show that:
// a frame arrives through the same texture, synchronised.
//
//   SharedTexture [--require]   (--require: no sharing here is a failure, not a skip)
class SharedTexture {
	static inline var W = 96;
	static inline var H = 64;

	static function main() {
		var args = Sys.args();
		if (args[0] == "produce") {
			produce();
			return;
		}
		Sys.exit(consume(args.contains("--require")) ? 0 : 1);
	}

	static function draw(device:Device, r:Renderer, swapped:Bool):Bool {
		var enc = device.beginFrame();
		if (enc == null) return false;
		r.begin(device.width, device.height);
		r.rect(0, 0, W / 2, H / 2, 0, Color.rgb(swapped ? 0x00ff00 : 0xff0000), 0, Color.rgb(0));
		r.rect(W / 2, H / 2, W / 2, H / 2, 0, Color.rgb(swapped ? 0xff0000 : 0x00ff00), 0, Color.rgb(0));
		r.prepare(enc);
		enc.beginPass({colors: [{load: Clear, clear: new helder.gfx.Color(0, 0, 1)}]});
		r.end(enc);
		enc.endPass();
		device.endFrame();
		return true;
	}

	static function produce() {
		var device = Device.create(Surface.headless(W, H));
		var out = Sys.stdout();
		var s = device.sharing == null ? null : device.createShared(W, H);
		if (s == null) {
			out.writeString("none " + (device.sharing ?? "-") + " " + device.backend + "\n");
			out.flush();
			return;
		}
		var r = new Renderer(device);
		device.frameInto(s.texture);
		if (!draw(device, r, false)) throw "SharedTexture: no frame";
		out.writeString("handle " + device.sharing + " " + s.handle + "\n");
		out.flush();
		var input = Sys.stdin();
		while (true) {
			var l = try input.readLine() catch (_:haxe.io.Eof) "end";
			if (l != "again") break;
			draw(device, r, true);
			out.writeString("drawn\n");
			out.flush();
		}
		device.destroyTexture(s.texture);
	}

	static function consume(require:Bool):Bool {
		var self = Sys.programPath();
		var p = new sys.io.Process(self, ["produce"]);
		var line = p.stdout.readLine();
		var f = line.split(" ");
		if (f[0] == "none") {
			p.close();
			Sys.println('SharedTexture: no shared textures here (${f[1]} on ${f[2]})' + (require ? ": FAILED (--require)" : ": skipped"));
			return !require;
		}
		var kind = f[1], handle = f[2];
		var device = Device.create(Surface.headless(W, H));
		var t = device.openShared(handle, W, H);
		if (t == null) {
			Sys.println('SharedTexture: FAIL: $kind: $handle not opened');
			p.kill();
			return false;
		}
		var r = new Renderer(device);
		var px = Bytes.alloc(W * H * 4);
		function frame():Bytes {
			var enc = device.beginFrame();
			r.begin(W, H);
			r.gpuTexture(t, -1, 0, 0, W, H);
			r.prepare(enc);
			enc.beginPass({colors: [{load: Clear, clear: new helder.gfx.Color(0, 0, 0)}]});
			r.end(enc);
			enc.endPass();
			device.readPixels(px);
			device.endFrame();
			return px;
		}
		function at(b:Bytes, x:Int, y:Int):Int {
			var i = (y * W + x) * 4;
			return (b.get(i) << 16) | (b.get(i + 1) << 8) | b.get(i + 2);
		}
		var ok = true;
		function expect(what:String, b:Bytes, tl:Int, br:Int) {
			var got = [at(b, W >> 2, H >> 2), at(b, 3 * W >> 2, 3 * H >> 2), at(b, 3 * W >> 2, H >> 2), at(b, W >> 2, 3 * H >> 2)];
			var want = [tl, br, 0x0000ff, 0x0000ff];
			for (k in 0...4)
				if (got[k] != want[k]) {
					ok = false;
					Sys.println('SharedTexture: FAIL: $kind: $what: [${got.map(c -> StringTools.hex(c, 6)).join(", ")}], not [${want.map(c -> StringTools.hex(c, 6)).join(", ")}]');
					return;
				}
		}
		var t0 = haxe.Timer.stamp();
		expect("the first frame", frame(), 0xff0000, 0x00ff00);
		var first = haxe.Timer.stamp() - t0;
		// (the producer draws again into the same texture: the next frame shows it)
		p.stdin.writeString("again\n");
		p.stdin.flush();
		var t1 = haxe.Timer.stamp();
		var drawn = p.stdout.readLine();
		expect("the second frame", drawn == "drawn" ? frame() : Bytes.alloc(W * H * 4), 0x00ff00, 0xff0000);
		var second = haxe.Timer.stamp() - t1;
		p.stdin.writeString("end\n");
		p.stdin.flush();
		p.exitCode();
		p.close();
		device.destroyTexture(t);
		if (ok)
			Sys.println('SharedTexture: ok: $kind (${device.backend}): two frames through the shared texture, the right pixels; opened and drawn in ${Math.round(first * 10000) / 10} ms, the next frame ${Math.round(second * 10000) / 10} ms');
		return ok;
	}
}
