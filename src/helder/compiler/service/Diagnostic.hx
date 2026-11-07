package helder.compiler.service;

using StringTools;

// A compiler message as data: the studio's and the agents' (build.check)
// form of what helder's compiler prints. Haxe's pretty format ("[ERROR]
// File.hx:3: characters 5-9", its code, "| message"), its classic one
// ("File.hx:3: characters 5-9 : message"), and a frontend's
// (helder.typescript: "file.ts:3: characters 5-9 : TS2322: message").
// Columns are Haxe's: characters from 1 on the line, end exclusive.
typedef Diagnostic = {
	file:Null<String>,
	line:Int,
	column:Int,
	endColumn:Int,
	severity:String,
	message:String,
}

class Diagnostics {
	static final pretty = ~/^\[(ERROR|WARNING|WARN|INFO)\]\s+(.*?):(\d+): (?:characters (\d+)-(\d+)|lines (\d+)-(\d+))\s*(.*)$/;
	static final bare = ~/^\[(ERROR|WARNING|WARN|INFO)\]\s+(.*)$/;
	static final classic = ~/^(.+?):(\d+): (?:characters (\d+)-(\d+)|lines (\d+)-(\d+)) : (Warning : |Info : )?(.*)$/;
	static final lined = ~/^(.+?\.(?:hx|ts|tsx|mts|cts)):(\d+): (.*)$/;
	static final message = ~/^ +\| (.*)$/;

	// a build's messages (the compiler's text) as diagnostics, in order
	public static function parse(text:String):Array<Diagnostic> {
		var out:Array<Diagnostic> = [];
		var current:Null<Diagnostic> = null;
		for (l in text.split("\n")) {
			if (pretty.match(l)) {
				var chars = pretty.matched(4) != null;
				current = {
					file: pretty.matched(2),
					line: Std.parseInt(pretty.matched(3)),
					column: chars ? Std.parseInt(pretty.matched(4)) : 1,
					endColumn: chars ? Std.parseInt(pretty.matched(5)) : 1,
					severity: severity(pretty.matched(1)),
					message: pretty.matched(8).trim()
				};
				out.push(current);
			} else if (bare.match(l)) {
				current = {file: null, line: 0, column: 0, endColumn: 0, severity: severity(bare.matched(1)), message: bare.matched(2).trim()};
				out.push(current);
			} else if (classic.match(l)) {
				var chars = classic.matched(3) != null, w = classic.matched(7);
				current = null;
				out.push({
					file: classic.matched(1),
					line: Std.parseInt(classic.matched(2)),
					column: chars ? Std.parseInt(classic.matched(3)) : 1,
					endColumn: chars ? Std.parseInt(classic.matched(4)) : 1,
					severity: w == null ? "error" : w.startsWith("Info") ? "info" : "warning",
					message: classic.matched(8)
				});
			} else if (message.match(l) && current != null) {
				// (the pretty format's message, under its code: | message)
				var m = message.matched(1).trim();
				if (m != "" && !~/^\^+$/.match(m)) current.message = current.message == "" ? m : current.message + "\n" + m;
			} else if (lined.match(l)) {
				current = null;
				out.push({file: lined.matched(1), line: Std.parseInt(lined.matched(2)), column: 1, endColumn: 1, severity: "error", message: lined.matched(3)});
			}
		}
		return out;
	}

	static function severity(kind:String):String
		return switch kind {
			case "ERROR": "error";
			case "INFO": "info";
			case _: "warning";
		}
}
