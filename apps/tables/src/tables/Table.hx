package tables;

import tables.Drizzle.Relation;

// a table or a view: its columns in order, its primary key (columns'
// indices; none: read only), its rows' count when known, the Drizzle
// schema's relations from it
class Table {
	public final schema:String;
	public final name:String;
	public final view:Bool;
	public final columns:Array<Column> = [];
	public var key(default, null):Array<Int> = [];
	public var count = -1;
	public var relations:Array<Relation> = [];

	public function new(schema:String, name:String, view:Bool) {
		this.schema = schema;
		this.name = name;
		this.view = view;
	}

	public var id(get, never):String;

	inline function get_id():String
		return schema == "" || schema == "main" || schema == "public" ? name : schema + "." + name;

	public var readOnly(get, never):Bool;

	inline function get_readOnly():Bool
		return view || key.length == 0;

	public function add(c:Column) {
		if (c.primary) key.push(columns.length);
		columns.push(c);
	}

	public function column(name:String):Int {
		for (k in 0...columns.length)
			if (columns[k].name == name) return k;
		return -1;
	}

	// the relation of one (a reference) from a column, if any
	public function reference(col:Int):Null<Relation> {
		for (r in relations)
			if (r.kind == "one" && r.columns.length == 1 && r.columns[0] == columns[col].name) return r;
		return null;
	}
}

class Column {
	public final name:String;
	public final type:String;
	public final nullable:Bool;
	public final primary:Bool;
	public final defaultValue:Null<String>;
	// Drizzle's mode for it, from the schema's source: "timestamp", "timestamp_ms", "boolean", "json" ("": none)
	public var mode = "";
	// the values it takes, when it is an enum (Drizzle's enum: [...], Postgres' enum type, MySQL's enum(...))
	public var values:Array<String> = [];

	public function new(name, type:String, nullable, primary, defaultValue) {
		this.name = name;
		this.type = type;
		this.nullable = nullable;
		this.primary = primary;
		this.defaultValue = defaultValue;
		if (StringTools.startsWith(type.toLowerCase(), "enum(")) values = quoted(type);
	}

	// the strings quoted in a list: 'a', 'b' or "a", "b"
	public static function quoted(list:String):Array<String> {
		var r = ~/'((?:[^']|'')*)'|"([^"]*)"/, out = [], at = 0;
		while (r.matchSub(list, at)) {
			out.push(r.matched(1) != null ? StringTools.replace(r.matched(1), "''", "'") : r.matched(2));
			var p = r.matchedPos();
			at = p.pos + p.len;
		}
		return out;
	}

	// numbers are aligned right
	public var numeric(get, never):Bool;

	function get_numeric():Bool {
		if (mode != "") return false;
		var t = type.toLowerCase();
		for (w in ["int", "real", "float", "double", "numeric", "decimal", "serial", "money"])
			if (t.indexOf(w) >= 0) return true;
		return false;
	}

	// what the header says beside its name
	public function detail():String {
		var t = mode != "" ? mode : values.length > 0 ? "enum" : type.toLowerCase();
		return primary ? (t == "" ? "key" : t + " · key") : t;
	}
}
