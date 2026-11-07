package studio;

import haxe.Json;
import haxe.io.Bytes;
import haxe.io.Path;
import helder.async.*;
import helder.compiler.service.Diagnostic;
import helder.compiler.service.Service;
import helder.image.Image;
#if !(hxmc.target == "wasm32-wasi")
import helder.story.FrameFile;
#end
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import studio.Project;
import sys.FileSystem;
import sys.io.File;

using StringTools;

#if (hxmc.target == "wasm32-wasi")
// (in the browser: one preview host in a worker, studio.web.WebPreviews)
typedef Previews = studio.web.WebPreviews;
#else
// The project's program, never in the studio's process: one process for
// the whole project, its preview host (natively; in the browser
// studio.web.WebPreviews, the same host in a worker). The studio builds the
// screens' program (Project.words: a dev build of the project's stories,
// helder.story.Screens over them: helder.story.NativeHost here) and starts
// it once, with helder dev's machinery (HXMC_DEV: a connection to the
// studio's socket speaking the devtools protocol, src/helder/devtools/
// README.md; HXMC_DEV_SNAPSHOT: its state across a rebuild). Every story
// is mounted in it as a root of its own with a context of its own
// (helder.ui.ScreenContext); only the screens in the canvas' view draw (the
// one zoomed into every frame, at the canvas' scale), the others suspended
// with their last frames here. Each frame is a GPU texture the host drew
// and this process opens and composites as an image (helder.gfx's shared
// textures: an IOSurface, a DXGI texture, a dma-buf; Image.ofShared, the
// renderer's own texture handling), or where the GPU shares none
// (llvmpipe) its pixels in shared memory (helder.story.FrameFile), copied
// into the image. A frame's target goes back to the host (Host.release)
// once the canvas drew a newer one twice. The compiler stays warm
// (helder.compiler.service: Service). A save of a file whose live literals
// only changed is patched in the host (Hot.literals, nothing built); any
// other a build, then the host asked to reload (Runtime.reload: its
// snapshot written) and started again from it; meanwhile and after a crash
// the canvas keeps the last frames (a crash's host is started again). A
// project without stories runs its own main instead (one window,
// helder.headless's serve mode: its frames through a file).
class Previews {
	public final project:Project;
	public final screens:Array<Screen>;
	// "starting", "building", "running", "failed" (the last good build keeps running)
	public final status = signal("starting");
	public final diagnostics:Signal<Array<Diagnostic>> = signal([]);
	// the last build's time, a patch's (ms)
	public final buildMs = signal(0);
	// told: a screen's new frame
	public var onFrame:Null<Screen->Void> = null;
	// told: a line of the studio's log (the builds, the programs' output)
	public var onLog:String->Void = s -> Sys.println(s);
	// how the host's frames come: "iosurface", "dxgi", "dmabuf" (shared
	// textures), "copy" (shared memory), "file" (a project without stories);
	// null until it said
	public var sharing(default, null):Null<String> = null;

	// the last build failed (or nothing could start)
	public var failed(default, null) = false;

	var service:Null<Service> = null;
	var server:Null<Server> = null;
	var builds = 0;
	var exe = "";
	var building = false;
	var rebuilding = false;
	// whether the running program is an incremental build's; the program a cold build made
	var incremental = false;
	var coldExe = "";
	// files written while a build runs, for after it
	final writes = new Map<String, String>();
	var stopping = false;
	// the edits waiting for the build in progress
	var again = false;
	// the host: its process (one asked to end: retiring, not a crash when
	// it does), its connection, since when, its restarts after crashes
	var process:Null<Process> = null;
	var connection:Null<Connection> = null;
	var retiring:Null<Process> = null;
	var startedAt = 0.0;
	var crashes = 0;
	var reloading = false;
	// the host's screens by index (Host.ready's)
	var order:Array<Screen> = [];
	// the screens in view and the one focused, last told; the last asked (told again to a new host)
	var shown = "";
	var showWanted:Null<{names:Array<String>, focused:Null<String>, scale:Float}> = null;
	// where the host's copies go (shared memory: /dev/shm), mapped here by path
	final framesDir:String;
	final files = new Map<String, FrameFile>();
	// frames' targets to give back to the host once a newer frame was drawn
	final releasing:Array<{screen:Int, buffer:Int, img:Image, mark:Int, at:Float}> = [];

	public function new(project:Project) {
		this.project = project;
		screens = [for (s in project.screens) new Screen(s)];
		// (shared memory where there is: each file unlinked once both have it mapped, nothing left behind)
		framesDir = FileSystem.exists("/dev/shm") ? "/dev/shm" : '${project.out}/frames';
	}

	public function screen(name:String):Null<Screen>
		return Lambda.find(screens, s -> s.info.name == name);

	// whether every screen shows a frame
	public function allShown():Bool
		return !Lambda.exists(screens, s -> s.version == 0 && !s.crashed) || failed;

	// whether work is in flight (a build, a reload, screens not shown yet)
	public function busy():Bool
		return building || rebuilding || again || reloading || (!failed && !allShown());

	// ms since the screens' program started (-1: none)
	public function sinceHost():Float
		return process == null ? -1 : Math.round((haxe.Timer.stamp() - startedAt) * 1000);

	// the compiler, the socket, the first build, the host started
	@:coroutine public function start(task:Node) {
		if (project.typescript) try helder.cli.Compiler.typescript(project.entry.helder) catch (e:Dynamic) {
			fail(Std.string(e));
			return;
		}
		if (!startCompiler(task)) return;
		server = Server.listen("127.0.0.1", 0);
		var srv = server;
		task.async(_ -> while (!stopping) {
			var s = srv.accept();
			task.async(_ -> connected(s));
		});
		// (the frames' targets given back, when the canvas drew newer ones)
		task.async(_ -> while (!stopping) {
			giveBack();
			Async.delay(0.004);
		});
		if (build(null)) launch(task, false);
	}

	@:coroutine function startCompiler(task:Node):Bool {
		service = Service.start(task, {tool: helder.cli.Compiler.tool(), env: Process.environment(), std: helder.cli.Compiler.hxmcStd()}, m -> onLog('studio: $m'));
		if (service == null) {
			fail("the compiler did not start");
			return false;
		}
		service.literals('${project.out}/literals');
		return true;
	}

	// A program of an incremental build that ends with an error right after
	// it starts is built again from cold (a new compiler) and started again:
	// the warm compiler of the pinned @hxmc/cli builds a wrong program after
	// some edits (hxmc's server: a padding added to a <text> of a module a
	// story file uses, the story's view crossing its attributes: "todos is
	// not a Direction"; fixed by hxmc#161, not in the nightly package.json
	// pins yet), and a cold build of the same files is right.
	@:coroutine function coldRebuild(task:Node) {
		if (rebuilding || building) return;
		rebuilding = true;
		onLog('studio: the incremental build\'s program ended at its start: building again from cold');
		try service.stop() catch (_:Dynamic) {}
		var ok = startCompiler(task) && build(null);
		coldExe = exe;
		rebuilding = false;
		if (ok) reload(task);
	}

	function setStatus(s:String) {
		failed = s == "failed";
		status(s);
	}

	function fail(why:String) {
		setStatus("failed");
		onLog('studio: $why');
	}

	// a file of the project written: at once, or after the build in progress
	// (a source written while the compiler reads it is read half old, half
	// new: its markup's literals' places off)
	public function write(path:String, text:String) {
		if (building) writes.set(path, text) else sys.io.File.saveContent(path, text);
	}

	function flushWrites() {
		for (p => t in writes) sys.io.File.saveContent(p, t);
		writes.clear();
	}

	// a build of the screens' program (changed: the files saved since); whether it compiled
	@:coroutine function build(changed:Null<Array<String>>):Bool {
		flushWrites();
		building = true;
		setStatus("building");
		helder.cli.TestCommand.mkdirs(project.out);
		// (a new file each build: a running program's executable is not written over)
		// (the one two builds before is not running any more: removed)
		var next = '${project.out}/screens-${++builds}';
		for (old in ['${project.out}/screens-${builds - 2}', '${project.out}/screens-${builds - 2}.exe'])
			try if (sys.FileSystem.exists(old) && old != exe) sys.FileSystem.deleteFile(old) catch (_:Dynamic) {}
		var t0 = haxe.Timer.stamp();
		var words = try project.words(next) catch (e:Dynamic) {
			building = false;
			fail(Std.string(e));
			return false;
		}
		// (a story file is built through its link: the link told too)
		if (changed != null) changed = changed.concat([for (l => r in project.links) if (changed.contains(r)) l]);
		var r = service.build(words, project.dir, changed);
		var ms = Math.round((haxe.Timer.stamp() - t0) * 1000);
		if (r.ok) try helder.cli.AssetStep.after(next, project.entry.target, project.entry.classPaths.concat([project.entry.root]), true) catch (_:Dynamic) {}
		diagnostics([for (d in r.diagnostics) d.file == null ? d : {file: project.real(d.file), line: d.line, column: d.column, endColumn: d.endColumn, severity: d.severity, message: d.message}]);
		building = false;
		buildMs(ms);
		if (!r.ok) {
			setStatus("failed");
			onLog('studio: the build failed in $ms ms' + (exe == "" ? "" : "; the last good build keeps running"));
			if (r.messages != "") onLog(r.messages);
			return false;
		}
		exe = next;
		incremental = changed != null;
		crashes = 0;
		onLog('studio: built ${project.name}\'s screens in $ms ms');
		setStatus("running");
		return true;
	}

	// whether the program is the stories' host (else the project's own main: one window)
	inline function hosting():Bool
		return screens[0].info.story;

	// the host started (withSnapshot: from the state its last one saved)
	@:coroutine function launch(task:Node, withSnapshot:Bool) {
		var env = Process.environment();
		env.set("HXMC_DEV", '127.0.0.1:${server.port}');
		env.set("HXMC_DEV_PROTOCOL", "1");
		// (the studio gone, its host with it)
		env.set("HXMC_DEV_EXIT_WITH_SERVER", "1");
		var snap = '${project.out}/host.snapshot';
		if (withSnapshot && FileSystem.exists(snap)) env.set("HXMC_DEV_SNAPSHOT", snap) else {
			env.remove("HXMC_DEV_SNAPSHOT");
			try FileSystem.deleteFile(snap) catch (_:Dynamic) {}
		}
		if (!FileSystem.exists(framesDir)) helder.cli.TestCommand.mkdirs(framesDir);
		env.set("HELDER_STUDIO_FRAMES", framesDir);
		// (a project without stories: its own window, offscreen, its frames to a file)
		// (the studio's own run's options not the host's)
		if (!hosting()) env.set("HELDER_HEADLESS", Json.stringify({serve: {frames: '$framesDir/app.rgba'}})) else env.remove("HELDER_HEADLESS");
		// (offscreen, no display: the GPU the studio has, so that the two share textures; one locale)
		env.set("LC_ALL", "C.UTF-8");
		env.set("LANG", "C.UTF-8");
		env.remove("DISPLAY");
		env.remove("WAYLAND_DISPLAY");
		var p = try new Process(exe, [], {env: env, cwd: project.dir}) catch (e:Dynamic) {
			onLog('studio: the screens\' program did not start: $e');
			null;
		}
		if (p == null) return;
		p.closeStdin();
		process = p;
		startedAt = haxe.Timer.stamp();
		// (the last process's frames' targets are not this one's; its copies' mappings let go: their pixels copied here)
		releasing.resize(0);
		for (f in files)
			f.close();
		files.clear();
		for (s in screens)
			s.buffer = 0;
		order = [];
		task.async(_ -> forward(p.stdout));
		task.async(_ -> forward(p.stderr));
		task.async(_ -> {
			var code = p.wait();
			if (process == p && retiring != p) {
				process = null;
				connection = null;
				// (it ended on its own: a crash, the last frames kept, started again)
				if (!stopping) {
					reloading = false;
					for (s in screens) {
						s.reloading = false;
						s.crashed = code != 0;
					}
					onLog('studio: the screens\' program ended (exit code $code)');
					if (onFrame != null) onFrame(screens[0]);
					if (code != 0 && incremental && coldExe != exe && haxe.Timer.stamp() - startedAt < 5) {
						coldExe = exe;
						task.async(_ -> coldRebuild(task));
					} else if (code != 0 && crashes++ < 3) {
						onLog('studio: starting it again');
						Async.delay(0.25);
						if (process == null && !stopping) launch(task, FileSystem.exists(snap));
					}
				}
			}
			p.close();
		});
	}

	@:coroutine function forward(src:Stream.Source) {
		var r = new Reader(src), line;
		try while ((line = r.readLine()) != null) onLog('[screens] $line') catch (_:haxe.Exception) {}
	}

	// the program's connection: its hello answered, then its messages
	@:coroutine function connected(socket:Socket) {
		var c = new Connection(socket);
		var r = new Reader(socket), line;
		try while ((line = r.readLine()) != null) {
			var m:Dynamic = try Json.parse(line) catch (_:Dynamic) null;
			if (m == null || m.jsonrpc == null) continue;
			if (m.method == "Runtime.hello" && m.id != null) {
				c.send({jsonrpc: "2.0", id: m.id, result: {protocol: 1, server: "helder studio"}});
				if (!hosting()) {
					connection = c;
					sharing = "file";
				}
				continue;
			}
			if (m.method == null) {
				c.answered(m);
				continue;
			}
			switch (m.method : String) {
				case "Host.ready":
					var list:Array<Dynamic> = m.params.screens;
					order = [for (x in list) screen(x.name)];
					sharing = m.params.sharing;
					connection = c;
					onLog('studio: the screens\' host is running (${order.length} screens, frames: $sharing)');
					// (what is in view, told again: those draw; the others keep their last frames, suspended)
					if (showWanted != null) c.request("Host.show", {screens: showWanted.names, focused: showWanted.focused, scale: showWanted.scale}, _ -> {});
					for (s in screens)
						if (s.version > 0 && (showWanted == null || !showWanted.names.contains(s.info.name))) s.reloading = false;
					if (!Lambda.exists(screens, x -> x.reloading)) reloading = false;
				case "Host.frame":
					frame(m.params);
				case "Headless.frame":
					fileFrame(m.params);
				case "Hot.patched":
					for (s in screens)
						s.patchedMs = m.params.ms;
				case _:
			}
		} catch (_:haxe.Exception) {}
		if (connection == c) connection = null;
		c.closed = true;
		socket.close();
	}

	// a screen's frame: its texture (another process's) the screen's image,
	// or its pixels copied in from shared memory (the target given back at once)
	function frame(p:Dynamic) {
		var index:Int = p.screen, s = order[index];
		if (s == null) return;
		var handle:String = p.handle, w:Int = p.pixelWidth, h:Int = p.pixelHeight, buffer:Int = p.buffer;
		var img = s.image.peek();
		if (handle.startsWith("copy:")) {
			var path = handle.substr(5), n = w * h * 4;
			var f = files.get(path);
			if (f == null) {
				f = FrameFile.open(path, n);
				if (f == null) return;
				files.set(path, f);
				// (mapped by both now: its name goes, its memory stays the two processes')
				f.unlink();
			}
			if (img != null && img.width == w && img.height == h && img.hasPixels && img.shared == null) {
				f.read(img.pixels, n);
				img.changed();
			} else {
				var b = Bytes.alloc(n);
				f.read(b, n);
				var next = new Image(w, h, b);
				if (img == null) s.image(next) else img.replace(next);
			}
			release(index, buffer);
		} else {
			var next = Image.ofShared(handle, w, h);
			if (img == null) s.image(next) else img.replace(next);
			var shown = s.image.peek();
			// (the target shown before: given back once the canvas drew this one twice, the GPU done with the old)
			if (s.buffer != 0 && s.buffer != buffer) releasing.push({screen: index, buffer: s.buffer, img: shown, mark: shown.drawn, at: haxe.Timer.stamp()});
			s.buffer = buffer;
		}
		shownFrame(s);
	}

	function shownFrame(s:Screen) {
		var first = s.version == 0;
		s.version++;
		s.frames(s.version);
		s.reloading = false;
		if (s.crashed) s.crashed = false;
		if (first) s.shownAt = haxe.Timer.stamp();
		if (!Lambda.exists(screens, x -> x.reloading)) reloading = false;
		if (onFrame != null) onFrame(s);
	}

	function release(screen:Int, buffer:Int) {
		var c = connection;
		if (c != null) c.request("Host.release", {screen: screen, buffer: buffer}, _ -> {});
	}

	// (the targets the canvas has drawn past, or half a second on: given back)
	function giveBack() {
		if (releasing.length == 0) return;
		var now = haxe.Timer.stamp();
		for (r in releasing.copy())
			if (r.img.drawn >= r.mark + 2 || now - r.at > 0.5) {
				releasing.remove(r);
				release(r.screen, r.buffer);
			}
	}

	// (a project without stories) a frame told: its pixels read from its file into the screen's image
	function fileFrame(p:Dynamic) {
		var s = screens[0];
		var b = try File.getBytes(p.path) catch (_:Dynamic) null;
		if (b == null || b.length < 16 || b.getString(0, 4) != "HLDF") return;
		var w = b.getInt32(4), h = b.getInt32(8);
		if (b.length < 16 + w * h * 4) return;
		var img = new Image(w, h, b.sub(16, w * h * 4));
		if (s.image.peek() == null) s.image(img) else s.image.peek().replace(img);
		shownFrame(s);
	}

	// ---- edits

	// a file's new text, saved: its live literals patched in the host when
	// only they changed (nothing built), else a build and a reload. What
	// happened: "patched", "unchanged", "built", "failed", or "queued" (a
	// build in progress: this one after it)
	@:coroutine public function saved(task:Node, file:String, ?literalsOnly:Bool):String {
		if (service == null || service.sources == null) return "failed";
		if (building || rebuilding) return rebuild(task, [file]) ? "built" : "failed";
		var why = null;
		var patches = service.sources.patches(file, w -> why = w);
		if (patches != null && patches.length == 0) return "unchanged";
		if (patches != null && patch(patches)) {
			service.sources.took(patches);
			return "patched";
		}
		if (literalsOnly == true) return "failed";
		onLog('studio: building: ${Path.withoutDirectory(file)}: ${why ?? "a literal read once, not bound"}');
		return rebuild(task, [file]) ? "built" : "failed";
	}

	// a file's text before it is saved: its live literals' patches when only
	// they changed (null: a build's, why said; empty: none changed)
	public function literalPatches(file:String, text:String, ?why:String->Void):Null<Array<{id:String, source:String}>>
		return service == null || service.sources == null ? null : service.sources.patchesOf(file, text, why);

	// the patches the host took (a save after them changes nothing)
	public function took(list:Array<{id:String, source:String}>)
		if (service != null && service.sources != null) service.sources.took(list);

	// live literals sent to the host (one program: every screen's next frame shows them); false: not connected
	public function patch(list:Array<{id:String, source:String}>):Bool {
		var c = connection;
		if (c == null) return false;
		for (s in screens)
			s.patchedMs = -1;
		c.request("Hot.literals", {set: list}, r -> {
			var stale:Array<String> = r.result?.stale ?? [];
			if (stale.length > 0) onLog('studio: ${stale.length} literal(s) read once: ${stale.join(", ")}');
		});
		return true;
	}

	// a build, then the host reloaded from its snapshot
	@:coroutine public function rebuild(task:Node, changed:Array<String>):Bool {
		// (one build at a time: the compiler's service is one; an edit during
		// a build is built after it, every source told, and waits for it)
		if (building || rebuilding) {
			again = true;
			while (building || rebuilding) Async.delay(0.005);
			return !failed;
		}
		rebuilding = true;
		var ok = build(changed);
		while (again) {
			again = false;
			ok = build(project.sources());
		}
		rebuilding = false;
		flushWrites();
		if (!ok) return false;
		reload(task);
		return true;
	}

	// the host asked to save its state and end, then the new build started from it
	@:coroutine function reload(task:Node) {
		reloading = true;
		for (s in screens)
			s.reloading = true;
		var c = connection, p = process;
		retiring = p;
		var snap = '${project.out}/host.snapshot';
		// (a program that ended: started from the state its last reload saved)
		var saved = p == null && FileSystem.exists(snap);
		if (c != null && p != null) {
			try FileSystem.deleteFile(snap) catch (_:Dynamic) {}
			var answer:Dynamic = null;
			c.request("Runtime.reload", {snapshot: snap}, r -> answer = r);
			var t0 = haxe.Timer.stamp();
			while (answer == null && !c.closed && haxe.Timer.stamp() - t0 < 3) Async.delay(0.005);
			saved = answer != null && answer.error == null;
		}
		if (p != null) {
			var t0 = haxe.Timer.stamp();
			while (!p.exited() && haxe.Timer.stamp() - t0 < 2) Async.delay(0.005);
			if (!p.exited()) p.kill();
		}
		process = null;
		connection = null;
		launch(task, saved);
	}

	// the screens in view (the others suspended in the host, their last
	// frames kept here) and the one zoomed into, drawn every frame at scale
	// pixels a point (the canvas' zoom: its frames as sharp as the studio shows them)
	public function show(names:Array<String>, focused:Null<String>, scale = 1.0) {
		var key = names.join("\n") + "\t" + (focused ?? "") + "\t" + scale;
		if (key == shown) return;
		shown = key;
		showWanted = {names: names, focused: focused, scale: scale};
		var c = connection;
		if (c != null && order.length > 0) c.request("Host.show", {screens: names, focused: focused, scale: scale}, _ -> {});
	}

	// a devtools request about a screen (false: the host is not connected)
	public function request(s:Screen, method:String, params:Dynamic, done:Dynamic->Void):Bool {
		var c = connection;
		if (c == null) return false;
		var p:Dynamic = Reflect.copy(params) ?? {};
		if (hosting()) p.screen = s.info.name;
		c.request(method, p, done);
		return true;
	}

	// a screen's last frame's pixels (the image's own; a texture's read back
	// by the host: Host.snap), or null
	@:coroutine public function pixels(s:Screen):Null<Image> {
		var img = s.image.peek();
		if (img == null) return null;
		if (img.hasPixels) return img;
		var path = '${project.out}/snap.rgba', answer:Dynamic = null;
		if (!request(s, "Host.snap", {path: path}, r -> answer = r)) return null;
		var t0 = haxe.Timer.stamp();
		while (answer == null && haxe.Timer.stamp() - t0 < 5) Async.delay(0.005);
		if (answer == null || answer.error != null) return null;
		var b = try File.getBytes(path) catch (_:Dynamic) null;
		if (b == null || b.length < 16 || b.getString(0, 4) != "HLDF") return null;
		var w = b.getInt32(4), h = b.getInt32(8);
		return b.length < 16 + w * h * 4 ? null : new Image(w, h, b.sub(16, w * h * 4));
	}

	// the program typed, nothing written: its diagnostics
	@:coroutine public function check():{ok:Bool, diagnostics:Array<Diagnostic>, ms:Int} {
		if (service == null) return {ok: false, diagnostics: [], ms: 0};
		var w = project.words('${project.out}/check');
		return service.check(w, project.dir, project.sources());
	}

	@:coroutine public function stop() {
		stopping = true;
		var p = process;
		process = null;
		if (p != null && !p.exited()) p.kill();
		if (server != null) server.close();
		if (service != null) service.stop();
		for (f in files)
			f.close();
		files.clear();
	}
}

#end

// One screen: its story, its last frame (natively: the host's target it is, its buffer)
class Screen {
	public final info:ScreenInfo;
	public final slug:String;
	// its last frame (replaced in place: one texture) and the frames' count
	public final image:Signal<Null<Image>> = signal(null);
	public final frames = signal(0);
	public var version = 0;
	// (natively) the host's target its image shows (helder.story.NativeHost's buffer; 0: none)
	public var buffer = 0;
	public var reloading = false;
	// its program ended with an error (shown over its last frame until it starts again)
	public final crashedSignal = signal(false);
	public var crashed(get, set):Bool;

	inline function get_crashed()
		return crashedSignal.peek();

	inline function set_crashed(v:Bool) {
		crashedSignal(v);
		return v;
	}
	public var shownAt = -1.0;
	// the last patch's ms to its frame (Hot.patched; -1: waiting)
	public var patchedMs = -1.0;

	public function new(info:ScreenInfo) {
		this.info = info;
		slug = ~/[^A-Za-z0-9_-]+/g.replace(info.name, "-");
	}

	// its size in points (the program's window when the story has none)
	public function width():Int {
		var i = image.peek();
		return info.width > 0 ? info.width : i != null ? i.width : 480;
	}

	public function height():Int {
		var i = image.peek();
		return info.height > 0 ? info.height : i != null ? i.height : 560;
	}
}

#if !(hxmc.target == "wasm32-wasi")
// A program's devtools connection: requests by id, written in order
class Connection {
	public final socket:Socket;
	public var closed = false;

	final lock = new Lock();
	final pending = new Map<Int, Dynamic->Void>();
	var nextId = 1;

	public function new(socket)
		this.socket = socket;

	public function send(m:Dynamic) {
		var line = Json.stringify(m) + "\n", s = socket, l = lock;
		Async.launch(_ -> {
			l.acquire();
			try s.writeString(line) catch (_:Dynamic) {}
			l.release();
		});
	}

	public function request(method:String, params:Dynamic, done:Dynamic->Void) {
		var id = nextId++;
		pending.set(id, done);
		send({jsonrpc: "2.0", id: id, method: method, params: params});
	}

	public function answered(m:Dynamic) {
		var id = Std.int(m.id);
		var f = pending.get(id);
		if (f == null) return;
		pending.remove(id);
		f(m);
	}
}
#end
