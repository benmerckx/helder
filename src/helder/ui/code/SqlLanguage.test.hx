package helder.ui.code;

import helder.test.Test;

function tests() {
	describe("SqlLanguage", () -> {
		function classes(line:String, state = 0):{tokens:Array<String>, state:Int} {
			var out = [], l = new SqlLanguage();
			var next = l.tokenize(line, state, out);
			return {tokens: [for (k in 0...Std.int(out.length / 3)) line.substring(out[k * 3], out[k * 3 + 1]) + ":" + out[k * 3 + 2]], state: next};
		}
		test("keywords, names, strings and numbers", () -> {
			equals(classes("SELECT count(*) FROM \"people\" WHERE name = 'O''Brien' AND id > 12").tokens,
				["SELECT:1", "count:6", "(:9", "*:9", "):9", "FROM:1", "\"people\":5", "WHERE:1", "=:9", "'O''Brien':2", "AND:1", ">:9", "12:3"]);
		});
		test("a comment to the line's end, one across lines", () -> {
			equals(classes("id -- the key").tokens, ["-- the key:4"]);
			var a = classes("x /* starts");
			equals(a.state, 1);
			equals(classes("ends */ y", a.state).tokens, ["ends */:4"]);
		});
	});
}
