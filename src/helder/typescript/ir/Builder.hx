package helder.typescript.ir;

import hxmc.ir.Ir;
import haxe.ds.Vector;

enum JumpKind {
	JLoop;
	JSwitch;
	JLabel;
	JFinally;
}

// A generator or async function body: its suspension points, the value a
// suspension hands out, and the step function's arguments (generator object,
// value sent in, resumption mode: 0 next, 1 throw, 2 return).
typedef Resumable = {count:Int, value:Local, gen:Local, sent:Local, mode:Local, async:Bool, generator:Bool, kinds:Map<Int, Int>};
typedef JumpTarget = {labels:Array<String>, kind:JumpKind, breakCode:Int, continueCode:Int, breakDepth:Int, continueDepth:Int};

class Builder {
	public var p:Program;
	public var f:FuncInfo;
	public var out:Array<Stmt> = [];
	// JS jumps (see Frontend.jump): the function's pending jump code, the value a
	// return through finally carries, enclosing jump targets and IR loop depth
	public var jump:Local = null;
	public var result:Local = null;
	public var targets:Array<JumpTarget> = [];
	public var depth = 0;
	public var codes = 0;
	public var flagged = 0;
	// class constructors: the `this` binding returned at the end, and parameter properties
	public var constructorThis:Dynamic = null;
	public var parameterProperties:Array<String> = null;
	public var resumable:Resumable = null;
	public function new(p:Program, f:FuncInfo) {
		this.p = p;
		this.f = f;
	}

	public static function func(p:Program, name:String, ret:Ty):FuncInfo {
		var f = new FuncInfo("ts_" + name + "_" + p.funcs.length, "helder.typescript.program");
		f.ret = ret;
		p.funcs.push(f);
		return f;
	}

	public function local(name:String, t:Ty):Local {
		var l = new Local(f.args.length + f.locals.length, name, t);
		f.locals.push(l);
		return l;
	}

	public function temp(e:Ex):Ex {
		var l = local("tmp", Ir.typeOf(e));
		out.push(SSet(l, e));
		return ELocal(l);
	}

	public function runtime(name:String, args:Array<Ex>):Ex {
		for (fn in p.funcs) if (fn.name == "helder_typescript_js_Seed_" + name) {
			var e = ECall(fn, Vector.fromArrayCopy(args));
			if (fn.ret == TVoid) {
				out.push(SExpr(e));
				return ENull(TRef(RAny));
			}
			return temp(e);
		}
		throw "TSHX004: runtime helper not linked: " + name;
	}

	// (the call expression alone, for statements built by hand)
	public function runtimeCall(name:String, args:Array<Ex>):Ex {
		for (fn in p.funcs) if (fn.name == "helder_typescript_js_Seed_" + name) return ECall(fn, Vector.fromArrayCopy(args));
		throw "TSHX004: runtime helper not linked: " + name;
	}

	public function finish() {
		if (jump != null) out.unshift(SSet(jump, EInt(0)));
		f.body = Vector.fromArrayCopy(out);
	}

	public function block(run:() -> Void):Vector<Stmt> {
		var old = out;
		out = [];
		run();
		var v = Vector.fromArrayCopy(out);
		out = old;
		return v;
	}

	public function coerce(e:Ex, t:Ty):Ex {
		var from = Ir.typeOf(e);
		if (Type.enumEq(from, t)) return e;
		return switch [from, t] {
			case [TI32, TBool]: ECast(TBool, e);
			case [TI32, TF64]: EConv(I2F, e);
			case [TF64, TI32]: EConv(F2I, e);
			case [TRef(RAny), TF64]: runtime("numeric", [e]);
			case [TRef(_), TRef(_)]: ECast(t, e);
			case [_, TRef(RAny)]: temp(EBox(from, e));
			case [TRef(_), _] if (Ir.isScalar(t)): EUnbox(t, e);
			case _: throw "TSHX003: cannot convert " + from + " to " + t;
		}
	}
}
