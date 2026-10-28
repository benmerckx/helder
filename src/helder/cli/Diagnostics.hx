package helder.cli;

import helder.cli.Style.Tone;

using StringTools;

// The compiler's messages, readable: in colour, its errors' and warnings'
// first lines a status line with the file:line:column in front (bold), the
// code's gutter dim, the carets red (yellow for a warning), the message
// bold; Haxe's pretty format ("[ERROR] File.hx:3: characters 5-9", the
// code, the carets, "| message") and its classic one ("File.hx:3:
// characters 5-9 : message"). Without colour each line as it is.
class Diagnostics {
	var warning = false;

	public function new() {}

	public static function format(text:String):String {
		if (!Style.color) return text;
		var d = new Diagnostics();
		return [for (l in text.split("\n")) d.line(l)].join("\n");
	}

	static final pretty = ~/^\[(ERROR|WARNING|WARN|INFO)\]\s+(.*?):(\d+): (?:characters (\d+)-\d+|lines (\d+)-\d+)\s*(.*)$/;
	static final bare = ~/^\[(ERROR|WARNING|WARN|INFO)\]\s+(.*)$/;
	static final classic = ~/^(.+?\.hx):(\d+): (?:characters (\d+)-\d+|lines (\d+)-\d+) : (Warning : |Info : )?(.*)$/;
	static final code = ~/^( *\d+ \| )(.*)$/;
	static final carets = ~/^( +\| *)(\^+)$/;
	static final message = ~/^( +\| )(.*)$/;

	public function line(l:String):String {
		if (!Style.color) return l;
		if (pretty.match(l)) {
			var kind = pretty.matched(1);
			warning = kind != "ERROR";
			// (characters a-b: the column a; lines a-b: the line a, no column)
			var at = pretty.matched(4) != null ? '${pretty.matched(2)}:${pretty.matched(3)}:${pretty.matched(4)}' : '${pretty.matched(2)}:${pretty.matched(3)}';
			var rest = pretty.matched(6);
			return verb(kind) + " " + Style.bold(at) + (rest == "" ? "" : " " + rest);
		}
		if (bare.match(l)) {
			warning = bare.matched(1) != "ERROR";
			return verb(bare.matched(1)) + " " + bare.matched(2);
		}
		if (classic.match(l)) {
			var w = classic.matched(5);
			warning = w != null;
			var at = classic.matched(3) != null ? '${classic.matched(1)}:${classic.matched(2)}:${classic.matched(3)}' : '${classic.matched(1)}:${classic.matched(2)}';
			return verb(w == null ? "ERROR" : w.startsWith("Info") ? "INFO" : "WARNING") + " " + Style.bold(at) + " " + Style.bold(classic.matched(6));
		}
		if (code.match(l)) return Style.dim(code.matched(1)) + code.matched(2);
		if (carets.match(l)) return Style.dim(carets.matched(1)) + (warning ? Style.yellow(carets.matched(2)) : Style.red(carets.matched(2)));
		if (message.match(l)) return Style.dim(message.matched(1)) + Style.bold(message.matched(2));
		return l;
	}

	static function verb(kind:String):String
		return switch kind {
			case "ERROR": Style.status("error", Fail, "");
			case "INFO": Style.status("info", Info, "");
			case _: Style.status("warning", Warn, "");
		}
}
