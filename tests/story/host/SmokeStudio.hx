import haxe.Json;
import haxe.io.Bytes;
import helder.async.*;
import helder.gfx.*;
import helder.os.Surface;
import helder.ui.draw.Renderer;

// The story-shared lane: helder.story's native preview host as the
// desktop studio uses it, end to end, with this program as the studio: it
// listens for the host's dev connection, starts SmokeHost (a dev build: its
// one story, blue with a red square at the top left) with helder dev's
// variables, answers its hello, asks it to show the story (Host.show), and
// takes its frames (Host.frame) as the studio does: a shared texture opened
// in this process's own device (helder.gfx's openShared), drawn with
// helder.ui's renderer and read back, or (llvmpipe) the pixels through
// shared memory (helder.story.FrameFile). Each frame's colours are checked
// where the square and the background are; then the story zoomed (scale
// 2: a new target of twice the size, the first one released) and checked
// again. --require: the frames must come as shared textures (macOS:
// IOSurface, Windows: DXGI), not copies.
//
//   SmokeStudio <SmokeHost's executable> [--require]
class SmokeStudio {
	static var failed = 0;
	static var socket:Null<Socket> = null;
	static var nextId = 1;

	@:coroutine static function send(m:Dynamic)
		socket.writeString(Json.stringify(m) + "\n");

	@:coroutine static function request(method:String, params:Dynamic)
		send({jsonrpc: "2.0", id: nextId++, method: method, params: params});

	static function check(what:String, ok:Bool, ?detail:String) {
		if (!ok) failed++;
		Sys.println('story-shared: ${ok ? "ok" : "FAIL"}: $what' + (detail == null ? "" : ': $detail'));
	}

	static function main() {
		var args = Sys.args(), exe = args[0], require = args.contains("--require");
		var device = Device.create(Surface.headless(240, 160));
		var r = new Renderer(device);
		var px = Bytes.alloc(240 * 160 * 4);
		Async.main(task -> {
			var server = Server.listen("127.0.0.1", 0);
			var env = Process.environment();
			env.set("HXMC_DEV", '127.0.0.1:${server.port}');
			env.set("HXMC_DEV_PROTOCOL", "1");
			env.set("HXMC_DEV_EXIT_WITH_SERVER", "1");
			env.remove("HELDER_HEADLESS");
			var t0 = haxe.Timer.stamp();
			var p = new Process(exe, [], {env: env});
			p.closeStdin();
			task.async(_ -> {
				var o = new Reader(p.stdout), l;
				while ((l = o.readLine()) != null) Sys.println('[host] $l');
			});
			task.async(_ -> {
				var o = new Reader(p.stderr), l;
				while ((l = o.readLine()) != null) Sys.println('[host] $l');
			});
			var s = Async.timeout(60, _ -> server.accept());
			var lines = new Reader(s), sharing = "", frames = 0, last = 0;
			socket = s;
			// a frame: drawn here at its pixels' size, two of its points' colours read back
			function frame(f:Dynamic):Bool {
				var w:Int = f.pixelWidth, h:Int = f.pixelHeight, k = w / 120, handle:String = f.handle;
				var img:Null<Texture> = null;
				if (StringTools.startsWith(handle, "copy:")) {
					var file = helder.story.FrameFile.open(handle.substr(5), w * h * 4);
					if (file == null) return false;
					file.unlink();
					var b = Bytes.alloc(w * h * 4);
					file.read(b, w * h * 4);
					file.close();
					img = device.createTexture({width: w, height: h, data: b});
				} else
					img = device.openShared(handle, w, h);
				if (img == null) {
					check('frame ${frames}: $handle opened', false);
					return false;
				}
				var enc = device.beginFrame();
				r.begin(240, 160);
				r.gpuTexture(img, -1, 0, 0, w, h);
				r.prepare(enc);
				enc.beginPass({colors: [{load: Clear, clear: new helder.gfx.Color(0, 0, 0)}]});
				r.end(enc);
				enc.endPass();
				device.readPixels(px);
				device.endFrame();
				device.destroyTexture(img);
				function at(x:Float, y:Float):String {
					var i = (Std.int(y) * 240 + Std.int(x)) * 4;
					return "#" + [for (c in 0...3) StringTools.hex(px.get(i + c), 2).toLowerCase()].join("");
				}
				var square = at(20 * k, 20 * k), back = at(100 * k, 60 * k);
				check('frame ${frames} (${w}x$h, $sharing): the square red, the background blue', square == "#ff0000" && back == "#0000ff", 'square $square, background $back');
				return true;
			}
			var line;
			while ((line = Async.timeout(30, _ -> lines.readLine())) != null) {
				var m:Dynamic = try Json.parse(line) catch (_:Dynamic) null;
				if (m == null || m.method == null) continue;
				switch (m.method : String) {
					case "Runtime.hello":
						send({jsonrpc: "2.0", id: m.id, result: {protocol: 1, server: "story-shared"}});
					case "Host.ready":
						sharing = m.params.sharing;
						check('the host ready: ${m.params.screens.length} screen, frames as $sharing', m.params.screens.length == 1);
						if (require) check('frames as shared textures (--require)', sharing != "copy" && sharing != null, sharing);
						request("Host.show", {screens: ["Smoke/Square"], focused: "Smoke/Square", scale: 1});
					case "Host.frame":
						frames++;
						if (frames == 1) Sys.println('story-shared: the first frame ${Math.round((haxe.Timer.stamp() - t0) * 1000)} ms after the host started');
						frame(m.params);
						if (last != 0) request("Host.release", {screen: 0, buffer: last});
						last = m.params.buffer;
						if (frames == 1) request("Host.show", {screens: ["Smoke/Square"], focused: "Smoke/Square", scale: 2});
						if (frames == 2) break;
					case _:
				}
			}
			check('two frames, at 1x and 2x', frames == 2, '$frames');
			s.close();
			server.close();
			if (!p.exited()) p.kill();
			p.wait();
		});
		Sys.println('story-shared: ' + (failed == 0 ? "ok" : '$failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}
}
