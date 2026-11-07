package helder.compiler.service;

import sys.FileSystem;
import sys.io.File;

using StringTools;

// Whether a saved file changed only its live literals' values (helder dev:
// patched, nothing built). The build that made the running program wrote
// each source's live literals (helder.markup.Live's table, -D
// helder.literals=<dir>: <dir>/<md5 of the source>.json, their byte spans
// and forms); helder dev keeps that source (Sources), and compares a save
// with it: the text between the spans the same, each span a literal of the
// same form (a quoted string, a number, a text's run). Any other change is
// a build's. The literals' ids are the build's (their places in the source
// it was built from), so they stay the program's however a value's length
// moved what follows it.
class LiteralEdit {
	// the changes from built to now (empty: none), null when anything but a live literal changed (why: said)
	public static function diff(built:String, now:String, entries:Array<helder.markup.Live.Entry>, ?why:String->Void):Null<Array<{id:String, source:String}>> {
		var list = entries.copy();
		list.sort((a, b) -> a.start - b.start);
		var out = [], pos = 0, q = 0, last = -1;
		function fail(at:Int, what:String):Null<Array<{id:String, source:String}>> {
			if (why != null) {
				var p = helder.markup.Live.lineColumn(now, at < now.length ? at : now.length);
				why('line ${p.line}: $what');
			}
			return null;
		}
		for (e in list) {
			if (e.start < last) continue;
			var seg = built.substring(pos, e.start);
			if (now.substr(q, seg.length) != seg) return fail(firstDiff(seg, now, q), "not a live literal's value");
			q += seg.length;
			var old = built.substring(e.start, e.end), next:Null<String> = switch e.form {
				case "quoted": quoted(now, q, old.charAt(0));
				case "number": number(now, q);
				case "text": text(now, q);
				case _: now.substr(q, old.length) == old ? old : null;
			}
			if (next == null) return fail(q, 'the ${e.form} literal ${old.length > 24 ? old.substr(0, 24) + "..." : old} is no longer one');
			if (e.form == "text" && helder.markup.Syntax.Whitespace.clean(next) == null) return fail(q, "a text emptied");
			if (next != old) out.push({id: e.id, source: next});
			q += next.length;
			pos = e.end;
			last = e.end;
		}
		if (built.substr(pos) != now.substr(q)) return fail(firstDiff(built.substr(pos), now, q), "not a live literal's value");
		return out;
	}

	// (where seg and now from q first differ, in now)
	static function firstDiff(seg:String, now:String, q:Int):Int {
		var i = 0;
		while (i < seg.length && q + i < now.length && seg.charCodeAt(i) == now.charCodeAt(q + i)) i++;
		return q + i;
	}

	// a quoted string at q (the quote it had), escapes and all
	static function quoted(s:String, q:Int, quote:String):Null<String> {
		if (s.charAt(q) != quote) return null;
		var i = q + 1;
		while (i < s.length) {
			var c = s.charAt(i);
			if (c == "\\") i += 2;
			else if (c == quote) return s.substring(q, i + 1);
			else if (c == "\n") return null;
			else i++;
		}
		return null;
	}

	// a number at q: decimal, hexadecimal, a fraction, an exponent (no identifier after it)
	static function number(s:String, q:Int):Null<String> {
		var r = ~/^-?(0[xX][0-9a-fA-F_]+|[0-9][0-9_]*(\.[0-9]*)?([eE][-+]?[0-9]+)?|\.[0-9]+([eE][-+]?[0-9]+)?)/;
		var rest = s.substr(q, 64);
		if (!r.match(rest)) return null;
		var m = r.matched(0);
		var after = rest.charAt(m.length);
		if (after != "" && ~/[A-Za-z0-9_$.]/.match(after)) return null;
		return m;
	}

	// a text's raw run at q: to the next < or {
	static function text(s:String, q:Int):Null<String> {
		var i = q;
		while (i < s.length && s.charAt(i) != "<" && s.charAt(i) != "{" && s.charAt(i) != "}" && s.charAt(i) != ">") i++;
		return i == q ? null : s.substring(q, i);
	}
}

// The sources the running program was built from, with their live
// literals' tables (helder.markup.Live's, in dir): kept after each build,
// a save compared with them (LiteralEdit.diff). The patches sent since,
// by id, so that a value set back to the built one is sent too.
class Sources {
	public final dir:String;
	final built = new Map<String, {content:String, entries:Array<helder.markup.Live.Entry>}>();
	final sent = new Map<String, String>();

	public function new(dir:String)
		this.dir = dir;

	// after a build: each table's source, when it is still the content it was made of (older tables removed)
	public function update() {
		built.clear();
		sent.clear();
		if (!FileSystem.exists(dir)) return;
		var current = new Map<String, String>();
		for (f in FileSystem.readDirectory(dir)) {
			if (!f.endsWith(".json")) continue;
			var path = '$dir/$f';
			var t:Dynamic = try haxe.Json.parse(File.getContent(path)) catch (_:Dynamic) null;
			if (t == null) continue;
			var file:String = t.file, hash = f.substr(0, f.length - 5);
			var content = current.get(file);
			if (content == null) {
				content = try File.getContent(file) catch (_:Dynamic) null;
				if (content == null) continue;
				current.set(file, content);
			}
			if (haxe.crypto.Md5.encode(content) != hash) {
				// (a table of another content of the file: not the program's)
				try FileSystem.deleteFile(path) catch (_:Dynamic) {};
				continue;
			}
			built.set(file, {content: content, entries: t.entries});
		}
	}

	// whether the file has a table (its live literals known)
	public function knows(file:String):Bool
		return built.exists(file);

	// a save of file: the patches (empty: no change), null when it needs a build (why: said)
	public function patches(file:String, ?why:String->Void):Null<Array<{id:String, source:String}>> {
		var b = built.get(file);
		if (b == null) {
			if (why != null) why("no live literals known (its first build, or none in it)");
			return null;
		}
		var now = try File.getContent(file) catch (_:Dynamic) return null;
		var d = LiteralEdit.diff(b.content, now, b.entries, why);
		if (d == null) return null;
		// (against what was sent since the build: a value set back is sent too)
		var out = [];
		var changed = new Map<String, String>();
		for (c in d) changed.set(c.id, c.source);
		for (e in b.entries) {
			var was = sent.get(e.id) ?? b.content.substring(e.start, e.end);
			var is = changed.get(e.id) ?? b.content.substring(e.start, e.end);
			if (was != is) out.push({id: e.id, source: is});
		}
		return out;
	}

	// the patches the program took
	public function took(list:Array<{id:String, source:String}>)
		for (c in list) sent.set(c.id, c.source);
}
