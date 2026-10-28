package helder.cli;

import helder.cli.Style.Tone;
import helder.test.Test;

// the CLI's look (Style, Diagnostics): when colours are on (NO_COLOR,
// FORCE_COLOR, TERM=dumb, a terminal), the status lines' column, and that
// the coloured text is the plain one with escapes, nothing else
function tests() {
	final saved = {color: Style.color, unicode: Style.unicode};
	afterEach(() -> {
		Style.color = saved.color;
		Style.unicode = saved.unicode;
	});
	final env = (vars:Map<String, String>) -> (k:String) -> vars.get(k);

	describe("colours on or off", () -> {
		test("a terminal's, a pipe's", () -> {
			equals(Style.wants(env([]), true), true);
			equals(Style.wants(env([]), false), false);
		});
		test("NO_COLOR (not empty) leaves them out", () -> {
			equals(Style.wants(env(["NO_COLOR" => "1"]), true), false);
			equals(Style.wants(env(["NO_COLOR" => ""]), true), true);
		});
		test("FORCE_COLOR forces them, but 0 and false", () -> {
			equals(Style.wants(env(["FORCE_COLOR" => "1"]), false), true);
			equals(Style.wants(env(["FORCE_COLOR" => "3", "NO_COLOR" => "1"]), false), true);
			equals(Style.wants(env(["FORCE_COLOR" => "0"]), true), false);
			equals(Style.wants(env(["FORCE_COLOR" => "false"]), true), false);
		});
		test("TERM=dumb", () -> equals(Style.wants(env(["TERM" => "dumb"]), true), false));
	});

	describe("lines", () -> {
		test("plain: no escapes, the verbs right-aligned", () -> {
			Style.color = false;
			equals(Style.status("built", Ok, "in " + Style.time(812)), "    built in 812 ms");
			equals(Style.status("reloaded", Ok, "in " + Style.time(1250)), " reloaded in 1.3 s");
			equals(Style.status("error", Fail, ""), "    error");
			equals(Style.usage("helder build: one entry"), "helder build: one entry");
		});
		test("coloured: the plain text, with escapes", () -> {
			Style.color = true;
			var s = Style.status("failed", Fail, "in " + Style.time(30) + Style.dim("; waiting for a change"));
			assert(s.indexOf("\x1b[31m") >= 0, "red");
			equals(Style.strip(s), "   failed in 30 ms; waiting for a change");
			equals(Style.strip(Style.usage("helder build: one entry")), "helder build: one entry");
		});
		test("the header", () -> {
			Style.color = false;
			Style.unicode = true;
			equals(Style.header("dev", ["web", "Counter"]), 'helder dev v${Style.VERSION}  web · Counter');
			Style.unicode = false;
			equals(Style.header("build", ["linux-x86_64", null, "Main"]), 'helder build v${Style.VERSION}  linux-x86_64, Main');
			assert(~/^\d+\.\d+\.\d+/.match(Style.VERSION), Style.VERSION);
		});
		test("the help: only escapes added", () -> {
			var text = Options.helpText();
			Style.color = false;
			equals(Style.help(text), text);
			Style.color = true;
			var h = Style.help(text);
			assert(h != text);
			equals(Style.strip(h), text);
			assert(h.indexOf("\x1b[1mdev\x1b[22m") >= 0, "a command's name bold");
		});
	});

	describe("the compiler's messages", () -> {
		final pretty = [
			"[ERROR] src/Bad.hx:3: characters 3-19",
			"",
			" 3 |   var x:Int = \"s\";",
			"   |   ^^^^^^^^^^^^^^^^",
			"   | String should be Int",
		].join("\n");
		test("plain: as the compiler wrote them", () -> {
			Style.color = false;
			equals(Diagnostics.format(pretty), pretty);
		});
		test("coloured: file:line:column in front", () -> {
			Style.color = true;
			var lines = Style.strip(Diagnostics.format(pretty)).split("\n");
			equals(lines[0], "    error src/Bad.hx:3:3");
			equals(lines.slice(1), pretty.split("\n").slice(1));
			assert(Diagnostics.format(pretty).indexOf("\x1b[31m^^^") >= 0, "the carets red");
		});
		test("a warning's carets yellow; lines a-b: no column", () -> {
			Style.color = true;
			var w = Diagnostics.format("[WARNING] A.hx:7: lines 7-9\n   |   ^^^");
			equals(Style.strip(w).split("\n")[0], "  warning A.hx:7");
			assert(w.indexOf("\x1b[33m^^^") >= 0, "yellow");
		});
		test("the classic format", () -> {
			Style.color = true;
			equals(Style.strip(Diagnostics.format("app/Tally.hx:12: characters 5-9 : Unexpected }")), "    error app/Tally.hx:12:5 Unexpected }");
			equals(Style.strip(Diagnostics.format("A.hx:1: characters 1-2 : Warning : unused")), "  warning A.hx:1:1 unused");
			equals(Diagnostics.format("something else"), "something else");
		});
	});
}
