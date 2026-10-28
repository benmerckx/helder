package helder.asset;

#if macro
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// Asset's macros: a path checked (AssetPath's rules, the file there in that
// case) and found under a class path, else under the project (-D
// helder.root, which helder's CLI gives: the folder of its package.json;
// else the working directory), then a call of its kind's loader with the
// key in a marker (Bundle's: the files the program still uses are those
// whose markers its output has). Dev builds (-D hxmc.dev) and other targets
// than hxmc's also get the file's full path, read from disk. No callback of
// the compiler's is registered, and nothing but files is read: a module
// naming assets stays in the module cache.
class AssetMacro {
	public static function handle(path:String, kind:String):Expr {
		var f = find(path, kind);
		bundle(path, f, false);
		var loader = switch kind {
			case "image": macro helder.asset.ImageAsset.load;
			case "font": macro helder.asset.FontAsset.load;
			case "sound": macro helder.asset.BytesAsset.sound;
			case _: macro helder.asset.BytesAsset.load;
		}
		return macro @:pos(Context.currentPos()) $loader(${key(path, false)}, $v{devPath(f)});
	}

	public static function model(path:String):Expr {
		var f = find(path, "model");
		bundle(path, f, false);
		// (its names typed from the file: a change to it types the module again)
		Context.registerModuleDependency(Context.getLocalModule(), f);
		var n = helder.scene.render.Model.names(File.getBytes(f), path, Context.currentPos());
		return macro @:pos(Context.currentPos()) helder.scene.render.Model.asset(${key(path, false)}, $v{devPath(f)}, ${n.nodes}, ${n.meshes},
			${n.materials}, ${n.animations});
	}

	public static function embed(path:String):Expr {
		var f = find(path, "embed");
		Context.registerModuleDependency(Context.getLocalModule(), f);
		var b = File.getBytes(f);
		return macro haxe.crypto.Base64.decode($v{haxe.crypto.Base64.encode(b)});
	}

	// path as the program has it: its marker (Bundle's: a literal the output
	// has while the code naming it is there; sync: read before main), the
	// key taken from it
	public static function key(path:String, sync:Bool):Expr
		return macro helder.asset.Assets.key($v{Bundle.MARK + (sync ? "now:" : "key:") + path + "\x01"});

	// what the build itself takes of file: on desktop (not in dev builds) its
	// bytes a resource of the executable, after a header naming it, unless
	// helder's CLI keeps it out (-D helder.asset.keep: the file of the keys a
	// last build used, null for all; the module typed again when it
	// changes); without the CLI (a build of hxmc's own), on the web, copied
	// beside the module (assets/<key>) and listed in <module>.assets.json
	// when it is read before main. The rest is the CLI's (BuildCommand: the
	// web's files, the APK's, the app's)
	public static function bundle(path:String, file:String, sync:Bool) {
		if (Context.defined("hxmc.dev") || Context.definedValue("target.name") != "hxmc") return;
		var t = Context.definedValue("hxmc.target") ?? "", keep = Context.definedValue("helder.asset.keep");
		var module = Context.getLocalModule();
		if (t == "" || t.startsWith("linux-") || t.startsWith("macos-") || t.startsWith("windows-")) {
			Context.registerModuleDependency(module, file);
			if (keep != null && keep != "") {
				Context.registerModuleDependency(module, keep);
				var kept:Null<Array<String>> = try haxe.Json.parse(File.getContent(keep)) catch (_:Dynamic) null;
				if (kept != null && !kept.contains(path)) return;
			}
			var header = haxe.io.Bytes.ofString(Bundle.MARK + "res:" + path + "\x01"), data = File.getBytes(file);
			var b = haxe.io.Bytes.alloc(header.length + data.length);
			b.blit(0, header, 0, header.length);
			b.blit(header.length, data, 0, data.length);
			Context.addResource(Bundle.PREFIX + path, b);
			return;
		}
		if (t != "wasm32-wasi" || keep != null) return;
		var out = haxe.macro.Compiler.getOutput();
		// (the repository tool's `hxmc <output> <args>` hides it)
		for (d in ["helder.asset.out", "helder.scene.out"])
			if ((out == null || out == "") && Context.defined(d)) out = Context.definedValue(d);
		if (out == null || out == "") return;
		var dest = Path.join([Path.directory(out), AssetPath.bundled(path)]);
		mkdirs(Path.directory(dest));
		File.copy(file, dest);
		if (sync && !early.contains(path)) early.push(path);
		if (!listing) {
			listing = true;
			Context.onAfterGenerate(() -> {
				early.sort(Reflect.compare);
				File.saveContent(out + ".assets.json", haxe.Json.stringify([for (k in early) AssetPath.bundled(k)]));
				early = [];
				listing = false;
			});
		}
	}

	// (a build of hxmc's own for the web: the files read before main)
	static var early:Array<String> = [];
	static var listing = false;

	static function mkdirs(d:String)
		if (d != "" && !FileSystem.exists(d)) {
			mkdirs(Path.directory(d));
			FileSystem.createDirectory(d);
		}

	// (the file's full path where the program reads it from disk, else null)
	public static function devPath(file:String):Null<String> {
		var hxmc = Context.definedValue("target.name") == "hxmc";
		return Context.defined("hxmc.dev") || !hxmc ? FileSystem.fullPath(file).split("\\").join("/") : null;
	}

	// the project's folder: where a path not under a class path is looked for
	public static function root():String {
		var r = Context.definedValue("helder.root");
		return r != null && r != "" ? r : Sys.getCwd();
	}

	// path's file (an error at the call when it is no asset's path, not
	// there, or there in another case)
	public static function find(path:String, kind:String):String {
		var pos = Context.currentPos();
		var what = 'Asset.$kind("$path")';
		var e = AssetPath.error(path);
		if (e != null) Context.error('$what: $e', pos);
		var cwd = Sys.getCwd();
		var roots = [for (cp in Context.getClassPath()) Path.removeTrailingSlashes(Path.isAbsolute(cp) ? cp : Path.join([cwd, cp]))];
		roots.push(Path.removeTrailingSlashes(root()));
		var other = null;
		var f = Bundle.locate(path, roots, d -> try FileSystem.readDirectory(d) catch (_:Dynamic) null, c -> if (other == null) other = c);
		if (f != null) {
			if (FileSystem.isDirectory(f)) Context.error('$what: a directory', pos);
			// (relative to the working directory where it is under it: a module
			// cache keeps a module whose dependency is named so, not by its full path)
			return f.startsWith(cwd) ? f.substr(cwd.length) : f;
		}
		if (other != null) Context.error('$what: "${other.part}" is "${other.actual}" on disk (paths are case-sensitive on Android and the web)', pos);
		return Context.error('$what: no such file under the class paths or the project (${root()})', pos);
	}
}
#end
