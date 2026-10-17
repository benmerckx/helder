import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.os.*;
import hxmc.os.x11.Xlib;
import hxmc.unsafe.*;

// The examples' frames, checked against golden images (make gfx-check): the
// triangle (Triangle.hx, triangle.png) and the cube (Cube.hx, turned by
// Scene.ANGLE: cube.png)
//
//   GfxTest headless triangle|cube <golden.png> <out.png> [--bless]
//     Linux: on an EGL pbuffer (Mesa's surfaceless platform), read back with
//     glReadPixels; macOS: Metal, on an offscreen texture copied to a buffer;
//     Windows: D3D11 (WARP with HXMC_GFX_SOFTWARE=1), on an offscreen
//     texture copied to a staging texture
//   GfxTest window triangle|cube <golden.png> <out.png> [frames]
//     in a window (X11 under Xvfb, Cocoa, Win32): the last frame's back
//     buffer before the present (readPixels) and the window's pixels after
//     it (XGetImage, CGWindowListCreateImage, PrintWindow or the screen's DC);
//     input sent to the window after the second frame must come back as
//     events: a key's character and the wheel (X11: a KeyPress of a and
//     button 4; Windows: WM_CHAR of U+00E9 and of a surrogate pair, WM_MOUSEWHEEL;
//     macOS: a key down of a, posted)
//
// Comparison: llvmpipe (LIBGL_ALWAYS_SOFTWARE=1) is deterministic, but its
// rasterization and interpolation may change between Mesa versions, and
// another GPU (Metal) or rasterizer (WARP) rounds the interpolated colours
// and covers the edges' pixels its own way: a pixel matches when no channel differs by
// more than TOLERANCE, and at most MAX_OFF of the pixels may differ by more
// (the edges). The report says whether the match was exact.
class GfxTest {
	static inline var WIDTH = 256;
	static inline var HEIGHT = 192;
	static inline var TOLERANCE = 2;
	static inline var MAX_OFF = 0.005;

	static function main() {
		var args = Sys.args();
		if (args.length < 4 || (args[1] != "triangle" && args[1] != "cube")) {
			Sys.println("usage: GfxTest headless|window triangle|cube <golden.png> <out.png> [--bless | frames]");
			Sys.exit(2);
		}
		var name = args[1], golden = args[2], out = args[3];
		var ok = switch args[0] {
			case "headless": headless(name, golden, out, args[4] == "--bless");
			case "window": window(name, golden, out, args.length > 4 ? Std.parseInt(args[4]) : 5);
			case m: throw "GfxTest: no mode " + m;
		}
		Sys.exit(ok ? 0 : 1);
	}

	static function headless(name:String, golden:String, out:String, bless:Bool):Bool {
		var device = try Device.create(Surface.headless(WIDTH, HEIGHT)) catch (e:String) {
			// (macOS virtual machines may have no GPU: check.sh skips the test)
			if (e != "hxmc.gfx: no Metal device") throw e;
			Sys.println("GfxTest: headless: skipped: no Metal device");
			Sys.exit(3);
			null;
		}
		var draw = Scene.make(name, device);
		// (the shader macro's other test shaders, with uniform blocks, textures and every builtin: this back end compiles them)
		device.createPipeline(LitShader.pipeline());
		device.createPipeline(BuiltinShader.pipeline());
		device.createPipeline(TexturedShader.pipeline());
		Sys.println("GfxTest: headless: LitShader, BuiltinShader and TexturedShader compile");
		var pixels = Bytes.alloc(WIDTH * HEIGHT * 4);
		var enc = device.beginFrame();
		draw(enc);
		device.readPixels(pixels);
		device.endFrame();
		device.dispose();
		sys.io.File.saveBytes(out, Png.encode(pixels, WIDTH, HEIGHT));
		if (bless) {
			sys.io.File.saveBytes(golden, Png.encode(pixels, WIDTH, HEIGHT));
			Sys.println('GfxTest: blessed $golden');
			return true;
		}
		return compare('$name, headless', pixels, golden);
	}

	static function window(name:String, golden:String, out:String, frames:Int):Bool {
		var w = new Window("GfxTest", WIDTH, HEIGHT);
		// (a Retina display: the window's size is in points)
		if (w.width != WIDTH) {
			var s = w.scale;
			w.close();
			w = new Window("GfxTest", Math.round(WIDTH / s), Math.round(HEIGHT / s));
		}
		if (Mem.os() == 1) CocoaTest.prepare(w);
		var device = Device.create(w.surface);
		var draw = Scene.make(name, device);
		var back = Bytes.alloc(WIDTH * HEIGHT * 4);
		var n = 0, tries = 0, events = 0, closed = false;
		// (typing on: the characters come as TextInput on every platform)
		w.startTextInput(0, 0, 1, 1);
		var text:Array<Int> = [], wheel = 0.0;
		App.run(() -> {
			if (++tries > frames + 1000) App.quit();
			var enc = device.beginFrame();
			if (enc == null) return;
			draw(enc);
			if (++n == frames) device.readPixels(back);
			device.endFrame();
			if (n == 2) Mem.os() == 1 ? CocoaTest.input(w) : Mem.os() == 2 ? WinTest.input(w) : sendInput(w);
			// then the window's close button (X11: the window manager's client message)
			if (n == frames) Mem.os() == 1 ? CocoaTest.close(w) : Mem.os() == 2 ? WinTest.close(w) : sendClose(w);
		}, e -> {
			events++;
			if (e.kind == TextInput)
				for (c in new haxe.iterators.StringIteratorUnicode(e.text))
					text.push(c);
			// (in notches up: a notch is 40 pixels at the window's scale)
			if (e.kind == Scroll) wheel -= e.deltaY / (40 * w.scale);
			if (e.kind == Close && e.window == w) {
				closed = true;
				App.quit();
			}
		});
		var shown = Mem.os() == 1 ? CocoaTest.capture(w, WIDTH, HEIGHT) : Mem.os() == 2 ? WinTest.capture(w, WIDTH, HEIGHT) : capture(w);
		sys.io.File.saveBytes(out, Png.encode(shown != null ? shown : back, WIDTH, HEIGHT));
		Sys.println('GfxTest: $n frames in a ${device.width}x${device.height} window, $events events' + (closed ? ", closed" : ", FAIL: no Close event"));
		var size = device.width == WIDTH && device.height == HEIGHT;
		if (!size) Sys.println('GfxTest: FAIL: not ${WIDTH}x${HEIGHT}');
		var want = Mem.os() == 1 ? [0x61] : Mem.os() == 2 ? [0xE9, 0x1F600] : [0x61], wantWheel = Mem.os() == 1 ? 0 : 1;
		var input = text.join(",") == want.join(",") && wheel == wantWheel;
		Sys.println('GfxTest: input: characters [' + [for (c in text) StringTools.hex(c)].join(", ") + '], wheel $wheel' + (input ? "" : ', FAIL: not [' + [for (c in want) StringTools.hex(c)].join(", ") + '], $wantWheel'));
		device.dispose();
		w.close();
		var a = compare('$name, window, back buffer', back, golden);
		if (shown == null) {
			// (macOS: the window server would not give the window's pixels; Windows: no GDI capture)
			Sys.println("GfxTest: window, screen pixels: skipped (no capture)");
			return a && closed && size && input;
		}
		var b = compare(name + ", window, " + (Mem.os() == 1 ? "screen" : Mem.os() == 2 ? "GDI" : "X11") + " pixels", shown, golden);
		return a && b && closed && size && input;
	}

	// a KeyPress of a, then button 4 (the wheel up)
	static function sendInput(w:Window) {
		var d = w.surface.display, id = w.surface.handle.toI64();
		Arena.scoped(a -> {
			var k:Ptr<XKeyEvent> = a.alloc(X.EVENT_SIZE);
			LibC.memset(k, 0, X.EVENT_SIZE);
			k.value.type = X.KeyPress;
			k.value.display = d;
			k.value.window = id;
			k.value.same_screen = 1;
			k.value.keycode = Xlib.XKeysymToKeycode(d, 0x61);
			Xlib.XSendEvent(d, id, 0, X.KeyPressMask, k.raw());
			k.value.type = X.ButtonPress;
			k.value.keycode = 4;
			k.value.x = 10;
			k.value.y = 10;
			Xlib.XSendEvent(d, id, 0, X.ButtonPressMask, k.raw());
			Xlib.XFlush(d);
		});
	}

	static function sendClose(w:Window) {
		var d = w.surface.display, id = w.surface.handle.toI64();
		Arena.scoped(a -> {
			var m:Ptr<XClientMessageEvent> = a.alloc(X.EVENT_SIZE);
			m.value.type = X.ClientMessage;
			m.value.window = id;
			m.value.message_type = Xlib.XInternAtom(d, Mem.cstr("WM_PROTOCOLS"), 0);
			m.value.format = 32;
			m.value.l0 = Xlib.XInternAtom(d, Mem.cstr("WM_DELETE_WINDOW"), 0);
			Xlib.XSendEvent(d, id, 0, 0, m.raw());
			Xlib.XFlush(d);
		});
	}

	// the window's pixels from the X server (ZPixmap, 32 bits: B, G, R, X)
	static function capture(w:Window):Bytes {
		var img = Xlib.XGetImage(w.surface.display, w.surface.handle.toI64(), 0, 0, WIDTH, HEIGHT, (-1 : Int64), X.ZPixmap);
		if (img.isNull()) throw "GfxTest: XGetImage failed";
		if (img.value.bits_per_pixel != 32) throw "GfxTest: " + img.value.bits_per_pixel + " bits per pixel";
		var rgba = Bytes.alloc(WIDTH * HEIGHT * 4);
		for (y in 0...HEIGHT) {
			var row = img.value.data.add(y * img.value.bytes_per_line);
			for (x in 0...WIDTH) {
				rgba.set(4 * (y * WIDTH + x), row[4 * x + 2]);
				rgba.set(4 * (y * WIDTH + x) + 1, row[4 * x + 1]);
				rgba.set(4 * (y * WIDTH + x) + 2, row[4 * x]);
				rgba.set(4 * (y * WIDTH + x) + 3, 255);
			}
		}
		Xlib.XDestroyImage(img);
		return rgba;
	}

	static function compare(what:String, pixels:Bytes, golden:String):Bool {
		var g = Png.decode(sys.io.File.getBytes(golden));
		if (g.width != WIDTH || g.height != HEIGHT) {
			Sys.println('GfxTest: $what: FAIL: the golden image is ${g.width}x${g.height}');
			return false;
		}
		var off = 0, differ = 0, max = 0, hidden = 0;
		for (p in 0...WIDTH * HEIGHT) {
			// (alpha below 255: a pixel the window does not show, its rounded corners)
			if (pixels.get(4 * p + 3) != 255) {
				hidden++;
				continue;
			}
			var d = 0;
			for (k in 0...3) {
				var v = pixels.get(4 * p + k) - g.rgba.get(4 * p + k);
				if (v < 0) v = -v;
				if (v > d) d = v;
			}
			if (d > 0) differ++;
			if (d > TOLERANCE) off++;
			if (d > max) max = d;
		}
		// a sanity check: the scene is there (the centre is not the clear colour, a corner is)
		var c = 4 * ((HEIGHT >> 1) * WIDTH + (WIDTH >> 1));
		var lit = Math.abs(pixels.get(c) - pixels.get(0)) + Math.abs(pixels.get(c + 1) - pixels.get(1)) + Math.abs(pixels.get(c + 2) - pixels.get(2)) > 30
			&& pixels.get(0) < 40;
		var ok = lit && off <= MAX_OFF * WIDTH * HEIGHT;
		Sys.println('GfxTest: $what: ' + (ok ? "ok" : "FAIL") + (differ == 0 ? " (exact)" : ' ($differ pixels differ, $off by more than $TOLERANCE, at most $max)')
			+ (hidden > 0 ? ' ($hidden pixels not shown)' : "") + (lit ? "" : " (nothing drawn)"));
		return ok;
	}
}
