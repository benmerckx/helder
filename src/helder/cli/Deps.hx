package helder.cli;

#if macro
import haxe.macro.Context;

// What a build read, for `helder dev`'s watcher: `--macro
// helder.cli.Deps.write("<file>")` writes, once the program is typed, the
// full path of each module's file, one per line (the types' positions:
// cached modules too, a compilation server's; called again with the types
// a callback defined, helder.view's late code: all of them written).
class Deps {
	static var seen = new Map<String, Bool>();

	public static function write(file:String) {
		seen = new Map();
		Context.onAfterTyping(types -> {
			for (t in types) {
				var pos = switch t {
					case TClassDecl(c): c.get().pos;
					case TEnumDecl(e): e.get().pos;
					case TTypeDecl(d): d.get().pos;
					case TAbstract(a): a.get().pos;
				}
				var f = Context.getPosInfos(pos).file;
				if (f != "" && !seen.exists(f)) seen.set(f, true);
			}
			var out = [];
			for (f in seen.keys()) out.push(try sys.FileSystem.fullPath(f) catch (_:Dynamic) f);
			out.sort(Reflect.compare);
			sys.io.File.saveContent(file, out.join("\n") + "\n");
		});
	}
}
#end
