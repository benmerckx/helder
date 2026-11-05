package viewer;

import sys.FileSystem;

using StringTools;

// The images of one folder, in natural order ("img2" before "img10",
// letters without case), and the one shown: next and previous wrap, the
// neighbours by distance (what to prefetch). rescan reads the folder again
// (the watch: every second or so): the list follows what was added or
// removed, the image shown kept by name (or the one now at its place), and
// the files whose size or time changed are named (to decode again).
class FolderModel {
	public static final EXTENSIONS = ["png", "apng", "jpg", "jpeg", "jfif", "gif", "webp"];

	public var dir(default, null) = "";
	public var files(default, null):Array<String> = [];
	// the image shown (-1: none)
	public var index(default, null) = -1;

	// (each file's stamp: size and modification time)
	var stamps = new Map<String, String>();

	public function new() {}

	public var current(get, never):Null<String>;

	function get_current():Null<String>
		return index < 0 ? null : path(index);

	public var name(get, never):String;

	function get_name():String
		return index < 0 ? "" : files[index];

	public function path(i:Int):String
		return join(dir, files[i]);

	public static function join(dir:String, name:String):String
		return dir == "" ? name : dir.endsWith("/") || dir.endsWith("\\") ? dir + name : dir + "/" + name;

	public static function isImage(name:String):Bool {
		var dot = name.lastIndexOf(".");
		return dot > 0 && EXTENSIONS.contains(name.substr(dot + 1).toLowerCase());
	}

	// a file (its folder, it shown even when its extension is another's) or
	// a folder (its first image); false when neither can be read
	public function open(path:String):Bool {
		path = normalize(path);
		var isDir = try FileSystem.isDirectory(path) catch (_:Dynamic) false;
		if (isDir) {
			dir = path;
			setEntries(list(path));
			index = files.length > 0 ? 0 : -1;
			restamp();
			return true;
		}
		if (!(try FileSystem.exists(path) catch (_:Dynamic) false)) return false;
		var slash = Std.int(Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\")));
		dir = slash < 0 ? "." : slash == 0 ? "/" : path.substr(0, slash);
		var name = path.substr(slash + 1);
		var names = list(dir);
		if (!names.contains(name)) names.push(name);
		setEntries(names, name);
		restamp();
		return true;
	}

	// (each file's stamp, as the folder is now)
	function restamp() {
		stamps = new Map();
		for (f in files)
			stamps.set(f, stamp(join(dir, f)));
	}

	// the names, sorted and filtered; the one named keep shown (else the
	// one at the index shown before, else the first)
	public function setEntries(names:Array<String>, ?keep:String) {
		var before = index;
		var wanted = keep;
		files = [for (n in names) if (isImage(n) || n == wanted) n];
		files.sort(compare);
		index = wanted != null ? files.indexOf(wanted) : -1;
		if (index < 0 && files.length > 0) index = before < 0 ? 0 : Std.int(Math.min(before, files.length - 1));
	}

	// the folder read again: whether its list changed, and the files whose
	// stamp changed (to decode again)
	public function rescan():{listChanged:Bool, modified:Array<String>} {
		if (dir == "") return {listChanged: false, modified: []};
		var names = list(dir);
		var keep = index >= 0 && names.contains(files[index]) ? files[index] : null;
		var old = files.copy();
		if (keep == null && index >= 0) {
			// (the one shown is gone: the one after it in the old order, else before)
			var i = index;
			while (keep == null && ++i < old.length)
				if (names.contains(old[i])) keep = old[i];
			i = index;
			while (keep == null && --i >= 0)
				if (names.contains(old[i])) keep = old[i];
		}
		var shown = index;
		setEntries(names, keep);
		if (keep == null && files.length > 0) index = Std.int(Math.min(Math.max(shown, 0), files.length - 1));
		var modified = [];
		var next = new Map<String, String>();
		for (f in files) {
			var s = stamp(join(dir, f));
			next.set(f, s);
			if (stamps.exists(f) && stamps.get(f) != s) modified.push(join(dir, f));
		}
		stamps = next;
		return {listChanged: old.join("\n") != files.join("\n"), modified: modified};
	}

	// the next or previous (delta), wrapping; false when there is no other
	public function go(delta:Int):Bool {
		if (files.length < 2) return false;
		index = ((index + delta) % files.length + files.length) % files.length;
		return true;
	}

	public function first():Bool {
		if (files.length == 0 || index == 0) return false;
		index = 0;
		return true;
	}

	public function last():Bool {
		if (files.length == 0 || index == files.length - 1) return false;
		index = files.length - 1;
		return true;
	}

	// the indices around the one shown, nearest first (it, the next, the
	// previous, the one after the next...), at most radius away
	public function around(radius:Int):Array<Int> {
		if (index < 0) return [];
		var out = [index];
		for (d in 1...radius + 1)
			for (s in [d, -d]) {
				var i = ((index + s) % files.length + files.length) % files.length;
				if (!out.contains(i)) out.push(i);
			}
		return out;
	}

	// natural order: runs of digits by their value, the rest without case,
	// then as they are (a stable, total order)
	public static function compare(a:String, b:String):Int {
		var i = 0, j = 0;
		var la = a.toLowerCase(), lb = b.toLowerCase();
		while (i < la.length && j < lb.length) {
			var ca = la.fastCodeAt(i), cb = lb.fastCodeAt(j);
			if (digit(ca) && digit(cb)) {
				var si = i, sj = j;
				while (i < la.length && digit(la.fastCodeAt(i)))
					i++;
				while (j < lb.length && digit(lb.fastCodeAt(j)))
					j++;
				// (by value: leading zeros off, then the longer run is larger)
				var na = la.substring(si, i), nb = lb.substring(sj, j);
				var ta = trimZeros(na), tb = trimZeros(nb);
				if (ta.length != tb.length) return ta.length - tb.length;
				if (ta != tb) return ta < tb ? -1 : 1;
				if (na.length != nb.length) return na.length - nb.length;
				continue;
			}
			if (ca != cb) return ca - cb;
			i++;
			j++;
		}
		if (la.length - i != lb.length - j) return (la.length - i) - (lb.length - j);
		return a == b ? 0 : a < b ? -1 : 1;
	}

	static inline function digit(c:Int):Bool
		return c >= "0".code && c <= "9".code;

	static function trimZeros(s:String):String {
		var k = 0;
		while (k < s.length - 1 && s.fastCodeAt(k) == "0".code)
			k++;
		return s.substr(k);
	}

	static function list(dir:String):Array<String>
		return try [for (n in FileSystem.readDirectory(dir)) if (!n.startsWith(".") && !isDirectory(join(dir, n))) n] catch (_:Dynamic) [];

	static function isDirectory(p:String):Bool
		return try FileSystem.isDirectory(p) catch (_:Dynamic) false;

	static function stamp(p:String):String
		return try {
			var s = FileSystem.stat(p);
			s.size + ":" + s.mtime.getTime();
		} catch (_:Dynamic) "";

	static function normalize(p:String):String {
		while (p.length > 1 && (p.endsWith("/") || p.endsWith("\\")) && !(p.length == 3 && p.charAt(1) == ":"))
			p = p.substr(0, p.length - 1);
		return p;
	}
}
