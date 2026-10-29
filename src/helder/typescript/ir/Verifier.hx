package helder.typescript.ir;

import hxmc.ir.Ir;
import haxe.ds.Vector;

class Verifier {
	var p:Program;
	var f:FuncInfo;
	var locals:Map<Int, Local> = [];
	function new(p:Program, f:FuncInfo) {
		this.p = p;
		this.f = f;
	}

	function error(s:String):Dynamic throw "TSHXIR003: " + f.name + ": " + s;

	function same(a:Ty, b:Ty):Bool return Type.enumEq(a, b) || Ir.isRef(a) && Ir.isRef(b);

	function expect(e:Ex, t:Ty) {
		if (!same(Ir.typeOf(e), t)) error("expected " + t + ", got " + Ir.typeOf(e));
	}

	function local(l:Local) {
		if (locals.get(l.id) != l) error("foreign or duplicate local " + l.name);
	}

	function expression(e:Ex, impure = false) {
		if (e == null) error("null expression");
		switch (e) {
			case ELocal(l): local(l);
			case EGlobal(g, t): if (g < 0 || g >= p.globals.length || !same(t, p.globals[g].ty)) error("invalid global");
			case ECall(fn, args):
				if (!impure) error("call nested in pure expression");
				if (p.funcs.indexOf(fn) < 0 || args.length != fn.args.length) error("invalid callee or arity");
				for (i in 0...args.length) {
					expression(args[i]);
					expect(args[i], fn.args[i].ty);
				}
			case ECallClos(sig, clos, args):
				if (!impure) error("nested closure call");
				expression(clos);
				if (args.length != sig.args.length) error("closure arity");
				for (i in 0...args.length) {
					expression(args[i]);
					expect(args[i], sig.args[i]);
				}
			case ECallDispatch(sel, sig, args):
				if (!impure || sel < 0 || sel >= p.selectors.length || args.length != sig.args.length) error("invalid dispatch");
				for (i in 0...args.length) {
					expression(args[i]);
					expect(args[i], sig.args[i]);
				}
			case ECallAnon(_, sig, obj, args):
				if (!impure) error("nested structural call");
				expression(obj);
				if (args.length != sig.args.length) error("structural arity");
				for (i in 0...args.length) {
					expression(args[i]);
					expect(args[i], sig.args[i]);
				}
			case ENewClos(li, vs):
				if (vs.length != li.captures.length) error("capture arity");
				for (i in 0...vs.length) {
					expression(vs[i]);
					expect(vs[i], li.captures[i].ty);
				}
			case ECapture(li, i, clos):
				if (f.lambda != li || i < 0 || i >= li.captures.length) error("invalid capture");
				expression(clos);
			case ECallHost(_, _, _): error("frontend cannot introduce unverified runtime symbols");
			case ENewArr(t, vs):
				for (v in vs) {
					expression(v);
					expect(v, t);
				}
			case EBin(op, a, b):
				expression(a);
				expression(b);
				switch (op) {
					case FAdd | FSub | FMul | FDiv | FMod | FEq | FNe | FLt | FLe | FGt | FGe:
						expect(a, TF64);
						expect(b, TF64);
					case LShl | LShr | LUShr:
						expect(a, TI64);
						expect(b, TI32);
					case RefEq | RefNe: if (!Ir.isRef(Ir.typeOf(a)) || !Ir.isRef(Ir.typeOf(b))) error("reference comparison needs references");
					case _: if (!same(Ir.typeOf(a), Ir.typeOf(b))) error("binary operand mismatch");
				}
			case ENot(v):
				expression(v);
				expect(v, TBool);
			case EConv(_, v) | ECast(_, v) | EBox(_, v) | EUnbox(_, v) | EBoxGet(_, v) | ENewBox(_, v) | EArrLen(v) | EInstOf(_, v) | EField(_, _, v) | EAnonGet(_, _, v, _): expression(v);
			case EArrGet(_, a, i):
				expression(a);
				expression(i);
				expect(i, TI32);
			case ENewAnon(shape, vs):
				if (vs.length != shape.fields.length) error("shape arity");
				for (i in 0...vs.length) {
					expression(vs[i]);
					expect(vs[i], shape.fields[i].ty);
				}
			case EInt(_) | EF64(_) | EStr(_) | ENull(_) | ENewObj(_):
			case _: error("unsupported verifier expression " + Type.enumConstructor(e));
		}
	}

	function block(ss:Vector<Stmt>, loops:Int):Bool {
		var terminal = false;
		for (s in ss) {
			if (terminal) continue;
			switch (s) {
				case SSet(l, e):
					local(l);
					expression(e, true);
					expect(e, l.ty);
				case SExpr(e): expression(e, true);
				case SBoxSet(t, a, v):
					expression(a);
					expression(v);
					expect(v, t);
				case SSetGlobal(g, v):
					if (g < 0 || g >= p.globals.length) error("invalid global store");
					expression(v);
					expect(v, p.globals[g].ty);
				case SSetField(c, i, o, v):
					if (i < 0 || i >= c.fields.length) error("invalid field index");
					expression(o);
					expression(v);
					expect(v, c.fields[i].ty);
				case SArrSet(t, a, i, v):
					local(a);
					expression(i);
					expect(i, TI32);
					expression(v);
					expect(v, t);
				case SArrPush(t, a, v):
					local(a);
					expression(v);
					expect(v, t);
				case SAnonSet(_, t, o, v):
					expression(o);
					expression(v);
					expect(v, t);
				case SIf(c, a, b):
					expression(c);
					expect(c, TBool);
					var at = block(a, loops);
					var bt = block(b, loops);
					terminal = at && bt;
				case SLoop(body): block(body, loops + 1);
				case SBreak | SContinue:
					if (loops == 0) error("loop terminator outside loop");
					terminal = true;
				case SThrow(e):
					expression(e);
					terminal = true;
				case STry(body, catches):
					var done = block(body, loops);
					for (c in catches) {
						local(c.l);
						done = block(c.body, loops) && done;
					}
					terminal = done;
				case SReturn(e):
					if (e == null) {
						if (f.ret != TVoid) error("missing return value");
					} else {
						expression(e);
						expect(e, f.ret);
					}
					terminal = true;
				case _: error("unsupported verifier statement " + Type.enumConstructor(s));
			}
		}
		return terminal;
	}

	public static function check(p:Program) {
		if (p.main == null || p.funcs.indexOf(p.main) < 0) throw "TSHXIR003: missing program entry";
		for (f in p.funcs) if (f.module == "helder.typescript.program") {
			var v = new Verifier(p, f);
			for (l in f.args.concat(f.locals)) {
				if (v.locals.exists(l.id)) v.error("duplicate local ID");
				v.locals.set(l.id, l);
			}
			if (!v.block(f.body, 0) && f.ret != TVoid) v.error("function may fall through without return");
		}
	}
}
