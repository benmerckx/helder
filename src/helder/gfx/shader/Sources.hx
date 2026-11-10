package helder.gfx.shader;

#if macro
import haxe.io.Bytes;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

// A plain function as shader code reads it (Lower): typed again from its
// source, without inlining, so that the math types' operators and
// ShaderMath's calls stay calls (the program's own typing inlines them).
// The function is read from its file at its field's position, parsed there
// (errors at its own lines) and typed in its module's imports and usings,
// with its module's types and fields, its package and, for a class's
// static, its class's other statics in scope (private ones too, as its own
// code sees them): Context.withImports, around the definition's typing.
// Any static or module-level function written in Haxe can be one; none
// needs a mark.
class Sources {
	static final cache = new Map<String, TypedExpr>();

	public static function typed(c:ClassType, cf:ClassField):Null<TypedExpr> {
		if (cf.kind.match(FVar(_, _))) return null;
		return parsed(c, cf, "\\bfunction\\s+" + cf.name + "\\b", "function");
	}

	// a static final's value (vec3(0.2, 0.3, 0.9): a vector constant),
	// typed again from its source as a function is
	public static function value(c:ClassType, cf:ClassField):Null<TypedExpr> {
		if (!cf.kind.match(FVar(_, AccNever | AccCtor))) return null;
		return parsed(c, cf, "\\b" + cf.name + "\\s*(:[^=]*)?=", "");
	}

	// the field's source from the end of a match of head (prefix and the rest)
	static function parsed(c:ClassType, cf:ClassField, head:String, prefix:String):Null<TypedExpr> {
		var key = c.module + ":" + c.name + "." + cf.name;
		var t = cache.get(key);
		if (t != null) return t;
		if (c.isExtern) return null;
		var info = Context.getPosInfos(cf.pos);
		var file = info.file;
		if (!sys.FileSystem.exists(file)) return null;
		// (positions are bytes)
		var bytes = Bytes.ofString(sys.io.File.getContent(file));
		var field = bytes.getString(info.min, info.max - info.min);
		var r = new EReg(head, "");
		if (!r.match(field)) return null;
		var at = info.min + Bytes.ofString(field.substr(0, r.matchedPos().pos + r.matchedPos().len)).length;
		var rest = bytes.getString(at, info.max - at);
		if (prefix == "") rest = ~/;\s*$/.replace(rest, "");
		// (`function` and the rest: an anonymous function where its name was)
		var fe = Context.parseInlineString(prefix + rest, Context.makePosition({min: at - prefix.length, max: info.max, file: file}));
		var imports = [], usings = [];
		var line = ~/^\s*(import|using)\s+([^;]+);/;
		for (l in bytes.toString().split("\n"))
			if (line.match(l)) (line.matched(1) == "import" ? imports : usings).push(StringTools.trim(line.matched(2)));
		var pack = c.module.split(".");
		pack.pop();
		if (pack.length > 0) imports.push(pack.join(".") + ".*");
		imports.push(c.module);
		if (!StringTools.endsWith(c.name, "_Fields_")) imports.push(c.module + (c.module.split(".").pop() == c.name ? "" : "." + c.name) + ".*");
		t = Context.withImports(imports, usings, () -> Context.withOptions({allowInlining: false}, () -> Context.typeExpr(macro @:privateAccess $fe)));
		cache.set(key, t);
		return t;
	}
}
#end
