package helder.text;

import haxe.io.Bytes;

// The fonts a program can use: the system's (OpenType files found in the
// usual directories of Linux, Windows and macOS, their names read without
// loading them; in a browser, the fonts the page gives: WebFonts) and fonts
// added from bytes (add: a program may bring its own). match picks a face as CSS does: the
// family (or a generic one: sans-serif, serif, monospace, mapped to
// families common on each system), then the italic style, then the closest
// weight. Faces are loaded (parsed) when first matched.
class SystemFonts {
	static var shared:Null<SystemFonts>;

	final faces:Array<FaceInfo> = [];
	final loaded = new Map<String, FontFile>();
	var scanned = false;

	public static final GENERIC = [
		"sans-serif" => [
			"Segoe UI", "SF Pro Text", "Helvetica Neue", "Helvetica", "Arial", "DejaVu Sans", "Noto Sans", "Liberation Sans", "Cantarell", "Ubuntu", "FreeSans",
			"Verdana"
		],
		"serif" => ["Times New Roman", "Georgia", "DejaVu Serif", "Noto Serif", "Liberation Serif", "Times", "FreeSerif"],
		"monospace" => ["Consolas", "Cascadia Mono", "Menlo", "SF Mono", "DejaVu Sans Mono", "Noto Sans Mono", "Liberation Mono", "Courier New", "FreeMono"],
	];

	// fonts tried for characters the matched face lacks, in order
	public static final FALLBACK = [
		"DejaVu Sans", "Noto Sans", "Segoe UI", "Segoe UI Symbol", "Arial Unicode MS", "FreeSans", "FreeSerif"
	];

	// colour emoji fonts, each loaded when an emoji first needs it
	public static final EMOJI = ["Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji"];

	// fonts tried after those, each loaded when a character first needs it: CJK, other scripts
	public static final MORE = [
		"Noto Sans CJK SC", "Noto Sans SC", "Microsoft YaHei", "PingFang SC", "Hiragino Sans", "Yu Gothic", "Malgun Gothic", "Apple SD Gothic Neo",
		"Source Han Sans SC", "WenQuanYi Zen Hei", "WenQuanYi Micro Hei", "Droid Sans Fallback", "IPAGothic", "Noto Sans Arabic", "Noto Sans Hebrew",
		"Noto Sans Devanagari", "Noto Sans Thai"
	];

	public function new() {}

	// one set of the system's fonts for the program
	public static function get():SystemFonts {
		if (shared == null) shared = new SystemFonts();
		return shared;
	}

	// a font's bytes (every face of a collection), found before the system's
	public function add(data:Bytes):Array<FontFile> {
		var out = [];
		for (i in 0...FontFile.faceCount(data)) {
			var f = try FontFile.parse(data, i) catch (e:Dynamic) null;
			if (f == null) continue;
			var key = "added:" + f.id;
			loaded.set(key, f);
			var fi = new FaceInfo(key, i, f.family, f.subfamily, f.weight, f.italic);
			for (a in f.axes)
				if (a.tag == "wght") {
					fi.minWeight = Std.int(a.min);
					fi.maxWeight = Std.int(a.max);
				}
			faces.insert(0, fi);
			fallbackList = null;
			out.push(f);
		}
		return out;
	}

	public function addFile(path:String):Array<FontFile>
		return add(sys.io.File.getBytes(path));

	// the face closest to the request, or null when there is no font at all
	public function match(family:String, weight = 400, italic = false):Null<FontFile> {
		scan();
		var names = GENERIC.exists(family.toLowerCase()) ? GENERIC.get(family.toLowerCase()) : [family].concat(GENERIC.get("sans-serif"));
		for (name in names) {
			var f = best(name, weight, italic);
			if (f != null) return f;
		}
		// anything
		for (fi in faces) {
			var f = load(fi);
			if (f != null) return f;
		}
		return null;
	}

	// the fallback faces (regular) found on this system
	public function fallbacks():Array<FontFile> {
		if (fallbackList != null) return fallbackList;
		scan();
		var out = [];
		for (name in FALLBACK) {
			var f = best(name, 400, false);
			if (f != null && !out.contains(f)) out.push(f);
		}
		return fallbackList = out;
	}

	// (found once; fonts added later find them again)
	var fallbackList:Null<Array<FontFile>> = null;

	// the first of MORE's faces that has a character (null: none)
	public function fallbackFor(cp:Int):Null<FontFile> {
		if (moreFound.exists(cp)) return moreFound.get(cp);
		if (moreFaces == null) {
			scan();
			moreFaces = [];
			for (name in MORE) {
				var fi = pick(name, 400, false);
				if (fi != null && !moreFaces.contains(fi)) moreFaces.push(fi);
			}
		}
		var found:Null<FontFile> = null;
		for (fi in moreFaces) {
			var f = load(fi);
			if (f != null && f.glyph(cp) != 0) {
				found = f;
				break;
			}
		}
		moreFound.set(cp, found);
		return found;
	}

	var moreFaces:Null<Array<FaceInfo>> = null;

	// the first of EMOJI's faces that has a character (null: none)
	public function emojiFor(cp:Int):Null<FontFile> {
		if (emojiFound.exists(cp)) return emojiFound.get(cp);
		if (emojiFaces == null) {
			scan();
			emojiFaces = [];
			for (name in EMOJI) {
				var fi = pick(name, 400, false);
				if (fi != null && !emojiFaces.contains(fi)) emojiFaces.push(fi);
			}
		}
		var found:Null<FontFile> = null;
		for (fi in emojiFaces) {
			var f = load(fi);
			if (f != null && f.glyph(cp) != 0) {
				found = f;
				break;
			}
		}
		emojiFound.set(cp, found);
		return found;
	}

	var emojiFaces:Null<Array<FaceInfo>> = null;
	final emojiFound = new Map<Int, Null<FontFile>>();
	final moreFound = new Map<Int, Null<FontFile>>();

	// the families found, sorted
	public function families():Array<String> {
		scan();
		var m = new Map<String, Bool>();
		for (f in faces)
			m.set(f.family, true);
		var out = [for (k in m.keys()) k];
		out.sort(Reflect.compare);
		return out;
	}

	function best(name:String, weight:Int, italic:Bool):Null<FontFile> {
		var pick = pick(name, weight, italic);
		if (pick == null) return null;
		var f = load(pick);
		// (a variable face: its instance at the weight, within its range)
		if (f == null || pick.maxWeight <= pick.minWeight) return f;
		var w = weight < pick.minWeight ? pick.minWeight : weight > pick.maxWeight ? pick.maxWeight : weight;
		var key = pick.path + "#" + pick.index + "@" + w;
		if (!loaded.exists(key)) loaded.set(key, f.instance(["wght" => w]));
		return loaded.get(key);
	}

	function pick(name:String, weight:Int, italic:Bool):Null<FaceInfo> {
		var lower = name.toLowerCase();
		var pick:Null<FaceInfo> = null, score = 1 << 30;
		for (fi in faces) {
			if (fi.family.toLowerCase() != lower) continue;
			// (a variable face has every weight of its range)
			var w = fi.maxWeight > fi.minWeight ? (weight < fi.minWeight ? fi.minWeight : weight > fi.maxWeight ? fi.maxWeight : weight) : fi.weight;
			var s = (fi.italic == italic ? 0 : 10000) + Std.int(Math.abs(w - weight)) + (w > weight && weight <= 400 ? 50 : 0);
			if (s < score) {
				score = s;
				pick = fi;
			}
		}
		return pick;
	}

	function load(fi:FaceInfo):Null<FontFile> {
		var key = fi.path + "#" + fi.index;
		if (loaded.exists(fi.path)) return loaded.get(fi.path);
		if (loaded.exists(key)) return loaded.get(key);
		var f = try FontFile.parse(sys.io.File.getBytes(fi.path), fi.index) catch (e:Dynamic) null;
		loaded.set(key, f);
		return f;
	}

	// --- discovery ---

	public static function directories():Array<String> {
		var home = Sys.getEnv("HOME");
		return switch Sys.systemName() {
			case "Windows":
				var win = Sys.getEnv("WINDIR") ?? "C:\\Windows";
				var local = Sys.getEnv("LOCALAPPDATA");
				[win + "\\Fonts"].concat(local != null ? [local + "\\Microsoft\\Windows\\Fonts"] : []);
			case "Mac":
				["/System/Library/Fonts", "/Library/Fonts"].concat(home != null ? [home + "/Library/Fonts"] : []);
			case _:
				var xdg = Sys.getEnv("XDG_DATA_HOME");
				["/usr/share/fonts", "/usr/local/share/fonts"].concat(home != null ? [home + "/.fonts", home + "/.local/share/fonts"] : []).concat(xdg != null ? [xdg + "/fonts"] : []);
		}
	}

	function scan() {
		if (scanned) return;
		scanned = true;
		#if (target.name == "hxmc")
		if (hxmc.unsafe.Mem.os() == 3) {
			for (b in WebFonts.all())
				add(b);
			return;
		}
		#end
		var seen = new Map<String, Bool>();
		function walk(dir:String, depth:Int) {
			if (depth > 6 || seen.exists(dir)) return;
			seen.set(dir, true);
			var entries = try sys.FileSystem.readDirectory(dir) catch (e:Dynamic) null;
			if (entries == null) return;
			entries.sort(Reflect.compare);
			for (e in entries) {
				var p = dir + "/" + e;
				var lower = e.toLowerCase();
				if (StringTools.endsWith(lower, ".ttf") || StringTools.endsWith(lower, ".ttc") || StringTools.endsWith(lower, ".otf")) {
					for (fi in FaceInfo.read(p))
						faces.push(fi);
				} else if (lower.indexOf(".") < 0 && try sys.FileSystem.isDirectory(p) catch (e:Dynamic) false) walk(p, depth + 1);
			}
		}
		for (d in directories())
			walk(d, 0);
	}
}

// a face of a font file, as discovery reads it (names, weight, style)
class FaceInfo {
	public final path:String;
	public final index:Int;
	public final family:String;
	public final subfamily:String;
	public final weight:Int;
	public final italic:Bool;
	// a variable face's wght axis (the weights it has; 0, 0: not variable)
	public var minWeight = 0;
	public var maxWeight = 0;

	public function new(path, index, family, subfamily, weight, italic) {
		this.path = path;
		this.index = index;
		this.family = family;
		this.subfamily = subfamily;
		this.weight = weight;
		this.italic = italic;
	}

	// the faces of an OpenType file, from its tables' directory, name and OS/2
	// tables only (read from the file at their offsets)
	public static function read(path:String):Array<FaceInfo> {
		var out = [];
		var f = try sys.io.File.read(path, true) catch (e:Dynamic) null;
		if (f == null) return out;
		try {
			f.bigEndian = true;
			var tag = f.readString(4);
			var offsets = [0];
			if (tag == "ttcf") {
				f.readInt32();
				var n = f.readInt32();
				offsets = [for (_ in 0...n) f.readInt32()];
			}
			for (i in 0...offsets.length) {
				f.seek(offsets[i], SeekBegin);
				var version = f.readInt32();
				// (TrueType's, 'true', 'OTTO': CFF's)
				if (version != 0x00010000 && version != 0x74727565 && version != 0x4F54544F) continue;
				var n = f.readUInt16();
				f.read(6);
				var name = -1, nameLen = 0, os2 = -1, os2Len = 0, fvar = -1, fvarLen = 0;
				for (_ in 0...n) {
					var t = f.readString(4);
					f.readInt32();
					var off = f.readInt32(), len = f.readInt32();
					if (t == "name") {
						name = off;
						nameLen = len;
					} else if (t == "OS/2") {
						os2 = off;
						os2Len = len;
					} else if (t == "fvar") {
						fvar = off;
						fvarLen = len;
					}
				}
				if (name < 0) continue;
				// a small font of just these two tables, read by FontFile's own code
				f.seek(name, SeekBegin);
				var nameBytes = f.read(nameLen);
				var weight = 400, italic = false;
				if (os2 >= 0 && os2Len >= 64) {
					f.seek(os2, SeekBegin);
					var o = f.read(64);
					weight = (o.get(4) << 8) | o.get(5);
					italic = ((o.get(62) << 8) | o.get(63)) & 1 != 0;
				}
				var names = Names.read(nameBytes);
				var sub = names.subfamily.toLowerCase();
				if (sub.indexOf("italic") >= 0 || sub.indexOf("oblique") >= 0) italic = true;
				var fi = new FaceInfo(path, i, names.family, names.subfamily, weight, italic);
				// (a variable face: its wght axis's range)
				if (fvar >= 0 && fvarLen >= 16) {
					f.seek(fvar, SeekBegin);
					var v = f.read(fvarLen);
					var arrays = (v.get(4) << 8) | v.get(5), count = (v.get(8) << 8) | v.get(9), size = (v.get(10) << 8) | v.get(11);
					for (k in 0...count) {
						var p = arrays + k * size;
						if (p + 16 > fvarLen || v.getString(p, 4) != "wght") continue;
						inline function fixed(q:Int):Int
							return ((v.get(q) << 24) | (v.get(q + 1) << 16)) >> 16;
						fi.minWeight = fixed(p + 4);
						fi.maxWeight = fixed(p + 12);
					}
				}
				out.push(fi);
			}
		} catch (e:Dynamic) {}
		f.close();
		return out;
	}
}

// the family and subfamily of a name table
class Names {
	public static function read(b:Bytes):{family:String, subfamily:String} {
		inline function u16(p:Int)
			return (b.get(p) << 8) | b.get(p + 1);
		var count = u16(2), strings = u16(4);
		var best = new Map<Int, String>();
		for (i in 0...count) {
			var r = 6 + 12 * i;
			var platform = u16(r), encoding = u16(r + 2), language = u16(r + 4), id = u16(r + 6);
			if (id != 1 && id != 2 && id != 16 && id != 17) continue;
			var len = u16(r + 8), off = strings + u16(r + 10);
			if (off + len > b.length) continue;
			var s = null;
			if (platform == 3 || platform == 0) {
				var sb = new StringBuf();
				var k = 0;
				while (k + 1 < len) {
					sb.addChar(u16(off + k));
					k += 2;
				}
				s = sb.toString();
			} else if (platform == 1 && encoding == 0) s = b.getString(off, len);
			if (s == null) continue;
			var rank = platform == 3 && language == 0x409 ? 3 : platform == 3 ? 2 : platform == 0 ? 1 : 0;
			var key = id * 10 + rank;
			if (!best.exists(key)) best.set(key, s);
		}
		function pick(ids:Array<Int>):String {
			for (id in ids)
				for (rank in [3, 2, 1, 0])
					if (best.exists(id * 10 + rank)) return best.get(id * 10 + rank);
			return "";
		}
		return {family: pick([16, 1]), subfamily: pick([17, 2])};
	}
}
