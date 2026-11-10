// SQL's suggestions at the caret: after FROM, JOIN, UPDATE, INTO or TABLE
// the tables; after a name and a dot that table's (or alias') columns;
// elsewhere the columns of the tables the query names, then the other
// tables and the keywords. Those whose name starts with what is typed, any
// case; a name that needs quotes put in quoted.
import { Completion, Completions } from "helder/ui";
import { Sql } from "./sql";
import { Table } from "./table";

const KEYWORDS = [
	"SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "NULL", "IS NULL", "IS NOT NULL", "IN", "LIKE", "BETWEEN", "JOIN", "LEFT JOIN", "INNER JOIN", "ON",
	"GROUP BY", "ORDER BY", "HAVING", "LIMIT", "OFFSET", "INSERT INTO", "VALUES", "UPDATE", "SET", "DELETE FROM", "RETURNING", "DISTINCT", "AS", "ASC",
	"DESC", "COUNT(*)", "CASE", "WHEN", "THEN", "ELSE", "END", "EXISTS", "UNION"
];

const word = (c: string) => /[A-Za-z0-9_]/.test(c);

export function complete(text: string, caret: number, tables: Table[], sql: Sql): Completions | null {
	let from = caret;
	while (from > 0 && word(text[from - 1])) from--;
	const typed = text.substring(from, caret).toLowerCase();
	const before = text.substring(0, from);
	// (in a string or a comment: none)
	if (inside(before)) return null;
	const named = mentioned(text, tables);
	const out: Completion[] = [];
	const add = (label: string, detail: string, insert?: string) => {
		const l = label.toLowerCase();
		if (l.startsWith(typed) && l !== typed) out.push({ label, detail, insert });
	};
	const done = () => (out.length === 0 ? null : { from, items: out });
	// (a qualifier: table.| or alias.|)
	if (from > 0 && text[from - 1] === ".") {
		let start = from - 1;
		while (start > 0 && (word(text[start - 1]) || text[start - 1] === '"')) start--;
		const name = text.substring(start, from - 1).replaceAll('"', "").toLowerCase();
		const t = named.get(name) ?? tables.find(t => t.name.toLowerCase() === name);
		if (t === undefined) return null;
		for (const c of t.columns) add(c.name, c.detail(), quotedName(c.name, sql));
		return done();
	}
	const last = /([A-Za-z_]+)[\s"`(]*$/.exec(before)?.[1].toLowerCase() ?? "";
	if (["from", "join", "update", "into", "table"].includes(last)) {
		for (const t of tables) add(t.name, t.view ? "view" : "table", quotedName(t.name, sql));
		return done();
	}
	if (typed === "") return null;
	const seen = new Set<string>();
	for (const t of new Set(named.values()))
		for (const c of t.columns)
			if (!seen.has(c.name)) {
				seen.add(c.name);
				add(c.name, t.name, quotedName(c.name, sql));
			}
	for (const t of tables) if (!seen.has(t.name)) add(t.name, "table", quotedName(t.name, sql));
	for (const k of KEYWORDS) add(k, "keyword");
	return done();
}

// (a name as SQL takes it: quoted unless it is a plain lower case one)
function quotedName(name: string, sql: Sql): string {
	return /^[a-z_][a-z0-9_]*$/.test(name) ? name : sql.name(name);
}

// (the tables the query names, by name and by alias: FROM issues i, JOIN people AS p)
function mentioned(text: string, tables: Table[]): Map<string, Table> {
	const out = new Map<string, Table>();
	for (const m of text.matchAll(/\b(?:from|join|update|into)\s+["`]?([A-Za-z_][A-Za-z0-9_]*)["`]?(?:\s+(?:as\s+)?([A-Za-z_][A-Za-z0-9_]*))?/gi)) {
		const name = m[1].toLowerCase();
		const t = tables.find(t => t.name.toLowerCase() === name);
		if (t === undefined) continue;
		out.set(name, t);
		const alias: string | undefined = m[2];
		if (alias !== undefined && !/^(where|join|left|right|inner|on|set|values|order|group|limit)$/i.test(alias)) out.set(alias.toLowerCase(), t);
	}
	return out;
}

// (whether text ends inside a string or a comment)
function inside(text: string): boolean {
	let quote = false, line = false, block = false;
	for (let i = 0; i < text.length; i++) {
		const c = text[i], next = text[i + 1] ?? "";
		if (line) {
			if (c === "\n") line = false;
		} else if (block) {
			if (c === "*" && next === "/") {
				block = false;
				i++;
			}
		} else if (quote) {
			if (c === "'") quote = false;
		} else if (c === "'") quote = true;
		else if (c === "-" && next === "-") line = true;
		else if (c === "/" && next === "*") block = true;
	}
	return quote || line || block;
}
