// The app's state: the server it talks to (connecting until it answers,
// tried again every two seconds), the database's tables, the one open (its
// rows in the grid, a filter and a sort, columns hidden, its changes until
// saved), the row panel, its structure, the SQL console and its results;
// where you came from (Back); what the status bar says
import { signal, Signal } from "helder/view";
import { CodeEditor, DataGrid, GridColumn, Svg, Theme, UiWindow } from "helder/ui";
import { Store } from "helder/os";
import { delay } from "helder/async";
import { complete } from "./complete";
import { Drizzle, Setup, VERSION, message } from "./drizzle";
import * as format from "./format";
import * as icons from "./icons";
import { Rows } from "./rows";
import { load as loadSchema } from "./schema";
import { Sql } from "./sql";
import { Column, Relation, Table } from "./table";

// (TextAlign's values: helder's enum abstracts are numbers to TypeScript)
const LEFT = 0, RIGHT = 2;

// a menu's item: its label, a quieter detail, an icon, disabled, checked (on), a separator (line)
export type Entry = { label: string; detail?: string; icon?: Svg; disabled?: boolean; on?: boolean; muted?: boolean; line?: boolean; run: () => void };
export const LINE: Entry = { label: "", line: true, run: () => {} };
export type Popup = { x: number; y: number; width?: number; items: Entry[] };
export type Link = { label: string; detail: string; run: () => void };

export class Tables {
	// "connecting", "ready", "offline"
	readonly state = signal("connecting");
	readonly setup: Signal<Setup | null> = signal<Setup | null>(null);
	readonly tables: Signal<Table[]> = signal<Table[]>([]);
	readonly current: Signal<Table | null> = signal<Table | null>(null);
	// the table being opened: its rows on their way, the one before shown until they are in
	readonly opening: Signal<Table | null> = signal<Table | null>(null);
	// "data", "structure", "sql"
	readonly mode = signal("data");
	// the sidebar's search, the filter as typed and as applied, whether it failed
	readonly search = signal("");
	readonly filter = signal("");
	readonly applied = signal("");
	readonly filterFailed = signal(false);
	// the open table's rows matching, its changes, the last query's time
	readonly count = signal(-1);
	readonly changes = signal(0);
	readonly took = signal(0);
	// the cursor's cell, as the status bar says it
	readonly cell = signal("");
	// a message for a moment (an error, "Saved"), and whether it is an error
	readonly note = signal("");
	readonly failed = signal(false);
	readonly saving = signal(false);
	// a menu: where (window pixels), how wide at least, its items
	readonly menu: Signal<Popup | null> = signal<Popup | null>(null);
	// the row panel: shown, and bumped when what it shows changed
	readonly panel = signal(false);
	readonly version = signal(0);
	// columns hidden, by table
	readonly hidden: Signal<Map<string, string[]>> = signal(new Map<string, string[]>());
	// the SQL console's text, its result's note, its state
	readonly query = signal("");
	readonly resultNote = signal("");
	readonly resultFailed = signal(false);
	readonly running = signal(false);
	readonly canBack = signal(false);
	// "system", "light" or "dark" (kept between runs)
	readonly appearance: Signal<string>;

	readonly grid = new DataGrid("rows");
	readonly structure = new DataGrid("structure");
	readonly results = new DataGrid("results");
	readonly editor = new CodeEditor("", "query.sql");

	private db: Drizzle;
	private sql = new Sql("sqlite");
	private rows: Rows | null = null;
	// (the grid's columns: the table's they show)
	private cols: number[] = [];
	private opened = new Map<string, Rows>();
	private history: { table: string; where: string }[] = [];
	private resultRows: Record<string, unknown>[] = [];
	private resultKeys: string[] = [];
	private noteId = 0;
	private store = Store.open("tables");

	constructor(readonly url: string) {
		this.db = new Drizzle(url);
		this.appearance = signal(this.store.get("appearance") ?? "system");
		for (const g of [this.grid, this.structure, this.results]) {
			g.titleFamily = Theme.UI;
			g.rowHeight = 28;
			g.headerHeight = 32;
		}
		const grid = this.grid;
		grid.text = (r, c) => this.rows?.text(r, this.cols[c]) ?? "";
		grid.flags = (r, c) => this.rows?.flags(r, c < 0 ? -1 : this.cols[c]) ?? 0;
		grid.onWindow = (a, b) => this.rows?.want(a, b);
		grid.onSort = c => this.sortBy(this.cols[c]);
		grid.onEdit = (r, c, typed) => this.edit(r, c, typed);
		grid.onCommit = (r, c, t) => this.setText(r, this.cols[c], t);
		grid.onClear = () => this.clearCells();
		grid.onSelect = () => {
			this.describe();
			this.bump();
		};
		grid.onContext = (r, c, x, y) => this.menu({ x, y, items: this.items(r, c) });
		grid.onHeaderContext = (c, x, y) => this.menu({ x, y, items: this.headerItems(c) });
		grid.onLink = (r, c) => {
			const t = this.rows?.table, v = this.rows?.value(r, this.cols[c]);
			const ref = t?.reference(this.cols[c]);
			if (ref && v !== null && v !== undefined) this.follow(ref, v);
		};
		grid.onPaste = text => this.paste(text);
		this.structure.readOnly = true;
		this.results.readOnly = true;
		this.editor.view.fontFamily = Theme.CODE;
		this.editor.view.fontSize = Theme.BODY;
		this.editor.view.lineHeight = 20;
		this.editor.onChange = () => this.query(this.editor.text);
		this.editor.complete = (text, caret) => complete(text, caret, this.tables.peek(), this.sql);
		this.results.text = (r, c) => {
			const v = this.resultRows[r]?.[this.resultKeys[c]];
			return v === null || v === undefined ? null : typeof v === "string" ? v : JSON.stringify(v);
		};
	}

	private bump() {
		this.version(this.version.peek() + 1);
	}

	// dark: the appearance chosen, or the system's
	dark(): boolean {
		const a = this.appearance();
		return a === "system" ? UiWindow.dark() : a === "dark";
	}

	appear(kind: string) {
		this.appearance(kind);
		this.store.set("appearance", kind);
	}

	// ---- the server

	async start() {
		while (true) {
			try {
				const s = await this.db.init();
				if (s.version !== VERSION) this.say(`drizzle-kit studio speaks ${s.version}, this was made for ${VERSION}: some things may not work`, true);
				this.sql = new Sql(s.dialect);
				const list = await loadSchema(this.db, s, this.sql);
				this.setup(s);
				this.tables(list);
				this.state("ready");
				const first = list.find(t => !t.view) ?? list[0];
				if (first !== undefined && this.current.peek() === null) this.open(first);
				if (this.query.peek() === "" && first !== undefined) {
					// (the signal's write lands later: the editor given the text itself)
					const q = `SELECT * FROM ${this.sql.table(first)} LIMIT 100`;
					this.query(q);
					this.editor.text = q;
				}
				return;
			} catch (e) {
				this.state("offline");
				await delay(2);
			}
		}
	}

	get dialect(): string {
		return this.setup.peek()?.dialect ?? "";
	}

	// ---- a table

	// a table open, filtered (its last filter: where is null), Back to the one
	// before it; a table not seen yet (or another filter) shown once its rows are in
	open(t: Table, where: string | null = null, remember = true) {
		this.menu(null);
		let r = this.opened.get(t.id);
		if (r === undefined) this.opened.set(t.id, r = new Rows(t, this.db, this.sql));
		const rows = r, w = where ?? r.where;
		if (r.count < 0 || w !== r.where) {
			this.opening(t);
			rows.reload(w, rows.sortCol, rows.sortDown).then(() => {
				if (this.opening.peek() !== t) return;
				this.opening(null);
				this.show(t, rows, w, remember);
			}, e => {
				if (this.opening.peek() !== t) return;
				this.opening(null);
				this.show(t, rows, w, remember);
				this.filterFailed(w !== "");
				this.say(message(e), true);
			});
			return;
		}
		this.opening(null);
		this.show(t, r, w, remember);
		// (its rows fetched again, those it had shown until they are in)
		this.load(false, w);
	}

	private show(t: Table, r: Rows, w: string, remember: boolean) {
		const was = this.current.peek();
		if (remember && was !== null && (was !== t || w !== this.applied.peek())) {
			this.history.push({ table: was.id, where: this.applied.peek() });
			this.canBack(true);
		}
		// (where the grid was, kept with the table left)
		const grid = this.grid;
		if (this.rows !== null && this.rows.table !== t) this.rows.view = { top: grid.scrollTop, left: grid.scrollLeft, row: grid.cursorRow, col: grid.cursorCol };
		const same = this.rows === r;
		this.rows = r;
		r.onChange = () => {
			if (this.rows !== r) return;
			grid.rowCount = r.length;
			grid.refresh();
			this.count(r.count);
			this.changes(r.changes());
			this.took(r.took);
			this.describe();
			this.bump();
		};
		r.onError = e => this.say(e, true);
		r.onTop = () => {
			if (this.rows !== r) return;
			grid.scrollTo(grid.scrollLeft, 0);
			grid.moveTo(0, grid.cursorCol);
		};
		grid.readOnly = t.readOnly;
		this.showColumns(t);
		grid.rowCount = r.length;
		if (!same && r.view !== null && w === r.where) grid.restore(r.view.top, r.view.left, r.view.row, r.view.col);
		else grid.reset();
		this.current(t);
		this.filter(w);
		this.applied(w);
		this.filterFailed(false);
		this.count(r.count);
		this.changes(r.changes());
		this.showStructure(t);
		this.bump();
		if (this.mode.peek() !== "sql") grid.focus(false);
	}

	// (the grid's columns: the table's not hidden)
	// (hidden: the map just written, as a signal's write is read only once the graph has taken it)
	private showColumns(t: Table, hidden = this.hidden.peek()) {
		const off = hidden.get(t.id) ?? [];
		this.cols = t.columns.map((_, k) => k).filter(k => !off.includes(t.columns[k].name));
		this.grid.columns = this.cols.map(k => {
			const c = t.columns[k];
			return new GridColumn(c.name, width(c), c.numeric ? RIGHT : LEFT, c.detail());
		});
		const r = this.rows;
		this.grid.sortColumn = r === null ? -1 : this.cols.indexOf(r.sortCol);
		this.grid.sortDown = r !== null && r.sortDown;
	}

	// the open table's rows fetched again (top: a new filter, shown from the
	// top), in the order the grid shows (where: a filter just applied, as a
	// signal's write is read only once the graph has taken it)
	private load(top = false, where = this.applied.peek()) {
		const r = this.rows;
		if (r === null) return;
		const s = this.sorting();
		r.reload(where, s.col, s.down, top).then(() => {
			if (this.rows === r) this.filterFailed(false);
		}, e => {
			if (this.rows !== r) return;
			this.filterFailed(where !== "");
			this.say(message(e), true);
		});
	}

	refresh() {
		this.load();
	}

	// the filter as typed applied
	applyFilter(text = this.filter.peek()) {
		if (this.current.peek() === null) return;
		const where = text.trim();
		this.applied(where);
		this.load(true, where);
	}

	clearFilter() {
		this.filter("");
		this.applyFilter("");
	}

	// a filter set and applied
	filterBy(where: string) {
		this.filter(where);
		this.applied(where);
		this.load(true, where);
	}

	// a column's title pressed: sorted by it, ascending, descending, then not (from the arrow shown)
	private sortBy(col: number) {
		const s = this.sorting();
		const next = s.col !== col ? { col, down: false } : !s.down ? { col, down: true } : { col: -1, down: false };
		this.sort(next.col, next.down);
	}

	// the order the grid shows (a sort asked for and not in yet: that one)
	private sorting(): { col: number; down: boolean } {
		const g = this.grid.sortColumn;
		return { col: g >= 0 && g < this.cols.length ? this.cols[g] : -1, down: this.grid.sortDown };
	}

	sort(col: number, down: boolean) {
		const r = this.rows;
		if (r === null) return;
		this.grid.sortColumn = this.cols.indexOf(col);
		this.grid.sortDown = down;
		r.reload(this.applied.peek(), col, down, true).catch(e => this.say(message(e), true));
	}

	back() {
		const h = this.history.pop();
		this.canBack(this.history.length > 0);
		if (h === undefined) return;
		const t = this.tables.peek().find(t => t.id === h.table);
		if (t !== undefined) this.open(t, h.where, false);
	}

	// whether a table has changes not saved
	pending(t: Table): boolean {
		this.changes();
		const r = this.opened.get(t.id);
		return r !== undefined && r.changes() > 0;
	}

	// ---- columns

	hide(col: number) {
		const t = this.current.peek();
		if (t === null || this.cols.length <= 1) return;
		const m = new Map(this.hidden.peek());
		m.set(t.id, [...(m.get(t.id) ?? []), t.columns[col].name]);
		this.hidden(m);
		const at = this.grid.cursorCol;
		this.showColumns(t, m);
		this.grid.moveTo(this.grid.cursorRow, Math.min(at, this.cols.length - 1));
	}

	showAll() {
		const t = this.current.peek();
		if (t === null) return;
		const m = new Map(this.hidden.peek());
		m.delete(t.id);
		this.hidden(m);
		this.showColumns(t, m);
		this.grid.refresh();
	}

	// ---- changes

	// a cell edited: a boolean toggled, an enum's value picked, the rest typed in the grid's editor
	private edit(row: number, c: number, typed: string | null) {
		const r = this.rows;
		if (r === null) return;
		const col = r.table.columns[this.cols[c]];
		const plain = typed === null || typed === " ";
		if (col.mode === "boolean" && plain) {
			const v = r.value(row, this.cols[c]);
			this.set(row, this.cols[c], !(v === true || v === 1));
			return;
		}
		if (col.values.length > 0 && plain) {
			this.pick(row, c);
			return;
		}
		this.grid.edit(row, c, typed ?? undefined);
	}

	// (an enum's values in a menu under its cell)
	private pick(row: number, c: number) {
		const r = this.rows;
		if (r === null) return;
		const col = r.table.columns[this.cols[c]], now = r.value(row, this.cols[c]);
		const items: Entry[] = col.values.map(v => ({ label: v, on: now === v, run: () => this.set(row, this.cols[c], v) }));
		if (col.nullable) items.push({ label: "NULL", on: now === null, muted: true, run: () => this.set(row, this.cols[c], null) });
		const b = this.grid.cellBounds(row, c);
		this.menu({ x: b.x, y: b.y + b.height + 2, width: b.width, items });
	}

	private set(row: number, col: number, v: unknown) {
		try {
			this.rows?.set(row, col, v);
		} catch (e) {
			this.say(message(e), true);
		}
	}

	// a cell set from text, as the column takes it
	setText(row: number, col: number, text: string) {
		const r = this.rows;
		if (r === null) return;
		try {
			r.set(row, col, format.parse(r.table.columns[col], text));
		} catch (e) {
			this.say(message(e), true);
		}
	}

	addRow() {
		const r = this.rows;
		if (r === null) return;
		try {
			const i = r.add();
			// (the first column the database does not fill: typed into at once)
			const first = Math.max(0, this.cols.findIndex(k => !r.table.columns[k].primary));
			this.grid.moveTo(i, first);
			this.grid.focus(false);
			if (r.table.columns[this.cols[first]].mode !== "boolean") this.edit(i, first, null);
		} catch (e) {
			this.say(message(e), true);
		}
	}

	deleteRows() {
		const r = this.rows;
		if (r === null) return;
		const range = this.grid.range();
		const list: number[] = [];
		for (let i = range.top; i <= range.bottom; i++) list.push(i);
		try {
			r.delete(list);
		} catch (e) {
			this.say(message(e), true);
		}
	}

	private clearCells() {
		const r = this.rows;
		if (r === null) return;
		const range = this.grid.range();
		if (this.grid.wholeRows) {
			this.deleteRows();
			return;
		}
		try {
			for (let c = range.left; c <= range.right; c++) {
				const col = r.table.columns[this.cols[c]];
				if (!col.nullable) throw new Error(`${col.name} can't be NULL`);
			}
			r.batch(() => {
				for (let i = range.top; i <= range.bottom; i++)
					for (let c = range.left; c <= range.right; c++) r.set(i, this.cols[c], null);
			});
		} catch (e) {
			this.say(message(e), true);
		}
	}

	// tab separated text pasted from the selection's top left (one value: into every selected cell)
	private paste(text: string) {
		const r = this.rows;
		if (r === null) return;
		const lines = text.replaceAll("\r\n", "\n").split("\n");
		if (lines.length > 1 && lines[lines.length - 1] === "") lines.pop();
		const cells = lines.map(l => l.split("\t"));
		const range = this.grid.range();
		const one = cells.length === 1 && cells[0].length === 1;
		const bottom = one ? range.bottom : Math.min(r.length - 1, range.top + cells.length - 1);
		const right = one ? range.right : Math.min(this.cols.length - 1, range.left + cells[0].length - 1);
		try {
			r.batch(() => {
				for (let i = range.top; i <= bottom; i++)
					for (let c = range.left; c <= right; c++) {
						const t = one ? cells[0][0] : cells[i - range.top]?.[c - range.left];
						if (t === undefined) continue;
						r.set(i, this.cols[c], format.parse(r.table.columns[this.cols[c]], t));
					}
			});
		} catch (e) {
			this.say(message(e), true);
		}
	}

	undo() {
		if (this.rows !== null && !this.rows.undo()) this.say("Nothing to undo");
	}

	discard() {
		this.rows?.discard();
	}

	save() {
		const r = this.rows;
		if (r === null || r.changes() === 0 || this.saving.peek()) return;
		const n = r.changes();
		this.saving(true);
		r.save().then(async () => {
			this.saving(false);
			this.say(n === 1 ? "Saved 1 change" : `Saved ${n} changes`);
			// (rows added or deleted: the sidebar's counts again)
			const c = await this.db.rows(this.sql.count(r.table, ""));
			if (c.length > 0) r.table.count = Math.floor(Number(c[0][0]));
			this.tables([...this.tables.peek()]);
		}, e => {
			this.saving(false);
			this.say("Not saved: " + message(e), true);
		});
	}

	// ---- the row panel

	// the cursor's row (-1: none)
	panelRow(): number {
		this.version();
		const r = this.rows;
		return r === null || r.length === 0 ? -1 : this.grid.cursorRow;
	}

	fieldText(col: number): string | null {
		const row = this.panelRow();
		return this.rows === null || row < 0 ? null : this.rows.text(row, col);
	}

	fieldFlags(col: number): number {
		const row = this.panelRow();
		return this.rows === null || row < 0 ? 0 : this.rows.flags(row, col);
	}

	setField(col: number, text: string) {
		const row = this.panelRow();
		if (row < 0) return;
		const now = this.fieldText(col);
		if (now === text || (now === null && text === "")) return;
		this.setText(row, col, text);
	}

	// ---- the status bar

	// a message, gone after a while
	say(text: string, error = false) {
		const id = ++this.noteId;
		this.note(text);
		this.failed(error);
		setTimeout(() => {
			if (this.noteId === id) this.note("");
		}, error ? 8000 : 3000);
	}

	private describe() {
		const r = this.rows;
		if (r === null || this.cols.length === 0 || r.length === 0) {
			this.cell("");
			return;
		}
		const range = this.grid.range();
		const rows = range.bottom - range.top + 1, n = range.right - range.left + 1;
		if (rows > 1 || n > 1) {
			this.cell(this.grid.wholeRows ? `${format.count(rows)} rows selected` : `${format.count(rows * n)} cells selected`);
			return;
		}
		const c = r.table.columns[this.cols[this.grid.cursorCol]];
		this.cell(`${c.name} · row ${format.count(this.grid.cursorRow + 1)}`);
	}

	// ---- menus

	// a cell's: its relations (the row it refers to, the rows referring to
	// it), filters by its value, copying, NULL, its change undone, deleting
	private items(row: number, c: number): Entry[] {
		const r = this.rows;
		if (r === null) return [];
		const t = r.table, col = this.cols[c], out: Entry[] = [];
		const column = t.columns[col], v = r.value(row, col);
		const ref = t.reference(col);
		if (ref !== null && v !== null) out.push({ label: `Open ${singular(ref.refTable)} ${format.text(column, v)}`, icon: icons.open, run: () => this.follow(ref, v) });
		for (const rel of t.relations) {
			if (rel.kind !== "many" || rel.columns.length !== 1) continue;
			const k = t.column(rel.columns[0]);
			const key = k < 0 ? null : r.value(row, k);
			if (key !== null) out.push({ label: `Show ${rel.name}`, detail: rel.refTable, icon: icons.link, run: () => this.follow(rel, key) });
		}
		if (out.length > 0) out.push(LINE);
		const name = this.sql.name(column.name);
		if (row < Math.max(0, r.count)) {
			const shown = v === null ? "NULL" : short(format.text(column, v) ?? "");
			out.push({ label: `Only ${shown}`, detail: "filter", icon: icons.filter, run: () => this.filterBy(v === null ? `${name} IS NULL` : `${name} = ${this.sql.literal(v)}`) });
			out.push({ label: `Without ${shown}`, detail: "filter", run: () => this.filterBy(v === null ? `${name} IS NOT NULL` : `${name} <> ${this.sql.literal(v)}`) });
			out.push(LINE);
		}
		out.push({ label: "Copy", detail: primary("C"), run: () => this.grid.copy() });
		out.push({ label: "Copy row as JSON", run: () => this.grid.copy(JSON.stringify(r.record(row))) });
		if (!t.readOnly) {
			out.push({ label: "Paste", detail: primary("V"), run: () => this.grid.paste() });
			out.push(LINE);
			if (r.edited(row, col)) out.push({ label: "Revert change", icon: icons.undo, run: () => r.revert(row, col) });
			out.push({ label: "Set to NULL", disabled: !column.nullable, run: () => this.clearCells() });
			const range = this.grid.range();
			out.push({ label: this.grid.wholeRows && range.bottom > range.top ? "Delete rows" : "Delete row", icon: icons.trash, run: () => {
				if (!this.grid.wholeRows) this.grid.moveTo(row, c, false, true);
				this.deleteRows();
			} });
		}
		return out;
	}

	// a column's title's: sorting, filtering, hiding
	private headerItems(c: number): Entry[] {
		const t = this.current.peek();
		if (this.rows === null || t === null) return [];
		const col = this.cols[c], name = this.sql.name(t.columns[col].name), s = this.sorting();
		const out: Entry[] = [
			{ label: "Sort ascending", on: s.col === col && !s.down, run: () => this.sort(col, false) },
			{ label: "Sort descending", on: s.col === col && s.down, run: () => this.sort(col, true) }
		];
		if (s.col >= 0) out.push({ label: "Don't sort", run: () => this.sort(-1, false) });
		out.push(LINE);
		out.push({ label: "Filter by this column", icon: icons.filter, run: () => {
			const f = this.filter.peek().trim();
			this.filter((f === "" ? "" : f + " AND ") + `${name} = `);
			this.focusFilter(true);
		} });
		out.push({ label: "Fit width", run: () => this.grid.fitColumn(c) });
		out.push({ label: "Hide column", disabled: this.cols.length <= 1, run: () => this.hide(col) });
		if (this.cols.length < t.columns.length) out.push({ label: "Show all columns", detail: `${t.columns.length - this.cols.length} hidden`, run: () => this.showAll() });
		return out;
	}

	// the filter field focused (set by the view)
	focusFilter: (end?: boolean) => void = () => {};

	// a relation followed: its table, filtered to the rows of the value
	follow(rel: Relation, v: unknown) {
		const t = this.tables.peek().find(t => t.name === rel.refTable && (t.schema === rel.refSchema || rel.refSchema === "public"));
		if (t === undefined) return;
		this.mode("data");
		this.open(t, `${this.sql.name(rel.refColumns[0])} = ${this.sql.literal(v)}`);
	}

	// the relations of the panel's row: each followed by its value
	links(): Link[] {
		const r = this.rows, row = this.panelRow();
		if (r === null || row < 0) return [];
		const t = r.table, out: Link[] = [];
		for (const rel of t.relations) {
			if (rel.columns.length !== 1) continue;
			const k = t.column(rel.columns[0]);
			const v = k < 0 ? null : r.value(row, k);
			if (v === null) continue;
			const shown = format.text(t.columns[k], v);
			out.push({
				label: rel.name,
				detail: rel.kind === "one" ? `${rel.refTable} ${shown}` : `${rel.refTable} where ${rel.refColumns[0]} = ${shown}`,
				run: () => this.follow(rel, v)
			});
		}
		return out;
	}

	// ---- the structure

	private showStructure(t: Table) {
		const list = t.columns;
		this.structure.columns = [
			new GridColumn("Column", 180), new GridColumn("Type", 150), new GridColumn("Null", 70), new GridColumn("Default", 200), new GridColumn("Drizzle", 120),
			new GridColumn("Values", 220), new GridColumn("References", 220)
		];
		this.structure.text = (r, c) => {
			const col = list[r];
			switch (c) {
				case 0: return col.primary ? col.name + "  (key)" : col.name;
				case 1: return col.type.toLowerCase();
				case 2: return col.nullable && !col.primary ? "yes" : "no";
				case 3: return col.defaultValue ?? "";
				case 4: return col.mode;
				case 5: return col.values.join(", ");
				default: {
					const ref = t.reference(r);
					return ref === null ? "" : ref.refTable + "." + ref.refColumns.join(", ");
				}
			}
		};
		this.structure.rowCount = list.length;
		this.structure.reset();
	}

	// ---- the console

	// the query run (the selection, if there is one)
	run() {
		const sel = this.editor.model.primary, text = this.editor.text;
		const q = (sel.empty() ? text : text.substring(sel.from, sel.to)).trim();
		if (q === "" || this.running.peek()) return;
		this.running(true);
		this.resultFailed(false);
		this.resultNote(sel.empty() ? "Running…" : "Running the selection…");
		const t0 = Date.now();
		this.db.records(q).then(recs => {
			this.running(false);
			const ms = Date.now() - t0;
			this.resultRows = recs;
			this.resultKeys = recs.length > 0 ? Object.keys(recs[0]) : [];
			this.results.columns = this.resultKeys.map(k => new GridColumn(k, 160, numeric(recs, k) ? RIGHT : LEFT));
			this.results.rowCount = recs.length;
			this.results.reset();
			this.resultNote(recs.length === 0 ? `No rows · ${ms} ms` : `${format.count(recs.length)} ${recs.length === 1 ? "row" : "rows"} · ${ms} ms`);
		}, e => {
			this.running(false);
			this.resultFailed(true);
			this.resultNote(message(e));
		});
	}
}

// (a column's width at first, by its kind)
function width(c: Column): number {
	if (c.mode === "timestamp" || c.mode === "timestamp_ms") return 168;
	if (c.mode === "boolean") return 96;
	if (c.numeric) return c.primary ? 132 : 120;
	if (c.type.toLowerCase().includes("json") || c.mode === "json") return 260;
	if (c.values.length > 0) return 150;
	return 200;
}

// (a result's column of numbers: its first values all numbers)
function numeric(recs: Record<string, unknown>[], k: string): boolean {
	let seen = 0;
	for (const r of recs) {
		const v = r[k];
		if (v === null || v === undefined) continue;
		if (typeof v !== "number") return false;
		if (++seen > 20) break;
	}
	return seen > 0;
}

function short(s: string): string {
	return s.length > 24 ? s.substring(0, 23) + "…" : s;
}

function singular(name: string): string {
	return name.endsWith("ies") ? name.substring(0, name.length - 3) + "y" : name.endsWith("s") ? name.substring(0, name.length - 1) : name;
}

// (a shortcut's label: Command on a Mac, else Control)
export let mac = false;
export function primary(key: string): string {
	return (mac ? "⌘" : "Ctrl+") + key;
}
export function setMac(on: boolean) {
	mac = on;
}
