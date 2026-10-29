package helder.cli;

import haxe.io.Bytes;
import helder.cli.Style.Tone;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The runtime objects (<dir>/<target>/{rt,ssl,uv}.o) that npm does not
// install: Android's (android-arm64, android-x86_64). @hxmc/cli's
// package.json names the GitHub release of benmerckx/hxmc built from the
// same sources ("hxmc": {"rt": "rt-<16 hex>"}); its assets
// <target>-<object>.gz are fetched on first use (curl, which follows the
// environment's proxy settings), gunzipped into <helder's cache>/rt/<tag>/
// and that directory added to HXMC_RT_DIR (hxmc adds HXMC_RT_DIR's to its
// own search). A directory already in HXMC_RT_DIR with the target's
// objects is used as it is. HELDER_RT_URL names another place for the
// releases (<it>/<tag>/<asset>; a mirror, a file:// directory).
class Runtime {
	public static final OBJECTS = ["rt.o", "ssl.o", "uv.o"];
	static final RELEASES = "https://github.com/benmerckx/hxmc/releases/download";

	// the targets whose objects come from the release, not npm
	public static function fetched(target:String):Bool
		return target == "android-arm64" || target == "android-x86_64";

	static function has(dir:String, target:String):Bool {
		for (o in OBJECTS) if (!FileSystem.exists('$dir/$target/$o')) return false;
		return true;
	}

	static function delimiter():String
		return Sys.systemName() == "Windows" ? ";" : ":";

	// @hxmc/cli's release tag of its runtime objects (null: not recorded)
	public static function tag():Null<String> {
		var p = Compiler.locate("node_modules/@hxmc/cli/package.json");
		if (p == null) return null;
		var j:Dynamic = try haxe.Json.parse(File.getContent(p)) catch (_:Dynamic) null;
		var t:Dynamic = j?.hxmc?.rt;
		return t is String && ~/^rt-[0-9a-f]+$/.match(t) ? t : null;
	}

	// the target's objects where the compiler finds them: fetched on first
	// use, HXMC_RT_DIR given their directory; an error's message thrown
	@:coroutine public static function ensure(target:String) {
		if (!fetched(target)) return;
		var given = [for (d in (Sys.getEnv("HXMC_RT_DIR") ?? "").split(delimiter())) if (d != "") d];
		for (d in given) if (has(d, target)) return;
		var tag = tag();
		if (tag == null) throw '$target\'s runtime objects: @hxmc/cli\'s package.json names no release ("hxmc": {"rt"}; HXMC_RT_DIR names a directory of them)';
		var dir = DevCommand.cache() + '/rt/$tag';
		if (!has(dir, target)) fetch(tag, target, dir);
		Sys.putEnv("HXMC_RT_DIR", [dir].concat(given).join(delimiter()));
	}

	@:coroutine static function fetch(tag:String, target:String, dir:String) {
		var base = (Sys.getEnv("HELDER_RT_URL") ?? "").trim();
		if (base == "") base = RELEASES;
		while (base.endsWith("/")) base = base.substr(0, base.length - 1);
		Term.out(Style.status("fetching", Info, '$target\'s runtime objects, once ${Style.path('($base/$tag → $dir)')}'));
		TestCommand.mkdirs('$dir/$target');
		for (o in OBJECTS) {
			var url = '$base/$tag/$target-$o.gz', out = '$dir/$target/$o', tmp = '$out.${Std.random(1 << 30)}';
			var r = Devices.output("curl", ["-sSfL", "--retry", "3", "-o", '$tmp.gz', url]);
			if (r.code != 0) {
				try FileSystem.deleteFile('$tmp.gz') catch (_:Dynamic) {};
				throw '$url: not fetched (curl: exit code ${r.code}) ${r.errors.trim()}'.trim();
			}
			var data = try gunzip(File.getBytes('$tmp.gz')) catch (e:Dynamic) {
				FileSystem.deleteFile('$tmp.gz');
				throw '$url: $e';
			}
			FileSystem.deleteFile('$tmp.gz');
			// (written beside it, then renamed: another build's fetch at the same time)
			File.saveBytes(tmp, data);
			try FileSystem.rename(tmp, out) catch (_:Dynamic) try FileSystem.deleteFile(tmp) catch (_:Dynamic) {};
		}
	}

	// a gzip member's data (RFC 1952: its header's optional fields skipped,
	// its size from the trailer)
	public static function gunzip(b:Bytes):Bytes {
		if (b.length < 18 || b.get(0) != 0x1f || b.get(1) != 0x8b || b.get(2) != 8) throw "not gzip";
		var flags = b.get(3), at = 10;
		if (flags & 4 != 0) at += 2 + (b.get(at) | b.get(at + 1) << 8);
		if (flags & 8 != 0) while (b.get(at++) != 0) {}
		if (flags & 16 != 0) while (b.get(at++) != 0) {}
		if (flags & 2 != 0) at += 2;
		var size = b.getInt32(b.length - 4);
		var out = Bytes.alloc(size);
		var input = new haxe.zip.InflateImpl(new haxe.io.BytesInput(b, at, b.length - 8 - at), false, false), n = 0;
		while (n < size) {
			var k = input.readBytes(out, n, size - n);
			if (k <= 0) break;
			n += k;
		}
		if (n != size) throw "gzip data shorter than its size";
		return out;
	}
}
