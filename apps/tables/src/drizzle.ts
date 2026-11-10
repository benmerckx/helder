// drizzle-kit studio's server (`npx drizzle-kit studio`: drizzle-kit's
// src/serializer/studio.ts): one POST of JSON, its type init (the dialect,
// the driver, the schema's relations and files), proxy (a statement, its
// rows as arrays or records) or tproxy (statements in a transaction,
// rolled back at the first error: an {error} after the results)
import { Client } from "helder/async";
import { Relation } from "./table";

// the server's protocol this was written against
export const VERSION = "6.2";

export type Setup = {
	version: string;
	dialect: string;
	driver: string;
	database: string | null;
	// the Drizzle schema's files: their names and text
	files: { name: string; content: string }[];
	relations: Relation[];
};

type Row = Record<string, unknown>;

export class Drizzle {
	constructor(readonly url: string) {}

	async init(): Promise<Setup> {
		const r = await this.post({ type: "init" });
		return {
			version: String(r.version),
			dialect: String(r.dialect),
			driver: String(r.packageName ?? r.driver ?? ""),
			database: r.databaseName ?? null,
			files: (r.schemaFiles ?? []).map((f: Row) => ({ name: String(f.name), content: String(f.content) })),
			relations: (r.relations ?? []).map((o: Row) => ({
				name: o.name, kind: o.type, table: o.table, schema: o.schema, columns: o.columns, refTable: o.refTable, refSchema: o.refSchema,
				refColumns: o.refColumns
			}) as Relation)
		};
	}

	// a statement's rows, each an array of its columns' values
	async rows(sql: string, params: unknown[] = []): Promise<unknown[][]> {
		const r = await this.post({ type: "proxy", data: { sql, params, mode: "array", method: "all" } });
		return Array.isArray(r) ? r : [];
	}

	// a statement's rows as records: their columns by name, in order
	async records(sql: string, params: unknown[] = []): Promise<Row[]> {
		const r = await this.post({ type: "proxy", data: { sql, params, mode: "object", method: "all" } });
		return Array.isArray(r) ? r : [];
	}

	// statements in one transaction (none kept if one fails: its error thrown)
	async transaction(statements: string[]): Promise<void> {
		const results = await this.post({ type: "tproxy", data: statements.map(sql => ({ sql, method: "run" })) });
		if (!Array.isArray(results)) return;
		for (const x of results)
			if (x !== null && typeof x === "object" && !Array.isArray(x) && "error" in x) throw new Error(String((x as Row).error));
	}

	async post(body: unknown): Promise<any> {
		let reply;
		try {
			reply = await Client.request(this.url, { method: "POST", contentType: "application/json", text: JSON.stringify(body) });
		} catch (e) {
			throw new Error(`No drizzle-kit studio at ${this.url}`);
		}
		const v = JSON.parse(reply.text());
		if (v !== null && typeof v === "object" && !Array.isArray(v) && v.status === "error") throw new Error(String(v.error));
		if (reply.status >= 400) throw new Error(`drizzle-kit studio answered ${reply.status}`);
		return v;
	}
}

export function message(e: unknown): string {
	return e instanceof Error ? e.message : String(e);
}
