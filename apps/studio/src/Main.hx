import helder.ui.actions.Actions;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import studio.Studio;

// helder studio (apps/studio/README.md): `helder studio [project]`, or
// `studio [project] [--events <file>] [--mcp-port <n>] [--hold-while <file>]`
class Main implements Markup {
	public static var window(default, null):Null<UiWindow> = null;

	static function main() {
		studio.Studio.processStart = haxe.Timer.stamp();
		var args = Sys.args(), dir:Null<String> = null, events:Null<String> = null, port:Null<Int> = null, holdWhile:Null<String> = null;
		var width = 1180, height = 740, exportWeb:Null<String> = null;
		var i = 0;
		while (i < args.length) {
			var a = args[i++];
			switch a {
				case "--events": events = args[i++];
				case "--mcp-port": port = Std.parseInt(args[i++]);
				case "--hold-while": holdWhile = args[i++];
				case "--width": width = Std.parseInt(args[i++]) ?? width;
				case "--height": height = Std.parseInt(args[i++]) ?? height;
				case "--export-web": exportWeb = args[i++];
				case _ if (!StringTools.startsWith(a, "--")): dir = a;
				case _: Sys.println('studio: $a: not an option (studio [project] [--events <file>] [--mcp-port <n>] [--hold-while <file>])');
			}
		}
		#if !(hxmc.target == "wasm32-wasi")
		// (helder's src/, which this studio was built from: a project without helder in its dependencies builds with it)
		if ((Sys.getEnv("HELDER_SRC") ?? "") == "") Sys.putEnv("HELDER_SRC", studio.BuildInfo.helderSrc());
		var env = Sys.getEnv("HELDER_STUDIO_MCP_PORT");
		if (port == null && env != null && env != "") port = Std.parseInt(env);
		#end
		#if !(hxmc.target == "wasm32-wasi")
		// (--export-web <dir>: the project for the studio in the browser, its preview built for the web; no window)
		if (exportWeb != null) Sys.exit(studio.WebExport.run(dir ?? ".", exportWeb));
		#end
		fonts();
		actions("studio", studio.Shell.StudioAction);
		helder.ui.actions.Keymap.global.bind("secondary-z", studio.Shell.StudioAction.Undo)
			.bind("secondary-shift-z", studio.Shell.StudioAction.Redo)
			.bind("secondary-y", studio.Shell.StudioAction.Redo)
			.bind("escape", studio.Shell.StudioAction.Overview)
			.bind("secondary-k", studio.Shell.StudioAction.Jump)
			.bind("shift-1", studio.Shell.StudioAction.FitAll)
			.bind("shift-2", studio.Shell.StudioAction.FitSelection);
		var s = new Studio(dir, {events: events, mcpPort: port, holdWhile: holdWhile});
		UiWindow.run(<Surface title={s.project == null ? "helder studio" : s.project.name + " · helder studio"} width={width} height={height} titlebar="inset"
			theme={studio.Theme.sheet} background={studio.Theme.c("bg")} dark={true} ref={w -> {
				window = w;
				w.onFrame = () -> s.drawn();
				s.open();
			}} onClose={() -> {
				helder.async.Async.launch(_ -> s.stop());
				window.close();
			}}>
			{studio.Shell.view(s)}
		</Surface>);
	}

	// the studio's fonts: Hanken Grotesk for the interface, Geist Mono for values (apps/studio/fonts)
	public static function fonts() {
		var f = helder.text.SystemFonts.get();
		for (b in [
			helder.asset.Asset.embed("fonts/HankenGrotesk-Regular.ttf"),
			helder.asset.Asset.embed("fonts/HankenGrotesk-Medium.ttf"),
			helder.asset.Asset.embed("fonts/GeistMono-Regular.ttf")
		])
			try f.add(b) catch (_:Dynamic) {}
	}
}
