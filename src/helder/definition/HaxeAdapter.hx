package helder.definition;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import helder.definition.Kernel;

// The Haxe side of definitions (DESIGN.md 2): a definition is a `macro`
// function marked @:definition, a forwarder that hands its argument to this
// adapter and returns what the handler's output makes:
//
//   @:definition public static macro function shader(def:Expr):Expr
//     return helder.gfx.shader.ShaderMacro.shader(def);
//
// node(e) makes the argument's kernel tree (Kernel) from the untyped
// expression, rejecting what is not static at its position; a function's
// source is its expression, which the handler's lowering types at the
// call (Context.typeExpr, in the caller's imports).
class HaxeAdapter implements Adapter {
	// the definition's name, prefixed to its diagnostics ("shader: ...")
	public final what:String;

	public function new(what:String) {
		this.what = what;
	}

	public function error(message:String, pos:KPos):Dynamic
		return Context.error('$what: $message', pos);

	public function defined(name:String):Null<String>
		return Context.definedValue(name);

	public function node(e:Expr):KNode {
		var pos:KPos = e.pos;
		return new KNode(switch e.expr {
			case EConst(CString(s, _)): KString(s);
			case EConst(CInt(s, _)): KInt(Std.parseInt(s));
			case EConst(CFloat(s, _)): KFloat(Std.parseFloat(s));
			case EConst(CIdent("true")): KBool(true);
			case EConst(CIdent("false")): KBool(false);
			case EConst(CIdent("null")): KNull;
			case EParenthesis(x) | ECheckType(x, _): return node(x);
			case EMeta(_, x): return node(x);
			case EObjectDecl(fields):
				var seen = new Map<String, Bool>();
				KObject([
					for (f in fields) {
						if (seen.exists(f.field)) error('the field ${f.field} is given twice', f.expr.pos);
						seen.set(f.field, true);
						{name: f.field, node: node(f.expr)};
					}
				]);
			case EArrayDecl(items): KArray([for (x in items) node(x)]);
			case EFunction(kind, f):
				var name = switch kind {
					case FNamed(n, _): n;
					case _: null;
				}
				KFunction(new KFunction(name, [for (a in f.args) a.name], pos, e));
			case EConst(CIdent(_)) | EField(_, _): KRef(reference(e));
			case EUnop(OpNeg, false, {expr: EConst(CInt(s, _))}): KInt(-Std.parseInt(s));
			case EUnop(OpNeg, false, {expr: EConst(CFloat(s, _))}): KFloat(-Std.parseFloat(s));
			case _: notStatic(e);
		}, pos);
	}

	// a module-level constant or definition (a final static): its path
	function reference(e:Expr):String {
		var t = try Context.typeExpr(e) catch (_:Dynamic) notStatic(e);
		return switch t.expr {
			case TField(_, FStatic(c, cf)):
				var cf = cf.get();
				switch cf.kind {
					case FVar(_, AccNever | AccCtor | AccInline):
						var c = c.get();
						c.pack.concat([c.name, cf.name]).join(".");
					case _: error('${cf.name} is not a constant (a definition reads module-level finals and other definitions)', e.pos);
				}
			case _: notStatic(e);
		}
	}

	function notStatic(e:Expr):Dynamic
		return error(haxe.macro.ExprTools.toString(e)
			+ " is not static (a definition takes literals, object and array literals, functions, and module-level constants and definitions)",
			e.pos);
}
#end
