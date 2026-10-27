package helder.web;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

// Exports' build macro: in a wasm32-wasi module, a @:hxmc.callback wrapper
// per function and register(); in JavaScript, the functions calling the
// module (Exports explains both).
class ExportsMacro {
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var exported = [for (f in fields) switch f.kind {
			case FFun(fn) if (f.access.contains(APublic) && f.access.contains(AStatic) && !f.access.contains(AMacro) && f.name != "main"):
				{field: f, fn: fn};
			case _: null;
		}].filter(x -> x != null);
		for (e in exported) {
			for (a in e.fn.args)
				kind(a.type, a.name, e.field.pos, false);
			kind(e.fn.ret, "the result", e.field.pos, true);
		}
		if (Context.defined("js")) return js(exported);
		if (Context.definedValue("hxmc.target") == "wasm32-wasi") return wasm(fields, exported);
		return fields;
	}

	// what crosses: Int, Float, Bool, String, Bytes (Void: a result only)
	static function kind(t:Null<ComplexType>, what:String, pos:Position, result:Bool):String {
		var name = switch t {
			case null: null;
			case TPath({pack: [], name: n, params: null | []}) | TPath({pack: ["StdTypes"], name: n}): n;
			case TPath({pack: ["haxe", "io"], name: "Bytes"}): "Bytes";
			case _: null;
		}
		if (name == "Int" || name == "Float" || name == "Bool" || name == "String" || name == "Bytes" || (result && name == "Void")) return name;
		return Context.error('helder.web.Exports: $what must be typed Int, Float, Bool, String or haxe.io.Bytes' + (result ? " (or Void)" : ""), pos);
	}

	static function wasm(fields:Array<Field>, exported:Array<{field:Field, fn:Function}>):Array<Field> {
		var cls = Context.getLocalClass().get();
		var path = cls.pack.concat([cls.name]);
		var defines = [macro helder.web.WasmBridge.start()];
		for (e in exported) {
			var f = e.field, pos = f.pos;
			var args:Array<FunctionArg> = [], call:Array<Expr> = [];
			for (a in e.fn.args) {
				var p = macro $i{"__" + a.name};
				switch kind(a.type, a.name, pos, false) {
					case "Int":
						args.push({name: "__" + a.name, type: macro :Int});
						call.push(p);
					case "Float":
						args.push({name: "__" + a.name, type: macro :Float});
						call.push(p);
					case "Bool":
						args.push({name: "__" + a.name, type: macro :Int});
						call.push(macro $p != 0);
					case k:
						var n = macro $i{"__" + a.name + "_length"};
						args.push({name: "__" + a.name, type: macro :Int});
						args.push({name: "__" + a.name + "_length", type: macro :Int});
						call.push(k == "Bytes" ? macro helder.web.WasmBridge.bytesIn($p, $n) : macro helder.web.WasmBridge.bytesIn($p, $n).toString());
				}
			}
			var c = {expr: ECall(macro $p{path.concat([f.name])}, call), pos: pos};
			var ret:ComplexType = macro :Int;
			var body = switch kind(e.fn.ret, "the result", pos, true) {
				case "Void":
					ret = macro :Void;
					c;
				case "Int": macro return $c;
				case "Float":
					ret = macro :Float;
					macro return $c;
				case "Bool": macro return $c ? 1 : 0;
				case "Bytes": macro return helder.web.WasmBridge.bytesOut($c);
				case _: macro return helder.web.WasmBridge.stringOut($c);
			}
			var name = "__export_" + f.name;
			fields.push({
				name: name,
				access: [AStatic],
				pos: pos,
				meta: [{name: ":hxmc.callback", pos: pos}],
				kind: FFun({args: args, ret: ret, expr: body})
			});
			defines.push(macro helder.web.WasmBridge.define($v{f.name}, hxmc.unsafe.Callback.addr($p{path.concat([name])})));
		}
		fields.push({
			name: "register",
			access: [APublic, AStatic],
			pos: Context.currentPos(),
			kind: FFun({args: [], ret: macro :Void, expr: macro $b{defines}})
		});
		return fields;
	}

	static function js(exported:Array<{field:Field, fn:Function}>):Array<Field> {
		var out:Array<Field> = [];
		var pos = Context.currentPos();
		out.push({
			name: "module",
			access: [APublic, AStatic],
			pos: pos,
			kind: FVar(macro :Null<helder.web.WasmModule>, macro null)
		});
		for (e in exported) {
			var f = e.field, pos = f.pos;
			var pre:Array<Expr> = [], post:Array<Expr> = [], call:Array<Expr> = [];
			for (a in e.fn.args) {
				var p = macro $i{a.name};
				switch kind(a.type, a.name, pos, false) {
					case "Int" | "Float": call.push(p);
					case "Bool": call.push(macro $p ? 1 : 0);
					case k:
						var b = "__" + a.name;
						pre.push(k == "Bytes" ? macro var $b = __m.copyIn($p) : macro var $b = __m.copyIn(haxe.io.Bytes.ofString($p)));
						call.push(macro $i{b}.address);
						call.push(macro $i{b}.length);
						post.push(macro __m.free($i{b}.address));
				}
			}
			var c = macro __m.call($v{f.name}, $a{call});
			var result = switch kind(e.fn.ret, "the result", pos, true) {
				case "Void": macro {};
				case "Bool": macro return __r != 0;
				case "Bytes": macro return __m.copyOut(__r);
				case "String":
					macro {
						var __b = __m.copyOut(__r);
						return __b == null ? null : __b.toString();
					};
				case _: macro return __r;
			}
			// (the copies' variables in the function's own block)
			var body = macro $b{
				[
					(macro var __m = module),
					macro if (__m == null) throw "helder.web: " + $v{f.name} + ": no module (set module to a WasmModule)"
				].concat(pre).concat([
					macro var __r:Dynamic = try $c catch (e:Dynamic) {
						$b{post};
						throw e;
					}
				]).concat(post).concat([result])
			};
			out.push({
				name: f.name,
				doc: f.doc,
				access: f.access,
				pos: pos,
				meta: f.meta,
				kind: FFun({args: e.fn.args, ret: e.fn.ret, expr: body, params: e.fn.params})
			});
		}
		return out;
	}
}
#end
