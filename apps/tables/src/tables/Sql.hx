package tables;

// SQL text for a dialect (drizzle-kit's: sqlite, postgresql, mysql,
// singlestore): names quoted, values written as literals (tproxy takes no
// parameters), placeholders numbered or not
class Sql {
	public final dialect:String;

	public function new(dialect:String)
		this.dialect = dialect;

	public var mysql(get, never):Bool;

	inline function get_mysql():Bool
		return dialect == "mysql" || dialect == "singlestore";

	public var postgres(get, never):Bool;

	inline function get_postgres():Bool
		return dialect == "postgresql";

	public function name(n:String):String
		return mysql ? "`" + StringTools.replace(n, "`", "``") + "`" : '"' + StringTools.replace(n, '"', '""') + '"';

	// a table's name, with its schema where the dialect has them
	public function table(t:Table):String
		return t.schema == "" || t.schema == "main" ? name(t.name) : name(t.schema) + "." + name(t.name);

	// the n-th parameter (from 1)
	public function param(n:Int):String
		return postgres ? "$" + n : "?";

	public function literal(v:Dynamic):String {
		if (v == null) return "NULL";
		if (v is Bool) return postgres ? (v ? "true" : "false") : (v ? "1" : "0");
		if (v is Int) return Std.string(v);
		if (v is Float) return Json.number(v);
		if (v is String) {
			var s = StringTools.replace(v, "'", "''");
			if (mysql) s = StringTools.replace(s, "\\", "\\\\");
			return "'" + s + "'";
		}
		return literal(Json.stringify(v));
	}

	// a row picked out by its key's values: "a" = 1 AND "b" = 'x'
	public function match(t:Table, values:Array<Dynamic>):String
		return [
			for (k in 0...t.key.length) {
				var v = values[k];
				name(t.columns[t.key[k]].name) + (v == null ? " IS NULL" : " = " + literal(v));
			}
		].join(" AND ");

	public function select(t:Table, where:String, order:String, limit:Int, offset:Int):String
		return 'SELECT * FROM ${table(t)}${clause("WHERE", where)}${clause("ORDER BY", order)} LIMIT $limit OFFSET $offset';

	public function count(t:Table, where:String):String
		return 'SELECT COUNT(*) AS n FROM ${table(t)}${clause("WHERE", where)}';

	static function clause(word:String, text:String):String
		return StringTools.trim(text) == "" ? "" : ' $word $text';

	public function update(t:Table, key:Array<Dynamic>, cols:Array<Int>, values:Array<Dynamic>):String {
		var set = [for (k in 0...cols.length) name(t.columns[cols[k]].name) + " = " + literal(values[k])].join(", ");
		return 'UPDATE ${table(t)} SET $set WHERE ${match(t, key)}';
	}

	public function insert(t:Table, cols:Array<Int>, values:Array<Dynamic>):String {
		if (cols.length == 0) return mysql ? 'INSERT INTO ${table(t)} () VALUES ()' : 'INSERT INTO ${table(t)} DEFAULT VALUES';
		var names = [for (c in cols) name(t.columns[c].name)].join(", ");
		return 'INSERT INTO ${table(t)} ($names) VALUES (${[for (v in values) literal(v)].join(", ")})';
	}

	public function delete(t:Table, key:Array<Dynamic>):String
		return 'DELETE FROM ${table(t)} WHERE ${match(t, key)}';
}
