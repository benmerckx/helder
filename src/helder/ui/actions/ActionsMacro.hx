package helder.ui.actions;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import helder.definition.HaxeAdapter;
import helder.definition.Kernel;
import helder.ui.actions.ActionsDefinition;
import helder.ui.actions.JsonType;

using haxe.macro.Tools;

// actions(namespace, Enum) in Haxe (Actions.hx's definition): the enum's
// constructors described to the handler (ActionsDefinition: the same
// checks as TypeScript's), then the space generated: its names and
// arguments' types as literals, and functions of the enum's own (which
// constructor a value is, its arguments, a value of them) written as
// switches, so that nothing is found by reflection at run time (-dce full
// keeps what they name). The namespace is recorded on the class where it
// is declared (@:helder.actions), each build's typed classes compared once
// typed: one declared twice is an error at the later one.
class ActionsMacro {
	public static function make(namespace:Expr, type:Expr):Expr {
		var a = new EnumAdapter();
		var pos = Context.currentPos();
		var typed = try Context.typeExpr(type) catch (_:Dynamic) null;
		var e = typed == null ? null : switch typed.expr {
			case TTypeExpr(TEnumDecl(r)): r;
			case _: null;
		}
		if (e == null) a.error("the actions are an enum, not " + type.toString(), type.pos);
		var et = e.get();
		if (et.params.length > 0) a.error('the actions are an enum without type parameters (${et.name} has some)', type.pos);
		a.enumType = et;
		var out = new ActionsDefinition().generate(new KNode(KArray([a.node(namespace), new KNode(KRef(et.name), type.pos)]), pos), a);
		record(out.namespace, namespace.pos);
		var where = Context.getPosInfos(namespace.pos);
		var origin = where.file + ":" + where.min;
		var path = et.module.split(".");
		if (path[path.length - 1] != et.name) path.push(et.name);
		var self = macro $p{path};
		var ct = TPath({pack: et.pack, name: et.module.split(".").pop(), sub: et.name == et.module.split(".").pop() ? null : et.name});
		function ctor(name:String):Expr
			return macro $p{path.concat([name])};
		var names = [for (n in et.names) n];
		var indexCases:Array<Case> = [], argsCases:Array<Case> = [], readCases:Array<Case> = [], sameCases:Array<Case> = [];
		for (i in 0...names.length) {
			var c = et.constructs.get(names[i]);
			var arity = switch c.type {
				case TFun(args, _): args.length;
				case _: 0;
			}
			var vars = [for (k in 0...arity) 'a$k'], others = [for (k in 0...arity) 'b$k'];
			function pattern(vs:Array<String>):Expr
				return arity == 0 ? ctor(names[i]) : {expr: ECall(ctor(names[i]), [for (v in vs) macro $i{v}]), pos: pos};
			indexCases.push({values: [pattern(vars)], expr: macro $v{i}});
			var params = out.actions[i].params;
			if (arity > 0) {
				argsCases.push({values: [pattern(vars)], expr: macro ([$a{[for (v in vars) macro $i{v}]}] : Array<Dynamic>)});
				var same = [for (k in 0...arity) sameExpr(params[k].type, macro $i{vars[k]}, macro $i{others[k]})];
				var all = same[0];
				for (k in 1...same.length)
					all = macro $all && ${same[k]};
				sameCases.push({values: [macro [${pattern(vars)}, ${pattern(others)}]], expr: all});
			}
			var made = arity == 0 ? ctor(names[i]) : {
				expr: ECall(ctor(names[i]), [
					for (k in 0...arity)
						readExpr(params[k].type, macro args[$v{k}], macro $v{out.namespace + "::" + out.actions[i].name + "'s " + params[k].name})
				]),
				pos: pos
			};
			readCases.push({values: [macro $v{i}], expr: made});
		}
		var indexSwitch:Expr = {expr: ESwitch(macro(v : $ct), indexCases, null), pos: pos};
		var argsSwitch:Expr = {expr: ESwitch(macro(v : $ct), argsCases, macro([] : Array<Dynamic>)), pos: pos};
		var readSwitch:Expr = {expr: ESwitch(macro i, readCases, macro null), pos: pos};
		var sameSwitch:Expr = {expr: ESwitch(macro [(a : $ct), (b : $ct)], sameCases, macro true), pos: pos};
		var list = [for (x in out.actions) info(x)];
		var infos = macro([$a{list}] : Array<helder.ui.actions.JsonType.ActionInfo>);
		return macro @:pos(pos) helder.ui.actions.Actions.register(new helder.ui.actions.Actions.ActionSpace<$ct>($v{out.namespace}, $v{origin}, $infos,
			cast $self, (v:Dynamic) -> Std.isOfType(v, $self) ? $indexSwitch : -1, (v:Dynamic) -> $argsSwitch,
			(i:Int, args:Array<Dynamic>) -> ($readSwitch : Dynamic), (i:Int, a:Dynamic, b:Dynamic) -> $sameSwitch));
	}

	static var temps = 0;

	// (an argument of type t read from a JSON value v: an object's fields by their names, as written)
	static function readExpr(t:JsonType, v:Expr, what:Expr):Expr {
		return switch t {
			case JNumber: macro helder.ui.actions.JsonType.JsonTypes.number($v, $what);
			case JInt: macro helder.ui.actions.JsonType.JsonTypes.int($v, $what);
			case JString: macro helder.ui.actions.JsonType.JsonTypes.string($v, $what);
			case JBool: macro helder.ui.actions.JsonType.JsonTypes.bool($v, $what);
			case JNull(t):
				var n = "n" + temps++;
				macro {
					var $n:Dynamic = $v;
					$i{n} == null ? null : ${readExpr(t, macro $i{n}, what)};
				}
			case JArray(t):
				var e = "e" + temps++;
				macro [for ($i{e} in helder.ui.actions.JsonType.JsonTypes.array($v, $what)) ${readExpr(t, macro $i{e}, macro $what + "[]")}];
			case JFields(fs):
				var o = "o" + temps++;
				var fields:Array<ObjectField> = [];
				for (f in fs) {
					var name = f.name;
					var read = readExpr(f.type, macro Reflect.field($i{o}, $v{name}), macro $what + $v{"." + name});
					fields.push({field: name, expr: f.optional ? macro Reflect.field($i{o}, $v{name}) == null ? null : $read : read});
				}
				var made:Expr = {expr: EObjectDecl(fields), pos: Context.currentPos()};
				macro {
					var $o:Dynamic = helder.ui.actions.JsonType.JsonTypes.object($v, $what);
					($made : Dynamic);
				}
		}
	}

	// (two arguments of type t the same)
	static function sameExpr(t:JsonType, a:Expr, b:Expr):Expr {
		return switch t {
			case JNumber | JInt | JString | JBool: macro $a == $b;
			case JNull(t):
				var x = "x" + temps++, y = "y" + temps++;
				macro {
					var $x:Dynamic = $a, $y:Dynamic = $b;
					$i{x} == null || $i{y} == null ? $i{x} == $i{y} : ${sameExpr(t, macro $i{x}, macro $i{y})};
				}
			case JArray(t):
				var x = "x" + temps++, y = "y" + temps++;
				macro helder.ui.actions.JsonType.JsonTypes.sameArrays($a, $b, ($x:Dynamic, $y:Dynamic) -> ${sameExpr(t, macro $i{x}, macro $i{y})});
			case JFields(fs):
				var x = "x" + temps++, y = "y" + temps++;
				var all:Expr = macro true;
				for (f in fs) {
					var name = f.name;
					var s = f.optional ? sameExpr(JNull(f.type), macro Reflect.field($i{x}, $v{name}), macro Reflect.field($i{y}, $v{name})) : sameExpr(f.type,
						macro Reflect.field($i{x}, $v{name}), macro Reflect.field($i{y}, $v{name}));
					all = macro $all && $s;
				}
				macro {
					var $x:Dynamic = $a, $y:Dynamic = $b;
					$all;
				}
		}
	}

	static function info(x:ActionInfo):Expr {
		var params = [for (p in x.params) macro new helder.ui.actions.JsonType.ParamInfo($v{p.name}, ${jsonType(p.type)})];
		return macro new helder.ui.actions.JsonType.ActionInfo($v{x.name}, $v{x.type}, [$a{params}]);
	}

	static function jsonType(t:JsonType):Expr
		return switch t {
			case JNumber: macro helder.ui.actions.JsonType.JNumber;
			case JInt: macro helder.ui.actions.JsonType.JInt;
			case JString: macro helder.ui.actions.JsonType.JString;
			case JBool: macro helder.ui.actions.JsonType.JBool;
			case JNull(t): macro helder.ui.actions.JsonType.JNull(${jsonType(t)});
			case JArray(t): macro helder.ui.actions.JsonType.JArray(${jsonType(t)});
			case JFields(fs):
				var list = [
					for (f in fs)
						macro new helder.ui.actions.JsonType.JsonField($v{f.name}, ${jsonType(f.type)}, $v{f.optional})
				];
				macro helder.ui.actions.JsonType.JFields([$a{list}]);
		}

	// --- a namespace declared once in the program

	static var hooked = false;

	static function record(ns:String, pos:Position) {
		var c = Context.getLocalClass();
		if (c != null) {
			var info = Context.getPosInfos(pos);
			var at = info.file + ":" + info.min;
			var meta = c.get().meta;
			if (!Lambda.exists(meta.extract(":helder.actions"), m -> switch m.params {
				case [{expr: EConst(CString(n, _))}, {expr: EConst(CString(p, _))}]: n == ns && p == at;
				case _: false;
			})) meta.add(":helder.actions", [macro $v{ns}, macro $v{at}], pos);
		}
		if (hooked) return;
		hooked = true;
		Context.onAfterTyping(check);
	}

	static function check(types:Array<ModuleType>) {
		var seen = new Map<String, {at:String, pos:Position}>();
		var all = [];
		for (t in types)
			switch t {
				case TClassDecl(c):
					for (m in c.get().meta.extract(":helder.actions"))
						switch m.params {
							case [{expr: EConst(CString(n, _))}, {expr: EConst(CString(p, _))}]: all.push({ns: n, at: p, pos: m.pos});
							case _:
						}
				case _:
			}
		all.sort((x, y) -> Reflect.compare(x.at, y.at));
		for (d in all) {
			var first = seen.get(d.ns);
			if (first == null) seen.set(d.ns, {at: d.at, pos: d.pos}) else if (first.at != d.at)
				Context.error("actions: " + ActionsDefinition.twice(d.ns), d.pos);
		}
	}
}

// The enum's constructors as the handler takes them: a constructor's name
// (its keymap name; its TypeScript object's type the name lower-cased
// first), its arguments' names and types
private class EnumAdapter extends HaxeAdapter implements ActionsAdapter {
	public var enumType:EnumType;

	public function new()
		super("actions");

	public function declared(_:KNode):Array<{name:String, type:String, params:Array<{name:String, type:ArgType, pos:KPos}>, pos:KPos}> {
		return [
			for (n in enumType.names) {
				var c = enumType.constructs.get(n);
				{
					name: n,
					type: n.charAt(0).toLowerCase() + n.substr(1),
					params: switch c.type {
						case TFun(args, _): [for (x in args) {name: x.name, type: argType(x.opt ? TAbstract(nullType(), [x.t]) : x.t), pos: (c.pos : KPos)}];
						case _: [];
					},
					pos: (c.pos : KPos)
				};
			}
		];
	}

	static function nullType():Ref<AbstractType>
		return switch Context.getType("Null") {
			case TAbstract(r, _): r;
			case _: throw "Null";
		}

	static function argType(t:Type):ArgType
		return new ArgType(TypeTools.toString(t), () -> kind(t));

	static function kind(t:Type):ArgKind {
		return switch t {
			case TMono(r): r.get() == null ? ABad("dynamic") : kind(r.get());
			case TLazy(f): kind(f());
			case TAbstract(_.get() => {pack: [], name: "Int"}, _): AInt;
			case TAbstract(_.get() => {pack: [], name: "Float"}, _): ANumber;
			case TAbstract(_.get() => {pack: [], name: "Bool"}, _): ABool;
			case TAbstract(_.get() => {pack: [], name: "Null"}, [i]): ANull(argType(i));
			case TType(_.get() => {pack: [], name: "Null"}, [i]): ANull(argType(i));
			case TAbstract(_.get() => {pack: [], name: "Dynamic" | "Any" | "EnumValue" | "Void"}, _): ABad("dynamic");
			case TAbstract(a, ps):
				var at = a.get();
				at.meta.has(":coreType") ? ABad("not a type JSON gives") : kind(at.type.applyTypeParameters(at.params, ps));
			case TInst(_.get() => {pack: [], name: "String"}, _): AString;
			case TInst(_.get() => {pack: [], name: "Array"}, [e]): AList(argType(e));
			case TInst(_.get() => {kind: KTypeParameter(_)}, _): ABad("a type parameter");
			case TInst(_, _): ABad("a class");
			case TEnum(_, _): ABad("an enum");
			case TFun(_, _): ABad("a function");
			case TDynamic(_): ABad("dynamic");
			case TType(d, ps):
				var dt = d.get();
				var inner = dt.type.applyTypeParameters(dt.params, ps);
				switch Context.follow(inner) {
					case TAnonymous(_): fields(Context.follow(inner));
					case _: kind(inner);
				}
			case TAnonymous(_): fields(t);
		}
	}

	static function fields(t:Type):ArgKind
		return switch t {
			case TAnonymous(r):
				var fs = r.get().fields.copy();
				fs.sort((x, y) -> Context.getPosInfos(x.pos).min - Context.getPosInfos(y.pos).min);
				var out = [];
				for (f in fs) {
					switch f.kind {
						case FMethod(_): return ABad("an object with methods");
						case _:
					}
					var opt = f.meta.has(":optional");
					var ft = opt ? switch f.type {
						case TAbstract(_.get() => {pack: [], name: "Null"}, [i]) | TType(_.get() => {pack: [], name: "Null"}, [i]): i;
						case x: x;
					} : f.type;
					out.push({name: f.name, type: argType(ft), optional: opt});
				}
				AFields(out);
			case _: ABad("not a type JSON gives");
		}
}
#end
