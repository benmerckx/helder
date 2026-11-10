package helder.ui.code;

import helder.syntax.Lexer.TokenClass;

// SQL's lines highlighted: keywords (any case), strings ('...', a quote
// doubled inside), quoted names ("..." and `...`: types' colour), numbers,
// -- comments and /* */ ones across lines, a name before "(" a function's
class SqlLanguage implements CodeLanguage {
	static inline var CODE = 0;
	static inline var COMMENT = 1;
	static inline var STRING = 2;

	static final KEYWORDS = [
		for (w in ("select from where and or not null is in as on join left right inner outer full cross natural using group by order having limit offset "
			+ "insert into values update set delete returning create table view index unique primary key foreign references drop alter add column "
			+ "default check constraint if exists distinct all union intersect except case when then else end asc desc like ilike between with "
			+ "recursive begin commit rollback transaction true false cast collate pragma explain analyze vacuum over partition window filter "
			+ "integer int bigint smallint text varchar char real double float numeric decimal boolean bool date time timestamp timestamptz json "
			+ "jsonb blob uuid serial bigserial bytea interval autoincrement conflict do nothing replace").split(" "))
			w => true
	];

	public function new() {}

	public function name():String
		return "sql";

	public function startState():Int
		return CODE;

	public function lineComment():Null<String>
		return "--";

	public function tokenize(line:String, state:Int, out:Array<Int>):Int {
		var i = 0, n = line.length;
		inline function at(k:Int):Int
			return k < n ? StringTools.fastCodeAt(line, k) : 0;
		inline function token(start:Int, end:Int, cls:TokenClass) {
			out.push(start);
			out.push(end);
			out.push(cls);
		}
		while (i < n) {
			var start = i;
			if (state == COMMENT) {
				while (i < n && !(at(i) == "*".code && at(i + 1) == "/".code))
					i++;
				if (i < n) {
					i += 2;
					state = CODE;
				}
				token(start, i, Comment);
				continue;
			}
			if (state == STRING) {
				i = quoted(line, i, "'".code);
				if (i <= n && at(i - 1) == "'".code && i > start) state = CODE;
				if (i > n) i = n;
				token(start, i, Str);
				continue;
			}
			var c = at(i);
			if (c == " ".code || c == "\t".code) {
				i++;
				continue;
			}
			if (c == "-".code && at(i + 1) == "-".code) {
				token(i, n, Comment);
				return state;
			}
			if (c == "/".code && at(i + 1) == "*".code) {
				state = COMMENT;
				i += 2;
				while (i < n && !(at(i) == "*".code && at(i + 1) == "/".code))
					i++;
				if (i < n) {
					i += 2;
					state = CODE;
				}
				token(start, i, Comment);
				continue;
			}
			if (c == "'".code) {
				i = quoted(line, i + 1, c);
				if (i > n) {
					i = n;
					state = STRING;
				}
				token(start, i, Str);
				continue;
			}
			if (c == '"'.code || c == "`".code) {
				i = quoted(line, i + 1, c);
				if (i > n) i = n;
				token(start, i, Type);
				continue;
			}
			if (c >= "0".code && c <= "9".code) {
				while (i < n && (at(i) >= "0".code && at(i) <= "9".code || at(i) == ".".code))
					i++;
				token(start, i, Num);
				continue;
			}
			if (word(c)) {
				while (i < n && (word(at(i)) || at(i) >= "0".code && at(i) <= "9".code))
					i++;
				var w = line.substring(start, i).toLowerCase();
				var k = i;
				while (k < n && at(k) == " ".code)
					k++;
				if (KEYWORDS.exists(w)) token(start, i, Keyword) else if (at(k) == "(".code) token(start, i, Function);
				continue;
			}
			if (c == "$".code || c == "?".code) {
				i++;
				while (i < n && at(i) >= "0".code && at(i) <= "9".code)
					i++;
				token(start, i, Attribute);
				continue;
			}
			i++;
			token(start, i, Punct);
		}
		return state;
	}

	static inline function word(c:Int):Bool
		return c >= "a".code && c <= "z".code || c >= "A".code && c <= "Z".code || c == "_".code || c >= 0x80;

	// (past the closing quote from i, a doubled one inside; past the end: n + 1)
	static function quoted(line:String, i:Int, q:Int):Int {
		var n = line.length;
		while (i < n) {
			if (StringTools.fastCodeAt(line, i) == q) {
				if (i + 1 < n && StringTools.fastCodeAt(line, i + 1) == q) {
					i += 2;
					continue;
				}
				return i + 1;
			}
			i++;
		}
		return n + 1;
	}
}
