package studio;

import helder.syntax.Document;
import helder.syntax.Scanner.Lang;
import helder.syntax.Transaction;
import helder.view.graph.Graph.*;
import sys.io.File;

// The project's files as the studio edits them: each open file's text and
// its syntax tree (helder.syntax, read again after each edit), and one
// history for every edit, whoever made it (the canvas, the inspector, the
// code view, an agent): each a helder.syntax Transaction on one file, its
// inverse the undo. Edits of one gesture (a number scrubbed, a word typed:
// the same group) merge into one entry. Files are the truth: an edit is
// written to its file at once (Studio.commit decides what the program does
// with it: a live literal's patch, or a build).
class Docs {
	final files = new Map<String, OpenFile>();
	final undos:Array<Entry> = [];
	final redos:Array<Entry> = [];
	// bumped by every edit, undo and redo (what reads files follows it)
	public final version = signal(0);
	public final canUndo = signal(false);
	public final canRedo = signal(false);
	// told after each change of a file's text: the file, the transaction (against its text before), who made it
	public var onChange:Null<(file:String, tx:Transaction, origin:String) -> Void> = null;

	public function new() {}

	// a file's current state (read from disk the first time)
	public function get(path:String):OpenFile {
		var f = files.get(path);
		if (f == null) {
			f = new OpenFile(path, File.getContent(path));
			files.set(path, f);
		}
		return f;
	}

	// an edit: tx (against the file's text now) applied, recorded (group: an
	// entry it merges with while the last entry is of that group)
	public function apply(path:String, tx:Transaction, label:String, origin:String, ?group:String) {
		if (tx.changes.length == 0) return;
		var f = get(path);
		var before = f.text;
		f.set(tx.apply(before));
		var last = undos.length > 0 ? undos[undos.length - 1] : null;
		if (group != null && last != null && last.group == group && last.file == path) {
			last.tx = last.tx.then(tx, last.before);
			last.after = f.text;
		} else undos.push({file: path, tx: tx, label: label, group: group, before: before, after: f.text});
		redos.resize(0);
		changed(path, tx, origin);
	}

	// the last edit undone (null: none), its label
	public function undo():Null<String> {
		var e = undos.pop();
		if (e == null) return null;
		var f = get(e.file);
		var back = new Transaction(e.tx.inverse.changes, null, f.text);
		f.set(e.before);
		redos.push(e);
		changed(e.file, back, "undo");
		return e.label;
	}

	public function redo():Null<String> {
		var e = redos.pop();
		if (e == null) return null;
		var f = get(e.file);
		var tx = new Transaction(e.tx.changes, null, f.text);
		f.set(e.after);
		undos.push(e);
		changed(e.file, tx, "redo");
		return e.label;
	}

	// the next edit starts an entry of its own (a gesture ended)
	public function close()
		if (undos.length > 0) undos[undos.length - 1].group = null;

	function changed(path:String, tx:Transaction, origin:String) {
		canUndo(undos.length > 0);
		canRedo(redos.length > 0);
		version(v -> v + 1);
		if (onChange != null) onChange(path, tx, origin);
	}
}

// An open file: its text and its syntax tree (read when asked)
class OpenFile {
	public final path:String;
	public var text(default, null):String;
	var parsed:Null<Document> = null;

	public function new(path:String, text:String) {
		this.path = path;
		this.text = text;
	}

	public function set(t:String) {
		text = t;
		parsed = null;
	}

	public var doc(get, never):Document;

	function get_doc():Document {
		if (parsed == null) parsed = Document.parse(text, Lang.of(path));
		return parsed;
	}

	public function save()
		File.saveContent(path, text);
}

typedef Entry = {
	file:String,
	tx:Transaction,
	label:String,
	group:Null<String>,
	// the file's text before and after it
	before:String,
	after:String,
}
