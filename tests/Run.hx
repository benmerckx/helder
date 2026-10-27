import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

using StringTools;

// The checks, from the repository's root, with @hxmc/cli's compiler (`haxe`,
// node_modules/.bin on the PATH):
//
//   bun run test                   the headless lanes (no GPU, display or browser)
//   bun run test <lane> ...        those lanes (-k: the next one after a failure)
//   bun run test help              the lanes
//
// Outputs go to bin/<lane>. GFX_TARGET and AUDIO_TARGET (the host's by
// default) cross-compile the native programs (windows-x86_64: run under
// Wine). BLESS=1 rewrites the golden files of the lanes that have them. The
// browser lanes need Playwright with Chromium (bun add --no-save playwright;
// bunx playwright install chromium); the gfx, ui-draw and 3d lanes Mesa and
// Xvfb on Linux.
class Run {
	static final TOOL = Sys.getEnv("HAXE") ?? (Sys.systemName() == "Windows" ? "haxe.cmd" : "haxe");
	static final NODE = Sys.getEnv("NODE") ?? "node";
	static final HOST = hostTarget();
	static final GFX_TARGET = Sys.getEnv("GFX_TARGET") ?? HOST;
	static final AUDIO_TARGET = Sys.getEnv("AUDIO_TARGET") ?? HOST;
	static final BLESS = Sys.getEnv("BLESS") != null && Sys.getEnv("BLESS") != "";

	static final HEADLESS = ["view", "text", "ui", "gfx-shader", "scoped", "examples"];

	static final LANES:Array<{name:String, about:String, run:Void->Void}> = [
		{name: "headless", about: "the lanes that need no GPU, display or browser: " + HEADLESS.join(", "), run: () -> for (l in HEADLESS) lane(l)},
		{name: "view", about: "helder.view on Eval, natively and as JavaScript: signals, markup, control flow, the programs the macro rejects", run: view},
		{name: "text", about: "helder.text on Eval: the rasterizer, DejaVu Sans, line layout, a sample through the atlas (tests/text/sample.png)", run: text},
		{name: "ui", about: "helder.ui on Eval: layout, events and focus, markup, the guide's and the widgets' examples (bin/ui/widgets.json)", run: ui},
		{name: "gfx-shader", about: "helder.gfx's shader macro on Eval: shaders on the CPU, the emitted GLSL, WGSL, MSL and HLSL, the programs it rejects", run: gfxShader},
		{name: "scoped", about: "helder.scoped on Eval, natively and as JavaScript, and the programs its checker rejects", run: scoped},
		{name: "examples", about: "every example built, not run: for wasm32-wasi, and those on a canvas or playing a sound natively too", run: examples},
		{name: "3d", about: "helder.scene and helder.physics: unit tests on Eval, natively and as wasm32-wasi, input actions, the renderer's frames against golden images (Mesa)", run: scene},
		{name: "3d-web", about: "helder.scene's frames on WebGPU and WebGL2 in headless Chromium, then as WasmGC", run: sceneWeb},
		{name: "gfx", about: "helder.gfx: the examples headless and in a window against golden images (tests/gfx/check.sh; Linux: Mesa, Xvfb)", run: gfx},
		{name: "gfx-web", about: "helder.gfx on WebGPU and WebGL2 (wasm32-wasi) in headless Chromium, then as WasmGC", run: gfxWeb},
		{name: "audio", about: "helder.os's audio through each back end without speakers (tests/os/audio.sh)", run: audio},
		{name: "audio-web", about: "helder.os's audio on WebAudio in headless Chromium", run: audioWeb},
		{name: "touch", about: "helder.os's touch gesture (TouchDrag), natively", run: touch},
		{name: "web", about: "helder.web: the static renderer on Eval and natively, then the DOM renderer, the demo page, islands and wasm in headless Chromium", run: web},
		{name: "ui-draw", about: "helder.ui's GPU renderer and its programs against golden images (Linux: Mesa, Xvfb, AT-SPI, GTK 3)", run: uiDraw},
		{name: "ui-web", about: "the todo example, the native form and text editors as wasm32-wasi in headless Chromium, then as WasmGC", run: uiWeb},
		{name: "dev", about: "the dev loop: helder.dev.Hot and view's signals across a reload, then `haxe --dev` in Chromium and natively", run: dev},
	];

	static function main() {
		var args = Sys.args();
		var keepGoing = args.remove("-k");
		if (args.length == 0) args = ["headless"];
		if (args.contains("help")) {
			Sys.println("bun run test [-k] <lane> ...\n");
			for (l in LANES) Sys.println("  " + l.name.rpad(" ", 15) + " " + l.about);
			return;
		}
		var failed = [];
		for (a in args) {
			try {
				lane(a);
			} catch (e:Failed) {
				Sys.println('\n$a: FAILED: ${e.message}');
				failed.push(a);
				if (!keepGoing) break;
			}
		}
		if (failed.length > 0) {
			Sys.println("failed: " + failed.join(", "));
			Sys.exit(1);
		}
	}

	static function lane(name:String) {
		var l = Lambda.find(LANES, l -> l.name == name);
		if (l == null) throw new Failed('no lane $name (bun run test help)');
		Sys.println('--- $name');
		l.run();
	}

	// --- the lanes

	static final UI_VIEW = ["-D", "helder.view.renderer.ui=helder.ui.view.NodeRenderer"];
	static final DOM = ["-D", "helder.view.renderer.dom=helder.web.DomRenderer"];
	static final STATIC = ["-D", "helder.view.renderer.html=helder.web.StaticRenderer"];

	static function view() {
		var cp = cps(["src", "tests/view"]).concat(["-D", "helder.view.renderer=TestRenderer", "-D", "helder.view.renderer.other=OtherRenderer"]);
		interp(cp, "ViewTest", [TOOL]);
		exe("bin/view/ViewTest", cp.concat(["-main", "ViewTest"]));
		run(exePath("bin/view/ViewTest", HOST), []);
		js("bin/view/ViewTest.js", cp.concat(["-main", "ViewTest"]));
		run(NODE, ["bin/view/ViewTest.js"]);
	}

	static function text() {
		mkdirs("bin");
		interp(cps(["src", "tests/text", "tests/gfx"]), "TextTest", BLESS ? ["--bless"] : []);
	}

	static function ui() {
		var cp = cps(["src", "tests/ui"]);
		interp(cp, "UiTest");
		interp(cp.concat(UI_VIEW), "MarkupTest");
		interp(cp.concat(UI_VIEW), "GuideTest");
		interp(cp.concat(UI_VIEW).concat(cps(["examples/widgets"])), "WidgetExamplesTest");
		mkdirs("bin/ui");
		interp(cps(["tests/ui"]), "WidgetDocs", ["src/helder/ui/widgets/Widgets.hx", "examples/widgets", "bin/ui/widgets.json"]);
	}

	static function gfxShader() {
		interp(cps(["src", "tests/gfx"]).concat(cps(GFX_EXAMPLES)), "ShaderTest", [TOOL].concat(BLESS ? ["--bless"] : []));
	}

	static function scoped() {
		var cp = cps(["src", "tests/scoped"]).concat(["--macro", "helder.scoped.Check.enable()"]);
		interp(cp, "ScopedTest");
		exe("bin/scoped/ScopedTest", cp.concat(["-main", "ScopedTest"]));
		run(exePath("bin/scoped/ScopedTest", HOST), []);
		js("bin/scoped/ScopedTest.js", cp.concat(["-main", "ScopedTest"]));
		run(NODE, ["bin/scoped/ScopedTest.js"]);
		interp(cps(["tests/scoped"]), "RejectTest", [TOOL]);
	}

	// (the examples' directories of gfx's, which its tests use)
	static final GFX_EXAMPLES = [for (e in ["triangle", "cube", "instances", "mips", "formats"]) 'examples/$e'];

	static function gfxCp()
		return cps(["src", "tests/gfx"].concat(GFX_EXAMPLES));

	static function gfxPrograms() {
		for (m in ["GfxTest", "Triangle", "Cube", "Instances", "Targets", "Mips", "Formats"])
			native('bin/gfx/$GFX_TARGET/$m', gfxCp().concat(["-main", m]), GFX_TARGET);
	}

	static function gfx() {
		gfxPrograms();
		run("sh", ["tests/gfx/check.sh", 'bin/gfx/$GFX_TARGET']);
	}

	static function gfxWeb() {
		wasm("bin/gfx/WebTest.wasm", gfxCp().concat(["-main", "WebTest"]));
		run(NODE, ["tests/gfx/web.mjs", "bin/gfx/WebTest.wasm", "bin/gfx"]);
		wasm("bin/gfx/gc/WebTest.wasm", gfxCp().concat(["-main", "WebTest", "-D", "hxmc.wasm-gc"]));
		run(NODE, ["tests/gfx/web.mjs", "bin/gfx/gc/WebTest.wasm", "bin/gfx/gc"]);
	}

	static function osCp()
		return cps(["src", "examples/tone", "tests/os"]);

	static function audio() {
		for (m in ["AudioTest", "Tone"])
			native('bin/audio/$AUDIO_TARGET/$m', osCp().concat(["-main", m]), AUDIO_TARGET);
		run("sh", ["tests/os/audio.sh", 'bin/audio/$AUDIO_TARGET']);
	}

	static function audioWeb() {
		wasm("bin/audio/AudioTest.wasm", osCp().concat(["-main", "AudioTest"]));
		run(NODE, ["tests/os/web.mjs", "bin/audio/AudioTest.wasm"]);
	}

	static function touch() {
		native("bin/os/TouchDragTest", osCp().concat(["-main", "TouchDragTest"]), HOST);
		run(exePath("bin/os/TouchDragTest", HOST), []);
	}

	static final SCENE_EXAMPLES = [for (e in ["gltf-viewer", "orbits", "showroom", "falling", "walker", "chains"]) 'examples/$e'];
	// the glTF samples packed for the packed scenes (the asset step)
	static final PACKED = ["examples/gltf-viewer/sample.glb", "tests/3d/skinned.glb", "examples/showroom/normals.glb", "examples/showroom/morph.glb"];

	static function sceneCp()
		return gfxCp().concat(cps(SCENE_EXAMPLES.concat(["tests/3d", "tests/physics"])));

	static function pack() {
		mkdirs("bin/3d");
		for (glb in PACKED)
			interp(sceneCp(), "helder.scene.gltf.Pack", [glb, "bin/3d/" + Path.withoutExtension(Path.withoutDirectory(glb)) + ".hxm3d"]);
	}

	static function scene() {
		var cp = sceneCp();
		var tests = ["SceneTest", "GltfTest", "PhysicsTest"];
		for (t in tests)
			interp(cp, t);
		for (t in tests) {
			exe('bin/3d/$t', cp.concat(["-main", t]));
			run(exePath('bin/3d/$t', HOST), []);
		}
		for (t in tests) {
			wasm('bin/3d/$t.wasm', cp.concat(["-main", t]));
			wasi('bin/3d/$t.wasm');
		}
		pack();
		var t = GFX_TARGET;
		for (m in ["RenderTest", "GltfViewer", "Orbits", "Showroom", "Falling", "Walker", "Chains", "InputTest"])
			native('bin/3d/$t/$m', cp.concat(["-main", m]), t);
		wasm("bin/3d/InputTest.wasm", cp.concat(["-main", "InputTest"]));
		run(exePath('bin/3d/$t/InputTest', t), []);
		wasi("bin/3d/InputTest.wasm");
		// (helder.scene.view: view's markup on the scene graph; natively: its meshes import gfx, which node lacks)
		native('bin/3d/$t/SceneUiTest', cps(["src", "tests/3d-ui"]).concat(["-D", "helder.view.renderer=helder.scene.view.SceneRenderer", "-main", "SceneUiTest"]), t);
		run(exePath('bin/3d/$t/SceneUiTest', t), []);
		run("sh", ["tests/3d/check.sh", 'bin/3d/$t']);
		// (Model.of's files beside the executable, -D helder.scene.embed=0)
		var files = exePath("bin/3d/files/RenderTest", t);
		native("bin/3d/files/RenderTest", cp.concat(["-main", "RenderTest", "-D", "helder.scene.embed=0", "-D", 'helder.scene.out=$files']), t);
		if (!FileSystem.exists("bin/3d/files/assets/sample.glb") || !FileSystem.exists('$files.assets.json'))
			throw new Failed("RenderTest with -D helder.scene.embed=0: no assets beside it");
		shell('cd bin/3d && LIBGL_ALWAYS_SOFTWARE=1 HXMC_GFX_SOFTWARE=1 env -u DISPLAY files/${Path.withoutDirectory(files)} skin ../../tests/3d/skin.png files/skin.png');
		// (Model.of: a name the file does not have is a compile error)
		var r = build(cp.concat(cps(["tests/3d/reject"])).concat(["-main", "ModelTypo", "--custom-target", "hxmc=bin/3d/ModelTypo"]), "bin/3d/ModelTypo.log");
		if (r.code == 0 || !r.log.contains("has no field bal"))
			throw new Failed("ModelTypo: expected the error \"has no field bal\":\n" + r.log);
	}

	static function sceneWeb() {
		pack();
		// (Model.of's files beside the module, -D helder.scene.embed=0: fetched by browser.mjs before main)
		rmrf("bin/3d/assets");
		wasm("bin/3d/SceneWebTest.wasm", sceneCp().concat(["-main", "SceneWebTest", "-D", "helder.scene.embed=0", "-D", "helder.scene.out=bin/3d/SceneWebTest.wasm"]));
		run(NODE, ["tests/3d/web.mjs", "bin/3d/SceneWebTest.wasm", "bin/3d"]);
		// (and as WasmGC, the files built in)
		wasm("bin/3d/gc/SceneWebTest.wasm", sceneCp().concat(["-main", "SceneWebTest", "-D", "hxmc.wasm-gc"]));
		run(NODE, ["tests/3d/web.mjs", "bin/3d/gc/SceneWebTest.wasm", "bin/3d/gc"]);
	}

	static function web() {
		var cp = cps(["src", "tests/web", "examples/web-demo"]);
		interp(cp.concat(STATIC), "StaticTest");
		exe("bin/web/StaticTest", cp.concat(STATIC).concat(["-main", "StaticTest"]));
		run(exePath("bin/web/StaticTest", HOST), []);
		rmrf("bin/web/demo");
		interp(cp.concat(STATIC), "DemoPage", ["bin/web/demo"]);
		js("bin/web/domtest.js", cp.concat(DOM).concat(STATIC).concat(["-main", "DomTest", "-debug"]));
		js("bin/web/demo/islands.js", cp.concat(DOM).concat(["-main", "DemoBundle", "-dce", "full", "-debug"]));
		js("bin/web/demo/counter.js", cp.concat(DOM).concat(["-main", "Counter", "-dce", "full", "-D", "js-es=6", "-D", "analyzer-optimize"]));
		wasm("bin/web/demo/lab.wasm", cps(["src", "examples/web-demo"]).concat(["-main", "Lab"]));
		wasm("bin/web/demo/cube.wasm", gfxCp().concat(["-main", "Cube"]));
		for (f in FileSystem.readDirectory("bin/web/demo"))
			if (f.endsWith(".log")) FileSystem.deleteFile('bin/web/demo/$f');
		run(NODE, ["tests/web/web.mjs", "bin/web"]);
	}

	static function uiCp()
		return cps(["src", "tests/gfx", "tests/ui", "examples/counter", "examples/gallery", "examples/todo", "examples/native-form"]).concat(UI_VIEW);

	static function uiPrograms() {
		var t = GFX_TARGET;
		var programs = ["UiDrawTest", "TodoTest", "GalleryTest", "StressTest", "ClipboardTest", "NativeTest", "EmojiTest", "BoxTest", "WindowTest"];
		if (t.startsWith("linux-")) programs = programs.concat(["TextInputTest", "LinuxAccessTest", "AtspiProbe"]);
		if (t.startsWith("windows-")) programs.push("WinAccessTest");
		for (m in programs)
			native('bin/ui/$t/$m', uiCp().concat(["-main", m]), t);
	}

	static function uiDraw() {
		uiPrograms();
		var b = 'bin/ui/$GFX_TARGET';
		var bless = BLESS ? " --bless" : "";
		var gpu = "LIBGL_ALWAYS_SOFTWARE=1 env -u DISPLAY";
		var xvfb = 'xvfb-run -a -s "-screen 0 640x480x24"';
		shell('$gpu $b/UiDrawTest tests/ui/draw.png $b/draw.png$bless');
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb $b/UiDrawTest tests/ui/draw.png $b/window.png --window');
		shell('$gpu $b/TodoTest tests/ui/todo.png $b/todo.png$bless');
		for (v in [["gallery", ""], ["gallery-dark", " --dark"], ["gallery-rtl", " --rtl"], ["gallery-unstyled", " --unstyled"]])
			shell('$gpu $b/GalleryTest tests/ui/${v[0]}.png $b/${v[0]}.png${v[1]}$bless');
		shell('$gpu $b/StressTest');
		shell('$gpu $b/EmojiTest tests/ui/emoji.png $b/emoji.png');
		shell('$gpu $b/BoxTest tests/ui/boxes.png $b/boxes.png');
		shell('$xvfb $b/ClipboardTest');
		shell('$xvfb $b/TextInputTest');
		shell('$xvfb $b/WindowTest');
		// (AT-SPI: the window's tree read by another process through libatspi, in a D-Bus session)
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb dbus-run-session -- sh -c \'$b/LinuxAccessTest & p=$$!; $b/AtspiProbe; s=$$?; wait $$p && exit $$s\'');
		shell('$xvfb $b/NativeTest $b/native.png');
	}

	static function uiWeb() {
		for (gc in [false, true]) {
			var b = gc ? "bin/ui/gc" : "bin/ui";
			var extra = gc ? ["-D", "hxmc.wasm-gc"] : [];
			wasm('$b/WebTodo.wasm', uiCp().concat(["-main", "WebTodo"]).concat(extra));
			run(NODE, ["tests/ui/web.mjs", '$b/WebTodo.wasm', b]);
			wasm('$b/NativeForm.wasm', uiCp().concat(["-main", "NativeForm"]).concat(extra));
			run(NODE, ["tests/ui/native-web.mjs", '$b/NativeForm.wasm', b]);
			wasm('$b/WebField.wasm', uiCp().concat(["-main", "WebField"]).concat(extra));
			run(NODE, ["tests/ui/web-field.mjs", '$b/WebField.wasm']);
		}
	}

	// (each program run twice, the second from the first's snapshot)
	static function dev() {
		var os = cps(["src", "tests/os"]).concat(["-D", "hxmc.dev"]);
		var views = cps(["src", "tests/view"]).concat(["-D", "helder.view.renderer=TestRenderer", "-D", "hxmc.dev"]);
		var snapshot = (file:String) -> ["HXMC_DEV_SNAPSHOT" => file];
		exe("bin/dev/HotTest", os.concat(["-main", "HotTest"]));
		exe("bin/dev/HotTestChanged", os.concat(["-main", "HotTest", "-D", "hot_changed"]));
		run(exePath("bin/dev/HotTest", HOST), ["save", "bin/dev/hot.snapshot"]);
		run(exePath("bin/dev/HotTest", HOST), ["restore", "-"], snapshot("bin/dev/hot.snapshot"));
		expect(exePath("bin/dev/HotTestChanged", HOST), ["restore", "-"], snapshot("bin/dev/hot.snapshot"), "changed reset: its type changed");
		interp(os, "HotTest", ["save", "bin/dev/hot-eval.snapshot"]);
		interp(os, "HotTest", ["restore", "-"], snapshot("bin/dev/hot-eval.snapshot"));
		exe("bin/dev/RefreshTest", views.concat(["-main", "RefreshTest"]));
		run(exePath("bin/dev/RefreshTest", HOST), ["save", "bin/dev/refresh.snapshot"]);
		run(exePath("bin/dev/RefreshTest", HOST), ["restore", "-"], snapshot("bin/dev/refresh.snapshot"));
		exe("bin/dev/RefreshTestChanged", views.concat(["-main", "RefreshTest", "-D", "refresh_changed"]));
		expect(exePath("bin/dev/RefreshTestChanged", HOST), ["restore", "-"], snapshot("bin/dev/refresh.snapshot"), "main.tuned reset: its initial value changed");
		interp(views, "RefreshTest", ["save", "bin/dev/refresh-eval.snapshot"]);
		interp(views, "RefreshTest", ["restore", "-"], snapshot("bin/dev/refresh-eval.snapshot"));
		// (the dev loop's server, @hxmc/cli's dev.mjs, run by node with the compiler)
		var compiler = "node_modules/.bin/haxe";
		run(NODE, ["tests/os/dev/dev-web.mjs", compiler, "bin/dev/web"]);
		run(NODE, ["tests/os/dev/dev-web.mjs", compiler, "bin/dev/web-gc", "--wasm-gc"]);
		if (HOST.startsWith("linux-")) shell('xvfb-run -a -s "-screen 0 640x480x24" $NODE tests/os/dev/dev-native.mjs $compiler bin/dev/native');
		else run(NODE, ["tests/os/dev/dev-native.mjs", compiler, "bin/dev/native"]);
		run(NODE, ["tests/os/dev/server-verify.mjs", compiler]);
		run(NODE, ["tests/os/dev/dev-verify.mjs", compiler, "Counter", "web"]);
	}

	// --- the examples

	static final HEADER = ~/^\/\/ *(title|summary|tags|demo): *(.*)$/;

	// each example directory's programs with a header naming them,
	//
	//   // title: Cube
	//   // summary: A textured cube casting a soft shadow, its shaders in Haxe
	//   // tags: gfx, shaders, 3d
	//   // demo: canvas 512x384
	//
	// (demo: canvas WxH, a program drawing on a canvas; sound, a program
	// started by a click; island, a JavaScript island of helder.web; module,
	// a wasm module JavaScript calls), each built for wasm32-wasi but the
	// islands, and those on a canvas or playing a sound for this machine
	// too, in parallel, into bin/examples (each one's log beside it). (Not
	// widgets/: each widget's snippet, which the ui lane renders.)
	static function examples() {
		var builds:Array<{id:String, target:String, out:String, args:Array<String>}> = [];
		var dirs = FileSystem.readDirectory("examples").filter(d -> d != "widgets");
		dirs.sort(Reflect.compare);
		for (dir in dirs) {
			var path = 'examples/$dir';
			var files = [for (f in FileSystem.readDirectory(path)) if (f.endsWith(".hx")) f];
			files.sort(Reflect.compare);
			// (markup on ui: its renderer)
			var ui = Lambda.exists(files, f -> File.getContent('$path/$f').contains("import helder.ui."));
			for (f in files) {
				var head = new Map<String, String>();
				for (line in File.getContent('$path/$f').split("\n")) {
					if (!line.startsWith("//")) break;
					if (HEADER.match(line.trim())) head.set(HEADER.matched(1), HEADER.matched(2).trim());
				}
				if (!head.exists("title")) continue;
				var main = f.substr(0, f.length - 3);
				var demo = head.get("demo") ?? "";
				var id = dir + (files.length > 1 && main.toLowerCase() != dir.replace("-", "") ? "-" + main.toLowerCase() : "");
				var args = cps(["src", path]).concat(ui ? UI_VIEW : []).concat(["-main", main]);
				if (demo != "island") {
					var out = 'bin/examples/wasm32-wasi/$id.wasm';
					// (legacy exception handling: every browser with WebGPU has it, those with WebGL2 since 2021)
					builds.push({id: id, target: "wasm32-wasi", out: out, args: args.concat(targetArgs("wasm32-wasi")).concat(["-D", "hxmc.wasm-eh=legacy"])});
				}
				if (demo.startsWith("canvas") || demo == "sound") {
					var out = exePath('bin/examples/$HOST/$id', HOST);
					builds.push({id: id, target: HOST, out: out, args: args.concat(targetArgs(HOST))});
				}
			}
		}
		var t0 = Sys.time();
		var failed = [];
		parallel(builds, b -> {
			mkdirs(Path.directory(b.out));
			var r = build(b.args.concat(["--custom-target", 'hxmc=${b.out}']), b.out + ".log");
			var ok = r.code == 0 && FileSystem.exists(b.out);
			Sys.println(b.id.rpad(" ", 22) + " " + b.target.rpad(" ", 15) + " " + (ok ? "ok  " : "FAIL") + " " + Std.string(Math.round(r.seconds * 10) / 10).lpad(" ", 6) + "s");
			if (!ok) {
				failed.push(b.id + " (" + b.target + ")");
				Sys.println(r.log.length > 1500 ? r.log.substr(r.log.length - 1500) : r.log);
			}
		});
		Sys.println('examples: ${builds.length - failed.length}/${builds.length} built, ${Math.round(Sys.time() - t0)}s');
		if (failed.length > 0) throw new Failed(failed.join(", "));
	}

	// --- building and running

	static function cps(dirs:Array<String>):Array<String>
		return [for (d in dirs) for (a in ["-cp", d]) a];

	// the compiler on Eval: `--run main args`
	static function interp(cp:Array<String>, main:String, ?args:Array<String>, ?env:Map<String, String>)
		run(TOOL, cp.concat(["--run", main]).concat(args ?? []), env);

	static function js(out:String, args:Array<String>) {
		mkdirs(Path.directory(out));
		run(TOOL, args.concat(["-js", out]));
	}

	// a program for this machine, for wasm32-wasi, for a target (Linux: the
	// dynamic glibc mode, which loads the GPU's and the sound's drivers)
	static function exe(out:String, args:Array<String>)
		hxmc(exePath(out, HOST), args);

	static function wasm(out:String, args:Array<String>)
		hxmc(out, args.concat(targetArgs("wasm32-wasi")));

	static function native(out:String, args:Array<String>, target:String)
		hxmc(exePath(out, target), args.concat(targetArgs(target)));

	static function targetArgs(target:String):Array<String>
		return ["-D", 'hxmc.target=$target'].concat(target.startsWith("linux-") ? ["-D", "hxmc.libc=glibc"] : []);

	static function exePath(out:String, target:String):String
		return target.startsWith("windows-") ? '$out.exe' : out;

	// a build by hxmc, its log beside the output (printed when it fails)
	static function hxmc(out:String, args:Array<String>) {
		mkdirs(Path.directory(out));
		var r = build(args.concat(["--custom-target", 'hxmc=$out']), '$out.log');
		if (r.code != 0) {
			Sys.println(r.log);
			throw new Failed('$out: the build failed');
		}
		Sys.println('$out (${Math.round(r.seconds * 10) / 10}s)');
	}

	static function build(args:Array<String>, log:String):{code:Int, log:String, seconds:Float} {
		var t0 = Sys.time();
		var p = new Process(TOOL, args);
		// (the compiler's messages are on stderr: read first, its pipe would fill)
		var err = p.stderr.readAll().toString();
		var out = p.stdout.readAll().toString();
		var code = p.exitCode();
		p.close();
		mkdirs(Path.directory(log));
		File.saveContent(log, out + err);
		return {code: code, log: out + err, seconds: Sys.time() - t0};
	}

	static function wasi(module:String)
		run(NODE, ["--stack-size=65500", "tests/wasi.mjs", module]);

	static function run(cmd:String, args:Array<String>, ?env:Map<String, String>) {
		var saved = new Map<String, Null<String>>();
		if (env != null) for (k => v in env) {
			saved.set(k, Sys.getEnv(k));
			Sys.putEnv(k, v);
		}
		var code = Sys.command(cmd, args);
		for (k => v in saved) Sys.putEnv(k, v ?? "");
		if (code != 0) throw new Failed('${[cmd].concat(args).join(" ")}: exit code $code');
	}

	static function shell(cmd:String)
		run("sh", ["-c", cmd]);

	// a program's output must contain `text`
	static function expect(cmd:String, args:Array<String>, env:Map<String, String>, text:String) {
		for (k => v in env) Sys.putEnv(k, v);
		var p = new Process(cmd, args);
		var out = p.stdout.readAll().toString() + p.stderr.readAll().toString();
		var code = p.exitCode();
		p.close();
		for (k in env.keys()) Sys.putEnv(k, "");
		Sys.print(out);
		if (code != 0 || !out.contains(text)) throw new Failed('$cmd: expected "$text" (exit code $code)');
	}

	// each item in a thread, half the cores' worth at once (each build is parallel itself)
	static function parallel<T>(items:Array<T>, f:T->Void) {
		var jobs = Std.parseInt(Sys.getEnv("JOBS") ?? "") ?? Std.int(Math.max(1, cpus() / 2));
		var queue = items.copy();
		var mutex = new sys.thread.Mutex();
		var done = new sys.thread.Lock();
		var workers = Std.int(Math.min(jobs, queue.length));
		for (_ in 0...workers)
			sys.thread.Thread.create(() -> {
				while (true) {
					mutex.acquire();
					var item = queue.shift();
					mutex.release();
					if (item == null) break;
					f(item);
				}
				done.release();
			});
		for (_ in 0...workers) done.wait();
	}

	static function cpus():Int {
		var n = Std.parseInt(Sys.getEnv("NUMBER_OF_PROCESSORS") ?? "");
		if (n != null) return n;
		try {
			var p = new Process("getconf", ["_NPROCESSORS_ONLN"]);
			n = Std.parseInt(p.stdout.readAll().toString().trim());
			p.close();
		} catch (_) {}
		return n ?? 4;
	}

	// hxmc's name of this machine
	static function hostTarget():String {
		var os = switch Sys.systemName() {
			case "Windows": "windows";
			case "Mac": "macos";
			case _: "linux";
		}
		var arch = if (os == "windows") Sys.getEnv("PROCESSOR_ARCHITECTURE") ?? "AMD64" else {
			var p = new Process("uname", ["-m"]);
			var m = p.stdout.readAll().toString().trim();
			p.close();
			m;
		}
		return os + "-" + (["aarch64", "arm64", "ARM64"].contains(arch) ? "arm64" : "x86_64");
	}

	static function mkdirs(dir:String)
		if (dir != "" && !FileSystem.exists(dir)) FileSystem.createDirectory(dir);

	static function rmrf(path:String) {
		if (!FileSystem.exists(path)) return;
		if (FileSystem.isDirectory(path)) {
			for (f in FileSystem.readDirectory(path)) rmrf('$path/$f');
			FileSystem.deleteDirectory(path);
		} else FileSystem.deleteFile(path);
	}
}

class Failed extends haxe.Exception {}
