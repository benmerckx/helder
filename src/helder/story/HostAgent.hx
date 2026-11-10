package helder.story;

#if hxmc.dev
import helder.devtools.Agent;
import helder.story.Host;

// The preview host's half of the devtools protocol (the studio's
// requests, each about a screen naming it: params.screen), the same in a
// web worker (helder.story.web.Preview) and in the native host process
// (helder.story.NativeHost):
//
//   Host.show {screens, focused, scale}  the screens in view, the one zoomed into (drawn every frame, at scale pixels a point)
//   Host.release {screen, buffer}        a frame's target the studio no longer shows (NativeHost: drawn into again)
//   Studio.screens {}                    {screens: [{name, width, height}]}
//   Ui.getTree {screen}                  that screen's tree ({uis: [{root}]}, as a program's)
//   Ui.nodesAt {screen, file, line, col}
//   Input.pointer {screen, type, x, y, button}  a press ("down"), a move, a release ("up") in its points: the studio's Play
//   Input.wheel {screen, x, y, dx, dy}
//   Input.key {screen, type, key, mods}  "down" or "up", an X11 KeySym (helder.os's)
//   Input.text {screen, text}
//   Story.controls {screen}               {controls: [{name, kind, value, options}]}, their values now
//   Story.set {screen, name, value}       a control set
//
// and anything else naming a screen is the program's agent's, run with
// that screen's context current (Hot.literals names none: every screen's
// next frame shows a patch, one program).
class HostAgent {
	// told Host.release (NativeHost's frames)
	public static var onRelease:Null<(s:HostScreen, buffer:Int) -> Void> = null;
	// told Host.snap: a screen's last frame written to a file (NativeHost)
	public static var onSnap:Null<(s:HostScreen, path:String) -> Dynamic> = null;

	public static function list(host:Host):Array<Dynamic>
		return [for (s in host.screens) {name: s.name, width: s.width, height: s.height}];

	// a message: true when it was the host's (answered here), else the agent's
	public static function receive(host:Host, m:Dynamic):Bool {
		if (m.method == null) return false;
		var p:Dynamic = m.params ?? {};
		var s = p.screen == null ? null : host.screen(Std.string(p.screen));
		var ui = s?.ui;
		inline function answer(r:Dynamic)
			if (m.id != null) Agent.respond(m.id, r);
		switch (m.method : String) {
			case "Host.show":
				var names:Array<String> = p.screens == null ? [] : [for (x in (p.screens : Array<Dynamic>)) Std.string(x)];
				host.show(names);
				host.focus(p.focused, p.scale == null ? null : (p.scale : Float));
				answer({});
			case "Host.release":
				var t = host.screens[Std.int(p.screen)];
				if (t != null && onRelease != null) onRelease(t, Std.int(p.buffer));
				answer({});
			case "Studio.screens":
				answer({screens: list(host)});
			case "Host.snap" | "Ui.getTree" | "Ui.nodesAt" | "Input.pointer" | "Input.wheel" | "Input.key" | "Input.text" | "Story.controls" | "Story.set"
				if (s == null || ui == null):
				if (m.id != null) Agent.respond(m.id, null, {code: -32602, message: 'no screen ${p.screen} shown'});
			case "Host.snap":
				answer(onSnap == null ? null : onSnap(s, p.path));
			case "Ui.getTree":
				answer(s.run(() -> helder.ui.DevTree.treeOf([ui])));
			case "Ui.nodesAt":
				answer(s.run(() -> helder.ui.DevTree.nodesAtOf([ui], p)));
			case "Input.pointer":
				var x:Float = p.x, y:Float = p.y, b = p.button == null ? 1 : Std.int(p.button);
				s.run(() -> switch (p.type : String) {
					case "down": ui.pointerDown(x, y, b);
					case "up": ui.pointerUp(x, y, b);
					case _: ui.pointerMove(x, y);
				});
				answer({});
			case "Input.wheel":
				s.run(() -> ui.wheel(p.x, p.y, p.dx, p.dy));
				answer({});
			case "Input.key":
				var key = Std.int(p.key), mods = p.mods == null ? 0 : Std.int(p.mods);
				s.run(() -> if (p.type == "up") ui.keyUp(key, mods) else ui.keyDown(key, mods));
				answer({});
			case "Input.text":
				s.run(() -> ui.textInput(Std.string(p.text)));
				answer({});
			case "Story.controls":
				var c = s.controls;
				answer({controls: c == null ? [] : [for (x in c.list) {name: x.name, kind: x.kind, value: c.signals.get(x.name)?.peek(), options: x.options}]});
			case "Story.set":
				var sig = s.controls?.signals.get(Std.string(p.name));
				if (sig != null) s.run(() -> {
					sig(p.value);
					helder.view.graph.Graph.flush();
				});
				answer({ok: sig != null});
			case _:
				if (s == null) return false;
				s.run(() -> Agent.dispatch(m));
		}
		return true;
	}
}
#end
