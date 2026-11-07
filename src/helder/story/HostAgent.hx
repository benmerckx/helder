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
			case "Host.snap" | "Ui.getTree" | "Ui.nodesAt" if (s == null || s.ui == null):
				if (m.id != null) Agent.respond(m.id, null, {code: -32602, message: 'no screen ${p.screen} shown'});
			case "Host.snap":
				answer(onSnap == null ? null : onSnap(s, p.path));
			case "Ui.getTree":
				answer(s.run(() -> helder.ui.DevTree.treeOf([s.ui])));
			case "Ui.nodesAt":
				answer(s.run(() -> helder.ui.DevTree.nodesAtOf([s.ui], p)));
			case _:
				if (s == null) return false;
				s.run(() -> Agent.dispatch(m));
		}
		return true;
	}
}
#end
