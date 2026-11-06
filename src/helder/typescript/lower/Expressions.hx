package helder.typescript.lower;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;
import hxmc.ir.Ir;
import haxe.ds.Vector;
import helder.typescript.ir.Builder;
import helder.typescript.check.Types;
import helder.typescript.lower.Classes.ClassLayout;
import helder.typescript.lower.Api;
import helder.typescript.lower.Core;
import helder.typescript.lower.Core.*;

// Expressions: operators, assignments, object literals, calls and
// constructions, optional chains and spreads.
@:access(helder.typescript.lower.Core)
abstract class Expressions extends Statements {
	function expr(n:Node):Ex {
		expressions++;
		var x = api == null ? null : apiExpr(n);
		if (x != null) return x;
		// (helder/platform's constants, and conditions of them: a literal)
		var k:Dynamic = n.kind == KindPropertyAccessExpression || n.kind == KindBinaryExpression || n.kind == KindPrefixUnaryExpression ? platform.constant(n) : null;
		if (k != null) return Std.isOfType(k, Bool) ? ECast(TBool, EInt(k ? 1 : 0)) : EStr(k);
		if (Platform.bare(n)) fail(n, "helder/platform's platform is the build's constants: read its fields (platform.os, platform.target, platform.arm)");
		var result:Ex = switch (n.kind) {
			case KindPropertyAccessExpression | KindElementAccessExpression | KindCallExpression if (chainTop(n)): optionalChain(n);
			case KindNumericLiteral: EF64(Std.parseFloat(n.text));
			case KindStringLiteral | KindNoSubstitutionTemplateLiteral: EStr(n.text);
			case KindTrueKeyword: ECast(TBool, EInt(1));
			case KindFalseKeyword: ECast(TBool, EInt(0));
			case KindNullKeyword: ENull(TRef(RAny));
			case KindThisKeyword: env.exists("this") ? read(env.get("this")) : b.runtime("getUndefined", []);
			case KindArrowFunction | KindFunctionExpression: closure(n, takeName());
			case KindClassExpression: classValue(n, takeName());
			case KindMetaProperty: env.exists("%newTarget") ? read(env.get("%newTarget")) : b.runtime("getUndefined", []);
			case KindNewExpression: construct(n);
			case KindIdentifier:
				var name = n.text;
				if (name == "undefined") b.runtime("getUndefined", []);
				else if (name == "NaN") EF64(Math.NaN);
				else if (name == "Infinity") EF64(Math.POSITIVE_INFINITY);
				else if (!env.exists(name) && functions.exists(name)) read(functionValues.get(name));
				// (in a namespace, a member exported by another declaration of it)
				else if (!env.exists(name) && env.exists("%namespace")) b.runtime("libNamespaceGet", [read(env.get("%namespace")), EStr(name)]);
				else if (!env.exists(name)) b.runtime("libGlobal", [EStr(name)]);
				else read(get(name, n));
			case KindParenthesizedExpression | KindAsExpression | KindTypeAssertionExpression | KindNonNullExpression | KindSatisfiesExpression: expr(n.expression());
			case KindBinaryExpression: binary(n);
			case KindPrefixUnaryExpression:
				var u = n;
				var x:Ex;
				if (u.unaryOperator() == KindPlusPlusToken || u.unaryOperator() == KindMinusMinusToken) {
					var target = numberElement(strip(u.operand())) ? numberTarget(strip(u.operand())) : lvalue(u.operand());
					x = b.temp(EBin(u.unaryOperator() == KindPlusPlusToken ? FAdd : FSub, b.coerce(target.read(), TF64), EF64(1)));
					target.write(x);
				}
				else x = u.unaryOperator() == KindMinusToken || u.unaryOperator() == KindPlusToken ? numeric(u.operand(), false) : expr(u.operand());
				switch (u.unaryOperator()) {
					case KindMinusToken: EConv(FNeg, b.coerce(x, TF64));
					case KindPlusToken: b.coerce(x, TF64);
					case KindExclamationToken: ENot(truth(x));
					case KindPlusPlusToken | KindMinusMinusToken: x;
					case KindTildeToken: EConv(I2F, EBin(Xor, b.runtime("libInt", [any(x)]), EInt(-1)));
					case _: fail(n, "unsupported unary operator");
				}
			case KindPostfixUnaryExpression:
				var u = n;
				var target = numberElement(strip(u.operand())) ? numberTarget(strip(u.operand())) : lvalue(u.operand());
				var previous = b.temp(b.coerce(target.read(), TF64));
				target.write(EBin(u.unaryOperator() == KindPlusPlusToken ? FAdd : FSub, previous, EF64(1)));
				previous;
			case KindVoidExpression:
				expr(n.expression());
				b.runtime("getUndefined", []);
			case KindTaggedTemplateExpression:
				var t = n;
				var template = t.template();
				var parts = template.kind == KindNoSubstitutionTemplateLiteral ? [template] : [template.head()].concat([for (span in template.templateSpans()) span.literal()]);
				var values = template.kind == KindNoSubstitutionTemplateLiteral ? [] : [for (span in template.templateSpans()) span.expression()];
				// (one frozen strings array per call site, created on first use)
				var site = global("%template" + serial++);
				b.out.push(SIf(ENot(b.runtime("libIsObject", [read(site)])), b.block(() -> set(site, b.runtime("libTemplateObject", [pack([for (x in parts) EStr(x.text)]), pack([for (x in parts) EStr(x.kind == KindNoSubstitutionTemplateLiteral ? x.rawText() : x.rawText())])]))), new Vector(0)));
				var tag = t.tag();
				while (tag.kind == KindParenthesizedExpression) tag = tag.expression();
				if ((tag.kind == KindPropertyAccessExpression || tag.kind == KindElementAccessExpression) && tag.expression().kind != KindSuperKeyword) {
					var obj = b.temp(any(expr(tag.expression())));
					var key = tag.kind == KindPropertyAccessExpression ? EStr(tag.name().text) : any(expr(tag.argumentExpression()));
					b.runtime("libCallMethod", [obj, key, pack([read(site)].concat(actuals(values)))]);
				}
				else {
					var fn = any(expr(t.tag()));
					b.runtime("libCall", [fn, b.runtime("getUndefined", []), pack([read(site)].concat(actuals(values)))]);
				}
			case KindRegularExpressionLiteral:
				var text = n.text;
				var slash = text.lastIndexOf("/");
				b.runtime("libRegExp", [EStr(text.substring(1, slash)), EStr(text.substr(slash + 1))]);
			case KindYieldExpression:
				if (b.resumable == null || !b.resumable.generator) fail(n, "yield outside a generator");
				if (n.asteriskToken() != null) {
					if (b.resumable.async) fail(n, "yield* in async generators is not implemented yet");
					delegate(any(expr(n.expression())));
				}
				else {
					var v = n.expression() == null ? b.runtime("getUndefined", []) : any(expr(n.expression()));
					// (an async generator awaits what it yields)
					if (b.resumable.async) v = yieldPoint(v, true, AWAIT);
					yieldPoint(v, true);
				}
			case KindAwaitExpression:
				if (b.resumable == null || !b.resumable.async) fail(n, "await outside an async function");
				yieldPoint(any(expr(n.expression())), true, AWAIT);
			case KindTemplateExpression:
				var t = n;
				var result:Ex = EStr(t.head().text);
				for (span in t.templateSpans()) {
					var piece = span;
					result = b.runtime("concat", [result, b.runtime("text", [any(expr(piece.expression()))])]);
					result = b.runtime("concat", [result, EStr(piece.literal().text)]);
				}
				result;
			case KindTypeOfExpression:
				var value = n.expression();
				while (value.kind == KindParenthesizedExpression) value = value.expression();
				if (value.kind == KindIdentifier && !env.exists(value.text) && !functions.exists(value.text)) {
					env.exists("%namespace") ? b.runtime("libTypeofNamespace", [read(env.get("%namespace")), EStr(value.text)]) : b.runtime("libTypeofGlobal", [EStr(value.text)]);
				}
				else b.runtime("typeOf", [any(expr(value))]);
			case KindCallExpression: call(n);
			case KindArrayLiteralExpression if (numberLiteral(n)):
				typedOperations++;
				var xs = [for (e in elements(n)) expr(e)];
				xs.filter(x -> Ir.typeOf(x) != TF64).length == 0 ? reps.numberArray(b, xs) : ECast(TRef(RObj(reps.arrayClass)), b.runtime("libArrayNumbers", [pack(xs)]));
			case KindArrayLiteralExpression:
				if (hasSpread(elements(n))) b.runtime("libArray", [spreadList(elements(n))]);
				else b.runtime("libArray", [pack([for (e in elements(n)) e.kind == KindOmittedExpression ? b.runtime("libHole", []) : expr(e)])]);
			case KindElementAccessExpression if (n.expression().kind == KindSuperKeyword):
				b.runtime("libSuperGet", [read(get("%home", n)), thisValue(), any(expr(n.argumentExpression()))]);
			case KindElementAccessExpression if (arrayElement(n)):
				var obj = b.temp(expr(n.expression()));
				typedOperations++;
				reps.arrayGet(b, obj, b.temp(number(expr(n.argumentExpression()))));
			case KindElementAccessExpression:
				var obj = expr(n.expression());
				chainCheck(n, obj);
				var key = expr(n.argumentExpression());
				dynamicOperations++;
				b.runtime("libGet", [any(obj), any(key)]);
			case KindObjectLiteralExpression: objectLiteral(n);
			case KindPropertyAccessExpression if (n.expression().kind == KindSuperKeyword):
				b.runtime("libSuperGet", [read(get("%home", n)), thisValue(), EStr(n.name().text)]);
			case KindPropertyAccessExpression if (n.name().kind == KindPrivateIdentifier):
				var a = expr(n.expression());
				chainCheck(n, a);
				b.runtime("libPrivateGet", [any(a), EStr(brand(n.name()))]);
			case KindPropertyAccessExpression if (n.name().text == "length" && plainAccess(n) && types.isString(n.expression().tsType)):
				typedOperations++;
				var s = b.temp(expr(n.expression()));
				Ir.typeOf(s).match(TRef(RStr)) ? b.runtime("stringLength", [s]) : b.coerce(b.runtime("libGet", [any(s), EStr("length")]), TF64);
			case KindPropertyAccessExpression if (n.name().text == "length" && plainAccess(n) && types.isArray(n.expression().tsType)):
				typedOperations++;
				reps.arrayLength(b, b.temp(expr(n.expression())));
			case KindPropertyAccessExpression if (layoutField(n) != null):
				typedOperations++;
				reps.fieldGet(b, layoutField(n), b.temp(expr(n.expression())), n.name().text, where());
			case KindPropertyAccessExpression:
				var a = expr(n.expression());
				var name = n.name().text;
				chainCheck(n, a);
				dynamicOperations++;
				b.runtime("libGet", [any(a), EStr(name)]);
			case KindDeleteExpression:
				var target = n.expression();
				if (target.kind == KindPropertyAccessExpression) b.runtime("libDelete", [any(expr(target.expression())), EStr(target.name().text)]);
				else if (target.kind == KindElementAccessExpression) {
					var obj = expr(target.expression());
					b.runtime("libDelete", [any(obj), any(expr(target.argumentExpression()))]);
				}
				else fail(n, "delete requires a property");
			case KindConditionalExpression if (platform.constant(n.condition()) != null):
				// (a platform's constant: only the branch taken)
				expr(Platform.truthy(platform.constant(n.condition())) ? n.whenTrue() : n.whenFalse());
			case KindConditionalExpression:
				var c = n;
				var cond = truth(expr(c.condition()));
				var l = b.local("conditional", reps.rep(n.tsType));
				var yes = b.block(() -> b.out.push(SSet(l, store(valueFor(c.whenTrue(), l.ty), l.ty))));
				var no = b.block(() -> b.out.push(SSet(l, store(valueFor(c.whenFalse(), l.ty), l.ty))));
				b.out.push(SIf(cond, yes, no));
				ELocal(l);
			case _: fail(n, "unsupported expression " + n.kind.toString());
		};
		if (Ir.typeOf(result).match(TRef(RAny))) dynamicSites++; else typed++;
		return switch (result) {
			case EInt(_) | EF64(_) | EStr(_) | ENull(_) | ELocal(_): result;
			case _: b.temp(result);
		};
	}

	function lvalue(n:Node):{read:() -> Ex, write:Ex->Void} {
		while (n.kind == KindParenthesizedExpression || n.kind == KindNonNullExpression || n.kind == KindAsExpression || n.kind == KindSatisfiesExpression || n.kind == KindTypeAssertionExpression) n = n.expression();
		var member = api == null ? null : apiTarget(n);
		if (member != null) return member;
		if (n.kind == KindIdentifier) {
			var v = get(n.text, n);
			return {read: () -> b.temp(read(v)), write: (e) -> set(v, e)};
		}
		if ((n.kind == KindPropertyAccessExpression || n.kind == KindElementAccessExpression) && n.expression().kind == KindSuperKeyword) {
			var key = n.kind == KindPropertyAccessExpression ? EStr(n.name().text) : b.temp(any(expr(n.argumentExpression())));
			var home = read(get("%home", n));
			return {
				read: () -> b.runtime("libSuperGet", [home, thisValue(), key]),
				write: (e) -> {
					b.runtime("libSuperSet", [home, thisValue(), key, any(e)]);
				}
			};
		}
		if (n.kind == KindPropertyAccessExpression && n.name().kind == KindPrivateIdentifier) {
			var obj = b.temp(any(expr(n.expression())));
			var key = EStr(brand(n.name()));
			return {
				read: () -> b.runtime("libPrivateGet", [obj, key]),
				write: (e) -> {
					b.runtime("libPrivateSet", [obj, key, any(e)]);
				}
			};
		}
		if (arrayElement(n)) {
			var obj = b.temp(expr(n.expression()));
			var key = b.temp(number(expr(n.argumentExpression())));
			var numbers = numberElement(n);
			return {
				read: () -> reps.arrayGet(b, obj, key),
				write: (e) -> numbers && Ir.typeOf(e) == TF64 ? reps.arraySetNumber(b, obj, key, e) : reps.arraySet(b, obj, key, e)
			};
		}
		var field = layoutField(n);
		if (field != null) {
			var obj = b.temp(expr(n.expression()));
			var name = n.name().text;
			return {
				read: () -> reps.fieldGet(b, field, obj, name, where()),
				write: (e) -> reps.fieldSet(b, field, obj, name, e, where())
			};
		}
		if (n.kind == KindPropertyAccessExpression || n.kind == KindElementAccessExpression) {
			var obj = expr(n.expression());
			var key = n.kind == KindPropertyAccessExpression ? EStr(n.name().text) : expr(n.argumentExpression());
			return {
				read: () -> b.runtime("libGet", [any(obj), any(key)]),
				write: (e) -> {
					b.runtime("libPut", [any(obj), any(key), any(e)]);
				}
			};
		}
		return fail(n, "unsupported assignment target");
	}

	function strictEquals(a:Ex, z:Ex):Ex return equals(a, z, true);

	// (a null or undefined literal: which)
	function nullish(n:Node):Null<String> {
		while (n.kind == KindParenthesizedExpression) n = n.expression();
		return n.kind == KindNullKeyword ? "null" : n.kind == KindIdentifier && n.text == "undefined" && !env.exists("undefined") ? "undefined" : null;
	}

	// whether a value is null, undefined, or (which: null) either: by reference
	function isNullish(e:Ex, which:Null<String>):Ex {
		var v = b.temp(any(e));
		var isNull = EBin(RefEq, v, ENull(TRef(RAny))), isUndefined = EBin(RefEq, v, b.runtime("getUndefined", []));
		typedOperations++;
		if (which == "null") return isNull;
		if (which == "undefined") return isUndefined;
		var l = b.local("nullish", TBool);
		b.out.push(SSet(l, isNull));
		b.out.push(SIf(ENot(ELocal(l)), Vector.fromArrayCopy([SSet(l, isUndefined)]), new Vector(0)));
		return ELocal(l);
	}

	function equals(a:Ex, z:Ex, strict:Bool):Ex {
		var direct:Ex = null;
		if (Ir.typeOf(a) == TF64 && Ir.typeOf(z) == TF64) direct = EBin(FEq, a, z);
		if (Ir.typeOf(a) == TBool && Ir.typeOf(z) == TBool) direct = EBin(Eq, a, z);
		if (Ir.typeOf(a).match(TRef(RStr)) && Ir.typeOf(z).match(TRef(RStr))) direct = b.runtime("stringEq", [a, z]);
		if (direct != null) {
			typedOperations++;
			return direct;
		}
		dynamicOperations++;
		return b.runtime(strict ? "strictEq" : "looseEq", [any(a), any(z)]);
	}

	function binary(n:Node):Ex {
		var x = n;
		var op = x.operatorToken().kind;
		if (op == KindCommaToken) {
			expr(x.left());
			return expr(x.right());
		}
		if (op >= KindFirstAssignment && op <= KindLastAssignment) return assign(n);
		if (op == KindInKeyword && x.left().kind == KindPrivateIdentifier) return b.runtime("libPrivateHas", [any(expr(x.right())), EStr(brand(x.left()))]);
		var a = numericOperator(op, n) ? numeric(x.left(), false) : expr(x.left());
		if (op == KindAmpersandAmpersandToken || op == KindBarBarToken || op == KindQuestionQuestionToken) {
			// (the result, the left or the right value, in a slot of the expression's type)
			var l = b.local("shortCircuit", reps.rep(n.tsType));
			var right = op == KindQuestionQuestionToken ? isNullish(a, null) : op == KindBarBarToken ? ENot(truth(a)) : truth(a);
			var lhs = b.block(() -> b.out.push(SSet(l, store(a, l.ty))));
			var rhs = b.block(() -> b.out.push(SSet(l, store(expr(x.right()), l.ty))));
			b.out.push(SIf(right, rhs, lhs));
			return ELocal(l);
		}
		if (op == KindInstanceOfKeyword) return b.runtime("libInstanceOf", [any(a), any(expr(x.right()))]);
		return operate(op, a, numericOperator(op, n) ? numeric(x.right(), false) : expr(x.right()), n);
	}
	function assign(n:Node):Ex {
		var x = n;
		var op = x.operatorToken().kind;
		var left = x.left();
		while (left.kind == KindParenthesizedExpression) left = left.expression();
		if (op == KindPlusEqualsToken && left.kind == KindIdentifier && env.exists(left.text) && env.get(left.text).buffer != null) {
			b.runtime("libBufferAdd", [ELocal(env.get(left.text).buffer), text(expr(x.right()))]);
			return b.runtime("getUndefined", []);
		}
		if (op == KindEqualsToken && (left.kind == KindArrayLiteralExpression || left.kind == KindObjectLiteralExpression)) {
			var e = b.temp(any(expr(x.right())));
			assignPattern(left, e);
			return e;
		}
		var arithmetic = op != KindEqualsToken && compound.exists(op) && numericOperator(compound.get(op), n);
		var target = arithmetic && numberElement(left) ? numberTarget(left) : lvalue(x.left());
		if (op == KindEqualsToken) {
			var e = numberSlot(left) ? numeric(x.right(), true) : named(x.right(), left.kind == KindIdentifier ? left.text : null);
			target.write(e);
			return e;
		}
		if (op == KindBarBarEqualsToken || op == KindAmpersandAmpersandEqualsToken || op == KindQuestionQuestionEqualsToken) {
			// (the right side is evaluated and stored only when it is needed)
			var previous = target.read();
			var l = b.local("logical", TRef(RAny));
			b.out.push(SSet(l, any(previous)));
			var cond = op == KindQuestionQuestionEqualsToken ? b.runtime("looseEq", [any(previous), ENull(TRef(RAny))]) : op == KindBarBarEqualsToken ? ENot(truth(previous)) : truth(previous);
			b.out.push(SIf(cond, b.block(() -> {
				var e = expr(x.right());
				target.write(e);
				b.out.push(SSet(l, any(e)));}), new Vector(0)));
			return ELocal(l);
		}
		var previous = target.read();
		var e = operate(compound.get(op), previous, arithmetic ? numeric(x.right(), false) : expr(x.right()), n);
		target.write(e);
		return e;
	}

	function operate(op:Kind, a:Ex, z:Ex, n:Node):Ex {
		if (op == KindInKeyword) return b.runtime("libHas", [any(z), any(a)]);
		if (op == KindEqualsEqualsEqualsToken || op == KindExclamationEqualsEqualsToken || op == KindEqualsEqualsToken || op == KindExclamationEqualsToken) {
			var strict = op == KindEqualsEqualsEqualsToken || op == KindExclamationEqualsEqualsToken;
			var literal = n.kind == KindBinaryExpression ? nullish(n.left()) ?? nullish(n.right()) : null;
			var e = literal != null ? isNullish(nullish(n.left()) != null ? z : a, strict ? literal : null) : equals(a, z, strict);
			return op == KindExclamationEqualsEqualsToken || op == KindExclamationEqualsToken ? ENot(e) : e;
		}
		if (op == KindPlusToken && (Ir.typeOf(a).match(TRef(RStr)) || Ir.typeOf(z).match(TRef(RStr)))) return b.runtime("concat", [text(a), text(z)]);
		if (op == KindPlusToken && (Ir.typeOf(a).match(TRef(RAny)) || Ir.typeOf(z).match(TRef(RAny)))) return b.runtime("add", [any(a), any(z)]);
		var relation = op == KindLessThanToken || op == KindLessThanEqualsToken || op == KindGreaterThanToken || op == KindGreaterThanEqualsToken;
		if (relation && !(Ir.typeOf(a) == TF64 && Ir.typeOf(z) == TF64)) {
			dynamicOperations++;
			return b.runtime("libRelation", [any(a), any(z), EStr(op == KindLessThanToken ? "<" : op == KindLessThanEqualsToken ? "<=" : op == KindGreaterThanToken ? ">" : ">=")]);
		}
		if (op == KindAmpersandToken || op == KindBarToken || op == KindCaretToken || op == KindLessThanLessThanToken || op == KindGreaterThanGreaterThanToken || op == KindGreaterThanGreaterThanGreaterThanToken) {
			var left = b.runtime("libInt", [any(a)]), right = b.runtime("libInt", [any(z)]);
			var value = EBin(op == KindAmpersandToken ? And : op == KindBarToken ? Or : op == KindCaretToken ? Xor : op == KindLessThanLessThanToken ? Shl : op == KindGreaterThanGreaterThanToken ? Shr : UShr, left, right);
			return op == KindGreaterThanGreaterThanGreaterThanToken ? b.runtime("libUnsigned", [b.temp(value)]) : EConv(I2F, value);
		}
		typedOperations++;
		if (op == KindPercentToken) return remainder(a, z);
		if (op == KindAsteriskAsteriskToken) return b.runtime("power", [b.coerce(a, TF64), b.coerce(z, TF64)]);
		var bin:BinOp = switch (op) {
			case KindPlusToken: FAdd;
			case KindMinusToken: FSub;
			case KindAsteriskToken: FMul;
			case KindSlashToken: FDiv;
			case KindPercentToken: FMod;
			case KindLessThanToken: FLt;
			case KindLessThanEqualsToken: FLe;
			case KindGreaterThanToken: FGt;
			case KindGreaterThanEqualsToken: FGe;
			case _: return fail(n, "unsupported binary operator " + op.toString());
		};
		return EBin(bin, b.coerce(a, TF64), b.coerce(z, TF64));
	}

	// `x % c` for a literal integer divisor. Integral dividends below 2^31 in
	// magnitude take a multiply-and-shift quotient (Granlund-Montgomery, as
	// optimizing JS engines do; exact over that range) instead of a hardware
	// division; others take exact binary long division. Both are inline: a call
	// in a loop makes hxmc keep the loop's variables in memory. Variable
	// divisors go through the runtime's JS-exact helper.
	function remainder(a:Ex, z:Ex):Ex {
		var x = b.temp(b.coerce(a, TF64));
		var c = switch (z) {
			case EF64(v) if (v >= 1 && v <= 2147483647 && Math.ffloor(v) == v): Std.int(v);
			case _: return b.runtime("modulo", [x, b.coerce(z, TF64)]);
		};
		var shift = 31;
		while (Math.pow(2, shift - 31) < c) shift++;
		var m = Math.ffloor(Math.pow(2, shift) / c) + 1;
		function long(v:Float):Ex {
			var high = Std.int(Math.ffloor(v / 4294967296.0)), low = Std.int(v - high * 4294967296.0);
			return EBin(LOr, EBin(LShl, EConv(I2L, EInt(high)), EInt(32)), EBin(LAnd, EConv(I2L, EInt(low)), EBin(LUShr, EConv(I2L, EInt(-1)), EInt(32))));
		}
		function set(l:Local, e:Ex) b.out.push(SSet(l, e));
		function when(cond:Ex, then:() -> Void, ?otherwise:() -> Void) b.out.push(SIf(cond, b.block(then), otherwise == null ? new Vector(0) : b.block(otherwise)));
		function loopWhile(cond:() -> Ex, body:() -> Void) b.out.push(SLoop(b.block(() -> {
			when(ENot(cond()), () -> b.out.push(SBreak));
			body();})));
		var l = b.local("remainder", TF64), magnitude = b.local("magnitude", TF64), r = b.local("rest", TF64), done = b.local("integral", TBool);
		set(done, ECast(TBool, EInt(0)));
		when(EBin(FLt, x, EF64(0)), () -> set(magnitude, EConv(FNeg, x)), () -> set(magnitude, x));
		when(EBin(FLt, ELocal(magnitude), EF64(2147483648.0)), () -> {
			var xi = b.temp(EConv(F2L, ELocal(magnitude)));
			when(EBin(FEq, EConv(L2F, xi), ELocal(magnitude)), () -> {
				var q = b.temp(EBin(LShr, EBin(LMul, xi, long(m)), EInt(shift)));
				set(r, EConv(L2F, EBin(LSub, xi, EBin(LMul, q, EConv(I2L, EInt(c))))));
				set(done, ECast(TBool, EInt(1)));
			});
		});
		when(ENot(ELocal(done)), () -> {
			// (x-x is 0 exactly when x is finite)
			when(ENot(EBin(FEq, EBin(FSub, x, x), EF64(0))), () -> set(r, EF64(Math.NaN)), () -> {
				set(r, ELocal(magnitude));
				var t = b.local("step", TF64);
				set(t, EF64(c));
				loopWhile(() -> EBin(FLe, ELocal(t), EBin(FMul, ELocal(r), EF64(0.5))), () -> set(t, EBin(FMul, ELocal(t), EF64(2))));
				loopWhile(() -> EBin(FGe, ELocal(t), EF64(c)), () -> {
					when(EBin(FGe, ELocal(r), ELocal(t)), () -> set(r, EBin(FSub, ELocal(r), ELocal(t))));
					set(t, EBin(FMul, ELocal(t), EF64(0.5)));
				});
			});
		});
		// (the sign of the dividend, -0 included)
		when(EBin(FEq, ELocal(r), EF64(0)), () -> set(l, EBin(FMul, EF64(0), x)), () -> when(EBin(FLt, x, EF64(0)), () -> set(l, EConv(FNeg, ELocal(r))), () -> set(l, ELocal(r))));
		return ELocal(l);
	}

	function brand(name:Node):String {
		var i = privateScopes.length - 1;
		while (i >= 0) {
			var scope = privateScopes[i--];
			if (scope.exists(name.text)) return scope.get(name.text);
		}
		return fail(name, "unknown private name " + name.text);
	}

	// A property key as an expression: names and literals are strings, computed keys are evaluated.
	function memberKey(name:Node):Ex return switch (name.kind) {
		case KindComputedPropertyName: b.temp(any(expr(name.expression())));
		case KindNumericLiteral: b.temp(b.runtime("text", [any(EF64(Std.parseFloat(name.text)))]));
		case _: EStr(name.text);
	};

	// Object literals: plain ones in one call; others property by property
	// (methods and accessors see the object as their home for super).
	function objectLiteral(n:Node):Ex {
		var props = properties(n);
		var plain = true;
		for (prop in props) if (!(prop.kind == KindPropertyAssignment && prop.name().kind != KindComputedPropertyName && prop.name().text != "__proto__" || prop.kind == KindShorthandPropertyAssignment)) plain = false;
		if (plain) {
			var ks:Array<Ex> = [], vs:Array<Ex> = [];
			for (prop in props) {
				ks.push(EStr(prop.kind == KindPropertyAssignment ? staticName(prop.name()) : prop.name().text));
				vs.push(prop.kind == KindPropertyAssignment ? named(prop.initializer(), staticName(prop.name())) : expr(prop.name()));
			}
			return b.runtime("libObject", [pack(ks), pack(vs)]);
		}
		var o = b.temp(b.runtime("libObject", [pack([]), pack([])]));
		var outer = env;
		env = env.copy();
		env.set("%home", {ty: TRef(RAny), cell: b.temp(ENewBox(TRef(RAny), o))});
		for (prop in props) switch (prop.kind) {
			case KindSpreadAssignment: b.runtime("libAssignSpread", [o, any(expr(prop.expression()))]);
			case KindShorthandPropertyAssignment: b.runtime("libDefineField", [o, EStr(prop.name().text), any(expr(prop.name()))]);
			case KindPropertyAssignment if (prop.name().kind != KindComputedPropertyName && prop.name().text == "__proto__"):
				b.runtime("libSetProto", [o, any(expr(prop.initializer()))]);
			case KindPropertyAssignment:
				var key = memberKey(prop.name());
				b.runtime("libDefineField", [o, any(key), any(named(prop.initializer(), staticName(prop.name())))]);
			case KindMethodDeclaration | KindGetAccessor | KindSetAccessor:
				var key = memberKey(prop.name());
				var fn = closure(prop, staticName(prop.name()));
				b.runtime("libDefineMethod", [o, any(key), fn, EInt(prop.kind == KindGetAccessor ? 1 : prop.kind == KindSetAccessor ? 2 : 0), bool(true)]);
			case _: fail(prop, "unsupported object member " + prop.kind.toString());
		}
		env = outer;
		return o;
	}

	// `a[k]` with a an array and k a number
	function arrayElement(n:Node):Bool
		return n.kind == KindElementAccessExpression && plainAccess(n) && types.isArray(n.expression().tsType) && types.isNumber(n.argumentExpression().tsType);

	// ---- number arrays (Reps: JsArray's nums)
	// `a[k]` of an array of numbers (number[], a branded number's, T extends number's)
	function numberElement(n:Node):Bool return arrayElement(n) && types.isNumber(n.expression().tsType.element);

	// an array literal of numbers, without holes or spreads (an empty one by
	// the type it is given: `const xs: number[] = []`)
	function numberLiteral(n:Node):Bool {
		var list = elements(n);
		for (e in list) if (e.kind == KindOmittedExpression || e.kind == KindSpreadElement) return false;
		function numbers(t:Null<TsType>) return types.isArray(t) && types.isNumber(t.element);
		if (numbers(n.tsType)) return true;
		if (list.length > 0 || n.parent == null) return false;
		var p = n.parent;
		return switch p.kind {
			case KindVariableDeclaration | KindPropertyDeclaration if (p.initializer() == n && p.name().kind == KindIdentifier): numbers(p.name().tsType);
			case KindBinaryExpression if (p.right() == n && p.operatorToken().kind == KindEqualsToken): numbers(p.left().tsType);
			case _: false;
		}
	}

	// n's value for a slot of type t: a number array's element read unboxed for a number's
	function valueFor(n:Node, t:Ty):Ex return t == TF64 ? numeric(n, true) : expr(n);

	// n's value where a number is wanted (slot: a typed slot's, its check
	// where it is none; else as ToNumber makes one): a number array's element
	// read unboxed, else the runtime's element made a number
	function numeric(n:Node, slot:Bool):Ex {
		var inner = strip(n);
		while (inner.kind == KindNonNullExpression) inner = strip(inner.expression());
		if (!numberElement(inner)) return expr(n);
		expressions++;
		typed++;
		typedOperations++;
		var obj = b.temp(expr(inner.expression()));
		var k = b.temp(number(expr(inner.argumentExpression())));
		return reps.arrayGetNumber(b, obj, k, g -> slot ? store(g, TF64) : number(g));
	}

	// (an operator that makes its operands numbers: arithmetic, and a
	// relation or + between numbers)
	function numericOperator(op:Kind, n:Node):Bool {
		if (op == KindMinusToken || op == KindAsteriskToken || op == KindSlashToken || op == KindPercentToken || op == KindAsteriskAsteriskToken) return true;
		var relation = op == KindLessThanToken || op == KindLessThanEqualsToken || op == KindGreaterThanToken || op == KindGreaterThanEqualsToken;
		return (relation || op == KindPlusToken) && n.kind == KindBinaryExpression && types.isNumber(n.left().tsType) && types.isNumber(n.right().tsType);
	}

	// a number array's element as a target whose value is read as a number (x[k] += 1, x[k]++)
	function numberTarget(n:Node):{read:() -> Ex, write:Ex->Void} {
		var obj = b.temp(expr(n.expression()));
		var key = b.temp(number(expr(n.argumentExpression())));
		return {
			read: () -> reps.arrayGetNumber(b, obj, key, g -> number(g)),
			write: (e) -> Ir.typeOf(e) == TF64 ? reps.arraySetNumber(b, obj, key, e) : reps.arraySet(b, obj, key, e)
		};
	}

	// (an assignment target that is a typed number slot: a binding or a typed class's field)
	function numberSlot(left:Node):Bool {
		return left.kind == KindIdentifier && env.exists(left.text) && env.get(left.text).ty == TF64 && env.get(left.text).buffer == null;
	}

	function construct(n:Node):Ex {
		var direct = layoutConstruct(n);
		if (direct != null) return direct;
		var callee = any(expr(n.expression()));
		return b.runtime("libConstruct", [callee, argumentList(n.arguments() == null ? [] : n.arguments()), callee]);
	}

	// Arguments to a known function: its parameters' types, missing ones
	// undefined, the rest (when it has a rest parameter) as an array.
	function positional(f:FuncInfo, values:Array<Ex>, skip:Int):Array<Ex> {
		var rest = restFunctions.exists(f);
		var fixed = f.args.length - skip - (rest ? 1 : 0);
		var out = [for (i in 0...fixed) store(i < values.length ? values[i] : b.runtime("getUndefined", []), f.args[i + skip].ty)];
		if (rest) out.push(b.runtime("libArray", [pack(values.slice(fixed))]));
		return out;
	}

	function hasSpread(nodes:Array<Node>):Bool {
		for (a in nodes) if (a.kind == KindSpreadElement) return true;
		return false;
	}

	// An argument (or array element) list as a runtime list, spreads expanded and holes kept.
	function spreadList(nodes:Array<Node>):Ex {
		var list = b.temp(ENewArr(TRef(RAny), new Vector(0)));
		for (e in nodes) switch (e.kind) {
			case KindSpreadElement: b.runtime("libAppendAll", [list, any(expr(e.expression()))]);
			case KindOmittedExpression: b.runtime("libAppend", [list, b.runtime("libHole", [])]);
			case _: b.runtime("libAppend", [list, any(expr(e))]);
		}
		return list;
	}

	function argumentList(nodes:Array<Node>):Ex return hasSpread(nodes) ? spreadList(nodes) : pack(actuals(nodes));

	// (in an optional chain, a nullish value at `?.` ends the whole chain with undefined)
	function chainCheck(n:Node, value:Ex) {
		if (n.questionDotToken() == null) return;
		if (b.depth != chainDepth) fail(n, "optional chain inside a nested loop");
		b.out.push(SIf(b.runtime("looseEq", [any(value), ENull(TRef(RAny))]), Vector.fromArrayCopy([SBreak]), new Vector(0)));
	}
	function chainTop(n:Node):Bool {
		if (n.flags & NodeFlags.OptionalChain == 0 || chainTops.exists(n)) return false;
		var parent = n.parent;
		return parent == null || parent.flags & NodeFlags.OptionalChain == 0 || parent.expression() != n
			|| !(parent.kind == KindPropertyAccessExpression || parent.kind == KindElementAccessExpression || parent.kind == KindCallExpression || parent.kind == KindNonNullExpression);
	}

	function optionalChain(n:Node):Ex {
		var l = b.local("chain", TRef(RAny));
		b.out.push(SSet(l, b.runtime("getUndefined", [])));
		var saved = chainDepth;
		chainTops.set(n, true);
		irLoop(() -> {
			chainDepth = b.depth;
			b.out.push(SSet(l, any(expr(n))));
			b.out.push(SBreak);});
		chainTops.remove(n);
		chainDepth = saved;
		return ELocal(l);
	}

	// job(f) (helder/jobs, its check JobDefinition's): f's case among the
	// program's jobs (helder.jobs.script.Entry.call, written once the
	// program is lowered: Frontend), a function of its own run on the
	// worker (a browser worker's instance: the runtime started there, the
	// constants f reads set from those sent), and the value
	// helder.jobs.script.Job.make's, with the constants as they are now
	function job(n:Node, fn:Node, captures:Array<String>):Ex {
		var name = fn.name().text;
		if (bridge == null) fail(n, "job: helder/jobs is not declared to the program");
		if (fn.file != n.file) fail(n, 'job: $name is another module\'s (job(f) is written in f\'s module)');
		var f = functions.get(name);
		if (f == null) fail(n, 'job: $name is not a plain function (it uses this, is async or a generator)');
		var index = jobs.length;
		var fi = Builder.func(p, "job" + index + "_" + name, TRef(RAny));
		var cs = new Local(0, "captures", TRef(RAny)), input = new Local(1, "input", TRef(RAny));
		fi.args = [cs, input];
		var outer = b;
		b = new Builder(p, fi);
		var ready = b.runtime("libReady", []);
		var start = b.block(() -> {
			b.runtime("libInit", []);
			for (feature in Features.of(src)) b.runtime("libInstall" + feature, []);
		});
		b.out.push(SIf(ready, Vector.fromArrayCopy([]), start));
		if (definitions.define("hxmc.target") == "wasm32-wasi")
			for (i in 0...captures.length) set(get(captures[i], fn), b.runtime("libGet", [ELocal(cs), b.coerce(EF64(i), TRef(RAny))]));
		var call = ECall(f, Vector.fromArrayCopy(positional(f, fn.parameters().length == 0 ? [] : [ELocal(input)], 0)));
		if (f.ret == TVoid) {
			b.out.push(SExpr(call));
			b.out.push(SReturn(b.runtime("getUndefined", [])));
		} else b.out.push(SReturn(any(b.temp(call))));
		b.finish();
		b = outer;
		jobs.push(fi);
		return bridge.call(bridge.fn("helder_jobs_script_Job_make"), [EInt(index), pack([for (c in captures) read(get(c, n))])]);
	}

	// native.c({lib, fns}) (helder/native): an object of the program's
	// functions, each a call of the C function of its name (hxmc's extern
	// machinery: its signature in CInterop's tables, called as Haxe's
	// @:hxmc.c externs are), its C types read from its annotations
	function nativeLibrary(n:Node, def:Null<Node>):Ex {
		if (bridge == null) fail(n, "native.c: helder/native is not declared to the program");
		if (def == null || def.kind != KindObjectLiteralExpression) fail(n, "native.c takes one argument, an object literal: {lib, fns}");
		var lib:Null<String> = null, fns:Null<Node> = null;
		for (f in def.properties()) {
			var key = f.name() == null ? "" : f.name().text;
			if (f.kind != KindPropertyAssignment) fail(f, 'native.c: $key is a field of the object literal ($key: ...)');
			var v = f.initializer();
			switch key {
				case "lib":
					if (v.kind != KindStringLiteral && v.kind != KindNoSubstitutionTemplateLiteral) fail(v, "native.c: lib is a string literal (the library's name or path)");
					lib = v.text;
				case "fns":
					if (v.kind != KindObjectLiteralExpression) fail(v, "native.c: fns is an object literal of functions");
					fns = v;
				case _: fail(f, 'native.c: no field $key (lib, fns)');
			}
		}
		if (fns == null) fail(n, "native.c: fns, the functions, is missing");
		var keys = [], values = [];
		for (f in fns.properties()) {
			var name = f.name() == null ? "" : f.name().text;
			var fn = f.kind == KindPropertyAssignment ? f.initializer() : f.kind == KindMethodDeclaration ? f : null;
			if (fn == null || (fn.kind != KindArrowFunction && fn.kind != KindFunctionExpression && fn.kind != KindMethodDeclaration))
				fail(f, 'native.c: $name is not a function (its parameters and result annotated with helder/native\'s C types)');
			keys.push(EStr(name));
			values.push(functionValue(nativeFunction(lib, name, fn), name));
		}
		return b.runtime("libObject", [pack(keys), pack(values)]);
	}

	// (a C type of helder/native's, by an annotation: the name it is imported as
	// from there, or number, boolean, string, void)
	function nativeType(t:Null<Node>, at:Node, what:String):String {
		var types = ["i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "isize", "usize", "f32", "f64", "bool", "cstring", "pointer", "buffer"];
		if (t == null) fail(at, 'native.c: $what has no type (helder/native\'s C types: ${types.join(", ")}, void)');
		switch t.kind {
			case KindNumberKeyword: return "f64";
			case KindBooleanKeyword: return "bool";
			case KindStringKeyword: return "cstring";
			case KindVoidKeyword: return "void";
			case KindTypeReference if (t.typeName().kind == KindIdentifier):
				var from = Definitions.Scope.imported(t.file, t.typeName().text);
				if (from != null && from.module == "helder/native" && types.contains(from.name)) return from.name;
			case _:
		}
		return fail(t, 'native.c: $what\'s type is not a C type (helder/native\'s: ${types.join(", ")}; number, boolean, string, void)');
	}

	static function nativeC(k:String):hxmc.ir.CInterop.CTy
		return switch k {
			case "i8": CI8;
			case "u8": CU8;
			case "i16": CI16;
			case "u16": CU16;
			case "i32" | "u32": CI32;
			case "i64" | "u64" | "isize" | "usize": CI64;
			case "f32": CF32;
			case "f64": CF64;
			case "bool": CBool;
			case "void": CVoid;
			case _: CPtr;
		}

	// (the C value's IR type)
	static function nativeIr(k:String):Ty
		return switch k {
			case "i8" | "u8" | "i16" | "u16" | "i32" | "u32": TI32;
			case "f32" | "f64": TF64;
			case "bool": TBool;
			case "void": TVoid;
			case _: TI64;
		}

	// a C function as a direct function of the program: its arguments made C's,
	// the call (a C string's and a buffer's memory freed after it), its result the program's
	function nativeFunction(lib:Null<String>, name:String, fn:Node):FuncInfo {
		var params = fn.parameters();
		var kinds = [for (q in params) nativeType(q.type(), q, "parameter " + q.name().text)];
		for (k in kinds) if (k == "void") fail(fn, 'native.c: $name takes void');
		var ret = nativeType(fn.type(), fn, name + "'s result");
		var rep = k -> switch k {
			case "bool": TBool;
			case "cstring" | "buffer": TRef(RAny);
			case "void": TVoid;
			case _: TF64;
		};
		var fi = Builder.func(p, "native_" + name + "_" + serial++, rep(ret));
		fi.args = [for (i in 0...params.length) new Local(i, params[i].name().kind == KindIdentifier ? params[i].name().text : "a" + i, rep(kinds[i]))];
		var outer = b;
		b = new Builder(p, fi);
		var where = Project.relative(fn.file.path) + ":" + fn.file.line(fn.file.skipTrivia(fn.pos));
		var script = n -> bridge.fn("helder_native_Script_" + n);
		var xs:Array<Ex> = [], after:Array<() -> Void> = [];
		for (i in 0...kinds.length) {
			var x = ELocal(fi.args[i]);
			xs.push(switch kinds[i] {
				case "i8" | "u8" | "i16" | "u16" | "i32" | "u32": b.temp(EConv(L2I, EConv(F2L, x)));
				case "f32" | "f64" | "bool": x;
				case "cstring":
					var at = b.temp(bridge.call(script("cstring"), [x]));
					after.push(() -> bridge.call(script("free"), [at]));
					b.temp(EConv(F2L, at));
				case "buffer":
					var bytes = b.temp(bridge.call(bridge.interop("bytes"), [x, EStr(where)]));
					var at = b.temp(bridge.call(script("bytesIn"), [bytes]));
					after.push(() -> bridge.call(script("bytesBack"), [at, bytes]));
					b.temp(EConv(F2L, at));
				case _: b.temp(EConv(F2L, x));
			});
		}
		// (hxmc's tables of C functions, as CInterop.declare fills them for Haxe's externs;
		// WebAssembly: a library's function the import (lib, name))
		var sym = name;
		if (hxmc.ir.Lower.targetOs == 3 && lib == null) fail(fn, 'native.c: wasm32-wasi has no C library: lib names the module its host imports $name from');
		if (hxmc.ir.Lower.targetOs == 3 && lib != null && lib != "env") {
			sym = "@import:" + lib.length + ":" + lib + "." + name;
			hxmc.ir.CInterop.IMPORT_NAMES.set(sym, name);
		}
		var sig:hxmc.ir.CInterop.CSig = {args: [for (k in kinds) nativeC(k)], ret: nativeC(ret)};
		var prev = hxmc.ir.CInterop.SIGS.get(sym);
		if (prev != null && (prev.ret != sig.ret || prev.args.length != sig.args.length || [for (i in 0...sig.args.length) prev.args[i] != sig.args[i]].contains(true)))
			fail(fn, 'native.c: $name is declared with another signature (by helder\'s Haxe or hxmc\'s runtime)');
		if (prev == null) hxmc.ir.CInterop.SIGS.set(sym, sig);
		// (a call in a safe region, as a Haxe extern's that is not @:hxmc.fast; one the runtime declares fast stays so)
		if (!hxmc.ir.FnLower.C_EXTERNS.exists(sym)) hxmc.ir.CInterop.BLOCKING.set(sym, true);
		// (Linux's glibc mode: libc's functions the runtime does not import are the program's, libc.so.6's)
		var glibc = hxmc.ir.Lower.targetOs == 0 && definitions.define("hxmc.libc") == "glibc" && hxmc.ir.Lower.targetCode != 9 && hxmc.ir.Lower.targetCode != 10;
		// (and libm and libc by their short names, their files: libm.so is a linker script)
		if (glibc && (lib == "m" || lib == "c")) lib = 'lib$lib.so.6';
		if (lib != null) hxmc.ir.CInterop.LIBS.set(sym, lib) else if (glibc && !hxmc.ir.CInterop.LIBS.exists(sym)) hxmc.ir.CInterop.LIBS.set(sym, "libc.so.6");
		hxmc.ir.CInterop.USER.set(sym, true);
		var t = nativeIr(ret);
		var call = ECallHost(sym, Vector.fromArrayCopy(xs), t);
		var r:Null<Ex> = null;
		if (t == TVoid) b.out.push(SExpr(call)) else r = b.temp(call);
		for (f in after) f();
		switch ret {
			case "void": b.out.push(SReturn(null));
			case "u32":
				var l = b.local("unsigned", TF64);
				b.out.push(SSet(l, EConv(I2F, r)));
				b.out.push(SIf(EBin(FLt, ELocal(l), EF64(0)), Vector.fromArrayCopy([SSet(l, EBin(FAdd, ELocal(l), EF64(4294967296.0)))]), new Vector(0)));
				b.out.push(SReturn(ELocal(l)));
			case "i8" | "u8" | "i16" | "u16" | "i32": b.out.push(SReturn(EConv(I2F, r)));
			case "f32" | "f64" | "bool": b.out.push(SReturn(r));
			case "cstring": b.out.push(SReturn(b.coerce(bridge.call(script("string"), [EConv(L2F, r)]), TRef(RAny))));
			case "buffer": fail(fn, 'native.c: $name returns a buffer: return a pointer (native.bytes reads it)');
			case _: b.out.push(SReturn(EConv(L2F, r)));
		}
		b.finish();
		b = outer;
		return fi;
	}

	// image(path)... (helder/asset): the handle helder.asset.ScriptAssets
	// makes of its key's marker (TsAssets), and its file in a dev build
	function asset(n:Node, kind:String, path:String, file:Null<String>):Ex {
		if (bridge == null) fail(n, "Asset." + kind + ": helder/asset is not declared to the program");
		var args = [EStr(TsAssets.marker(path))];
		if (file != null) args.push(EStr(file));
		return bridge.call(bridge.fn("helder_asset_ScriptAssets_" + kind), args);
	}

	// `import x from "./x.png" with {type: "image"}`: x set to the asset's handle
	function assetImport(n:Node) {
		var a = TsAssets.imported(n);
		var clause = n.importClause();
		if (a == null || clause == null || clause.name() == null) return;
		var file = TsAssets.find(src, a.kind, a.path, n, definitions.define);
		set(get(clause.name().text, n), asset(n, a.kind, a.path, TsAssets.devFile(file, definitions.define)));
	}

	function call(n:Node):Ex {
		var actual = n.arguments();
		if (actual == null) actual = [];
		var callee = n.expression();
		if (callee.kind == KindSuperKeyword && superInit != null) return superInit(actual);
		// (a definition: compiled now, what its handler made its last argument; keep's slot)
		switch definitions.call(n) {
			case null:
			case Generated(json): return apply(any(expr(callee)), pack(actuals(actual).concat([EStr(json)])));
			case GeneratedWith(json, uniforms):
				return apply(any(expr(callee)), pack(actuals(actual).concat([EStr(json), b.runtime("libArray", [pack([for (u in uniforms) expr(u)])])])));
			case Keep(key, type, source, init):
				var f = any(expr(init));
				if (dev && bridge != null) return bridge.call(bridge.interop("hotKeep"), [f, EStr(key), EStr(type), EStr(source)]);
				return apply(f, pack([]));
			case Checked:
				var x = api == null ? null : apiCall(n);
				if (x == null) fail(n, "this definition is a call into helder's API (its module's declarations)");
				return x;
			case Dropped: return b.runtime("getUndefined", []);
			case Job(fn, captures): return job(n, fn, captures);
			case AssetCall(kind, path, file): return asset(n, kind, path, file);
			case Native(def): return nativeLibrary(n, def);
			case Located(index, at):
				if (hasSpread(actual) || actual.length > index) return apply(expr(callee), argumentList(actual));
				var xs = actuals(actual);
				while (xs.length < index) xs.push(b.runtime("getUndefined", []));
				return apply(any(expr(callee)), pack(xs.concat([EStr(at)])));
		}
		if (callee.kind == KindSuperKeyword) {
			var list = argumentList(actual);
			var t = b.runtime("libSuperConstruct", [read(get("%class", n)), list, read(get("%newTarget", n))]);
			set(get("this", n), t);
			parameterProperties();
			return t;
		}
		if (callee.kind == KindPropertyAccessExpression && callee.expression().kind == KindIdentifier && callee.expression().text == "console" && !env.exists("console") && callee.name().text == "log") {
			// (numbers print through the typed path; other lines through Node's formatting)
			var values = hasSpread(actual) ? null : actuals(actual);
			if (values != null && values.length > 0 && values.filter(v -> Ir.typeOf(v) != TF64).length == 0) {
				for (i in 0...values.length) {
					if (i > 0) b.runtime("print", [EStr(" ")]);
					b.runtime("print", [b.runtime("consoleNumber", [values[i]])]);
				}
			}
			else b.runtime("print", [b.runtime("consoleLine", [values == null ? spreadList(actual) : pack(values)])]);
			b.runtime("print", [EStr("\n")]);
			return b.runtime("getUndefined", []);
		}
		if (callee.kind == KindIdentifier && !env.exists(callee.text) && functions.exists(callee.text) && n.questionDotToken() == null) {
			var f = functions.get(callee.text);
			if (hasSpread(actual)) return apply(read(functionValues.get(callee.text)), spreadList(actual));
			typedOperations++;
			var fixed = f.args.length - (restFunctions.exists(f) ? 1 : 0);
			var args = positional(f, [for (i in 0...actual.length) valueFor(actual[i], i < fixed ? f.args[i].ty : TRef(RAny))], 0);
			if (f.ret == TVoid) {
				b.out.push(SExpr(ECall(f, Vector.fromArrayCopy(args))));
				return b.runtime("getUndefined", []);
			}
			return b.temp(ECall(f, Vector.fromArrayCopy(args)));
		}
		var math = mathCall(n, callee, actual);
		if (math != null) return math;
		// (s.charCodeAt(i) on a string: String.prototype's, read-only)
		if (callee.kind == KindPropertyAccessExpression && plainAccess(callee) && callee.name().text == "charCodeAt" && actual.length <= 1 && !hasSpread(actual)
			&& types.isString(callee.expression().tsType)) {
			var s = b.temp(expr(callee.expression()));
			var i = actual.length == 0 ? EF64(0) : b.temp(number(expr(actual[0])));
			if (Ir.typeOf(s).match(TRef(RStr))) {
				typedOperations++;
				return b.runtime("stringCharCodeAt", [s, i]);
			}
			return b.runtime("libCallMethod", [any(s), EStr("charCodeAt"), pack([i])]);
		}
		// (a.push(v) of a number on a number array: appended unboxed, while Array.prototype's push is the built-in)
		if (callee.kind == KindPropertyAccessExpression && plainAccess(callee) && callee.name().text == "push" && actual.length == 1 && !hasSpread(actual)
			&& n.questionDotToken() == null && types.isArray(callee.expression().tsType) && types.isNumber(callee.expression().tsType.element)) {
			var o = b.temp(expr(callee.expression()));
			var v = b.temp(expr(actual[0]));
			if (Ir.typeOf(v) == TF64) {
				typedOperations++;
				var length = b.local("pushed", TF64), r = b.local("push", TRef(RAny));
				b.out.push(SSet(length, EF64(-1)));
				var fast = () -> b.out.push(SSet(length, b.runtime("libPushNumber", [ECast(TRef(RObj(reps.arrayClass)), o), v])));
				if (reps.exact(o, reps.arrayClass)) fast(); else b.out.push(SIf(EInstOf(reps.arrayClass, any(o)), b.block(fast), new Vector(0)));
				var used = n.parent == null || n.parent.kind != KindExpressionStatement;
				b.out.push(SIf(EBin(FLt, ELocal(length), EF64(0)), b.block(() -> b.out.push(SSet(r, b.runtime("libCallMethod", [any(o), EStr("push"), pack([v])])))),
					b.block(() -> if (used) b.out.push(SSet(r, any(ELocal(length)))))));
				if (!used) return b.runtime("getUndefined", []);
				return ELocal(r);
			}
			return b.runtime("libCallMethod", [any(o), EStr("push"), pack([v])]);
		}
		var inner = callee;
		while (inner.kind == KindParenthesizedExpression) inner = inner.expression();
		var method = layoutCall(n, inner, actual);
		if (method != null) return method;
		if ((inner.kind == KindPropertyAccessExpression || inner.kind == KindElementAccessExpression) && inner.expression().kind == KindSuperKeyword) {
			var key = inner.kind == KindPropertyAccessExpression ? EStr(inner.name().text) : any(expr(inner.argumentExpression()));
			return b.runtime("libSuperCall", [read(get("%home", n)), thisValue(), key, argumentList(actual)]);
		}
		if (inner.kind == KindPropertyAccessExpression || inner.kind == KindElementAccessExpression) {
			var obj = b.temp(any(expr(inner.expression())));
			chainCheck(inner, obj);
			var key:Ex = inner.kind == KindElementAccessExpression ? b.temp(any(expr(inner.argumentExpression()))) : inner.name().kind == KindPrivateIdentifier ? null : EStr(inner.name().text);
			if (key == null || n.questionDotToken() != null) {
				var fn = key == null ? b.runtime("libPrivateGet", [obj, EStr(brand(inner.name()))]) : b.runtime("libGet", [obj, key]);
				chainCheck(n, fn);
				return b.runtime("libCall", [fn, obj, argumentList(actual)]);
			}
			return b.runtime("libCallMethod", [obj, key, argumentList(actual)]);
		}
		var fn = expr(callee);
		chainCheck(n, fn);
		return apply(fn, argumentList(actual));
	}
}
