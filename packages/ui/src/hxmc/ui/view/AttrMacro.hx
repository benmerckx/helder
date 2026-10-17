package hxmc.ui.view;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.TypeTools;

// StyleAttrs's apply, generated from Style: every public property with a
// setter is an attribute, named as the property or in kebab-case, its value
// converted by the property's type (Null<T> as T):
// - a function of StyleAttrs named as the property, (style, v), when it has
//   one (the properties whose values CSS writes its own way: background,
//   radius, transform...);
// - Float, Int, Bool, String; Dim ("50%", 12), EdgesValue ("8 12"), Color
//   (CSS's colours, 0xRRGGBB opaque);
// - an enum abstract: its values' names in any case, kebab-case or not
//   ("space-between": SpaceBetween), or the names their @:css gives
//   ("flex-start", "ew-resize");
// - a type with a static parse(String) (Shadow, Gradient...): a string
//   parsed, else the value as it is;
// - else the value as it is.
// So a property added to Style is an attribute with no more code.
class AttrMacro {
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var own = [for (f in fields) f.name => true];
		var cases:Array<Case> = [];
		var names:Array<Expr> = [];
		var enums = new Map<String, Bool>();
		var style = switch Context.getType("hxmc.ui.Style") {
			case TInst(c, _): c.get();
			case _: throw "hxmc.ui.Style";
		}
		for (f in style.fields.get()) {
			if (!f.isPublic) continue;
			switch f.kind {
				case FVar(_, AccCall):
				case _: continue;
			}
			var name = f.name;
			var value = if (own.exists(name)) macro $i{name}(style, v) else {
				var conv = convert(f.type, fields, enums);
				macro style.$name = $conv;
			}
			// (matched as written, either way: no conversion on the way)
			var kebab = ~/([A-Z])/g.map(name, r -> "-" + r.matched(1).toLowerCase());
			cases.push({values: kebab == name ? [macro $v{name}] : [macro $v{name}, macro $v{kebab}], expr: value});
			names.push(macro $v{name} => true);
		}
		// (another spelling camel turns into a property's name)
		var other = macro {
			var c = camel(name);
			return c != name && NAMES.exists(c) ? apply(style, c, v) : false;
		};
		var sw = {expr: ESwitch(macro name, cases, other), pos: Context.currentPos()};
		fields.push({
			name: "apply",
			access: [APublic, AStatic],
			pos: Context.currentPos(),
			kind: FFun({args: [{name: "style", type: macro :hxmc.ui.Style}, {name: "name", type: macro :String}, {name: "v", type: macro :Dynamic}],
				ret: macro :Bool, expr: macro {
					$sw;
					return true;
				}})
		});
		fields.push({
			name: "NAMES",
			access: [AStatic, AFinal],
			pos: Context.currentPos(),
			kind: FVar(macro :Map<String, Bool>, macro [$a{names}])
		});
		return fields;
	}

	// v as the type t
	static function convert(t:Type, fields:Array<Field>, enums:Map<String, Bool>):Expr {
		var nullable = false;
		switch t {
			case TAbstract(_.get() => {name: "Null", pack: []}, [inner]):
				t = inner;
				nullable = true;
			case TType(_.get() => {name: "Null", pack: []}, [inner]):
				t = inner;
				nullable = true;
			case _:
		}
		var e = switch t {
			case TAbstract(_.get() => {name: "Float", pack: []}, _): macro float(v);
			case TAbstract(_.get() => {name: "Int", pack: []}, _): macro Std.int(float(v));
			case TAbstract(_.get() => {name: "Bool", pack: []}, _): return macro v == true || v == "true";
			case TInst(_.get() => {name: "String", pack: []}, _): return macro v == null ? null : Std.string(v);
			case TAbstract(_.get() => {name: "Dim"}, _): macro dim(v);
			case TAbstract(_.get() => {name: "EdgesValue"}, _): macro edges(v);
			case TAbstract(_.get() => {name: "Color"}, _): macro colorOf(v);
			case TAbstract(a, _) if (a.get().meta.has(":enum")):
				var fn = "enum" + a.get().name;
				if (!enums.exists(fn)) {
					enums.set(fn, true);
					fields.push(enumParser(fn, a.get(), t));
				}
				return macro $i{fn}(v);
			case _:
				var ct = t.toComplexType();
				if (hasParse(t)) {
					var path = typeExpr(t);
					macro Std.isOfType(v, String) ? $path.parse(v) : (v : $ct);
				} else return macro(v : $ct);
		}
		return nullable ? macro v == null ? null : $e : e;
	}

	static function hasParse(t:Type):Bool
		return switch t {
			case TInst(c, _): c.get().statics.get().filter(f -> f.name == "parse").length > 0;
			case TAbstract(a, _): a.get().impl != null && a.get().impl.get().statics.get().filter(f -> f.name == "parse").length > 0;
			case _: false;
		}

	// the type's path as an expression (its module's, when it is not the module's main type)
	static function typeExpr(t:Type):Expr {
		var b:BaseType = switch t {
			case TInst(c, _): c.get();
			case TAbstract(a, _): a.get();
			case TEnum(e, _): e.get();
			case _: throw "a type";
		}
		var mod = b.module.split(".").pop();
		var path = b.pack.copy();
		if (mod != b.name) path.push(mod);
		path.push(b.name);
		return macro $p{path};
	}

	// an enum abstract's values by name (key: lower case, no - or _) and @:css
	static function enumParser(fn:String, a:AbstractType, t:Type):Field {
		var cases:Array<Case> = [];
		var path = typeExpr(t);
		var ct = t.toComplexType();
		for (f in a.impl.get().statics.get()) {
			if (!f.meta.has(":enum") || !f.kind.match(FVar(_, _))) continue;
			var keys = [key(f.name)];
			for (m in f.meta.extract(":css"))
				for (p in m.params)
					switch p.expr {
						case EConst(CString(s, _)): keys.push(key(s));
						case _:
					}
			var name = f.name;
			cases.push({values: [for (k in keys) macro $v{k}], expr: macro $path.$name});
		}
		var msg = " is not a " + a.name;
		var sw = {expr: ESwitch(macro key(v), cases, macro throw "hxmc.ui: " + v + $v{msg}), pos: Context.currentPos()};
		return {
			name: fn,
			access: [AStatic],
			pos: Context.currentPos(),
			kind: FFun({args: [{name: "v", type: macro :Dynamic}], ret: macro :Null<$ct>, expr: macro {
				if (v == null) return null;
				if (!Std.isOfType(v, String)) return v;
				return $sw;
			}})
		};
	}

	static function key(s:String):String
		return StringTools.replace(StringTools.replace(s, "-", ""), "_", "").toLowerCase();

	// [every value of an enum abstract]
	public static function values(e:Expr):Expr {
		var t = Context.getType(haxe.macro.ExprTools.toString(e));
		var abs = switch t {
			case TAbstract(a, _): a.get();
			case _: Context.error("an enum abstract", e.pos);
		}
		var path = typeExpr(t);
		var items = [for (f in abs.impl.get().statics.get()) if (f.meta.has(":enum") && f.kind.match(FVar(_, _))) {
			var n = f.name;
			macro $path.$n;
		}];
		return macro $a{items};
	}
}
#end
