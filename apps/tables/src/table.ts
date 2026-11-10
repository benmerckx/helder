// A table or a view: its columns in order, its primary key (columns'
// indices; none: read only), its rows' count when known, the Drizzle
// schema's relations from it.

// a relation of the Drizzle schema: one (a reference) or many (what refers to it)
export type Relation = {
	name: string;
	kind: string;
	table: string;
	schema: string;
	columns: string[];
	refTable: string;
	refSchema: string;
	refColumns: string[];
};

export class Column {
	// Drizzle's mode for it, from the schema's source: "timestamp", "timestamp_ms", "boolean", "json" ("": none)
	mode = "";
	// the values it takes, when it is an enum (Drizzle's enum: [...], Postgres' enum type, MySQL's enum(...))
	values: string[] = [];

	constructor(readonly name: string, readonly type: string, readonly nullable: boolean, readonly primary: boolean, readonly defaultValue: string | null) {
		if (type.toLowerCase().startsWith("enum(")) this.values = quoted(type);
		// (a boolean by its type: Postgres' boolean, MySQL's tinyint(1))
		if (["boolean", "bool", "tinyint(1)"].includes(type.toLowerCase())) this.mode = "boolean";
	}

	// numbers are aligned right
	get numeric(): boolean {
		if (this.mode !== "") return false;
		const t = this.type.toLowerCase();
		return ["int", "real", "float", "double", "numeric", "decimal", "serial", "money"].some(w => t.includes(w));
	}

	// what the header says beside its name
	detail(): string {
		const t = this.mode !== "" ? this.mode : this.values.length > 0 ? "enum" : this.type.toLowerCase();
		return this.primary ? (t === "" ? "key" : t + " · key") : t;
	}
}

// the strings quoted in a list: 'a', 'b' or "a", "b"
export function quoted(list: string): string[] {
	const out: string[] = [];
	for (const m of list.matchAll(/'((?:[^']|'')*)'|"([^"]*)"/g)) out.push(m[1] !== undefined ? m[1].replaceAll("''", "'") : m[2]);
	return out;
}

export class Table {
	readonly columns: Column[] = [];
	key: number[] = [];
	count = -1;
	relations: Relation[] = [];

	constructor(readonly schema: string, readonly name: string, readonly view: boolean) {}

	get id(): string {
		const s = this.schema;
		return s === "" || s === "main" || s === "public" ? this.name : s + "." + this.name;
	}

	get readOnly(): boolean {
		return this.view || this.key.length === 0;
	}

	add(c: Column) {
		if (c.primary) this.key.push(this.columns.length);
		this.columns.push(c);
	}

	column(name: string): number {
		return this.columns.findIndex(c => c.name === name);
	}

	// the relation of one (a reference) from a column, if any
	reference(col: number): Relation | null {
		const name = this.columns[col]?.name;
		return this.relations.find(r => r.kind === "one" && r.columns.length === 1 && r.columns[0] === name) ?? null;
	}
}
