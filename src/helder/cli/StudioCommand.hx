package helder.cli;

import haxe.io.Path;
import helder.async.*;
import helder.cli.BuildCommand.Lines;
import sys.FileSystem;

using StringTools;

// `helder studio [project] [--mcp-port <n>]`: helder studio (apps/studio,
// beside helder's src/) built for this machine when a source of it changed,
// then run on the project (the directory given, else this one) in a window
// of its own. The project's program is never in the studio's process: the
// studio builds it (a dev build) and runs each screen in a process of its
// own (apps/studio/README.md).
class StudioCommand {
	@:coroutine public static function run(o:Options):Int {
		var dir = o.entry ?? ".";
		if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) {
			Term.err(Style.usage('helder studio: $dir is not a directory (helder studio [project])'));
			return 2;
		}
		var app = studioDir();
		if (app == null) {
			Term.err(Style.usage("helder studio: apps/studio is not beside helder's src/ (this helder has no studio)"));
			return 1;
		}
		var e = try Entry.resolve(app) catch (err:Dynamic) {
			Term.err(Style.status("error", Fail, Std.string(err)));
			return 1;
		}
		Term.out(Style.header("studio", [e.target, FileSystem.fullPath(dir)]));
		var exe = e.out(e.target);
		var r = BuildCommand.build(e, exe, Release);
		if (!r.ok) return 1;
		var args = [FileSystem.fullPath(dir)];
		var port = o.value("mcp-port");
		if (port != null) args = args.concat(["--mcp-port", port]);
		var p = new Process(FileSystem.fullPath(exe), args.concat(o.programArgs ?? []));
		p.closeStdin();
		Async.scope(task -> {
			task.async(_ -> Lines.forward(p.stdout, false));
			task.async(_ -> Lines.forward(p.stderr, true));
			null;
		});
		var code = p.wait();
		p.close();
		return code;
	}

	// apps/studio of this helder: beside its src/ (a checkout, or the npm package's files)
	static function studioDir():Null<String> {
		var e = try Entry.resolve(".") catch (_:Dynamic) null;
		var roots = [Path.directory(Sys.programPath()) + "/../.."];
		if (e != null) roots.unshift(e.helder + "/..");
		for (r in roots) {
			var d = Path.normalize(r + "/apps/studio");
			if (FileSystem.exists('$d/src/Main.hx')) return d;
		}
		return null;
	}
}
