// A table's rows as the grid shows them: those matching the filter, in the
// sort's order, fetched a page at a time a page before they come into view
// (a small table whole); a new filter or order fetched in the background
// (the count and the pages in view) and shown all at once, the rows before
// it shown until then; the changes made to them (cells set, rows added and
// deleted) kept until saved in one transaction, or discarded, each undone
// in turn (undo)
import { DataGrid } from "helder/ui";
import { Drizzle, message } from "./drizzle";
import * as format from "./format";
import { Sql } from "./sql";
import { Table } from "./table";

export const PAGE = 200;
// (a table this small fetched whole when first shown)
const WHOLE = 1000;

type Edit = { key: unknown[]; cells: Map<number, unknown> };
type Changes = { edits: Map<string, Edit>; deleted: Map<string, unknown[]>; added: Map<number, unknown>[] };

export class Rows {
	// a WHERE clause's text, the column sorted by (-1: none) and whether descending: those shown
	where = "";
	sortCol = -1;
	sortDown = false;
	// the rows matching (-1: not counted yet), the last query's time (seconds)
	count = -1;
	took = 0;
	// where the grid was (scroll, cursor) when another table was opened
	view: { top: number; left: number; row: number; col: number } | null = null;

	// something shown changed: the grid drawn again; a query failed; rows from the top shown
	onChange: (() => void) | null = null;
	onError: ((e: string) => void) | null = null;
	onTop: (() => void) | null = null;

	private pages = new Map<number, unknown[][]>();
	private asked = new Set<number>();
	// (bumped when a reload starts and when it lands: pages fetched for rows no longer shown dropped)
	private generation = 0;
	// (the rows the grid last showed: what a reload fetches before it shows anything)
	private shownFirst = 0;
	private shownEnd = 0;

	private edits = new Map<string, Edit>();
	private deleted = new Map<string, unknown[]>();
	readonly added: Map<number, unknown>[] = [];
	// (the changes as they were before each change: undo's; inside a batch, one for all)
	private undos: Changes[] = [];
	private batching = false;

	constructor(readonly table: Table, private db: Drizzle, private sql: Sql) {}

	// the rows shown: those matching and those added
	get length(): number {
		return Math.max(0, this.count) + this.added.length;
	}

	// the rows for a filter and an order: counted, the pages of the rows in
	// view (top: the first) fetched, then shown (until then, those shown before)
	async reload(where: string, sortCol: number, sortDown: boolean, top = false) {
		const g = ++this.generation;
		const t0 = Date.now();
		const n = await this.db.rows(this.sql.count(this.table, where));
		if (g !== this.generation) return;
		const total = n.length > 0 ? Math.floor(Number(n[0][0])) : 0;
		const order = this.orderOf(sortCol, sortDown);
		let p0 = Math.floor(this.shownFirst / PAGE), p1 = Math.floor(Math.max(0, Math.min(total - 1, this.shownEnd - 1)) / PAGE);
		if (p0 > p1) p0 = p1;
		if (top) p0 = p1 = 0;
		const fresh = new Map<number, unknown[][]>();
		for (let p = p0; p <= p1; p++) {
			fresh.set(p, await this.db.rows(this.sql.select(this.table, where, order, PAGE, p * PAGE)));
			if (g !== this.generation) return;
		}
		this.generation++;
		this.where = where;
		this.sortCol = sortCol;
		this.sortDown = sortDown;
		this.count = total;
		this.pages = fresh;
		this.asked = new Set(fresh.keys());
		this.took = (Date.now() - t0) / 1000;
		if (top) this.onTop?.();
		this.changed();
	}

	private orderOf(col: number, down: boolean): string {
		if (col >= 0) return this.sql.name(this.table.columns[col].name) + (down ? " DESC" : " ASC");
		// (a stable order for paging: the key's)
		return this.table.key.map(k => this.sql.name(this.table.columns[k].name)).join(", ");
	}

	// the rows first to before end in view: their pages fetched (a page ahead each way, a small table whole)
	want(first: number, end: number) {
		this.shownFirst = first;
		this.shownEnd = end;
		if (this.count <= 0) return;
		const last = Math.min(end, this.count);
		const ahead = this.count <= WHOLE ? this.count : PAGE;
		const p0 = Math.floor(Math.max(0, first - ahead) / PAGE), p1 = Math.floor(Math.max(0, Math.min(this.count - 1, last + ahead)) / PAGE);
		const g = this.generation, w = this.where, order = this.orderOf(this.sortCol, this.sortDown), into = this.pages;
		for (let p = p0; p <= p1; p++) {
			if (this.asked.has(p)) continue;
			this.asked.add(p);
			this.db.rows(this.sql.select(this.table, w, order, PAGE, p * PAGE)).then(rows => {
				if (g !== this.generation) return;
				into.set(p, rows);
				this.changed();
			}, e => {
				if (g !== this.generation) return;
				this.asked.delete(p);
				this.onError?.(message(e));
			});
		}
	}

	private changed() {
		this.onChange?.();
	}

	// a row's values as fetched (null: not here yet, or an added row)
	row(i: number): unknown[] | null {
		if (this.count < 0 || i >= this.count) return null;
		return this.pages.get(Math.floor(i / PAGE))?.[i % PAGE] ?? null;
	}

	// (a row's key: its key columns' values as JSON)
	private keyOf(r: unknown[]): string {
		return JSON.stringify(this.table.key.map(k => r[k]));
	}

	// a cell's value now: as changed, else as fetched
	value(i: number, col: number): unknown {
		if (this.count >= 0 && i >= this.count) return this.added[i - this.count]?.get(col) ?? null;
		const r = this.row(i);
		if (r === null) return null;
		const e = this.edits.get(this.keyOf(r));
		return e !== undefined && e.cells.has(col) ? e.cells.get(col) : r[col];
	}

	text(i: number, col: number): string | null {
		return format.text(this.table.columns[col], this.value(i, col));
	}

	// a cell's flags (col -1: its row's): DataGrid's
	flags(i: number, col: number): number {
		if (this.count >= 0 && i >= this.count) {
			if (col < 0) return DataGrid.ADDED;
			const a = this.added[i - this.count], c = this.table.columns[col];
			// (not set: the column's default, a key the database gives)
			if (!a.has(col)) return c.defaultValue !== null || c.primary ? DataGrid.DEFAULT : DataGrid.NULL;
			return a.get(col) === null ? DataGrid.NULL : 0;
		}
		const r = this.row(i);
		if (r === null) return col < 0 ? 0 : DataGrid.LOADING;
		const k = this.keyOf(r);
		if (col < 0) return this.deleted.has(k) ? DataGrid.DELETED : 0;
		let f = 0;
		if (this.edits.get(k)?.cells.has(col)) f |= DataGrid.EDITED;
		if (this.value(i, col) === null) f |= DataGrid.NULL;
		else if (this.table.reference(col) !== null) f |= DataGrid.LINK;
		return f;
	}

	private writable(what: string) {
		if (this.table.readOnly) throw new Error(this.table.view ? "A view can't be edited" : `This table has no primary key, so ${what}`);
	}

	// a cell set (as typed: an error when it is not the column's kind)
	set(i: number, col: number, v: unknown) {
		this.writable("its rows can't be edited");
		this.keep();
		if (this.count >= 0 && i >= this.count) {
			this.added[i - this.count].set(col, v);
			this.changed();
			return;
		}
		const r = this.row(i);
		if (r === null) return;
		const k = this.keyOf(r);
		let e = this.edits.get(k);
		if (e === undefined) this.edits.set(k, e = { key: this.table.key.map(c => r[c]), cells: new Map() });
		// (back to what it was: no change)
		if (same(r[col], v)) e.cells.delete(col);
		else e.cells.set(col, v);
		if (e.cells.size === 0) this.edits.delete(k);
		this.changed();
	}

	// a new row, at the end: its index
	add(): number {
		this.writable("rows can't be added here");
		this.keep();
		this.added.push(new Map());
		this.changed();
		return this.length - 1;
	}

	// rows deleted (added ones taken out; deleted ones again: kept)
	delete(rows: number[]) {
		this.writable("its rows can't be deleted");
		this.keep();
		const gone: number[] = [];
		for (const i of rows) {
			if (this.count >= 0 && i >= this.count) {
				gone.push(i - this.count);
				continue;
			}
			const r = this.row(i);
			if (r === null) continue;
			const k = this.keyOf(r);
			if (this.deleted.has(k)) this.deleted.delete(k);
			else this.deleted.set(k, this.table.key.map(c => r[c]));
		}
		gone.sort((a, b) => b - a);
		for (const k of gone) this.added.splice(k, 1);
		this.changed();
	}

	changes(): number {
		let n = this.added.length + this.deleted.size;
		for (const e of this.edits.values()) n += e.cells.size;
		return n;
	}

	discard() {
		this.keep();
		this.edits.clear();
		this.deleted.clear();
		this.added.length = 0;
		this.changed();
	}

	// (the changes now, kept for undo)
	private keep() {
		if (this.batching) return;
		this.undos.push({
			edits: new Map([...this.edits].map(([k, e]) => [k, { key: e.key, cells: new Map(e.cells) }])),
			deleted: new Map(this.deleted),
			added: this.added.map(a => new Map(a))
		});
		if (this.undos.length > 200) this.undos.shift();
	}

	// several changes as one (one undo)
	batch(f: () => void) {
		this.keep();
		this.batching = true;
		try {
			f();
		} finally {
			this.batching = false;
		}
	}

	// the last change undone: whether there was one
	undo(): boolean {
		const u = this.undos.pop();
		if (u === undefined) return false;
		this.edits = u.edits;
		this.deleted = u.deleted;
		this.added.length = 0;
		this.added.push(...u.added);
		this.changed();
		return true;
	}

	// a cell as fetched again (its change dropped)
	revert(i: number, col: number) {
		const r = this.row(i);
		if (r === null) return;
		const k = this.keyOf(r), e = this.edits.get(k);
		if (e === undefined || !e.cells.has(col)) return;
		this.keep();
		e.cells.delete(col);
		if (e.cells.size === 0) this.edits.delete(k);
		this.changed();
	}

	edited(i: number, col: number): boolean {
		return (this.flags(i, col) & DataGrid.EDITED) !== 0;
	}

	// a row's values by column, in order (JSON's)
	record(i: number): Record<string, unknown> {
		const o: Record<string, unknown> = {};
		this.table.columns.forEach((c, k) => (o[c.name] = this.value(i, k)));
		return o;
	}

	// the changes as SQL: updates (deleted rows' edits dropped), deletes, inserts
	statements(): string[] {
		const t = this.table, out: string[] = [];
		for (const [k, e] of this.edits) {
			if (this.deleted.has(k)) continue;
			const cols = [...e.cells.keys()].sort((a, b) => a - b);
			out.push(this.sql.update(t, e.key, cols, cols.map(c => e.cells.get(c))));
		}
		for (const key of this.deleted.values()) out.push(this.sql.delete(t, key));
		for (const a of this.added) {
			const cols = [...a.keys()].sort((a, b) => a - b);
			out.push(this.sql.insert(t, cols, cols.map(c => a.get(c))));
		}
		return out;
	}

	// the changes in one transaction, then the rows again
	async save(statements = this.statements()) {
		if (statements.length === 0) return;
		await this.db.transaction(statements);
		this.undos.length = 0;
		this.edits.clear();
		this.deleted.clear();
		this.added.length = 0;
		await this.reload(this.where, this.sortCol, this.sortDown);
	}
}

function same(a: unknown, b: unknown): boolean {
	return a === b || (a !== null && b !== null && JSON.stringify(a) === JSON.stringify(b));
}
