package helder.cli;

using StringTools;

// The CLI's look, after cargo's, bun's and vite's: a header line (`helder
// dev v0.1.0  linux-x86_64 · app/Main.hx`, the details dim), then status
// lines, a verb right-aligned in its column and coloured by what it says
// (green built, rebuilt, reloaded; cyan serving, watching; yellow warning;
// red failed, error, crashed; dim the rest), the compiler's errors with
// their file:line:column in front. Pure: the escapes only when `color` is
// set, which Term does from the terminal and the environment (NO_COLOR,
// FORCE_COLOR, TERM=dumb); without it the same text, plain (CI's logs, the
// cli lane's checks).
class Style {
	public static final VERSION:String = #if macro "" #else version() #end;

	// escapes written (Term: stdout or stderr is a terminal, or forced)
	public static var color = false;
	// ✓ ✗ » · and a braille spinner; else ASCII (a Windows console not in UTF-8)
	public static var unicode = true;

	// the verbs' column
	public static inline var WIDTH = 9;

	// whether a stream gets colours: FORCE_COLOR (but 0 or false) forces them,
	// NO_COLOR (not empty) or TERM=dumb leaves them out, else a terminal's
	public static function wants(env:String->Null<String>, tty:Bool):Bool {
		var force = env("FORCE_COLOR");
		if (force != null && force != "") return force != "0" && force != "false";
		var no = env("NO_COLOR");
		if (no != null && no != "") return false;
		if (env("TERM") == "dumb") return false;
		return tty;
	}

	// --- colours (SGR, each closed by its own reset: nesting keeps the outer one)

	static function sgr(open:String, close:String, s:String):String
		return color && s != "" ? '\x1b[${open}m$s\x1b[${close}m' : s;

	public static function bold(s:String):String
		return sgr("1", "22", s);

	public static function dim(s:String):String
		return sgr("2", "22", s);

	public static function underline(s:String):String
		return sgr("4", "24", s);

	public static function red(s:String):String
		return sgr("31", "39", s);

	public static function green(s:String):String
		return sgr("32", "39", s);

	public static function yellow(s:String):String
		return sgr("33", "39", s);

	public static function cyan(s:String):String
		return sgr("36", "39", s);

	public static function paint(tone:Tone, s:String):String
		return switch tone {
			case Ok: green(s);
			case Info: cyan(s);
			case Warn: yellow(s);
			case Fail: red(s);
			case Quiet: dim(s);
		}

	// the escapes taken out
	public static function strip(s:String):String
		return s.indexOf("\x1b") < 0 ? s : ~/\x1b\[[0-9;?]*[A-Za-z]/g.replace(s, "");

	// --- lines

	// `helder <command> v<version>  <details · ...>`
	public static function header(command:String, details:Array<String>):String {
		var d = [for (x in details) if (x != null && x != "") x];
		return bold('helder $command') + " " + dim('v$VERSION') + (d.length == 0 ? "" : "  " + dim(d.join(sep())));
	}

	// a status line: the verb right-aligned, bold in its tone, then the message
	public static function status(verb:String, tone:Tone, message:String):String
		return paint(tone, bold(verb.lpad(" ", WIDTH))) + (message == "" ? "" : " " + message);

	// what follows a status line, under its message
	public static function indent(s:String):String
		return "".lpad(" ", WIDTH + 1) + s;

	// a usage mistake, `helder <command>: <what>`: its `helder <command>:` red
	public static function usage(line:String):String {
		var i = line.indexOf(": ");
		return i < 0 ? red(line) : bold(red(line.substr(0, i + 1))) + line.substr(i + 1);
	}

	// a time: 812 ms, 1.2 s
	public static function time(ms:Int):String
		return bold(ms < 1000 ? '$ms ms' : Math.round(ms / 100) / 10 + " s");

	// " · " between details (", " in ASCII)
	public static function sep():String
		return unicode ? " · " : ", ";

	// a path or a detail, dim
	public static function path(s:String):String
		return dim(s);

	// a URL: cyan, underlined
	public static function url(s:String):String
		return cyan(underline(s));

	// the spinner's frames
	public static function frames():Array<String>
		return unicode ? ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"] : ["|", "/", "-", "\\"];

	// --- the help

	// a help screen (Options.helpText's): the usage lines and the commands'
	// and options' names bold, their descriptions dim, the headings bold
	public static function help(text:String):String {
		if (!color) return text;
		var out = [];
		var row = ~/^(  )(\S.*?)(   +|  (?=\S))(.*)$/;
		for (l in text.split("\n")) {
			if (l.startsWith("helder ")) {
				var gap = ~/^(.*?)(   +)(.*)$/;
				out.push(gap.match(l) ? bold(gap.matched(1)) + gap.matched(2) + dim(gap.matched(3)) : bold(l));
			}
			else if (l.endsWith(":") && !l.startsWith(" ")) out.push(bold(l));
			else if (row.match(l) && !l.startsWith("  entry:")) out.push(row.matched(1) + bold(row.matched(2)) + row.matched(3) + dim(row.matched(4)));
			else out.push(dim(l));
		}
		return out.join("\n");
	}

	static macro function version():haxe.macro.Expr {
		// (package.json, three directories above this file: src/helder/cli)
		var dir = haxe.io.Path.directory(sys.FileSystem.fullPath(haxe.macro.Context.resolvePath("helder/cli/Style.hx")));
		var f = haxe.io.Path.normalize('$dir/../../../package.json');
		var v = try (haxe.Json.parse(sys.io.File.getContent(f)).version : String) catch (_:Dynamic) null;
		if (v != null) haxe.macro.Context.registerModuleDependency("helder.cli.Style", f);
		return macro $v{v ?? "0.0.0"};
	}
}

enum Tone {
	Ok;
	Info;
	Warn;
	Fail;
	Quiet;
}
