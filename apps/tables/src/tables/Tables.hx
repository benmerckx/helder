package tables;

import haxe.Exception;
import helder.async.Async;
import helder.ui.widgets.DataGrid;
import helder.ui.widgets.GridColumn;
import helder.ui.widgets.Theme;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import tables.Drizzle.Relation;
import tables.Drizzle.Setup;
import tables.Json.Record;
import tables.Table.Column;

// The app's state: the server it talks to (connecting until it answers,
// tried again every two seconds), the database's tables, the one open
// (its rows in the grid, a filter and a sort, columns hidden, its changes
// until saved), the row panel, its structure, the SQL console and its
// results; where you came from (Back); what the status bar says
class Tables {
	public final url:String;
	// "connecting", "ready", "offline"
	public final state = signal("connecting");
	public final setup:Signal<Null<Setup>> = signal(null);
	public final tables:Signal<Array<Table>> = signal([]);
	public final current:Signal<Null<Table>> = signal(null);
	// the table being opened: its rows on their way, the one before shown until they are in
	public final opening:Signal<Null<Table>> = signal(null);
	// "data", "structure", "sql"
	public final mode = signal("data");
	// the sidebar's search, the filter as typed and as applied, whether it failed
	public final search = signal("");
	public final filter = signal("");
	public final applied = signal("");
	public final filterFailed = signal(false);
	// the open table's rows matching, its changes, the last query's time
	public final count = signal(-1);
	public final changes = signal(0);
	public final took = signal(0.0);
	// the cursor's cell, as the status bar says it
	public final cell = signal("");
	// a message for a moment (an error, "Saved"), and whether it is an error
	public final note = signal("");
	public final failed = signal(false);
	public final saving = signal(false);
	// a menu: where (window pixels), how wide at least, its items
	public final menu:Signal<Null<Popup>> = signal(null);
	// the row panel: shown, and bumped when what it shows changed
	public final panel = signal(false);
	public final version = signal(0);
	// columns hidden, by table
	public final hidden:Signal<Map<String, Array<String>>> = signal(new Map());
	// the SQL console's text, its result's note, its state
	public final query = signal("");
	public final resultNote = signal("");
	public final resultFailed = signal(false);
	public final running = signal(false);
	// "system", "light" or "dark" (kept between runs)
	public final appearance:Signal<String>;
	public final history:Array<{table:String, where:String}> = [];
	public final canBack = signal(false);

	public final grid = new DataGrid("rows");
	public final structure = new DataGrid("structure");
	public final results = new DataGrid("results");
	public final editor = new helder.ui.code.CodeEditor("", "query.sql");

	var db:Drizzle;
	var sql = new Sql("sqlite");
	var rows:Null<Rows> = null;
	// (the grid's columns: the table's they show)
	var cols:Array<Int> = [];
	final opened = new Map<String, Rows>();
	var resultRows:Array<Record> = [];
	var resultKeys:Array<String> = [];
	var noteId = 0;
	final store = helder.os.Store.open("tables");

	public function new(url:String) {
		this.url = url;
		appearance = signal(store.get("appearance") ?? "system");
		db = new Drizzle(url);
		for (g in [grid, structure, results]) {
			g.titleFamily = Theme.UI;
			g.style.fontFamily = Theme.CODE;
			g.style.fontSize = Theme.BODY;
			g.rowHeight = 28;
			g.headerHeight = 32;
		}
		grid.semantics.label = "Rows";
		grid.text = (r, c) -> rows == null ? "" : rows.text(r, cols[c]);
		grid.flags = (r, c) -> rows == null ? 0 : rows.flags(r, c < 0 ? -1 : cols[c]);
		grid.onWindow = (a, b) -> if (rows != null) rows.want(a, b);
		grid.onSort = c -> sortBy(cols[c]);
		grid.onEdit = (r, c, typed) -> edit(r, c, typed);
		grid.onCommit = (r, c, t) -> setText(r, cols[c], t);
		grid.onClear = clearCells;
		grid.onSelect = () -> {
			describe();
			bump();
		};
		grid.onContext = (r, c, x, y) -> menu({x: x, y: y, items: items(r, c)});
		grid.onHeaderContext = (c, x, y) -> menu({x: x, y: y, items: headerItems(c)});
		grid.onLink = (r, c) -> {
			var t = rows?.table, v = rows?.value(r, cols[c]);
			var ref = t?.reference(cols[c]);
			if (ref != null && v != null) follow(ref, v);
		};
		grid.onPaste = paste;
		structure.readOnly = true;
		structure.semantics.label = "Columns";
		results.readOnly = true;
		results.semantics.label = "Results";
		editor.view.fontFamily = Theme.CODE;
		editor.view.fontSize = Theme.BODY;
		editor.view.lineHeight = 20;
		editor.onChange = _ -> query(editor.text);
		editor.complete = (text, caret) -> Complete.at(text, caret, tables.peek(), sql);
		results.text = (r, c) -> {
			var v = resultRows[r]?.get(resultKeys[c]);
			v == null ? null : Json.text(v);
		};
	}

	// dark: the appearance chosen, or the system's
	public function dark():Bool {
		var a = appearance();
		return a == "system" ? helder.ui.draw.UiWindow.dark() : a == "dark";
	}

	public function appear(kind:String) {
		appearance(kind);
		store.set("appearance", kind);
	}

	inline function bump()
		version(version.peek() + 1);

	// ---- the server

	public function start()
		Async.launch(_ -> connect());

	@:coroutine function connect() {
		while (true) {
			try {
				var s = db.init();
				if (s.version != Drizzle.VERSION) say('drizzle-kit studio speaks ${s.version}, this was made for ${Drizzle.VERSION}: some things may not work', true);
				sql = new Sql(s.dialect);
				var list = Schema.load(db, s, sql);
				setup(s);
				tables(list);
				state("ready");
				var first = list.filter(t -> !t.view)[0] ?? list[0];
				if (first != null && current.peek() == null) open(first);
				if (query.peek() == "" && first != null) {
					// (the signal's write lands later: the editor given the text itself)
					var q = 'SELECT * FROM ${sql.table(first)} LIMIT 100';
					query(q);
					editor.text = q;
				}
				return;
			} catch (e:Exception) {
				state("offline");
				Async.delay(2);
			}
		}
	}

	public var dialect(get, never):String;

	function get_dialect():String
		return setup.peek()?.dialect ?? "";

	// ---- a table

	// a table open, filtered (its last filter: where is null), Back to the
	// one before it; a table not seen yet (or another filter) shown once its rows are in
	public function open(t:Table, ?where:String, remember = true) {
		menu(null);
		var r = opened.get(t.id);
		if (r == null) {
			r = new Rows(t, db, sql);
			opened.set(t.id, r);
		}
		var w = where ?? r.where;
		if (r.count < 0 || w != r.where) {
			opening(t);
			var rows = r;
			Async.launch(_ -> rows.reload(w, rows.sortCol, rows.sortDown)).onCompletion((_, e) -> {
				if (opening.peek() != t) return;
				opening(null);
				show(t, rows, w, remember);
				if (e != null) {
					filterFailed(w != "");
					say(Rows.message(e), true);
				}
			});
			return;
		}
		opening(null);
		show(t, r, w, remember);
		// (its rows fetched again, those it had shown until they are in)
		load();
	}

	function show(t:Table, r:Rows, w:String, remember:Bool) {
		var was = current.peek();
		if (remember && was != null && (was != t || w != applied.peek())) {
			history.push({table: was.id, where: applied.peek()});
			canBack(true);
		}
		// (where the grid was, kept with the table left)
		if (rows != null && rows.table != t)
			rows.view = {top: grid.scrollTop, left: grid.scrollLeft, row: grid.cursorRow, col: grid.cursorCol};
		var same = rows == r;
		rows = r;
		r.onChange = () -> {
			if (rows != r) return;
			grid.rowCount = r.length;
			grid.refresh();
			count(r.count);
			changes(r.changes());
			took(r.took);
			describe();
			bump();
		};
		r.onError = e -> say(e, true);
		r.onTop = () -> if (rows == r) {
			grid.scrollTo(grid.scrollLeft, 0);
			grid.moveTo(0, grid.cursorCol);
		};
		grid.readOnly = t.readOnly;
		showColumns(t);
		grid.rowCount = r.length;
		if (!same && r.view != null && w == r.where) grid.restore(r.view.top, r.view.left, r.view.row, r.view.col) else grid.reset();
		current(t);
		filter(w);
		applied(w);
		filterFailed(false);
		count(r.count);
		changes(r.changes());
		showStructure(t);
		bump();
		if (mode.peek() != "sql" && grid.ui != null) grid.focus(false);
	}

	// (the grid's columns: the table's not hidden)
	// (hidden: the map just written, as a signal's write is read only once the graph has taken it)
	function showColumns(t:Table, ?hidden:Map<String, Array<String>>) {
		var off = (hidden ?? this.hidden.peek()).get(t.id) ?? [];
		cols = [for (k in 0...t.columns.length) if (off.indexOf(t.columns[k].name) < 0) k];
		grid.columns = [
			for (k in cols) {
				var c = t.columns[k];
				new GridColumn(c.name, width(c), c.numeric ? Right : Left, c.detail());
			}
		];
		var r = rows;
		grid.sortColumn = r == null ? -1 : cols.indexOf(r.sortCol);
		grid.sortDown = r != null && r.sortDown;
	}

	// (a column's width at first, by its kind)
	static function width(c:Column):Float {
		if (c.mode == "timestamp" || c.mode == "timestamp_ms") return 168;
		if (c.mode == "boolean") return 96;
		if (c.numeric) return c.primary ? 132 : 120;
		var t = c.type.toLowerCase();
		if (t.indexOf("json") >= 0 || c.mode == "json") return 260;
		if (c.values.length > 0) return 150;
		return 200;
	}

	// the open table's rows fetched again (top: a new filter, shown from the top), in the order the grid shows
	function load(top = false) {
		var r = rows;
		if (r == null) return;
		var s = sorting();
		Async.launch(_ -> r.reload(applied.peek(), s.col, s.down, top)).onCompletion((_, e) -> {
			if (rows != r) return;
			filterFailed(e != null && applied.peek() != "");
			if (e != null) say(Rows.message(e), true);
		});
	}

	public function refresh()
		load();

	// the filter as typed applied
	public function applyFilter() {
		if (current.peek() == null) return;
		applied(StringTools.trim(filter.peek()));
		load(true);
	}

	public function clearFilter() {
		filter("");
		applyFilter();
	}

	// a filter set and applied
	public function filterBy(where:String) {
		filter(where);
		applied(where);
		load(true);
	}

	// a column's title pressed: sorted by it, ascending, descending, then not
	function sortBy(col:Int) {
		var r = rows;
		if (r == null) return;
		// (from the arrow shown: a sort still on its way counts)
		var s = sorting();
		var next = s.col != col ? {col: col, down: false} : !s.down ? {col: col, down: true} : {col: -1, down: false};
		sort(next.col, next.down);
	}

	// the order the grid shows (a sort asked for and not in yet: that one)
	function sorting():{col:Int, down:Bool}
		return {col: grid.sortColumn >= 0 && grid.sortColumn < cols.length ? cols[grid.sortColumn] : -1, down: grid.sortDown};

	public function sort(col:Int, down:Bool) {
		var r = rows;
		if (r == null) return;
		grid.sortColumn = cols.indexOf(col);
		grid.sortDown = down;
		Async.launch(_ -> r.reload(applied.peek(), col, down, true)).onCompletion((_, e) -> if (e != null) say(Rows.message(e), true));
	}

	public function back() {
		var h = history.pop();
		canBack(history.length > 0);
		if (h == null) return;
		var t = tables.peek().filter(t -> t.id == h.table)[0];
		if (t != null) open(t, h.where, false);
	}

	// whether a table has changes not saved
	public function pending(t:Table):Bool {
		changes();
		var r = opened.get(t.id);
		return r != null && r.changes() > 0;
	}

	// ---- columns

	public function hide(col:Int) {
		var t = current.peek();
		if (t == null || cols.length <= 1) return;
		var m = hidden.peek().copy(), off = (m.get(t.id) ?? []).copy();
		off.push(t.columns[col].name);
		m.set(t.id, off);
		hidden(m);
		var at = grid.cursorCol;
		showColumns(t, m);
		grid.moveTo(grid.cursorRow, at < cols.length ? at : cols.length - 1);
	}

	public function showAll() {
		var t = current.peek();
		if (t == null) return;
		var m = hidden.peek().copy();
		m.remove(t.id);
		hidden(m);
		showColumns(t, m);
		grid.refresh();
	}

	// ---- changes

	// a cell edited: a boolean toggled, an enum's value picked, the rest typed in the grid's editor
	function edit(row:Int, c:Int, typed:Null<String>) {
		var r = rows;
		if (r == null) return;
		var col = r.table.columns[cols[c]];
		var plain = typed == null || typed == " ";
		if (col.mode == "boolean" && plain) {
			var v:Dynamic = r.value(row, cols[c]);
			var on = v == true || v == 1;
			set(row, cols[c], !on);
			return;
		}
		if (col.values.length > 0 && plain) {
			pick(row, c);
			return;
		}
		grid.edit(row, c, typed);
	}

	// (an enum's values in a menu under its cell)
	function pick(row:Int, c:Int) {
		var r = rows;
		if (r == null) return;
		var col = r.table.columns[cols[c]], now = r.value(row, cols[c]);
		var items:Array<Entry> = [
			for (v in col.values)
				{label: v, on: now == v, run: () -> set(row, cols[c], v)}
		];
		if (col.nullable) items.push({label: "NULL", on: now == null, muted: true, run: () -> set(row, cols[c], null)});
		var b = grid.cellBounds(row, c);
		menu({x: b.x, y: b.y + b.height + 2, width: b.width, items: items});
	}

	function set(row:Int, col:Int, v:Dynamic) {
		var r = rows;
		if (r == null) return;
		try r.set(row, col, v) catch (e:Exception) say(e.message, true);
	}

	// a cell set from text, as the column takes it
	public function setText(row:Int, col:Int, text:String) {
		var r = rows;
		if (r == null) return;
		try r.set(row, col, Format.parse(r.table.columns[col], text)) catch (e:Dynamic) say(Rows.message(e), true);
	}

	public function addRow() {
		var r = rows;
		if (r == null) return;
		try {
			var i = r.add();
			// (the first column the database does not fill: typed into at once)
			var first = 0;
			for (k in 0...cols.length)
				if (!r.table.columns[cols[k]].primary) {
					first = k;
					break;
				}
			grid.moveTo(i, first);
			grid.focus(false);
			var col = r.table.columns[cols[first]];
			if (col.mode != "boolean") edit(i, first, null);
		} catch (e:Exception) say(e.message, true);
	}

	public function deleteRows() {
		var r = rows;
		if (r == null) return;
		var range = grid.range();
		try r.delete([for (i in range.top...range.bottom + 1) i]) catch (e:Exception) say(e.message, true);
	}

	function clearCells() {
		var r = rows;
		if (r == null) return;
		var range = grid.range();
		if (grid.wholeRows) {
			deleteRows();
			return;
		}
		try {
			for (c in range.left...range.right + 1) {
				var col = r.table.columns[cols[c]];
				if (!col.nullable) throw new Exception('${col.name} can\'t be NULL');
			}
			r.batch(() -> for (i in range.top...range.bottom + 1)
				for (c in range.left...range.right + 1)
					r.set(i, cols[c], null));
		} catch (e:Exception) say(e.message, true);
	}

	// tab separated text pasted from the selection's top left (one value: into every selected cell)
	function paste(text:String) {
		var r = rows;
		if (r == null) return;
		var lines = StringTools.replace(text, "\r\n", "\n").split("\n");
		if (lines.length > 1 && lines[lines.length - 1] == "") lines.pop();
		var grid = [for (l in lines) l.split("\t")];
		var range = this.grid.range();
		var one = grid.length == 1 && grid[0].length == 1;
		var bottom = one ? range.bottom : Std.int(Math.min(r.length - 1, range.top + grid.length - 1));
		var right = one ? range.right : Std.int(Math.min(cols.length - 1, range.left + grid[0].length - 1));
		try r.batch(() -> for (i in range.top...bottom + 1)
			for (c in range.left...right + 1) {
				var t = one ? grid[0][0] : grid[i - range.top][c - range.left];
				if (t == null) continue;
				var col = r.table.columns[cols[c]];
				r.set(i, cols[c], Format.parse(col, t));
			}) catch (e:Dynamic) say(Rows.message(e), true);
	}

	public function undo() {
		if (rows != null && !rows.undo()) say("Nothing to undo");
	}

	public function discard() {
		if (rows != null) rows.discard();
	}

	public function save() {
		var r = rows;
		if (r == null || r.changes() == 0 || saving.peek()) return;
		var n = r.changes();
		saving(true);
		Async.launch(_ -> r.save()).onCompletion((_, e) -> {
			saving(false);
			if (e != null) say("Not saved: " + Rows.message(e), true) else {
				say(n == 1 ? "Saved 1 change" : 'Saved $n changes');
				// (rows added or deleted: the sidebar's counts again)
				Async.launch(_ -> {
					var c = db.rows(sql.count(r.table, ""));
					r.table.count = c.length > 0 ? Std.int(Std.parseFloat(Std.string(c[0][0]))) : r.table.count;
					tables(tables.peek().copy());
				});
			}
		});
	}

	// ---- the row panel

	// the cursor's row (-1: none)
	public function panelRow():Int {
		version();
		var r = rows;
		return r == null || r.length == 0 ? -1 : grid.cursorRow;
	}

	public function fieldText(col:Int):Null<String> {
		version();
		var r = rows, row = panelRow();
		return r == null || row < 0 ? null : r.text(row, col);
	}

	public function fieldFlags(col:Int):Int {
		version();
		var r = rows, row = panelRow();
		return r == null || row < 0 ? 0 : r.flags(row, col);
	}

	public function setField(col:Int, text:String) {
		var row = panelRow();
		if (row < 0) return;
		var now = fieldText(col);
		if (now == text || now == null && text == "") return;
		setText(row, col, text);
	}

	public function setFieldNull(col:Int) {
		var row = panelRow();
		if (row >= 0) set(row, col, null);
	}

	public function rowValue(col:Int):Dynamic {
		var row = panelRow();
		return rows == null || row < 0 ? null : rows.value(row, col);
	}

	// ---- the status bar

	// a message, gone after a while
	public function say(text:String, error = false) {
		var id = ++noteId;
		note(text);
		failed(error);
		haxe.Timer.delay(() -> if (noteId == id) note(""), error ? 8000 : 3000);
	}

	function describe() {
		var r = rows;
		if (r == null || cols.length == 0 || r.length == 0) {
			cell("");
			return;
		}
		var range = grid.range();
		var rowsSel = range.bottom - range.top + 1, n = range.right - range.left + 1;
		if (rowsSel > 1 || n > 1) {
			cell(grid.wholeRows ? '${Format.count(rowsSel)} rows selected' : '${Format.count(rowsSel * n)} cells selected');
			return;
		}
		var c = r.table.columns[cols[grid.cursorCol]];
		cell('${c.name} · row ${Format.count(grid.cursorRow + 1)}');
	}

	// ---- menus

	// a cell's: its relations (the row it refers to, the rows referring to
	// it), filters by its value, copying, NULL, its change undone, deleting
	function items(row:Int, c:Int):Array<Entry> {
		var r = rows;
		if (r == null) return [];
		var t = r.table, col = cols[c], out:Array<Entry> = [];
		var column = t.columns[col], v = r.value(row, col);
		var ref = t.reference(col);
		if (ref != null && v != null) out.push({label: 'Open ${singular(ref.refTable)} ${Format.text(column, v)}', icon: Icons.open, run: () -> follow(ref, v)});
		for (rel in t.relations) {
			if (rel.kind != "many" || rel.columns.length != 1) continue;
			var k = t.column(rel.columns[0]);
			var key = k < 0 ? null : r.value(row, k);
			if (key != null) out.push({label: 'Show ${rel.name}', detail: rel.refTable, icon: Icons.link, run: () -> follow(rel, key)});
		}
		if (out.length > 0) out.push(Entry.LINE);
		var name = sql.name(column.name);
		if (row < (r.count < 0 ? 0 : r.count)) {
			var shown = v == null ? "NULL" : short(Format.text(column, v));
			out.push({label: 'Only $shown', detail: "filter", icon: Icons.filter, run: () -> filterBy(v == null ? '$name IS NULL' : '$name = ${sql.literal(v)}')});
			out.push({label: 'Without $shown', detail: "filter", run: () -> filterBy(v == null ? '$name IS NOT NULL' : '$name <> ${sql.literal(v)}')});
			out.push(Entry.LINE);
		}
		var mac = helder.ui.actions.Keymap.mac;
		out.push({label: "Copy", detail: mac ? "⌘C" : "Ctrl+C", run: () -> if (grid.ui != null) grid.ui.clipboard.write(grid.selectionText())});
		out.push({label: "Copy row as JSON", run: () -> if (grid.ui != null) grid.ui.clipboard.write(Json.stringify(r.record(row)))});
		if (!t.readOnly) {
			out.push({label: "Paste", detail: mac ? "⌘V" : "Ctrl+V", run: () -> if (grid.ui != null) grid.ui.clipboard.read(s -> if (s != null && s != "") paste(s))});
			out.push(Entry.LINE);
			if (r.edited(row, col)) out.push({label: "Revert change", icon: Icons.undo, run: () -> r.revert(row, col)});
			out.push({label: "Set to NULL", disabled: !column.nullable, run: clearCells});
			out.push({label: grid.wholeRows && grid.range().bottom > grid.range().top ? "Delete rows" : "Delete row", icon: Icons.trash, run: () -> {
				if (!grid.wholeRows) grid.moveTo(row, c, false, true);
				deleteRows();
			}});
		}
		return out;
	}

	static function short(s:String):String
		return s.length > 24 ? s.substr(0, 23) + "…" : s;

	// a column's title's: sorting, filtering, hiding
	function headerItems(c:Int):Array<Entry> {
		var r = rows, t = current.peek();
		if (r == null || t == null) return [];
		var col = cols[c], name = sql.name(t.columns[col].name);
		var out:Array<Entry> = [
			{label: "Sort ascending", on: r.sortCol == col && !r.sortDown, run: () -> sort(col, false)},
			{label: "Sort descending", on: r.sortCol == col && r.sortDown, run: () -> sort(col, true)}
		];
		if (r.sortCol >= 0) out.push({label: "Don't sort", run: () -> sort(-1, false)});
		out.push(Entry.LINE);
		out.push({label: "Filter by this column", icon: Icons.filter, run: () -> {
			var f = StringTools.trim(filter.peek());
			filter((f == "" ? "" : f + " AND ") + '$name = ');
			Shell.focusFilter(true);
		}});
		out.push({label: "Fit width", run: () -> grid.fitColumn(c)});
		out.push({label: "Hide column", disabled: cols.length <= 1, run: () -> hide(col)});
		if (cols.length < t.columns.length) out.push({label: 'Show all columns', detail: '${t.columns.length - cols.length} hidden', run: showAll});
		return out;
	}

	static function singular(name:String):String
		return StringTools.endsWith(name, "ies") ? name.substr(0, name.length - 3) + "y" : StringTools.endsWith(name, "s") ? name.substr(0, name.length - 1) : name;

	// a relation followed: its table, filtered to the rows of the value
	public function follow(rel:Relation, v:Dynamic) {
		var t = tables.peek().filter(t -> t.name == rel.refTable && (t.schema == rel.refSchema || rel.refSchema == "public"))[0];
		if (t == null) return;
		mode("data");
		open(t, '${sql.name(rel.refColumns[0])} = ${sql.literal(v)}');
	}

	// the relations of the open table: (label, the relation, the value to follow it by) for the panel's row
	public function links():Array<{label:String, detail:String, run:Void->Void}> {
		version();
		var r = rows, row = panelRow();
		if (r == null || row < 0) return [];
		var t = r.table, out = [];
		for (rel in t.relations) {
			if (rel.columns.length != 1) continue;
			var k = t.column(rel.columns[0]);
			var v = k < 0 ? null : r.value(row, k);
			if (v == null) continue;
			out.push(rel.kind == "one" ? {label: rel.name, detail: '${rel.refTable} ${Format.text(t.columns[k], v)}', run: () -> follow(rel, v)} : {
				label: rel.name,
				detail: '${rel.refTable} where ${rel.refColumns[0]} = ${Format.text(t.columns[k], v)}',
				run: () -> follow(rel, v)
			});
		}
		return out;
	}

	// ---- the structure

	function showStructure(t:Table) {
		var list = t.columns;
		structure.columns = [
			new GridColumn("Column", 180), new GridColumn("Type", 150), new GridColumn("Null", 70), new GridColumn("Default", 200), new GridColumn("Drizzle", 120),
			new GridColumn("Values", 220), new GridColumn("References", 220)
		];
		structure.text = (r, c) -> {
			var col = list[r];
			switch c {
				case 0: col.primary ? col.name + "  (key)" : col.name;
				case 1: col.type.toLowerCase();
				case 2: col.nullable && !col.primary ? "yes" : "no";
				case 3: col.defaultValue ?? "";
				case 4: col.mode;
				case 5: col.values.join(", ");
				case _:
					var ref = t.reference(r);
					ref == null ? "" : ref.refTable + "." + ref.refColumns.join(", ");
			}
		};
		structure.rowCount = list.length;
		structure.reset();
	}

	// ---- the console

	// the query run (the selection, if there is one)
	public function run() {
		var sel = editor.model.primary;
		var text = editor.text;
		var q = StringTools.trim(sel.empty() ? text : text.substring(sel.from, sel.to));
		if (q == "" || running.peek()) return;
		running(true);
		resultFailed(false);
		resultNote(sel.empty() ? "Running…" : "Running the selection…");
		var t0 = haxe.Timer.stamp();
		Async.launch(_ -> db.records(q)).onCompletion((recs, e) -> {
			running(false);
			if (e != null) {
				resultFailed(true);
				resultNote(Rows.message(e));
				return;
			}
			var ms = Math.round((haxe.Timer.stamp() - t0) * 1000);
			resultRows = recs;
			resultKeys = recs.length > 0 ? recs[0].keys : [];
			results.columns = [for (k in resultKeys) new GridColumn(k, 160, numeric(recs, k) ? Right : Left)];
			results.rowCount = recs.length;
			results.reset();
			resultNote(recs.length == 0 ? 'No rows · $ms ms' : '${Format.count(recs.length)} ${recs.length == 1 ? "row" : "rows"} · $ms ms');
		});
	}

	// (a result's column of numbers: its first values all numbers)
	static function numeric(recs:Array<Record>, k:String):Bool {
		var seen = 0;
		for (r in recs) {
			var v = r.get(k);
			if (v == null) continue;
			if (!(v is Int || v is Float)) return false;
			if (++seen > 20) break;
		}
		return seen > 0;
	}
}

typedef Popup = {x:Float, y:Float, ?width:Float, items:Array<Entry>};

// a menu's item: its label, a quieter detail, an icon, disabled, checked (on), a separator (LINE)
@:structInit class Entry {
	public static final LINE:Entry = {label: "", line: true, run: () -> {}};

	public final label:String;
	public final detail:Null<String> = null;
	public final icon:Null<helder.ui.Svg> = null;
	public final disabled:Bool = false;
	public final on:Bool = false;
	public final muted:Bool = false;
	public final line:Bool = false;
	public final run:Void->Void;
}
