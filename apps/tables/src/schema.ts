// The database's tables and views, from its own catalog through the server
// (each dialect's in one query, their counts in another), with the Drizzle
// schema's relations and its columns' modes and enums (read from the
// schema's source). Every column is given a name of its own: drizzle-kit's
// libsql proxy makes a row's array of its object's values, so columns of
// one name would be one.
import { Drizzle, Setup } from "./drizzle";
import { Sql } from "./sql";
import { Column, Table, quoted } from "./table";

export async function load(db: Drizzle, setup: Setup, sql: Sql): Promise<Table[]> {
	const tables = sql.postgres ? await postgres(db) : sql.mysql ? await mysql(db) : await sqlite(db);
	for (const t of tables)
		t.relations = setup.relations.filter(r => r.table === t.name && (r.schema === t.schema || (plain(r.schema) && plain(t.schema))));
	modes(tables, setup.files);
	await counts(db, sql, tables);
	// (the default schema's first: public, main)
	return [...tables].sort((a, b) => rank(a) - rank(b));
}

function rank(t: Table): number {
	return plain(t.schema) ? 0 : 1;
}

// (the default schema: SQLite's main, Postgres' public, MySQL's none; drizzle's relations say public for all)
function plain(schema: string): boolean {
	return schema === "" || schema === "public" || schema === "main";
}

type Read = (r: any[]) => { schema: string; table: string; view: boolean; column: Column };

// (rows of a table's columns, in order, into tables)
function group(rows: unknown[][], read: Read): Table[] {
	const out: Table[] = [];
	let last: Table | null = null;
	for (const r of rows) {
		const c = read(r);
		if (last === null || last.name !== c.table || last.schema !== c.schema) {
			last = new Table(c.schema, c.table, c.view);
			out.push(last);
		}
		last.add(c.column);
	}
	return out;
}

async function sqlite(db: Drizzle): Promise<Table[]> {
	const rows = await db.rows(`SELECT m.name AS t, m.type AS k, p.name AS c, p.type AS ty, p."notnull" AS nn, p.dflt_value AS df, p.pk AS pk FROM sqlite_master m `
		+ `JOIN pragma_table_info(m.name) p WHERE m.type IN ('table', 'view') AND m.name NOT LIKE 'sqlite_%' `
		+ `AND m.name NOT LIKE '\\_\\_drizzle%' ESCAPE '\\' ORDER BY m.name, p.cid`);
	return group(rows, r => ({ schema: "main", table: r[0], view: r[1] === "view", column: new Column(r[2], r[3] ?? "", r[4] !== 1, (r[6] ?? 0) > 0, r[5]) }));
}

async function postgres(db: Drizzle): Promise<Table[]> {
	const keys = await db.rows(`SELECT k.table_schema AS s, k.table_name AS t, k.column_name AS c FROM information_schema.table_constraints c `
		+ `JOIN information_schema.key_column_usage k ON k.constraint_name = c.constraint_name AND k.table_schema = c.table_schema `
		+ `WHERE c.constraint_type = 'PRIMARY KEY'`);
	const primary = new Set(keys.map(k => `${k[0]}.${k[1]}.${k[2]}`));
	const labels = new Map<string, string[]>();
	for (const e of await db.rows(`SELECT t.typname AS t, e.enumlabel AS l FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid ORDER BY t.typname, e.enumsortorder`)) {
		const name = String(e[0]);
		if (!labels.has(name)) labels.set(name, []);
		labels.get(name)!.push(String(e[1]));
	}
	const rows = await db.rows(`SELECT c.table_schema AS s, c.table_name AS t, t.table_type AS k, c.column_name AS c, c.data_type AS ty, c.is_nullable AS nl, c.column_default AS df, c.udt_name AS u `
		+ `FROM information_schema.columns c JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name `
		+ `WHERE c.table_schema NOT IN ('pg_catalog', 'information_schema', 'drizzle') AND c.table_schema NOT LIKE 'pg_toast%' `
		+ `ORDER BY c.table_schema, c.table_name, c.ordinal_position`);
	return group(rows, r => {
		const c = new Column(r[3], pgType(r[4], r[7]), r[5] === "YES", primary.has(`${r[0]}.${r[1]}.${r[3]}`), r[6]);
		if (labels.has(r[7])) c.values = labels.get(r[7])!;
		return { schema: r[0], table: r[1], view: r[2] === "VIEW", column: c };
	});
}

// (a Postgres type by its short name: timestamptz for timestamp with time zone, an enum's own, an array's element's[])
const SHORT: Record<string, string> = {
	"timestamp without time zone": "timestamp",
	"timestamp with time zone": "timestamptz",
	"time without time zone": "time",
	"time with time zone": "timetz",
	"character varying": "varchar",
	"character": "char",
	"double precision": "double",
	"bit varying": "varbit"
};

function pgType(data: string | null, udt: string | null): string {
	if (data === "USER-DEFINED") return udt ?? "";
	if (data === "ARRAY") return udt !== null && udt.startsWith("_") ? udt.substring(1) + "[]" : "array";
	return data === null ? "" : SHORT[data] ?? data;
}

async function mysql(db: Drizzle): Promise<Table[]> {
	const rows = await db.rows(`SELECT c.table_name AS t, t.table_type AS k, c.column_name AS c, c.column_type AS ty, c.is_nullable AS nl, c.column_default AS df, c.column_key AS pk `
		+ `FROM information_schema.columns c JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name `
		+ `WHERE c.table_schema = DATABASE() AND c.table_name NOT LIKE '\\_\\_drizzle%' ORDER BY c.table_name, c.ordinal_position`);
	return group(rows, r => ({ schema: "", table: r[0], view: r[1] === "VIEW", column: new Column(r[2], r[3] ?? "", r[4] === "YES", r[6] === "PRI", r[5]) }));
}

async function counts(db: Drizzle, sql: Sql, tables: Table[]) {
	const real = tables.filter(t => !t.view);
	if (real.length === 0) return;
	// (Postgres: the planner's estimates for a big table, not scanned; a
	// small one, or one never analysed (-1, 0), counted)
	let exact = real;
	if (sql.postgres) {
		const rows = await db.rows(`SELECT n.nspname AS s, c.relname AS t, c.reltuples::bigint AS n FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind = 'r'`);
		for (const r of rows)
			for (const t of real)
				if (t.schema === r[0] && t.name === r[1] && Number(r[2]) > 100000) t.count = Math.floor(Number(r[2]));
		exact = real.filter(t => t.count < 0);
		if (exact.length === 0) return;
	}
	const q = exact.map((t, k) => `SELECT ${k} AS i, COUNT(*) AS n FROM ${sql.table(t)}`).join(" UNION ALL ");
	for (const r of await db.rows(q)) exact[Number(r[0])].count = Number(r[1]);
}

// Drizzle's modes and enums, from the schema's source: in a table's
// definition (sqliteTable("name", {...}), pgTable, mysqlTable), a column
// written integer("col", { mode: "timestamp" }), text("col", { enum: [...] })
function modes(tables: Table[], files: { name: string; content: string }[]) {
	const head = /(?:sqlite|pg|mysql|singlestore)Table\(\s*["'`]([^"'`]+)["'`]/g;
	const col = /\b(?:integer|int|text|blob|json|timestamp)\(\s*["'`]([^"'`]+)["'`]\s*,\s*\{[^}]*mode:\s*["'`](\w+)["'`]/g;
	const enums = /\b(?:text|varchar|char)\(\s*["'`]([^"'`]+)["'`]\s*,\s*\{[^}]*enum:\s*\[([^\]]*)\]/g;
	for (const f of files) {
		const starts = [...f.content.matchAll(head)].map(m => ({ name: m[1], pos: m.index ?? 0 }));
		starts.forEach((s, k) => {
			const t = tables.find(t => t.name === s.name);
			if (t === undefined) return;
			const part = f.content.substring(s.pos, k + 1 < starts.length ? starts[k + 1].pos : f.content.length);
			for (const m of part.matchAll(col)) {
				const c = t.column(m[1]);
				if (c >= 0 && ["timestamp", "timestamp_ms", "boolean", "json"].includes(m[2])) t.columns[c].mode = m[2];
			}
			for (const m of part.matchAll(enums)) {
				const c = t.column(m[1]);
				if (c >= 0) t.columns[c].values = quoted(m[2]);
			}
		});
	}
}
