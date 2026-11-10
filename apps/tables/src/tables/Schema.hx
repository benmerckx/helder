package tables;

import tables.Drizzle.Setup;
import tables.Table.Column;

// (every column given a name of its own: drizzle-kit's libsql proxy makes
// a row's array of its object's values, columns of one name one)
//
// the database's tables and views, from its own catalog through the
// server (each dialect's in one query, their counts in another), with the
// Drizzle schema's relations and its columns' modes (read from the
// schema's source: a timestamp or a boolean stored as an integer)
class Schema {
	@:coroutine public static function load(db:Drizzle, setup:Setup, sql:Sql):Array<Table> {
		var tables = if (sql.postgres) postgres(db) else if (sql.mysql) mysql(db) else sqlite(db);
		for (t in tables)
			t.relations = setup.relations.filter(r -> r.table == t.name && (r.schema == t.schema || r.schema == "public" && t.schema == "main"));
		modes(tables, setup.files);
		counts(db, sql, tables);
		return tables;
	}

	@:coroutine static function sqlite(db:Drizzle):Array<Table> {
		var rows = db.rows("SELECT m.name AS t, m.type AS k, p.name AS c, p.type AS ty, p.\"notnull\" AS nn, p.dflt_value AS df, p.pk AS pk FROM sqlite_master m "
			+ "JOIN pragma_table_info(m.name) p WHERE m.type IN ('table', 'view') AND m.name NOT LIKE 'sqlite_%' "
			+ "AND m.name NOT LIKE '\\_\\_drizzle%' ESCAPE '\\' ORDER BY m.name, p.cid");
		return group(rows, r -> {
			schema: "main",
			table: r[0],
			view: r[1] == "view",
			column: new Column(r[2], r[3] ?? "", r[4] != 1, (r[6] ?? 0) > 0, r[5])
		});
	}

	@:coroutine static function postgres(db:Drizzle):Array<Table> {
		var keys = db.rows("SELECT k.table_schema AS s, k.table_name AS t, k.column_name AS c FROM information_schema.table_constraints c "
			+ "JOIN information_schema.key_column_usage k ON k.constraint_name = c.constraint_name AND k.table_schema = c.table_schema "
			+ "WHERE c.constraint_type = 'PRIMARY KEY'");
		var primary = [for (k in keys) k[0] + "." + k[1] + "." + k[2] => true];
		var labels = new Map<String, Array<String>>();
		for (e in db.rows("SELECT t.typname AS t, e.enumlabel AS l FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid ORDER BY t.typname, e.enumsortorder")) {
			if (!labels.exists(e[0])) labels.set(e[0], []);
			labels.get(e[0]).push(e[1]);
		}
		var rows = db.rows("SELECT c.table_schema AS s, c.table_name AS t, t.table_type AS k, c.column_name AS c, c.data_type AS ty, c.is_nullable AS nl, c.column_default AS df, c.udt_name AS u "
			+ "FROM information_schema.columns c JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name "
			+ "WHERE c.table_schema NOT IN ('pg_catalog', 'information_schema', 'drizzle') AND c.table_schema NOT LIKE 'pg_toast%' "
			+ "ORDER BY c.table_schema, c.table_name, c.ordinal_position");
		return group(rows, r -> {
			schema: r[0],
			table: r[1],
			view: r[2] == "VIEW",
			column: {
				var c = new Column(r[3], r[4] == "USER-DEFINED" ? r[7] : r[4] ?? "", r[5] == "YES", primary.exists(r[0] + "." + r[1] + "." + r[3]), r[6]);
				if (labels.exists(r[7])) c.values = labels.get(r[7]);
				c;
			}
		});
	}

	@:coroutine static function mysql(db:Drizzle):Array<Table> {
		var rows = db.rows("SELECT c.table_name AS t, t.table_type AS k, c.column_name AS c, c.column_type AS ty, c.is_nullable AS nl, c.column_default AS df, c.column_key AS pk "
			+ "FROM information_schema.columns c JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name "
			+ "WHERE c.table_schema = DATABASE() AND c.table_name NOT LIKE '\\_\\_drizzle%' ORDER BY c.table_name, c.ordinal_position");
		return group(rows, r -> {
			schema: "",
			table: r[0],
			view: r[1] == "VIEW",
			column: new Column(r[2], r[3] ?? "", r[4] == "YES", r[6] == "PRI", r[5])
		});
	}

	// (rows of a table's columns, in order, into tables)
	static function group(rows:Array<Array<Dynamic>>, read:Array<Dynamic>->{schema:String, table:String, view:Bool, column:Column}):Array<Table> {
		var out:Array<Table> = [], last:Null<Table> = null;
		for (r in rows) {
			var c = read(r);
			if (last == null || last.name != c.table || last.schema != c.schema) {
				last = new Table(c.schema, c.table, c.view);
				out.push(last);
			}
			last.add(c.column);
		}
		return out;
	}

	@:coroutine static function counts(db:Drizzle, sql:Sql, tables:Array<Table>) {
		var real = tables.filter(t -> !t.view);
		if (real.length == 0) return;
		// (Postgres and MySQL: the planner's estimates, a big table not scanned)
		if (sql.postgres) {
			var rows = db.rows("SELECT n.nspname AS s, c.relname AS t, c.reltuples::bigint AS n FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind = 'r'");
			for (r in rows)
				for (t in real)
					if (t.schema == r[0] && t.name == r[1]) t.count = Std.int(Math.max(0, Std.parseFloat(Std.string(r[2]))));
			return;
		}
		var q = [for (k in 0...real.length) 'SELECT $k AS i, COUNT(*) AS n FROM ${sql.table(real[k])}'].join(" UNION ALL ");
		for (r in db.rows(q))
			real[r[0]].count = r[1];
	}

	// Drizzle's modes, from the schema's source: in a table's definition
	// (sqliteTable("name", {...}), pgTable, mysqlTable), a column written
	// integer("col", { mode: "timestamp" }), text("col", { mode: "json" })...
	static function modes(tables:Array<Table>, files:Array<{name:String, content:String}>) {
		var head = ~/(?:sqlite|pg|mysql|singlestore)Table\(\s*["'`]([^"'`]+)["'`]/;
		var col = ~/\b(?:integer|int|text|blob|json|timestamp)\(\s*["'`]([^"'`]+)["'`]\s*,\s*\{[^}]*mode:\s*["'`](\w+)["'`]/;
		var enums = ~/\b(?:text|varchar|char)\(\s*["'`]([^"'`]+)["'`]\s*,\s*\{[^}]*enum:\s*\[([^\]]*)\]/;
		for (f in files) {
			var src = f.content, at = 0;
			var starts:Array<{name:String, pos:Int}> = [];
			while (head.matchSub(src, at)) {
				var p = head.matchedPos();
				starts.push({name: head.matched(1), pos: p.pos});
				at = p.pos + p.len;
			}
			for (k in 0...starts.length) {
				var t = tables.filter(t -> t.name == starts[k].name)[0];
				if (t == null) continue;
				var end = k + 1 < starts.length ? starts[k + 1].pos : src.length;
				var part = src.substring(starts[k].pos, end), from = 0;
				while (col.matchSub(part, from)) {
					var c = t.column(col.matched(1));
					var mode = col.matched(2);
					if (c >= 0 && (mode == "timestamp" || mode == "timestamp_ms" || mode == "boolean" || mode == "json")) t.columns[c].mode = mode;
					var p = col.matchedPos();
					from = p.pos + p.len;
				}
				from = 0;
				while (enums.matchSub(part, from)) {
					var c = t.column(enums.matched(1));
					if (c >= 0) t.columns[c].values = Table.Column.quoted(enums.matched(2));
					var p = enums.matchedPos();
					from = p.pos + p.len;
				}
			}
		}
	}
}
