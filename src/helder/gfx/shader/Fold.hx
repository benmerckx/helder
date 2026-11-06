package helder.gfx.shader;

import helder.gfx.shader.Ir;

// A variant's constants folded (both adapters, a slot object's variant
// only: other shaders print what they are written as): a test of options,
// !, &&, || and comparisons of constants, and the arithmetic of integer and
// float constants, so that an if on them takes one branch at build time and
// a loop over them is unrolled.
class Fold {
	public static function expr(x:SExpr):SExpr {
		return switch x.e {
			case EUnop(Not, {e: EBool(b)}): {e: EBool(!b), t: TBool};
			case EUnop(Neg, {e: EInt(i)}): {e: EInt(-i), t: x.t};
			case EUnop(Neg, {e: EFloat(f)}): {e: EFloat(-f), t: x.t};
			case EBinop(And, {e: EBool(a)}, y): a ? y : {e: EBool(false), t: TBool};
			case EBinop(Or, {e: EBool(a)}, y): a ? {e: EBool(true), t: TBool} : y;
			// (shader code has no side effects but a statement's: y may go)
			case EBinop(And, y, {e: EBool(b)}): b ? y : {e: EBool(false), t: TBool};
			case EBinop(Or, y, {e: EBool(b)}): b ? {e: EBool(true), t: TBool} : y;
			case EBinop(op, {e: EBool(a)}, {e: EBool(b)}):
				switch op {
					case Eq: {e: EBool(a == b), t: TBool};
					case Ne: {e: EBool(a != b), t: TBool};
					case _: x;
				}
			case EBinop(op, {e: EInt(a)}, {e: EInt(b)}):
				switch op {
					case Add: {e: EInt(a + b), t: x.t};
					case Sub: {e: EInt(a - b), t: x.t};
					case Mul: {e: EInt(a * b), t: x.t};
					case Eq | Ne | Lt | Le | Gt | Ge: {e: EBool(compare(op, a, b)), t: TBool};
					case _: x;
				}
			case EBinop(op, {e: EFloat(a)}, {e: EFloat(b)}):
				switch op {
					case Eq | Ne | Lt | Le | Gt | Ge: {e: EBool(compare(op, a, b)), t: TBool};
					case _: x;
				}
			case _: x;
		}
	}

	static function compare(op:SBinop, a:Float, b:Float):Bool
		return switch op {
			case Eq: a == b;
			case Ne: a != b;
			case Lt: a < b;
			case Le: a <= b;
			case Gt: a > b;
			case _: a >= b;
		}
}
