package tables;

import helder.ui.code.CodeCompletion.Completion;
import helder.ui.code.CodeCompletion.Completions;

// SQL's suggestions at the caret: after FROM, JOIN, UPDATE, INTO or TABLE
// the tables; after a name and a dot that table's (or alias') columns;
// elsewhere the columns of the tables the query names, then the other
// tables and the keywords. Those whose name starts with what is typed,
// any case; a name that needs quotes put in quoted.
class Complete {
	static final KEYWORDS = [
		"SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "NULL", "IS NULL", "IS NOT NULL", "IN", "LIKE", "BETWEEN", "JOIN", "LEFT JOIN", "INNER JOIN", "ON",
		"GROUP BY", "ORDER BY", "HAVING", "LIMIT", "OFFSET", "INSERT INTO", "VALUES", "UPDATE", "SET", "DELETE FROM", "RETURNING", "DISTINCT", "AS", "ASC",
		"DESC", "COUNT(*)", "CASE", "WHEN", "THEN", "ELSE", "END", "EXISTS", "UNION"
	];

	public static function at(text:String, caret:Int, tables:Array<Table>, sql:Sql):Null<Completions> {
		var from = caret;
		while (from > 0 && word(StringTools.fastCodeAt(text, from - 1)))
			from--;
		var typed = text.substring(from, caret).toLowerCase();
		var before = text.substring(0, from);
		// (in a string or a comment: none)
		if (inside(before)) return null;
		var named = mentioned(text, tables);
		var out:Array<Completion> = [];
		function add(label:String, detail:String, ?insert:String)
			if (StringTools.startsWith(label.toLowerCase(), typed) && label.toLowerCase() != typed) out.push({label: label, detail: detail, insert: insert});
		// (a qualifier: table.| or alias.|)
		if (from > 0 && StringTools.fastCodeAt(text, from - 1) == ".".code) {
			var q = from - 1, start = q;
			while (start > 0 && (word(StringTools.fastCodeAt(text, start - 1)) || StringTools.fastCodeAt(text, start - 1) == '"'.code))
				start--;
			var name = StringTools.replace(text.substring(start, q), '"', "").toLowerCase();
			var t = named.get(name) ?? tables.filter(t -> t.name.toLowerCase() == name)[0];
			if (t == null) return null;
			for (c in t.columns)
				add(c.name, c.detail(), quoted(c.name, sql));
			return out.length == 0 ? null : {from: from, items: out};
		}
		var last = lastWord(before);
		if (last == "from" || last == "join" || last == "update" || last == "into" || last == "table") {
			for (t in tables)
				add(t.name, t.view ? "view" : "table", quoted(t.name, sql));
			return out.length == 0 ? null : {from: from, items: out};
		}
		if (typed == "") return null;
		var seen = new Map<String, Bool>();
		for (t in named)
			for (c in t.columns)
				if (!seen.exists(c.name)) {
					seen.set(c.name, true);
					add(c.name, t.name, quoted(c.name, sql));
				}
		for (t in tables)
			if (!seen.exists(t.name)) add(t.name, "table", quoted(t.name, sql));
		for (k in KEYWORDS)
			add(k, "keyword");
		return out.length == 0 ? null : {from: from, items: out};
	}

	static inline function word(c:Int):Bool
		return c >= "a".code && c <= "z".code || c >= "A".code && c <= "Z".code || c >= "0".code && c <= "9".code || c == "_".code;

	// (a name as SQL takes it: quoted unless it is a plain lower case one)
	static function quoted(name:String, sql:Sql):String
		return ~/^[a-z_][a-z0-9_]*$/.match(name) ? name : sql.name(name);

	// (the last word before the caret's, lower case)
	static function lastWord(before:String):String {
		var r = ~/([A-Za-z_]+)[\s"`(]*$/;
		return r.match(before) ? r.matched(1).toLowerCase() : "";
	}

	// (the tables the query names, by name and by alias: FROM issues i, JOIN people AS p)
	static function mentioned(text:String, tables:Array<Table>):Map<String, Table> {
		var out = new Map<String, Table>();
		var r = ~/\b(?:from|join|update|into)\s+["`]?([A-Za-z_][A-Za-z0-9_]*)["`]?(?:\s+(?:as\s+)?([A-Za-z_][A-Za-z0-9_]*))?/i, at = 0;
		while (r.matchSub(text, at)) {
			var name = r.matched(1).toLowerCase();
			var t = tables.filter(t -> t.name.toLowerCase() == name)[0];
			if (t != null) {
				out.set(name, t);
				var alias = r.matched(2);
				if (alias != null && !~/^(where|join|left|right|inner|on|set|values|order|group|limit)$/i.match(alias)) out.set(alias.toLowerCase(), t);
			}
			var p = r.matchedPos();
			at = p.pos + p.len;
		}
		return out;
	}

	// (whether text ends inside a string or a comment)
	static function inside(text:String):Bool {
		var quote = false, line = false, block = false, i = 0;
		inline function next():Int
			return i + 1 < text.length ? StringTools.fastCodeAt(text, i + 1) : 0;
		while (i < text.length) {
			var c = StringTools.fastCodeAt(text, i);
			if (line) {
				if (c == "\n".code) line = false;
			} else if (block) {
				if (c == "*".code && next() == "/".code) {
					block = false;
					i++;
				}
			} else if (quote) {
				if (c == "'".code) quote = false;
			} else if (c == "'".code) quote = true
			else if (c == "-".code && next() == "-".code) line = true
			else if (c == "/".code && next() == "*".code) block = true;
			i++;
		}
		return quote || line || block;
	}
}
