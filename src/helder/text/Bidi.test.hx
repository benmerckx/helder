package helder.text;

import helder.test.Test;

// UAX #9 against Unicode's own cases: a sample of BidiCharacterTest.txt
// (tests/text/bidi-character-test.txt: explicit embeddings, overrides and
// isolates, bracket pairs, numbers, all the paragraph directions): each
// line's paragraph level, levels and visual order.
@:test.interp
function tests() {
	describe("Bidi (UAX #9)", () -> {
		test("BidiCharacterTest.txt's sample: levels and visual order", () -> {
			var lines = [for (l in sys.io.File.getContent("tests/text/bidi-character-test.txt").split("\n")) if (l != "" && l.charAt(0) != "#") l];
			assert(lines.length > 500, "the sample");
			var failed = [];
			for (line in lines) {
				var f = line.split(";");
				var cps = [for (h in f[0].split(" ")) Std.parseInt("0x" + h)];
				var pd = Std.parseInt(f[1]);
				var r = Bidi.levels(cps, pd == 2 ? -1 : pd);
				var want = f[3].split(" "), ok = r.base == Std.parseInt(f[2]);
				for (i in 0...cps.length)
					if (want[i] != "x" && Std.parseInt(want[i]) != r.levels[i]) ok = false;
				// (the order of the characters X9 keeps)
				var order = [for (i in Bidi.reorder(cps, r.levels, r.base, 0, cps.length)) if (want[i] != "x") i];
				if (order.join(" ") != StringTools.trim(f[4])) ok = false;
				if (!ok && failed.length < 5) failed.push('$line: ${r.base}; ${r.levels.join(" ")}; ${order.join(" ")}');
			}
			equals(failed, [], "the lines that differ");
		});
		test("an isolate keeps its neighbours' order: a right-to-left name in English", () -> {
			// (abc RLI שלום PDI def: the Hebrew reversed inside, the English around it in order)
			var cps = [0x61, 0x20, 0x2067, 0x5E9, 0x5DC, 0x20, 0x31, 0x2069, 0x20, 0x62];
			var r = Bidi.levels(cps, -1);
			equals(r.base, 0);
			equals(Bidi.reorder(cps, r.levels, r.base, 0, cps.length), [0, 1, 2, 6, 5, 4, 3, 7, 8, 9]);
		});
	});
}
