package helder.cli;

import haxe.io.Path;
import helder.async.*;
import helder.cli.BuildCommand.Lines;
import helder.cli.Style.Tone;
import sys.FileSystem;

using StringTools;

// `helder run --headless [entry] [options]`: the program built for a
// headless run (-D helder.headless: helder.headless, its windows offscreen
// surfaces, its loop a virtual clock, its events a script's) into
// bin/headless/<name>, then run with its options in HELDER_HEADLESS (JSON:
// what Headless reads), its output here. Determinism: Linux's GL forced to
// Mesa's llvmpipe (LIBGL_ALWAYS_SOFTWARE), no display, a fixed locale and
// time zone (C.UTF-8, UTC), Math.random seeded (--seed). A video is the
// run's frames as PNGs (a directory beside it), encoded by ffmpeg after,
// the frames removed. (The options: Options.HEADLESS.)
//
// Why run's flag and not a command of its own: it is a run of the same
// program (the same entry, built the same way, its arguments after --),
// only where it draws and what drives it differ; Rune's tools are its
// programs' flags in the same way.
class HeadlessCommand {
	@:coroutine public static function run(o:Options, e:Entry):Int {
		var video = o.value("video");
		if (video != null && !has("ffmpeg")) {
			Term.err(Style.usage("helder run: --video: ffmpeg encodes it and is not on the PATH (PNG frames: --frames <n> -o <dir>)"));
			return 2;
		}
		Term.out(Style.header("run", ["headless", e.label()]));
		var exe = e.out("headless");
		// (--dev: a dev build, -D hxmc.dev: its live literals, which a script's literal step patches)
		var r = BuildCommand.build(e, exe, o.has("dev") ? Dev : Release, null, ["-D", "helder.headless"]);
		if (!r.ok) return 1;
		var frames = video == null ? null : Path.withoutExtension(video) + ".frames";
		var cfg = config(o, frames);
		var env = Process.environment();
		env.set("HELDER_HEADLESS", haxe.Json.stringify(cfg));
		// (the same pixels each run: Mesa's software rasterizer, no display, one locale and time zone)
		env.set("LIBGL_ALWAYS_SOFTWARE", "1");
		env.set("HXMC_GFX_SOFTWARE", "1");
		env.set("LC_ALL", "C.UTF-8");
		env.set("LANG", "C.UTF-8");
		env.set("TZ", "UTC");
		env.remove("DISPLAY");
		env.remove("WAYLAND_DISPLAY");
		var args = o.programArgs ?? [];
		var p = new Process(exe.contains("/") || exe.contains("\\") ? exe : './$exe', args, {env: env});
		p.closeStdin();
		Async.scope(task -> {
			task.async(_ -> Lines.forward(p.stdout, false));
			task.async(_ -> Lines.forward(p.stderr, true));
			null;
		});
		var code = p.wait();
		p.close();
		if (code != 0 || video == null) return code;
		var fps = o.value("fps") ?? "60";
		var codec = video.endsWith(".webm") ? ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "30"] : video.endsWith(".mov") ? ["-c:v", "prores_ks", "-profile:v", "4444"] : [
			"-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart"
		];
		Term.spin("encoding " + video);
		var f = new Process("ffmpeg", ["-y", "-loglevel", "error", "-framerate", fps, "-i", '$frames/frame_%04d.png'].concat(codec).concat([video]));
		f.closeStdin();
		var lines = [];
		Async.scope(task -> {
			task.async(_ -> Lines.collect(f.stdout, lines));
			task.async(_ -> Lines.collect(f.stderr, lines));
			null;
		});
		var fc = f.wait();
		f.close();
		Term.done();
		if (fc != 0) {
			Term.err(Style.status("failed", Fail, 'ffmpeg (exit $fc): ' + lines.join("\n")));
			return 1;
		}
		for (x in FileSystem.readDirectory(frames))
			FileSystem.deleteFile('$frames/$x');
		FileSystem.deleteDirectory(frames);
		Term.out(Style.status("wrote", Ok, Style.path(video)));
		return 0;
	}

	// HELDER_HEADLESS's options from the command line's: each --at for the
	// --snap and --tree before it without one (one before them all: theirs)
	public static function config(o:Options, ?videoFrames:String):Dynamic {
		var shots:Array<{kind:String, path:String, at:Null<String>}> = [], first:Null<String> = null;
		for (x in o.own)
			switch x.key {
				case "snap" | "tree":
					shots.push({kind: x.key, path: x.value, at: null});
				case "at":
					var any = false;
					for (s in shots)
						if (s.at == null) {
							s.at = x.value;
							any = true;
						}
					if (!any && first == null) first = x.value;
				case _:
			}
		var cfg:Dynamic = {};
		var snaps = [for (s in shots) if (s.kind == "snap") {path: s.path, at: s.at ?? first ?? "end"}];
		var trees = [for (s in shots) if (s.kind == "tree") {path: s.path, at: s.at ?? first ?? "end"}];
		if (snaps.length > 0) cfg.snaps = snaps;
		if (trees.length > 0) cfg.trees = trees;
		var sequences:Array<Dynamic> = [];
		var start = o.value("start") ?? "0";
		if (o.out != null) {
			var q:Dynamic = {dir: o.out, start: start};
			if (o.has("frames")) q.count = Std.parseInt(o.value("frames"));
			else q.duration = o.value("duration") ?? "auto";
			if (o.has("every")) q.every = Std.parseInt(o.value("every"));
			sequences.push(q);
		}
		if (videoFrames != null) sequences.push({dir: videoFrames, start: start, duration: o.has("frames") ? null : o.value("duration") ?? "auto", count: o.has("frames") ? Std.parseInt(o.value("frames")) : null});
		if (sequences.length > 0) cfg.sequences = sequences;
		for (k in ["script", "trace", "stats", "size", "theme", "keys-theme"])
			if (o.value(k) != null) Reflect.setField(cfg, k == "keys-theme" ? "keysTheme" : k, o.value(k));
		for (k in ["scale", "fps", "seed"])
			if (o.value(k) != null) Reflect.setField(cfg, k, Std.parseFloat(o.value(k)));
		if (o.has("keys")) cfg.keys = o.value("keys-at") ?? "bottom-left";
		if (o.has("pointer")) cfg.pointer = true;
		if (o.has("reduced-motion")) cfg.reducedMotion = true;
		return cfg;
	}

	// whether a program is on the PATH
	static function has(program:String):Bool {
		var sep = Sys.systemName() == "Windows" ? ";" : ":";
		for (d in (Sys.getEnv("PATH") ?? "").split(sep))
			if (d != "" && (FileSystem.exists('$d/$program') || FileSystem.exists('$d/$program.exe'))) return true;
		return false;
	}
}
