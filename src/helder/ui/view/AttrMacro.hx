package helder.ui.view;

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
// So a property added to Style is an attribute with no more code. Each
// property's conversion is a function of its own (the one above, or one made
// here), and so is setting it on a node, set<Property>(node, name, v): a
// literal attribute name in markup calls that alone (setter, NodeRenderer's
// setProperty macro), so a program links the parsers its attributes use.
class AttrMacro {
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var own = [for (f in fields) f.name => true];
		var cases:Array<Case> = [];
		var names:Array<Expr> = [];
		var enums = new Map<String, Bool>();
		var pos = Context.currentPos();
		for (f in styleProperties()) {
			var name = f.name;
			if (!own.exists(name)) {
				var conv = convert(f.type, fields, enums);
				fields.push({
					name: name,
					access: [AStatic],
					pos: pos,
					kind: FFun({args: [{name: "style", type: macro :helder.ui.Style}, {name: "v", type: macro :Dynamic}], ret: macro :Void, expr: macro style.$name = $conv})
				});
			}
			fields.push({
				name: setterName(name),
				access: [APublic, AStatic],
				pos: pos,
				kind: FFun({
					args: [{name: "n", type: macro :helder.ui.Node}, {name: "name", type: macro :String}, {name: "v", type: macro :Dynamic}],
					ret: macro :Void,
					expr: macro $i{name}(n.style, v)
				})
			});
			// (matched as written, either way: no conversion on the way)
			var kebab = kebab(name);
			cases.push({values: kebab == name ? [macro $v{name}] : [macro $v{name}, macro $v{kebab}], expr: macro $i{name}(style, v)});
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
			kind: FFun({args: [{name: "style", type: macro :helder.ui.Style}, {name: "name", type: macro :String}, {name: "v", type: macro :Dynamic}],
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

	// Style's properties that are attributes: the public ones with a setter
	static function styleProperties():Array<ClassField> {
		var style = switch Context.getType("helder.ui.Style") {
			case TInst(c, _): c.get();
			case _: throw "helder.ui.Style";
		}
		return [for (f in style.fields.get()) if (f.isPublic && f.kind.match(FVar(_, AccCall))) f];
	}

	static function kebab(name:String):String
		return ~/([A-Z])/g.map(name, r -> "-" + r.matched(1).toLowerCase());

	static function setterName(property:String):String
		return "set" + property.charAt(0).toUpperCase() + property.substr(1);

	// NodeRenderer's setAttribute, made from its own attributes (its
	// @:attribute functions, each named as the attribute or in kebab-case),
	// data-* and aria-*, then Style's (StyleAttrs.apply)
	public static function renderer():Array<Field> {
		var fields = Context.getBuildFields();
		var cases:Array<Case> = [];
		// (each by its class: an attribute may be named as setAttribute's arguments, name)
		var cls = Context.getLocalClass().get(), path = cls.pack.concat([cls.name]);
		for (f in fields)
			if (Lambda.exists(f.meta, m -> m.name == ":attribute")) {
				var name = f.name, k = kebab(f.name);
				cases.push({values: k == name ? [macro $v{name}] : [macro $v{name}, macro $v{k}], expr: macro $p{path.concat([name])}(n, name, v)});
			}
		var sw = {expr: ESwitch(macro name, cases, macro if (!StyleAttrs.apply(n.style, name, v)) noAttribute(n, name)), pos: Context.currentPos()};
		fields.push({
			name: "setAttribute",
			access: [APublic, AStatic],
			pos: Context.currentPos(),
			kind: FFun({
				args: [{name: "n", type: macro :helder.ui.Node}, {name: "name", type: macro :String}, {name: "v", type: macro :Dynamic}],
				ret: macro :Void,
				expr: macro if (StringTools.startsWith(name, "data-") || StringTools.startsWith(name, "aria-")) setData(n, name, v) else $sw
			})
		});
		return fields;
	}

	// the function setting attribute name on a node, (node, name, v): one of
	// NodeRenderer's own, data-* and aria-*, then Style's, else setAttribute
	public static function setter(name:String, pos:Position, lenient = false):Expr {
		if (StringTools.startsWith(name, "data-") || StringTools.startsWith(name, "aria-")) return macro @:pos(pos) helder.ui.view.NodeRenderer.setData;
		switch Context.getType("helder.ui.view.NodeRenderer") {
			case TInst(c, _):
				for (f in c.get().statics.get())
					if (f.meta.has(":attribute") && (f.name == name || kebab(f.name) == name)) {
						var fn = f.name;
						return macro @:pos(pos) @:privateAccess helder.ui.view.NodeRenderer.$fn;
					}
			case _:
		}
		for (f in styleProperties())
			if (f.name == name || kebab(f.name) == name) {
				var fn = setterName(f.name);
				return macro @:pos(pos) helder.ui.view.StyleAttrs.$fn;
			}
		// (another spelling camel turns into one of Style's: StyleAttrs.apply's)
		var c = camel(name);
		if (c != name) for (f in styleProperties())
			if (f.name == c) {
				var fn = setterName(f.name);
				return macro @:pos(pos) helder.ui.view.StyleAttrs.$fn;
			}
		// (a name none of them has: an error at the attribute, the name meant
		// suggested, as an unknown event is, MarkupMacro.handler; lenient, an
		// agnostic literal's element of another renderer's: looked up at run
		// time, which throws when it is set)
		if (!lenient) Context.error(unknown(name), pos);
		return macro @:pos(pos) helder.ui.view.NodeRenderer.setAttribute;
	}

	// (CSS's names that are another's here)
	static final CSS:Map<String, String> = [
		"flex-wrap" => "wrap", "flexWrap" => "wrap", "border-radius" => "radius", "borderRadius" => "radius",
		"background-color" => "background", "backgroundColor" => "background", "box-shadow" => "shadow", "boxShadow" => "shadow"
	];

	// the message for an attribute none of ui's elements has: the name meant,
	// CSS's (CSS) or the nearest of theirs
	public static function unknown(name:String):String {
		var names = [for (t in table()) if (t.name.indexOf("*") < 0) t.name];
		var meant = CSS.get(name);
		if (meant != null && names.indexOf(meant) < 0) meant = null;
		if (meant == null) {
			var best = 4;
			for (n in names) {
				var d = distance(name.toLowerCase(), n.toLowerCase());
				if (d < best) {
					best = d;
					meant = n;
				}
			}
		}
		return "helder.ui: no attribute " + name + " (not one of NodeRenderer's or Style's)" + (meant == null ? "" : "; did you mean " + meant + "?");
	}

	static function camel(n:String):String {
		if (n.indexOf("-") < 0) return n;
		var parts = n.split("-");
		return parts[0] + [for (p in parts.slice(1)) p.charAt(0).toUpperCase() + p.substr(1)].join("");
	}

	// (Levenshtein's)
	static function distance(a:String, b:String):Int {
		var prev = [for (j in 0...b.length + 1) j];
		for (i in 1...a.length + 1) {
			var cur = [i];
			for (j in 1...b.length + 1)
				cur.push(Std.int(Math.min(Math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + (a.charCodeAt(i - 1) == b.charCodeAt(j - 1) ? 0 : 1))));
			prev = cur;
		}
		return prev[b.length];
	}

	// what setter resolves at compile time, as names to their functions' paths
	// (each attribute's, as named and in kebab-case; data-* and aria-* as
	// prefixes, * any other name: setAttribute): helder.typescript's manifest
	// lists them (NodeRenderer.setterTable)
	public static function table():Array<{name:String, fn:String}> {
		var out = [
			{name: "data-*", fn: "helder.ui.view.NodeRenderer.setData"},
			{name: "aria-*", fn: "helder.ui.view.NodeRenderer.setData"}
		];
		var seen = new Map<String, Bool>();
		function add(n:String, fn:String)
			for (k in [n, kebab(n)])
				if (!seen.exists(k)) {
					seen.set(k, true);
					out.push({name: k, fn: fn});
				}
		// (setter's order: the renderer's own attributes, then Style's)
		switch Context.getType("helder.ui.view.NodeRenderer") {
			case TInst(c, _):
				for (f in c.get().statics.get())
					if (f.meta.has(":attribute")) add(f.name, "helder.ui.view.NodeRenderer." + f.name);
			case _:
		}
		for (f in styleProperties())
			add(f.name, "helder.ui.view.StyleAttrs." + setterName(f.name));
		out.push({name: "*", fn: "helder.ui.view.NodeRenderer.setAttribute"});
		return out;
	}

	// v as the type t
	static function convert(t:Type, fields:Array<Field>, enums:Map<String, Bool>):Expr {
		var nullable = false;
		switch lazy(t) {
			case TAbstract(_.get() => {name: "Null", pack: []}, [inner]):
				t = lazy(inner);
				nullable = true;
			case TType(_.get() => {name: "Null", pack: []}, [inner]):
				t = lazy(inner);
				nullable = true;
			case l = TType(_, _):
				// (a typedef: its type; ui's Cursor is helder.os's)
				t = lazy(Context.follow(l, true));
			case l:
				t = l;
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

	// t, typed if it is not yet (a field's type read before its class is typed)
	static function lazy(t:Type):Type {
		while (true)
			switch t {
				case TLazy(f): t = f();
				case _: return t;
			}
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
		var sw = {expr: ESwitch(macro key(v), cases, macro throw "helder.ui: " + v + $v{msg}), pos: Context.currentPos()};
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
