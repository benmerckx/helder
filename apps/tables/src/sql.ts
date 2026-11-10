// SQL text for a dialect (drizzle-kit's: sqlite, postgresql, mysql,
// singlestore): names quoted, values written as literals (tproxy takes no
// parameters)
import { Table } from "./table";

export class Sql {
	constructor(readonly dialect: string) {}

	get mysql(): boolean {
		return this.dialect === "mysql" || this.dialect === "singlestore";
	}

	get postgres(): boolean {
		return this.dialect === "postgresql";
	}

	name(n: string): string {
		return this.mysql ? "`" + n.replaceAll("`", "``") + "`" : '"' + n.replaceAll('"', '""') + '"';
	}

	// a table's name, with its schema where the dialect has them
	table(t: Table): string {
		return t.schema === "" || t.schema === "main" ? this.name(t.name) : this.name(t.schema) + "." + this.name(t.name);
	}

	literal(v: unknown): string {
		if (v === null || v === undefined) return "NULL";
		if (typeof v === "boolean") return this.postgres ? (v ? "true" : "false") : v ? "1" : "0";
		if (typeof v === "number") return String(v);
		if (typeof v === "string") {
			let s = v.replaceAll("'", "''");
			if (this.mysql) s = s.replaceAll("\\", "\\\\");
			return "'" + s + "'";
		}
		return this.literal(JSON.stringify(v));
	}

	// a pattern matched without regard to case (Postgres' LIKE has it, and
	// takes text only)
	like(expr: string, pattern: string): string {
		return this.postgres ? `CAST(${expr} AS TEXT) ILIKE ${this.literal(pattern)}` : `${expr} LIKE ${this.literal(pattern)}`;
	}

	// a row picked out by its key's values: "a" = 1 AND "b" = 'x'
	match(t: Table, values: unknown[]): string {
		return t.key.map((c, k) => this.name(t.columns[c].name) + (values[k] === null ? " IS NULL" : " = " + this.literal(values[k]))).join(" AND ");
	}

	select(t: Table, where: string, order: string, limit: number, offset: number): string {
		return `SELECT * FROM ${this.table(t)}${clause("WHERE", where)}${clause("ORDER BY", order)} LIMIT ${limit} OFFSET ${offset}`;
	}

	count(t: Table, where: string): string {
		return `SELECT COUNT(*) AS n FROM ${this.table(t)}${clause("WHERE", where)}`;
	}

	update(t: Table, key: unknown[], cols: number[], values: unknown[]): string {
		const set = cols.map((c, k) => this.name(t.columns[c].name) + " = " + this.literal(values[k])).join(", ");
		return `UPDATE ${this.table(t)} SET ${set} WHERE ${this.match(t, key)}`;
	}

	insert(t: Table, cols: number[], values: unknown[]): string {
		if (cols.length === 0) return this.mysql ? `INSERT INTO ${this.table(t)} () VALUES ()` : `INSERT INTO ${this.table(t)} DEFAULT VALUES`;
		const names = cols.map(c => this.name(t.columns[c].name)).join(", ");
		return `INSERT INTO ${this.table(t)} (${names}) VALUES (${values.map(v => this.literal(v)).join(", ")})`;
	}

	delete(t: Table, key: unknown[]): string {
		return `DELETE FROM ${this.table(t)} WHERE ${this.match(t, key)}`;
	}
}

function clause(word: string, text: string): string {
	return text.trim() === "" ? "" : ` ${word} ${text}`;
}
