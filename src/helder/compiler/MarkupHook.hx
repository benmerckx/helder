package helder.compiler;

import core.Ast;
import core.ds.VectorTools.vector;
import syntax.Parser.ParseResult;

// Markup in any function (DESIGN.md 3.5): each file helder's compiler parses
// has its markup literals (@:markup "<...>", Haxe's parse of <view/>)
// wrapped as `implements Markup` wraps them, helder.view.View.literal(@:markup
// "<...>"), compiled when they are typed (MarkupMacro.literal), so that a
// module-level function or a class of no interface returns markup. Done on
// the parsed file in place (a compilation server keeps it: wrapped once).
class MarkupHook {
	static var installed:Null<Dynamic> = null;

	// around hxmc's parse (again when a compilation server has replaced it)
	public static function install() {
		var current:Dynamic = typing.TypeloadParse.parseHook;
		if (installed != null && current == installed) return;
		var inner = typing.TypeloadParse.parseHook;
		var hook = function(com, rfile, p) {
			var r = inner(com, rfile, p);
			if (!com.isMacroContext) switch r {
				case ParseSuccess(data, _) | ParseError(data, _, _): wrap(data);
			}
			return r;
		}
		installed = hook;
		typing.TypeloadParse.parseHook = hook;
	}

	static function wrap(pack:Package) {
		for (d in pack.declarations)
			switch d.definition {
				case EClass(c):
					for (f in c.data)
						f.cffKind = kind(f.cffKind);
				case EAbstract(a):
					for (f in a.data)
						f.cffKind = kind(f.cffKind);
				case EStatic(s): s.data = kind(s.data);
				case _:
			}
	}

	static function kind(k:ClassFieldKind):ClassFieldKind
		return switch k {
			case FFun(f):
				if (f.fExpr != null && has(f.fExpr)) f.fExpr = literals(f.fExpr);
				k;
			case FVar(t, e) if (e != null && has(e)): FVar(t, literals(e));
			case FProp(g, s, t, e) if (e != null && has(e)): FProp(g, s, t, literals(e));
			case _: k;
		}

	static function isMarkup(e:Expr):Bool
		return switch e.expr {
			case EMeta(m, {expr: EConst(String(_))}): core.Meta.metaEq(core.MetaList.StrictMeta.Markup, m.meta);
			case _: false;
		}

	// (a literal wrapped already: View.literal's, literalFor's)
	static function wrapped(e:Expr):Bool
		return switch e.expr {
			case ECall({expr: EField(_, "literal" | "literalFor", _)}, args):
				args.length > 0 && isMarkup(args[args.length - 1]);
			case _: false;
		}

	static function has(e:Expr):Bool {
		if (isMarkup(e) && !wrapped(e)) return true;
		var found = false;
		Ast.iterExpr(x -> if (!found && !wrapped(x) && has(x)) found = true, e);
		return found;
	}

	static function literals(e:Expr):Expr {
		if (wrapped(e)) return e;
		if (isMarkup(e)) {
			var p = e.pos;
			var callee:Expr = {expr: EConst(Ident("helder")), pos: p};
			for (n in ["view", "View", "literal"])
				callee = {expr: EField(callee, n, EFNormal), pos: p};
			return {expr: ECall(callee, vector(e)), pos: p};
		}
		return Ast.mapExpr(literals, e);
	}
}
