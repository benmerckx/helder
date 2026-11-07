package helder.story.web;

#if (hxmc.target == "wasm32-wasi")
import haxe.Json;
import helder.gfx.Device;
import helder.os.Surface;
import helder.story.Host;
import helder.story.Story;
import hxmc.unsafe.*;

// The studio's preview host in the browser: the project's program, a dev
// build for the web (wasm32-wasi), run in a Web Worker (worker.mjs here)
// with every story mounted in one helder.story.Host. Each screen drawn goes
// to an OffscreenCanvas of the worker's, at the screen's size, and leaves
// as an ImageBitmap posted to the page (the studio's), which draws it with
// its own renderer. The page speaks the devtools protocol to it as the
// worker's messages (src/helder/devtools/README.md, JSON-RPC lines), each
// request about a screen naming it (params.screen):
//
//   Host.show {screens, focused}     the screens in view, the one zoomed into (drawn every frame)
//   Studio.screens {}                {screens: [{name, width, height}]}
//   Ui.getTree {screen}              that screen's tree ({uis: [{root}]}, as a program's)
//   Ui.nodesAt {screen, file, line, col}
//   Hot.literals {set}               live literals patched (every screen: one program)
//
// and anything else the program's agent answers (helder.devtools.Agent),
// with that screen's context current. It tells Host.ready {screens} once
// running, Host.frame {screen, version, width, height} with each frame's
// bitmap beside it (worker.mjs: the message's bitmap), and Hot.patched
// after a patch's frame.
//
//   // the studio's generated main for the web (apps/studio: Previews)
//   helder.story.web.Preview.run(helder.story.Stories.of("Todo_story"));
class Preview {
	static var host:Null<Host> = null;

	public static function run(stories:Array<Story>) {
		var rt = new WorkerHost();
		var h = new Host(stories, rt);
		host = h;
		#if hxmc.dev
		helder.devtools.Agent.serve(send);
		helder.devtools.Agent.notify("Host.ready", {screens: list()});
		#end
		PreviewWeb.start(Callback.addr(turn));
	}

	static function list():Array<Dynamic>
		return [for (s in host.screens) {name: s.name, width: s.width, height: s.height}];

	static function send(line:String)
		Arena.scoped(a -> PreviewWeb.send(a.cstring(line)));

	// (the worker's loop, each animation frame) the page's messages, then the screens shown drawn
	@:hxmc.callback static function turn():Int {
		var h;
		while ((h = PreviewWeb.next()) != 0)
			receive(take(h));
		host.frame(haxe.Timer.stamp());
		#if hxmc.dev
		helder.dev.Hot.framed();
		#end
		return 1;
	}

	static function receive(line:String) {
		var m:Dynamic = try Json.parse(line) catch (_:Dynamic) null;
		if (m == null || m.method == null) return;
		#if hxmc.dev
		var p:Dynamic = m.params ?? {};
		var s = p.screen == null ? null : host.screen(p.screen);
		inline function answer(r:Dynamic)
			if (m.id != null) helder.devtools.Agent.respond(m.id, r);
		switch (m.method : String) {
			case "Host.show":
				var names:Array<String> = p.screens == null ? [] : [for (x in (p.screens : Array<Dynamic>)) Std.string(x)];
				host.show(names);
				host.focus(p.focused);
				answer({});
			case "Studio.screens":
				answer({screens: list()});
			case "Ui.getTree" | "Ui.nodesAt" if (s == null || s.ui == null):
				if (m.id != null) helder.devtools.Agent.respond(m.id, null, {code: -32602, message: 'no screen ${p.screen} shown'});
			case "Ui.getTree":
				answer(s.run(() -> helder.ui.DevTree.treeOf([s.ui])));
			case "Ui.nodesAt":
				answer(s.run(() -> helder.ui.DevTree.nodesAtOf([s.ui], p)));
			case _:
				if (s != null) s.run(() -> helder.devtools.Agent.dispatch(m)) else helder.devtools.Agent.dispatch(m);
		}
		#end
	}

	static function take(h:Int):String {
		var n = PreviewWeb.text_length(h);
		var b = haxe.io.Bytes.alloc(n);
		Arena.scoped(a -> {
			var p = a.alloc(n + 1, 1);
			PreviewWeb.text_take(h, p);
			BytesPtr.copyIn(b, 0, p, n);
		});
		return b.toString();
	}
}

// The worker's target: one OffscreenCanvas (its GPU context), sized for
// each screen's frame, the frame transferred out as an ImageBitmap
class WorkerHost implements HostRuntime {
	public var surface(default, null):Surface;

	final canvas:Int;

	public function new() {
		canvas = PreviewWeb.canvas();
		surface = new Surface(Canvas, Ptr.nil(), Ptr.ofI64(canvas), 1, 1);
	}

	public function size(width:Int, height:Int) {
		if (surface.width == width && surface.height == height) return;
		PreviewWeb.resize(canvas, width, height);
		@:privateAccess surface.resized(width, height);
	}

	public function capture(s:HostScreen, device:Device) {}

	// (a frame that changed nothing, the focused screen's of every turn, is not posted: the page has those pixels)
	public function present(s:HostScreen, changed:Bool)
		if (changed) PreviewWeb.present(canvas, s.host.screens.indexOf(s), s.version, s.width, s.height);
}

// The worker's side (src/helder/story/web/imports.mjs: the module "helder_preview")
@:hxmc.c @:hxmc.lib("helder_preview") extern class PreviewWeb {
	// a new OffscreenCanvas (a handle), resized (pixels)
	static function canvas():Int;
	static function resize(canvas:Int, width:Int, height:Int):Void;
	// the canvas's frame (just drawn) to the page as an ImageBitmap: screen
	// (its index), its frame's count, its size in points
	static function present(canvas:Int, screen:Int, version:Int, width:Int, height:Int):Void;
	// a protocol line to the page
	static function send(line:CString):Void;
	// the page's next line (a string handle; 0: none), its UTF-8 length, its bytes into p (the handle freed)
	static function next():Int;
	static function text_length(h:Int):Int;
	static function text_take(h:Int, p:Ptr):Void;
	// the worker's loop: frame (a @:hxmc.callback ():Int) each animation frame until it returns 0
	static function start(frame:Ptr):Void;
}
#end
