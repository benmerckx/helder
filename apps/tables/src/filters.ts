// The rows narrowed without writing SQL: conditions picked from a column,
// an operator and a value, and a search of every column, each as SQL
// joined with the WHERE written by hand
import { Column, Table } from "./table";
import { Sql } from "./sql";
import * as format from "./format";

export type Op = "=" | "<>" | ">" | "<" | ">=" | "<=" | "contains" | "starts" | "null" | "notnull";

export type Condition = { col: number; op: Op; value: string };

export const OPS: { op: Op; label: string }[] = [
	{ op: "=", label: "is" },
	{ op: "<>", label: "is not" },
	{ op: "contains", label: "contains" },
	{ op: "starts", label: "starts with" },
	{ op: ">", label: "greater than" },
	{ op: "<", label: "less than" },
	{ op: ">=", label: "at least" },
	{ op: "<=", label: "at most" },
	{ op: "null", label: "is empty" },
	{ op: "notnull", label: "is not empty" }
];

export function label(op: Op): string {
	return OPS.find(o => o.op === op)?.label ?? op;
}

// (whether the operator takes a value)
export function valued(op: Op): boolean {
	return op !== "null" && op !== "notnull";
}

// what a column is first filtered by: text by what it contains, the rest by its value
export function first(c: Column): Op {
	return text(c) && c.values.length === 0 ? "contains" : "=";
}

// the values a column's condition picks from (an enum's, a boolean's), null: typed
export function choices(c: Column): string[] | null {
	if (c.values.length > 0) return c.values;
	return c.mode === "boolean" ? ["true", "false"] : null;
}

// what a value is typed as, shown while it is empty
export function hint(c: Column): string {
	if (c.mode === "timestamp" || c.mode === "timestamp_ms") return "2024-05-06";
	return c.numeric ? "number" : "value";
}

// whether a condition's value is one its column takes (a date half typed is not yet)
export function valid(t: Table, c: Condition): boolean {
	const col = t.columns[c.col];
	if (col === undefined || !valued(c.op) || c.value === "" || c.op === "contains" || c.op === "starts") return true;
	try {
		format.parse(col, c.value);
		return true;
	} catch (_) {
		return false;
	}
}

// a condition as SQL ("": one whose value is not given yet, or not one its column takes)
export function condition(t: Table, c: Condition, sql: Sql): string {
	if (!valid(t, c)) return "";
	const col = t.columns[c.col];
	if (col === undefined) return "";
	const name = sql.name(col.name);
	if (c.op === "null") return name + " IS NULL";
	if (c.op === "notnull") return name + " IS NOT NULL";
	if (c.value === "") return "";
	if (c.op === "contains") return sql.like(name, "%" + c.value + "%");
	if (c.op === "starts") return sql.like(name, c.value + "%");
	return `${name} ${c.op} ${sql.literal(format.parse(col, c.value))}`;
}

// the text searched for in every column: text containing it, numbers equal to it
export function search(t: Table, q: string, sql: Sql): string {
	const s = q.trim();
	if (s === "") return "";
	const n = Number(s);
	const parts = t.columns.flatMap(c => {
		if (text(c)) return [sql.like(sql.name(c.name), "%" + s + "%")];
		if (c.numeric && s !== "" && !isNaN(n)) return [`${sql.name(c.name)} = ${n}`];
		return [];
	});
	return parts.length === 0 ? "1 = 0" : parts.join(" OR ");
}

// the parts given, each in parentheses when there are several
export function joined(parts: string[]): string {
	const given = parts.map(p => p.trim()).filter(p => p !== "");
	return given.length === 1 ? given[0] : given.map(p => `(${p})`).join(" AND ");
}

// (a column searched as text)
function text(c: Column): boolean {
	if (c.numeric || ["timestamp", "timestamp_ms", "boolean"].includes(c.mode)) return false;
	const t = c.type.toLowerCase();
	return !["blob", "bytea", "binary"].some(w => t.includes(w));
}
