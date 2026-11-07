package studio;

import haxe.Json;
import haxe.io.Path;
import helder.async.*;
import helder.compiler.service.Diagnostic;
import helder.compiler.service.Service;
import helder.image.Image;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import studio.Project;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The project's program, never in the studio's process: one process a
// screen (the screens' host, Project.words: a dev build run headless), each
// started with helder dev's machinery (HXMC_DEV: a connection to the
// studio's socket speaking the devtools protocol, src/helder/devtools/
// README.md; HXMC_DEV_SNAPSHOT: its state across a rebuild), drawing
// offscreen at its story's size (helder.headless's serve mode: each frame
// drawn written to a file, told as Headless.frame) which the canvas shows.
// The compiler stays warm (helder.compiler.service: Service). A save of a
// file whose live literals only changed is patched in every screen
// (Hot.literals, nothing built); any other a build, then each process asked
// to reload (Runtime.reload: its snapshot written) and started again from it.
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

	public function new(project:Project) {
		this.project = project;
		screens = [for (s in project.screens) new Screen(s)];
	}

	public function screen(name:String):Null<Screen>
		return Lambda.find(screens, s -> s.info.name == name);

	// whether every screen shows a frame
	public function allShown():Bool
		return !Lambda.exists(screens, s -> s.version == 0 && !s.crashed) || failed;

	// whether work is in flight (a build, a reload, screens not shown yet)
	public function busy():Bool
		return building || rebuilding || again || Lambda.exists(screens, s -> s.reloading) || (!failed && !allShown());

	// the compiler, the socket, the first build, the screens started
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
			task.async(_ -> connection(s));
		});
		if (build(null)) for (s in screens) launch(task, s, false);
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
	// it starts is built again from cold (a new compiler) and its screens
	// started again: the warm compiler has built a wrong program after some
	// edits (hxmc's server: a padding added to a <text> of a module a story
	// file uses, the story's view crossing its attributes: "todos is not a
	// Direction"), and a cold build of the same files is right.
	@:coroutine function coldRebuild(task:Node) {
		if (rebuilding || building) return;
		rebuilding = true;
		onLog('studio: the incremental build\'s program ended at its start: building again from cold');
		try service.stop() catch (_:Dynamic) {}
		var ok = startCompiler(task) && build(null);
		coldExe = exe;
		rebuilding = false;
		if (!ok) return;
		for (s in screens) {
			s.reloading = true;
			task.async(_ -> reload(task, s));
		}
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
		onLog('studio: built ${project.name}\'s screens in $ms ms');
		setStatus("running");
		return true;
	}

	// a screen's process started (withSnapshot: from the state its last one saved)
	@:coroutine function launch(task:Node, s:Screen, withSnapshot:Bool) {
		var env = Process.environment();
		env.set("HXMC_DEV", '127.0.0.1:${server.port}');
		env.set("HXMC_DEV_PROTOCOL", "1");
		// (the studio gone, its screens with it)
		env.set("HXMC_DEV_EXIT_WITH_SERVER", "1");
		var snap = '${project.out}/${s.slug}.snapshot';
		if (withSnapshot && FileSystem.exists(snap)) env.set("HXMC_DEV_SNAPSHOT", snap) else {
			env.remove("HXMC_DEV_SNAPSHOT");
			try FileSystem.deleteFile(snap) catch (_:Dynamic) {}
		}
		if (s.info.story) env.set("HELDER_STUDIO_SCREEN", s.info.name);
		env.set("HELDER_HEADLESS", Json.stringify({serve: {frames: s.framesFile(project.out)}}));
		// (offscreen: Mesa's llvmpipe on Linux, no display; one locale and time zone)
		env.set("LIBGL_ALWAYS_SOFTWARE", "1");
		env.set("HXMC_GFX_SOFTWARE", "1");
		env.set("LP_NUM_THREADS", "2");
		env.set("LC_ALL", "C.UTF-8");
		env.set("LANG", "C.UTF-8");
		env.remove("DISPLAY");
		env.remove("WAYLAND_DISPLAY");
		var p = try new Process(exe, [], {env: env, cwd: project.dir}) catch (e:Dynamic) {
			onLog('studio: ${s.info.name} did not start: $e');
			null;
		}
		if (p == null) return;
		p.closeStdin();
		s.process = p;
		s.crashed = false;
		s.startedAt = haxe.Timer.stamp();
		var label = s.info.label;
		task.async(_ -> forward(p.stdout, label));
		task.async(_ -> forward(p.stderr, label));
		task.async(_ -> {
			var code = p.wait();
			if (s.process == p && s.retiring != p) {
				s.process = null;
				s.connection = null;
				// (it ended on its own: a crash, its last frame kept)
				if (!stopping) {
					s.reloading = false;
					s.crashed = code != 0;
					onLog('studio: ${s.info.name} ended (exit code $code)');
					if (onFrame != null) onFrame(s);
					if (code != 0 && incremental && coldExe != exe && haxe.Timer.stamp() - s.startedAt < 5) {
						coldExe = exe;
						task.async(_ -> coldRebuild(task));
					}
				}
			}
			p.close();
		});
	}

	@:coroutine function forward(src:Stream.Source, label:String) {
		var r = new Reader(src), line;
		try while ((line = r.readLine()) != null) onLog('[$label] $line') catch (_:haxe.Exception) {}
	}

	// a program's connection: its hello answered, the screen it is asked, then its messages
	@:coroutine function connection(socket:Socket) {
		var c = new Connection(socket);
		var r = new Reader(socket), line;
		try while ((line = r.readLine()) != null) {
			var m:Dynamic = try Json.parse(line) catch (_:Dynamic) null;
			if (m == null || m.jsonrpc == null) continue;
			if (m.method == "Runtime.hello" && m.id != null) {
				c.send({jsonrpc: "2.0", id: m.id, result: {protocol: 1, server: "helder studio"}});
				c.request("Studio.screens", {}, res -> {
					var name:String = res.result?.screen;
					var s = name == null ? screens[0] : screen(name) ?? screens[0];
					s.connection = c;
					c.screen = s;
					// (a frame told before this answer: shown now)
					var early = c.early;
					c.early = null;
					if (early != null) frame(s, early);
				});
				continue;
			}
			if (m.method == null) {
				c.answered(m);
				continue;
			}
			switch (m.method : String) {
				case "Headless.frame":
					if (c.screen != null) frame(c.screen, m.params) else c.early = m.params;
				case "Hot.patched" if (c.screen != null):
					c.screen.patchedMs = m.params.ms;
				case _:
			}
		} catch (_:haxe.Exception) {}
		if (c.screen != null && c.screen.connection == c) c.screen.connection = null;
		c.closed = true;
		socket.close();
	}

	// a frame told: its pixels read into the screen's image
	function frame(s:Screen, p:Dynamic) {
		var b = try File.getBytes(p.path) catch (_:Dynamic) null;
		if (b == null || b.length < 16 || b.getString(0, 4) != "HLDF") return;
		var w = b.getInt32(4), h = b.getInt32(8);
		if (b.length < 16 + w * h * 4) return;
		var img = new Image(w, h, b.sub(16, w * h * 4));
		var first = s.version == 0;
		if (s.image.peek() == null) s.image(img) else s.image.peek().replace(img);
		s.version++;
		s.frames(s.version);
		s.reloading = false;
		if (first) s.shownAt = haxe.Timer.stamp();
		if (onFrame != null) onFrame(s);
	}

	// ---- edits

	// a file's new text, saved: its live literals patched in every screen
	// when only they changed (nothing built), else a build and a reload.
	// What happened: "patched", "unchanged", "built", "failed", or "queued"
	// (a build in progress: this one after it)
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

	// the patches the screens took (a save after them changes nothing)
	public function took(list:Array<{id:String, source:String}>)
		if (service != null && service.sources != null) service.sources.took(list);

	// live literals sent to every screen (a patch shows in its next frame); false: none connected
	public function patch(list:Array<{id:String, source:String}>):Bool {
		var any = false;
		for (s in screens) {
			var c = s.connection;
			if (c == null) continue;
			any = true;
			s.patchedMs = -1;
			c.request("Hot.literals", {set: list}, r -> {
				var stale:Array<String> = r.result?.stale ?? [];
				if (stale.length > 0) onLog('studio: ${stale.length} literal(s) read once in ${s.info.name}: ${stale.join(", ")}');
			});
		}
		return any;
	}

	// a build, then each screen reloaded from its snapshot
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
		for (s in screens) {
			s.reloading = true;
			task.async(_ -> reload(task, s));
		}
		return true;
	}

	@:coroutine function reload(task:Node, s:Screen) {
		var c = s.connection, p = s.process;
		s.retiring = p;
		var snap = '${project.out}/${s.slug}.snapshot';
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
		s.process = null;
		s.connection = null;
		launch(task, s, saved);
	}

	// a devtools request to a screen's program (false: none connected)
	public function request(s:Screen, method:String, params:Dynamic, done:Dynamic->Void):Bool {
		var c = s.connection;
		if (c == null) return false;
		c.request(method, params, done);
		return true;
	}

	// the program typed, nothing written: its diagnostics
	@:coroutine public function check():{ok:Bool, diagnostics:Array<Diagnostic>, ms:Int} {
		if (service == null) return {ok: false, diagnostics: [], ms: 0};
		var w = project.words('${project.out}/check');
		return service.check(w, project.dir, project.sources());
	}

	@:coroutine public function stop() {
		stopping = true;
		for (s in screens) {
			var p = s.process;
			s.process = null;
			if (p != null && !p.exited()) p.kill();
		}
		if (server != null) server.close();
		if (service != null) service.stop();
	}
}

// One screen: its story, its process and connection, its last frame
class Screen {
	public final info:ScreenInfo;
	public final slug:String;
	// its last frame (replaced in place: one texture) and the frames' count
	public final image:Signal<Null<Image>> = signal(null);
	public final frames = signal(0);
	public var version = 0;
	public var process:Null<Process> = null;
	public var connection:Null<Connection> = null;
	public var reloading = false;
	// the process asked to end (a reload's), not a crash when it does
	public var retiring:Null<Process> = null;
	// its program ended with an error (shown over its last frame until it starts again)
	public final crashedSignal = signal(false);
	public var crashed(get, set):Bool;
	public var startedAt = 0.0;

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

	public function framesFile(out:String):String
		return '$out/frames/$slug.rgba';

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

// A program's devtools connection: requests by id, written in order
class Connection {
	public final socket:Socket;
	public var screen:Null<Screen> = null;
	public var closed = false;
	// a frame told before the screen it is was known
	public var early:Null<Dynamic> = null;

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
