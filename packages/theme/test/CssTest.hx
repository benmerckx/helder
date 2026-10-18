import hxmc.theme.Css;

using StringTools;

// packages/theme's CSS (make theme-check), on Eval: each class of shadcn's
// sheet as Css writes it against the CSS Tailwind writes for it
// (tailwind.txt, from css-ref.mjs), rule by rule; then the sheet's
// stylesheet made, every class known.
class CssTest {
	static function main() {
		var dir = haxe.io.Path.directory(Sys.programPath() ?? "packages/theme/test/CssTest.hx");
		if (dir == "") dir = "packages/theme/test";
		var want = new Map<String, Array<String>>(), order = [];
		for (line in sys.io.File.getContent('$dir/tailwind.txt').split("\n")) {
			if (line == "") continue;
			var c = line.substr(0, line.indexOf("\t"));
			if (!want.exists(c)) {
				want[c] = [];
				order.push(c);
			}
			want[c].push(line);
		}
		var checks = 0, failed = 0;
		for (c in order) {
			checks++;
			var rs = Css.rules(c);
			var got = rs == null ? ["unknown"] : [
				for (r in rs)
					if (r.decls.length > 0) [c, r.at.join(" | "), r.sel, [for (d in r.decls) d[0] + ": " + d[1]].join("; ")].join("\t")
			];
			if (got.join("\n") != want[c].join("\n")) {
				failed++;
				Sys.println('FAILED $c\n  got  ${got.join("\n       ")}\n  want ${want[c].join("\n       ")}');
			}
		}
		// (the sheet: every class of it known)
		checks++;
		var errors = [];
		var css = Css.sheet('$dir/../src/hxmc/theme/shadcn.json', m -> errors.push(m));
		if (errors.length > 0) {
			failed++;
			Sys.println("FAILED the sheet: " + errors.join("; "));
		}
		Sys.println('CssTest: $checks checks (${css.length} bytes of CSS)' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}
}
