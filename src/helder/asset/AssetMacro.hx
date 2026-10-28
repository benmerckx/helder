package helder.asset;

#if macro
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
import sys.FileSystem;

using StringTools;

// Asset's macros: a path checked (AssetPath's rules, the file there in that
// case) and found under a class path, else under the project (-D
// helder.root, which helder's CLI gives: the folder of its package.json;
// else the working directory), then a call of its kind's loader with the
// key as a constant, which Bundle finds in the program after typing. Dev
// builds (-D hxmc.dev) and other targets than hxmc's also get the file's
// full path, read from disk.
class AssetMacro {
	public static function handle(path:String, kind:String):Expr {
		var f = find(path, kind);
		var loader = switch kind {
			case "image": macro helder.asset.ImageAsset.load;
			case "font": macro helder.asset.FontAsset.load;
			case "sound": macro helder.asset.BytesAsset.sound;
			case _: macro helder.asset.BytesAsset.load;
		}
		return macro @:pos(Context.currentPos()) $loader($v{path}, $v{devPath(f)});
	}

	public static function model(path:String):Expr {
		var f = find(path, "model");
		// (its names typed from the file: a change to it types the module again)
		Context.registerModuleDependency(Context.getLocalModule(), f);
		var n = helder.scene.render.Model.names(sys.io.File.getBytes(f), path, Context.currentPos());
		return macro @:pos(Context.currentPos()) helder.scene.render.Model.asset($v{path}, $v{devPath(f)}, ${n.nodes}, ${n.meshes}, ${n.materials}, ${n.animations});
	}

	public static function embed(path:String):Expr {
		var f = find(path, "embed", false);
		Context.registerModuleDependency(Context.getLocalModule(), f);
		var b = sys.io.File.getBytes(f);
		return macro haxe.crypto.Base64.decode($v{haxe.crypto.Base64.encode(b)});
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
	// there, or there in another case); its use recorded (Bundle)
	public static function find(path:String, kind:String, bundled = true):String {
		var pos = Context.currentPos();
		var what = 'Asset.$kind("$path")';
		var e = AssetPath.error(path);
		if (e != null) Context.error('$what: $e', pos);
		var other = null;
		var f = search(path, c -> if (other == null) other = c);
		if (f != null) {
			if (FileSystem.isDirectory(f)) Context.error('$what: a directory', pos);
			if (bundled) Bundle.ensure();
			return f;
		}
		if (other != null) Context.error('$what: "${other.part}" is "${other.actual}" on disk (paths are case-sensitive on Android and the web)', pos);
		return Context.error('$what: no such file under the class paths or the project (${root()})', pos);
	}

	// path's file, as find finds it (null: none)
	public static function locate(path:String):Null<String>
		return search(path, _ -> {});

	// (the class paths, then the project: the first with path in its case;
	// another case told to mismatch)
	static function search(path:String, mismatch:{part:String, actual:String}->Void):Null<String> {
		var cwd = Sys.getCwd();
		var roots = [for (cp in Context.getClassPath()) Path.removeTrailingSlashes(Path.isAbsolute(cp) ? cp : Path.join([cwd, cp]))];
		roots.push(Path.removeTrailingSlashes(root()));
		for (r in roots) {
			var c = AssetPath.caseOf(path, d -> try FileSystem.readDirectory(d == "" ? r : '$r/$d') catch (_:Dynamic) []);
			if (c == null) return '$r/$path';
			if (c.actual != null) mismatch({part: c.part, actual: c.actual});
		}
		return null;
	}
}
#end
