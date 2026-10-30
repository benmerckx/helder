package helder.dev;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;

// What Hot's macros compute when compiling (-D hxmc.dev), public for state
// libraries' own macros:
//
//   HotMacro.hash(t)      a type's shape as a hash (Hot.typeOf): its fields
//                         and their types, recursively; "" for a type that is
//                         not data (a function, Dynamic, a native handle, a
//                         type not yet known), whose values are never kept
//   HotMacro.here(pos)    the static identity of the place pos is in
//                         (Hot.here): its type, its function, the variable
//                         the expression at pos is assigned to (else its
//                         order among the unnamed ones of that function). A
//                         library's macro passes Context.currentPos(), its
//                         call's place (Hot.here() written in a macro's
//                         `macro` block is the place of that block)
// Both give "" without -D hxmc.dev.
class HotMacro {
	// (macro statics start afresh with each compilation, a compilation server's too)
	static var hashes = new Map<String, String>();
	static var sources = new Map<String, String>();
	static var unnamed = new Map<String, Array<Int>>();

	// the type's shape as 16 hex digits, "" when it is not data (and without -D hxmc.dev)
	public static function hash(t:Type):String {
		if (!Context.defined("hxmc.dev")) return "";
		var key = TypeTools.toString(t);
		var h = hashes.get(key);
		if (h != null) return h;
		var d = new Describe();
		var s = d.desc(t);
		if (!d.data) return "";
		h = haxe.crypto.Md5.encode(s).substr(0, 16);
		hashes.set(key, h);
		return h;
	}

	// the type `(_ : T)` names, else the type of e (not evaluated)
	public static function typeOfExpr(e:Expr):Type {
		return switch e.expr {
			case EParenthesis({expr: ECheckType({expr: EConst(CIdent("_"))}, ct)}) | ECheckType({expr: EConst(CIdent("_"))}, ct):
				Context.resolveType(ct, e.pos);
			case _: Context.typeof(e);
		}
	}

	// Type.method.variable (the parts there are): see the class's comment
	public static function here(pos:Position):String {
		if (!Context.defined("hxmc.dev")) return "";
		var parts = [];
		var cls = Context.getLocalClass();
		if (cls != null) parts.push(cls.toString());
		var method = Context.getLocalMethod();
		if (method != null) parts.push(method);
		var name = assigned(pos);
		if (name != null && name != method) parts.push(name);
		if (name == null) {
			var info = Context.getPosInfos(pos);
			var k = info.file + ":" + parts.join(".");
			var seen = unnamed.get(k);
			if (seen == null) unnamed.set(k, seen = []);
			var i = seen.indexOf(info.min);
			if (i < 0) {
				seen.push(info.min);
				i = seen.length - 1;
			}
			parts.push("#" + i);
		}
		return parts.join(".");
	}

	// the name the expression starting at pos is assigned to (`var x =`,
	// `final x:T =`, `x =`, `this.x =`), read from the source before it
	static function assigned(pos:Position):Null<String> {
		var info = Context.getPosInfos(pos);
		var src = sources.get(info.file);
		if (src == null) {
			src = try sys.io.File.getContent(info.file) catch (_:Dynamic) "";
			sources.set(info.file, src);
		}
		// (bytes and characters agree for ASCII sources, as Haxe's positions count bytes)
		var i = info.min - 1;
		inline function space(c:Int)
			return c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code;
		while (i >= 0 && space(StringTools.fastCodeAt(src, i)))
			i--;
		if (i < 0 || StringTools.fastCodeAt(src, i) != "=".code) return null;
		var before = i > 0 ? StringTools.fastCodeAt(src, i - 1) : 0;
		if (before == "=".code || before == "!".code || before == "<".code || before == ">".code) return null;
		// the statement's text before the `=`: from the last ; { } or ( outside a type
		var j = i - 1, depth = 0;
		while (j >= 0) {
			var c = StringTools.fastCodeAt(src, j);
			if (c == ">".code) depth++;
			else if (c == "<".code) depth--;
			else if (depth <= 0 && (c == ";".code || c == "{".code || c == "}".code || c == "(".code || c == ",".code)) break;
			j--;
		}
		var stmt = src.substring(j + 1, i);
		var re = ~/([A-Za-z_][A-Za-z0-9_]*)\s*(:[^=]*)?\s*$/;
		return re.match(stmt) ? re.matched(1) : null;
	}
}

// a type's description (its fields and their types, recursively), and
// whether its values are data: what haxe.Serializer writes and reads back as
// the same type (basic types, strings, arrays, maps and lists, structures,
// enums and classes of data, abstracts over data)
private class Describe {
	public var data = true;

	final seen = new Map<String, Bool>();

	public function new() {}

	function no(why:String):String {
		data = false;
		return "!" + why;
	}

	// a variable with storage (what Reflect.fields of an instance lists)
	static function physical(f:ClassField):Bool {
		return switch f.kind {
			case FVar(r, w): f.meta.has(":isVar") || r.match(AccNormal | AccNo) || w.match(AccNormal | AccNo | AccCtor);
			case _: false;
		}
	}

	function params(ps:Array<Type>):String
		return ps.length == 0 ? "" : "<" + [for (p in ps) desc(p)].join(",") + ">";

	public function desc(t:Type):String {
		return switch t {
			case TMono(r): r.get() == null ? no("unknown") : desc(r.get());
			case TLazy(f): desc(f());
			case TType(r, ps):
				// (a recursive typedef: its name where it is used inside itself)
				var d = r.get();
				var path = d.pack.concat([d.name]).join(".") + params(ps);
				if (seen.exists(path)) return path;
				seen.set(path, true);
				var s = desc(TypeTools.applyTypeParameters(d.type, d.params, ps));
				seen.remove(path);
				path + "=" + s;
			case TFun(_, _): no("function");
			case TDynamic(_): no("Dynamic");
			case TAnonymous(a):
				var fs = [for (f in a.get().fields) if (f.kind.match(FVar(_, _))) f];
				fs.sort((x, y) -> x.name < y.name ? -1 : x.name > y.name ? 1 : 0);
				"{" + [for (f in fs) f.name + ":" + desc(f.type)].join(",") + "}";
			case TEnum(r, ps):
				var e = r.get();
				var path = e.pack.concat([e.name]).join(".") + params(ps);
				if (seen.exists(path)) return path;
				seen.set(path, true);
				var cs = [for (n in e.names) e.constructs.get(n)];
				path + "{" + [for (c in cs) c.name + switch TypeTools.applyTypeParameters(c.type, e.params, ps) {
					case TFun(args, _): "(" + [for (a in args) desc(a.t)].join(",") + ")";
					case _: "";
				}].join("|") + "}";
			case TInst(r, ps):
				var c = r.get();
				var path = c.pack.concat([c.name]).join(".");
				switch c.kind {
					case KTypeParameter(_): return no("type parameter " + c.name);
					case _:
				}
				switch path {
					case "String": return path;
					case "Array" | "List" | "haxe.ds.List" | "haxe.ds.StringMap" | "haxe.ds.IntMap" | "haxe.ds.ObjectMap" | "haxe.ds.EnumValueMap":
						return path + params(ps);
					case _:
				}
				if (c.isExtern || c.isInterface) return no("extern " + path);
				// (a generic class's type parameters are not read: encoding them
				// for a macro resolves their constraints, and for a class typed
				// later than this they would be resolved empty and stay so: a
				// "Constraint check failure" in a program that compiles)
				if (ps.length > 0) return no("generic class " + path);
				var full = path + params(ps);
				if (seen.exists(full)) return full;
				seen.set(full, true);
				var fs = [];
				var k = c;
				while (k != null) {
					for (f in k.fields.get())
						if (physical(f)) fs.push(f.name + ":" + desc(f.type));
					if (k.superClass == null) break;
					if (k.superClass.params.length > 0) return no("generic class " + k.superClass.t.toString());
					k = k.superClass.t.get();
				}
				fs.sort((x, y) -> x < y ? -1 : x > y ? 1 : 0);
				full + "{" + fs.join(",") + "}";
			case TAbstract(r, ps):
				var a = r.get();
				var path = a.pack.concat([a.name]).join(".");
				switch path {
					case "Int" | "Float" | "Bool" | "UInt" | "haxe.Int64" | "haxe.Int32": path;
					case "Null": "Null<" + desc(ps[0]) + ">";
					case "haxe.ds.Map" | "Map": "Map" + params(ps);
					case "Void": no("Void");
					case "Class" | "Enum" | "EnumValue" | "Any": no(path);
					case _:
						if (a.meta.has(":coreType")) no("core type " + path) else path + params(ps) + "=" + desc(TypeTools.applyTypeParameters(a.type, a.params, ps));
				}
		}
	}
}
#end
