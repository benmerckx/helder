package helder.cli;

import helder.async.Async;

using StringTools;

// The CLI's terminal: whether stdout and stderr are terminals (isatty;
// Windows: a character device, its console switched to VT processing, which
// Windows 10 and later have), Style's colour and symbols decided from them
// and the environment, and its writes: out and err, each stream's escapes
// taken out when it gets none. One spinner at a time, on stdout and only on
// a terminal: the lines written meanwhile go above it.
class Term {
	public static var outColor(default, null) = false;
	public static var errColor(default, null) = false;
	// stdout is a terminal (a spinner)
	public static var tty(default, null) = false;
	static var spinning:Null<String> = null;
	static var spins = 0;
	static var frame = 0;

	public static function init() {
		var outTty = isTty(1), errTty = isTty(2);
		var env = (k:String) -> Sys.getEnv(k);
		outColor = Style.wants(env, outTty);
		errColor = Style.wants(env, errTty);
		tty = outTty && Sys.getEnv("TERM") != "dumb";
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		if (hxmc.unsafe.Mem.os() == 2) {
			// (a console without VT processing, before Windows 10: no escapes but forced ones, no spinner)
			var forced = Sys.getEnv("FORCE_COLOR") != null;
			if (!vt(-11)) {
				tty = false;
				if (!forced) outColor = false;
			}
			if (!vt(-12) && !forced) errColor = false;
			// (the console shows bytes in its code page: ✓ in UTF-8's, 65001)
			Style.unicode = TermK32.GetConsoleOutputCP() == 65001;
		} else Style.unicode = Sys.getEnv("TERM") != "linux";
		#end
		Style.color = outColor || errColor;
	}

	// a line to stdout
	public static function out(line:String) {
		clear();
		try Sys.println(outColor ? line : Style.strip(line)) catch (_:Dynamic) {};
		redraw();
	}

	// a line to stderr
	public static function err(line:String) {
		clear();
		try {
			Sys.stdout().flush();
			Sys.stderr().writeString((errColor ? line : Style.strip(line)) + "\n");
			Sys.stderr().flush();
		} catch (_:Dynamic) {};
		redraw();
	}

	// text, several lines, to stdout or stderr
	public static function write(text:String, toErr = false)
		for (l in text.split("\n")) toErr ? err(l) : out(l);

	// a spinner with its text (a terminal's; elsewhere nothing), until done()
	public static function spin(text:String) {
		if (!tty) return;
		spinning = text;
		frame = 0;
		var mine = ++spins;
		draw();
		Async.launch(_ -> {
			while (spins == mine && spinning != null) {
				Async.delay(0.08);
				if (spins == mine && spinning != null) {
					frame++;
					draw();
				}
			}
		});
	}

	public static function done() {
		if (spinning == null) return;
		clear();
		spinning = null;
		spins++;
	}

	static function draw() {
		var f = Style.frames();
		try {
			Sys.print("\r\x1b[2K" + (outColor ? "\x1b[36m" + f[frame % f.length] + "\x1b[39m \x1b[2m" + spinning + "\x1b[22m" : f[frame % f.length] + " " + spinning));
			Sys.stdout().flush();
		} catch (_:Dynamic) {}
	}

	static function clear()
		if (spinning != null) try {
			Sys.print("\r\x1b[2K");
			Sys.stdout().flush();
		} catch (_:Dynamic) {};

	static function redraw()
		if (spinning != null) draw();

	static function isTty(fd:Int):Bool {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		if (hxmc.unsafe.Mem.os() == 2) {
			var h = TermK32.GetStdHandle(fd == 1 ? -11 : -12);
			return TermK32.GetFileType(h) == 2; // FILE_TYPE_CHAR
		}
		return hxmc.unsafe.Posix.isatty(fd) != 0;
		#else
		return false;
		#end
	}

	#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
	// (Windows: ENABLE_VIRTUAL_TERMINAL_PROCESSING on the console's handle; false where it has none)
	@:hxmc.unsafe static function vt(which:Int):Bool {
		var h = TermK32.GetStdHandle(which);
		var mode = hxmc.unsafe.Mem.stack(8);
		if (TermK32.GetConsoleMode(h, mode) == 0) return false;
		var m = hxmc.unsafe.Mem.getI32(mode, 0);
		return (m & 4) != 0 || TermK32.SetConsoleMode(h, m | 4) != 0;
	}
	#end
}

#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
// (Windows: kernel32's console)
@:hxmc.c @:hxmc.fast @:hxmc.lib("kernel32") extern class TermK32 {
	static function GetStdHandle(which:Int):hxmc.unsafe.Ptr;
	static function GetFileType(h:hxmc.unsafe.Ptr):Int;
	static function GetConsoleMode(h:hxmc.unsafe.Ptr, mode:hxmc.unsafe.Ptr):Int;
	static function SetConsoleMode(h:hxmc.unsafe.Ptr, mode:Int):Int;
	static function GetConsoleOutputCP():Int;
}
#end
