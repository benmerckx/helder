package helder.gfx.shader;

#if macro
import haxe.macro.Context;

// The names a module's own code sees (Sources, a slot object's functions):
// its file's imports and usings, its package, its module and its module's
// fields (a class's statics too, for a static's code), for
// Context.withImports.
class Scopes {
	static final cache = new Map<String, Scope>();

	public static function of(module:String, file:String, ?className:String):Scope {
		var key = module + ":" + file + ":" + className;
		var s = cache.get(key);
		if (s != null) return s;
		var imports = [], usings = [];
		var line = ~/^\s*(import|using)\s+([^;]+);/;
		for (l in sys.io.File.getContent(file).split("\n"))
			if (line.match(l)) (line.matched(1) == "import" ? imports : usings).push(StringTools.trim(line.matched(2)));
		var pack = module.split(".");
		pack.pop();
		if (pack.length > 0) imports.push(pack.join(".") + ".*");
		imports.push(module);
		if (className != null && !StringTools.endsWith(className, "_Fields_"))
			imports.push(module + (module.split(".").pop() == className ? "" : "." + className) + ".*");
		s = {imports: imports, usings: usings};
		cache.set(key, s);
		return s;
	}

	// the scope of the module a position is in (its file's), its module's name given
	public static function at(module:String, pos:haxe.macro.Expr.Position):Scope
		return of(module, Context.getPosInfos(pos).file);
}

typedef Scope = {imports:Array<String>, usings:Array<String>};
#end
