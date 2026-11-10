package tables;

import haxe.Exception;
import helder.async.Async;
import helder.ui.widgets.DataGrid;

// a table's rows as the grid shows them: those matching the filter, in
// the sort's order, fetched a page at a time a page before they come into
// view (a small table whole); a new
// filter or order fetched in the background (the count and the pages in
// view) and shown all at once, the rows before it shown until then; the
// changes made to them (cells set, rows added and deleted) kept until
// saved in one transaction, or discarded, each undone in turn (undo)
class Rows {
	public static inline var PAGE = 200;
	// (a table this small fetched whole when first shown)
	static inline var WHOLE = 1000;

	public final table:Table;
	final db:Drizzle;
	final sql:Sql;

	// a WHERE clause's text, the column sorted by (-1: none) and whether descending: those shown
	public var where(default, null) = "";
	public var sortCol(default, null) = -1;
	public var sortDown(default, null) = false;
	// the rows matching (-1: not counted yet), the last query's time (seconds)
	public var count(default, null) = -1;
	public var took(default, null) = 0.0;

	// something shown changed: the grid drawn again
	public var onChange:Null<Void->Void> = null;
	// a query failed
	public var onError:Null<String->Void> = null;
	// rows from the top shown (a new filter or order): the grid back to its top, as they land
	public var onTop:Null<Void->Void> = null;

	var pages = new Map<Int, Array<Array<Dynamic>>>();
	var asked = new Map<Int, Bool>();
	// (bumped when a reload starts and when it lands: pages fetched for rows no longer shown dropped)
	var generation = 0;
	// (the rows the grid last showed: what a reload fetches before it shows anything)
	var shownFirst = 0;
	var shownEnd = 0;

	// the changes: cells by row key, rows deleted by key, rows added (their cells set)
	final edits = new Map<String, Edit>();
	final deleted = new Map<String, Array<Dynamic>>();
	public final added:Array<Map<Int, Dynamic>> = [];
	// (the changes as they were before each change: undo's)
	final undos:Array<{edits:Map<String, Edit>, deleted:Map<String, Array<Dynamic>>, added:Array<Map<Int, Dynamic>>}> = [];
	// (inside a batch: one undo for all of it)
	var batching = false;
	// where the grid was (scroll, cursor) when another table was opened
	public var view:Null<{top:Float, left:Float, row:Int, col:Int}> = null;

	public function new(table:Table, db:Drizzle, sql:Sql) {
		this.table = table;
		this.db = db;
		this.sql = sql;
	}

	// the rows shown: those matching and those added
	public var length(get, never):Int;

	function get_length():Int
		return (count < 0 ? 0 : count) + added.length;

	// the rows for a filter and an order: counted, the pages of the rows in
	// view (top: the first) fetched, then shown (until then, those shown before)
	@:coroutine public function reload(where:String, sortCol:Int, sortDown:Bool, top = false) {
		var g = ++generation;
		var t0 = haxe.Timer.stamp();
		var n = db.rows(sql.count(table, where));
		if (g != generation) return;
		var total = n.length > 0 ? Std.int(Std.parseFloat(Std.string(n[0][0]))) : 0;
		var order = orderOf(sortCol, sortDown);
		var p0 = Std.int(shownFirst / PAGE), p1 = Std.int(Math.max(0, Math.min(total - 1, shownEnd - 1)) / PAGE);
		if (p0 > p1) p0 = p1;
		if (top) p0 = p1 = 0;
		var fresh = new Map<Int, Array<Array<Dynamic>>>();
		for (p in p0...p1 + 1) {
			fresh.set(p, db.rows(sql.select(table, where, order, PAGE, p * PAGE)));
			if (g != generation) return;
		}
		generation++;
		this.where = where;
		this.sortCol = sortCol;
		this.sortDown = sortDown;
		count = total;
		pages = fresh;
		asked = [for (p in fresh.keys()) p => true];
		took = haxe.Timer.stamp() - t0;
		if (top && onTop != null) onTop();
		changed();
	}

	function orderOf(col:Int, down:Bool):String {
		if (col >= 0) return sql.name(table.columns[col].name) + (down ? " DESC" : " ASC");
		// (a stable order for paging: the key's)
		return [for (k in table.key) sql.name(table.columns[k].name)].join(", ");
	}

	// the rows first to before end in view: their pages fetched (a page more on each side)
	public function want(first:Int, end:Int) {
		shownFirst = first;
		shownEnd = end;
		if (count <= 0) return;
		var last = end < count ? end : count;
		// (a page ahead each way, five screens or so: scrolling, rows are in before they show; a small table whole)
		var ahead = count <= WHOLE ? count : PAGE;
		var p0 = Std.int(Math.max(0, first - ahead) / PAGE), p1 = Std.int(Math.max(0, Math.min(count - 1, last + ahead)) / PAGE);
		var g = generation, w = where, order = orderOf(sortCol, sortDown);
		for (p in p0...p1 + 1) {
			if (asked.exists(p)) continue;
			asked.set(p, true);
			var into = pages;
			Async.launch(_ -> db.rows(sql.select(table, w, order, PAGE, p * PAGE))).onCompletion((rows, e) -> {
				if (g != generation) return;
				if (e != null) {
					asked.remove(p);
					if (onError != null) onError(message(e));
					return;
				}
				into.set(p, rows);
				changed();
			});
		}
	}

	inline function changed()
		if (onChange != null) onChange();

	// a row's values as fetched (null: not here yet, or an added row)
	public function row(i:Int):Null<Array<Dynamic>> {
		if (count < 0 || i >= count) return null;
		var p = pages.get(Std.int(i / PAGE));
		return p == null ? null : p[i % PAGE];
	}

	// (a row's key: its key columns' values as JSON)
	function keyOf(r:Array<Dynamic>):String
		return Json.stringify([for (k in table.key) r[k]]);

	// a cell's value now: as changed, else as fetched
	public function value(i:Int, col:Int):Dynamic {
		if (count >= 0 && i >= count) return added[i - count].get(col);
		var r = row(i);
		if (r == null) return null;
		var e = edits.get(keyOf(r));
		return e != null && e.cells.exists(col) ? e.cells.get(col) : r[col];
	}

	public function text(i:Int, col:Int):Null<String>
		return Format.text(table.columns[col], value(i, col));

	// a cell's flags (col -1: its row's): DataGrid's
	public function flags(i:Int, col:Int):Int {
		if (count >= 0 && i >= count) {
			if (col < 0) return DataGrid.ADDED;
			var a = added[i - count], c = table.columns[col];
			// (not set: the column's default, a key the database gives)
			if (!a.exists(col)) return c.defaultValue != null || c.primary ? DataGrid.DEFAULT : DataGrid.NULL;
			return a.get(col) == null ? DataGrid.NULL : 0;
		}
		var r = row(i);
		if (r == null) return col < 0 ? 0 : DataGrid.LOADING;
		var k = keyOf(r);
		if (col < 0) return deleted.exists(k) ? DataGrid.DELETED : 0;
		var e = edits.get(k), f = 0;
		if (e != null && e.cells.exists(col)) f |= DataGrid.EDITED;
		if (value(i, col) == null) f |= DataGrid.NULL else if (table.reference(col) != null) f |= DataGrid.LINK;
		return f;
	}

	// a cell set (as typed: an error when it is not the column's kind)
	public function set(i:Int, col:Int, v:Dynamic) {
		if (table.readOnly) throw new Exception(table.view ? "A view can't be edited" : "This table has no primary key, so its rows can't be edited");
		keep();
		if (count >= 0 && i >= count) {
			added[i - count].set(col, v);
			changed();
			return;
		}
		var r = row(i);
		if (r == null) return;
		var k = keyOf(r);
		var e = edits.get(k);
		if (e == null) edits.set(k, e = {key: [for (c in table.key) r[c]], cells: new Map()});
		// (back to what it was: no change)
		if (same(r[col], v)) e.cells.remove(col) else e.cells.set(col, v);
		if (!e.cells.keys().hasNext()) edits.remove(k);
		changed();
	}

	static function same(a:Dynamic, b:Dynamic):Bool
		return a == b || a != null && b != null && Json.stringify(a) == Json.stringify(b);

	// a new row, at the end: its index
	public function add():Int {
		if (table.readOnly) throw new Exception(table.view ? "A view can't be edited" : "This table has no primary key, so rows can't be added here");
		keep();
		added.push(new Map());
		changed();
		return length - 1;
	}

	// rows deleted (added ones taken out; deleted ones again: kept)
	public function delete(rows:Array<Int>) {
		if (table.readOnly) throw new Exception(table.view ? "A view can't be edited" : "This table has no primary key, so its rows can't be deleted");
		keep();
		var gone = [];
		for (i in rows) {
			if (count >= 0 && i >= count) {
				gone.push(i - count);
				continue;
			}
			var r = row(i);
			if (r == null) continue;
			var k = keyOf(r);
			if (deleted.exists(k)) deleted.remove(k) else deleted.set(k, [for (c in table.key) r[c]]);
		}
		gone.sort((a, b) -> b - a);
		for (k in gone)
			added.splice(k, 1);
		changed();
	}

	public function changes():Int {
		var n = added.length;
		for (_ in deleted)
			n++;
		for (e in edits)
			for (_ in e.cells)
				n++;
		return n;
	}

	public function discard() {
		keep();
		edits.clear();
		deleted.clear();
		added.resize(0);
		changed();
	}

	// (the changes now, kept for undo)
	function keep() {
		if (batching) return;
		undos.push({
			edits: [for (k => e in edits) k => {key: e.key, cells: e.cells.copy()}],
			deleted: deleted.copy(),
			added: [for (a in added) a.copy()]
		});
		if (undos.length > 200) undos.shift();
	}

	// several changes as one (one undo)
	public function batch(f:Void->Void) {
		keep();
		batching = true;
		try f() catch (e:Dynamic) {
			batching = false;
			throw e;
		}
		batching = false;
	}

	// the last change undone: whether there was one
	public function undo():Bool {
		var u = undos.pop();
		if (u == null) return false;
		edits.clear();
		for (k => e in u.edits)
			edits.set(k, e);
		deleted.clear();
		for (k => d in u.deleted)
			deleted.set(k, d);
		added.resize(0);
		for (a in u.added)
			added.push(a);
		changed();
		return true;
	}

	// a cell as fetched again (its change dropped)
	public function revert(i:Int, col:Int) {
		var r = row(i);
		if (r == null) return;
		var k = keyOf(r), e = edits.get(k);
		if (e == null || !e.cells.exists(col)) return;
		keep();
		e.cells.remove(col);
		if (!e.cells.keys().hasNext()) edits.remove(k);
		changed();
	}

	public function edited(i:Int, col:Int):Bool
		return flags(i, col) & DataGrid.EDITED != 0;

	// a row's values by column, in order (JSON's)
	public function record(i:Int):Json.Record {
		var o = new Json.Record();
		for (c in 0...table.columns.length)
			o.set(table.columns[c].name, value(i, c));
		return o;
	}

	// the changes in one transaction (deleted rows' edits dropped), then the rows again
	@:coroutine public function save() {
		var statements = [];
		for (k => e in edits) {
			if (deleted.exists(k)) continue;
			var cols = [for (c in e.cells.keys()) c];
			cols.sort((a, b) -> a - b);
			statements.push(sql.update(table, e.key, cols, [for (c in cols) e.cells.get(c)]));
		}
		for (key in deleted)
			statements.push(sql.delete(table, key));
		for (a in added) {
			var cols = [for (c in a.keys()) c];
			cols.sort((a, b) -> a - b);
			statements.push(sql.insert(table, cols, [for (c in cols) a.get(c)]));
		}
		if (statements.length == 0) return;
		db.transaction(statements);
		undos.resize(0);
		edits.clear();
		deleted.clear();
		added.resize(0);
		reload(where, sortCol, sortDown);
	}

	public static function message(e:Dynamic):String
		return e is Exception ? (e : Exception).message : Std.string(e);
}

typedef Edit = {key:Array<Dynamic>, cells:Map<Int, Dynamic>}
