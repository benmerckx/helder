package helder.cli;

import haxe.io.Path;
import helder.asset.AssetPath;
import helder.asset.Bundle;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The program's assets around a build (helder.asset's Bundle): before it,
// the file of the keys the last build used (-D helder.asset.keep: on
// desktop the macro builds those into the executable, every one named when
// it holds null); after it, the keys whose markers the output has, each
// found as the macro finds it (the class paths, then the project), written
// to the manifest ({target, dev, assets: [{key, file, sync, bytes}], built:
// [keys]}); desktop's built in, or an app's copied (iOS: intoApp, before
// linking), were those or not: when not, the keys written and the build
// made again. The web's files copied beside the module (assets/<key>, what
// is there besides them removed) and <module>.assets.json (those read
// before main); the APK's are Android's (pack). Kept in helder's cache,
// not beside the output (what is shipped): <cache>/assets/<hash of the
// output's path>-<name>.json, .keep.
class AssetStep {
	public static function manifest(exe:String):String {
		var full = FileSystem.fullPath(Path.directory(exe) == "" ? "." : Path.directory(exe)).split("\\").join("/") + "/" + Path.withoutDirectory(exe);
		return DevCommand.cache() + "/assets/" + haxe.crypto.Md5.encode(full).substr(0, 16) + "-" + Path.withoutDirectory(exe) + ".json";
	}

	// the keys the last build used (null: not known, all)
	public static function kept(exe:String):Null<Array<String>> {
		var k = manifest(exe) + ".keep";
		return try haxe.Json.parse(File.getContent(k)) catch (_:Dynamic) null;
	}

	// a release build's define: the keep file (made, holding null, when there is none)
	public static function define(exe:String):Array<String> {
		var k = manifest(exe) + ".keep";
		TestCommand.mkdirs(Path.directory(k));
		if (!FileSystem.exists(k)) File.saveContent(k, "null");
		return ["-D", "helder.asset.keep=" + FileSystem.fullPath(k).split("\\").join("/")];
	}

	// the files of a build's manifest (none when it wrote none)
	public static function assets(exe:String):Array<{key:String, file:String, sync:Bool, bytes:Int}> {
		var m = manifest(exe);
		if (!FileSystem.exists(m)) return [];
		var j:Dynamic = try haxe.Json.parse(File.getContent(m)) catch (_:Dynamic) null;
		return j == null || j.assets == null ? [] : j.assets;
	}

	// roots: where keys are looked for (class paths, the project)
	public static function locate(key:String, roots:Array<String>):Null<String>
		return Bundle.locate(key, [for (r in roots) Path.removeTrailingSlashes(FileSystem.fullPath(r)).split("\\").join("/")],
			d -> try FileSystem.readDirectory(d) catch (_:Dynamic) null);

	// after a build of target (web: wasm32-wasi; an app's: copied, the keys
	// put in it before it was linked): whether what the output has built in
	// was what it uses; when not, those written for the next build
	public static function after(exe:String, target:String, roots:Array<String>, dev:Bool, ?copied:Array<String>):Bool {
		var scan = Bundle.scan(File.getBytes(exe));
		var keys = [for (k in scan.used.keys()) k];
		keys.sort(Reflect.compare);
		var entries = [];
		for (k in keys) {
			var f = locate(k, roots);
			if (f != null) entries.push({key: k, file: f, sync: scan.used.get(k), bytes: FileSystem.stat(f).size});
		}
		var m = manifest(exe);
		TestCommand.mkdirs(Path.directory(m));
		File.saveContent(m, haxe.Json.stringify({target: target, dev: dev, assets: entries, built: scan.built}, "\t"));
		var used = [for (e in entries) e.key];
		if (target == "wasm32-wasi") web(exe, entries, dev);
		if (dev) return true;
		var desktop = target.startsWith("linux-") || target.startsWith("macos-") || target.startsWith("windows-");
		var built = desktop ? scan.built : copied;
		if (built == null || built.join("\n") == used.join("\n")) return true;
		var k = m + ".keep", text = haxe.Json.stringify(used);
		if ((try File.getContent(k) catch (_:Dynamic) "") != text) File.saveContent(k, text);
		return false;
	}

	// the web's: the files beside the module (none for dev, whose server
	// serves them), the list of those read before main
	static function web(exe:String, entries:Array<{key:String, file:String, sync:Bool, bytes:Int}>, dev:Bool) {
		var dir = Path.directory(exe);
		if (dir == "") dir = ".";
		if (!dev) {
			prune(dir, "assets", [for (e in entries) AssetPath.bundled(e.key) => true]);
			for (e in entries) {
				var dest = '$dir/${AssetPath.bundled(e.key)}';
				TestCommand.mkdirs(Path.directory(dest));
				File.copy(e.file, dest);
			}
		}
		File.saveContent(exe + ".assets.json", haxe.Json.stringify([for (e in entries) if (e.sync) AssetPath.bundled(e.key)]));
	}

	// iOS, before linking: the kept keys' files in the bundle (assets/<key>),
	// their names and bytes for CodeResources; the keys put there
	public static function intoApp(exe:String, app:String, roots:Array<String>):{keys:Array<String>, files:Map<String, haxe.io.Bytes>} {
		var keys = [], files = new Map<String, haxe.io.Bytes>();
		for (k in kept(exe) ?? []) {
			var f = locate(k, roots);
			if (f == null) continue;
			var rel = AssetPath.bundled(k), b = File.getBytes(f);
			TestCommand.mkdirs(Path.directory('$app/$rel'));
			File.saveBytes('$app/$rel', b);
			files.set(rel, b);
			keys.push(k);
		}
		keys.sort(Reflect.compare);
		return {keys: keys, files: files};
	}

	// the files under root/rel not kept (paths from root), and the directories left empty
	static function prune(root:String, rel:String, keep:Map<String, Bool>) {
		var d = '$root/$rel';
		if (!FileSystem.exists(d) || !FileSystem.isDirectory(d)) return;
		for (n in FileSystem.readDirectory(d)) {
			var p = '$rel/$n';
			if (FileSystem.isDirectory('$root/$p')) {
				prune(root, p, keep);
				if (FileSystem.readDirectory('$root/$p').length == 0) FileSystem.deleteDirectory('$root/$p');
			} else if (!keep.exists(p)) FileSystem.deleteFile('$root/$p');
		}
	}
}
