package helder.typescript.lower;

import haxe.ds.Vector;
import hxmc.ir.Ir;
import helder.typescript.ir.Builder;
import helder.typescript.lower.Api;

// Calls from the compiled TypeScript program into helder's Haxe API,
// straight to the functions Haxe's typing lowered (their IR names: hxmc's,
// the manifest's classes' idents), each value converted by the type the
// manifest gives (DESIGN.md 7.3): a JavaScript value into a Haxe parameter
// (a number into an Int or a Float, a string, a Bool, a Read, an instance
// checked, an array's elements, a function as a closure of the parameter's
// signature, a structure field by field; else untyped, Interop.toHaxe), a
// Haxe result back (Interop.toJs, numbers as they are). The Interop
// functions it calls are where values cross.
@:access(helder.typescript.lower.Frontend)
class Haxe {
	final f:Frontend;
	final p:Program;
	public final manifest:Manifest;
	final funcs:Map<String, FuncInfo> = [];
	final classInfos:Map<String, ClassInfo> = [];
	final globals:Map<String, Int> = [];
	final closures:Map<String, LambdaInfo> = [];
	var serial = 0;

	public function new(f:Frontend, p:Program, manifest:Manifest) {
		this.f = f;
		this.p = p;
		this.manifest = manifest;
		for (fn in p.funcs) funcs.set(fn.name, fn);
		for (c in p.classes) classInfos.set(c.name, c);
		for (i in 0...p.globals.length) globals.set(p.globals[i].name, i);
		for (li in p.lambdas) closures.set(li.fn.name, li);
	}

	var b(get, never):Builder;

	function get_b():Builder return f.b;

	// ---- the program's functions, classes and statics by name

	public function fn(name:String):FuncInfo {
		var x = funcs.get(name);
		if (x == null) throw "TSHX004: helder's " + name + " is not in the program (the manifest's keep names it: helder.typescript.api.Manifest)";
		return x;
	}

	public function hasFn(name:String):Bool return funcs.exists(name);

	// a Haxe class path's (or a module's subtype's: TestRenderer.TestNode) hxmc class
	public function classInfo(path:String):Null<ClassInfo> {
		var c = classInfos.get(path);
		if (c != null) return c;
		var m = manifest.cls(path);
		return m == null ? null : classInfos.get(m.path);
	}

	// a static's global (its index), by its IR name
	public function global(name:String):Null<Int> return globals.get(name);

	// a static function as a closure (hxmc's: <name>__sclos, made when Haxe names it as a value)
	public function staticClosure(name:String):Ex {
		var li = closures.get(name + "__sclos");
		if (li == null) throw "TSHX004: helder's " + name + " as a value is not in the program";
		return ENewClos(li, new Vector(0));
	}

	public function interop(name:String):FuncInfo return fn("helder_typescript_js_Interop_" + name);

	// a call, its result a temp (undefined: Void)
	public function call(fi:FuncInfo, args:Array<Ex>):Ex {
		var xs = [for (i in 0...fi.args.length) i < args.length ? b.coerce(args[i], fi.args[i].ty) : zero(fi.args[i].ty)];
		if (fi.ret == TVoid) {
			b.out.push(SExpr(ECall(fi, Vector.fromArrayCopy(xs))));
			return ENull(TRef(RAny));
		}
		return b.temp(ECall(fi, Vector.fromArrayCopy(xs)));
	}

	// (an argument not given: null, 0, false)
	public static function zero(t:Ty):Ex return switch t {
		case TI32 | TU8: EInt(0);
		case TBool: ECast(TBool, EInt(0));
		case TF64: EF64(0);
		case TI64: EConv(I2L, EInt(0));
		case _: ENull(t);
	}

	// ---- representations of Haxe types

	// the IR type a Haxe type's values have (in a structure's field, a closure's signature)
	public function ty(t:HType):Ty return switch t {
		case HInt: TI32;
		case HFloat: TF64;
		case HBool: TBool;
		case HVoid: TVoid;
		case HString: TRef(RStr);
		case HNull(x): switch ty(x) {
				case TI32 | TF64 | TBool: TRef(RAny);
				case r: r;
			}
		case HFn(args, ret): TRef(RClos(p.sig([for (a in args) ty(a.t)], ty(ret))));
		case HAbstract(_, _, under, null): ty(under);
		case HAbstract(_, _, under, _): ty(under);
		case _: TRef(RAny);
	}

	// ---- JavaScript into Haxe

	// e (a JavaScript value, or a typed one: a number, a string, a Bool) as
	// Haxe's t, into a slot of IR type to
	public function toHaxe(e:Ex, t:HType, to:Ty, where:String):Ex {
		var from = Ir.typeOf(e);
		return switch t {
			case HInt:
				from == TF64 ? EConv(F2I, e) : from == TI32 ? e : call(interop("int"), [any(e), EStr(where)]);
			case HFloat:
				from == TF64 ? e : call(interop("float"), [any(e), EStr(where)]);
			case HBool:
				from == TBool ? e : call(interop("bool"), [any(e), EStr(where)]);
			case HString:
				from.match(TRef(RStr)) ? e : call(interop("string"), [any(e), EStr(where)]);
			case HNull(x) if (x.match(HInt | HFloat | HBool)):
				// (a scalar or null, boxed)
				var v = b.temp(any(e));
				var l = b.local("nullable", to);
				b.out.push(SIf(nullish(v), b.block(() -> b.out.push(SSet(l, ENull(to)))), b.block(() -> {
					var s = toHaxe(v, x, ty(x), where);
					b.out.push(SSet(l, b.coerce(b.temp(EBox(Ir.typeOf(s), s)), to)));
				})));
				ELocal(l);
			case HNull(x) | HAbstract(_, _, x, _):
				toHaxe(e, x, to, where);
			case HRead(_):
				b.coerce(call(interop("reader"), [any(e)]), to);
			case HClass(path, _):
				var ci = classInfo(path);
				if (ci == null) b.coerce(call(interop("toHaxe"), [any(e)]), to) else b.coerce(checked(ci, e, where), to);
			case HArray(x):
				var items = call(interop("items"), [any(e), EStr(where)]);
				var elem = switch to {
					case TRef(RArr(t)): t;
					case _: TRef(RAny);
				}
				var out = b.local("items", TRef(RArr(elem)));
				b.out.push(SSet(out, ENewArr(elem, new Vector(0))));
				var i = b.local("i", TI32);
				b.out.push(SSet(i, EInt(0)));
				var list = b.temp(items);
				b.out.push(SLoop(b.block(() -> {
					b.out.push(SIf(EBin(Ge, ELocal(i), EArrLen(list)), Vector.fromArrayCopy([SBreak]), new Vector(0)));
					var v = b.temp(EArrGet(TRef(RAny), list, ELocal(i)));
					b.out.push(SArrPush(elem, out, b.coerce(toHaxe(v, x, elem, where), elem)));
					b.out.push(SSet(i, EBin(Add, ELocal(i), EInt(1))));
				})));
				b.coerce(ELocal(out), to);
			case HFn(args, ret):
				switch to {
					case TRef(RClos(s)): adapter(e, s, args, ret, where);
					case _: b.coerce(call(interop("toHaxe"), [any(e)]), to);
				}
			case HAnon(fields):
				var o = b.temp(any(e));
				b.coerce(structure(o, fields, where), to);
			case HView(_) | HDynamic | HParam(_) | HEnum(_) | HVoid:
				b.coerce(call(interop("toHaxe"), [any(e)]), to);
		}
	}

	// a structure of fields from a JavaScript object's properties (each converted by its type)
	function structure(o:Ex, fields:Array<HArg>, where:String):Ex {
		var shape = [for (x in fields) {name: x.name, ty: ty(x.t)}];
		var values = [for (x in fields) {
			var v = b.temp(call(interop("field"), [o, EStr(x.name)]));
			fieldValue(v, x, where);
		}];
		var s = p.shape(shape);
		var sorted = [for (k in 0...s.fields.length) values[shape.indexOf(Lambda.find(shape, x -> x.name == s.fields[k].name))]];
		return b.temp(ENewAnon(s, Vector.fromArrayCopy(sorted)));
	}

	// (a field's value: undefined, when optional, its type's null)
	public function fieldValue(v:Ex, x:HArg, where:String):Ex {
		var t = ty(x.t);
		if (!x.opt) return b.coerce(toHaxe(v, x.t, t, where), t);
		var l = b.local("field", t);
		b.out.push(SIf(nullish(v), b.block(() -> b.out.push(SSet(l, zero(t)))), b.block(() -> b.out.push(SSet(l, b.coerce(toHaxe(v, x.t, t, where), t))))));
		return ELocal(l);
	}

	// a structure from values given by name (a component's props: the
	// JavaScript values of those given, converted; the others null)
	public function props(fields:Array<HArg>, given:Map<String, Ex>, where:String):Ex {
		var shape = [for (x in fields) {name: x.name, ty: ty(x.t)}];
		var values = new Map<String, Ex>();
		for (x in fields) {
			var v = given.get(x.name);
			values.set(x.name, v == null ? zero(ty(x.t)) : fieldValue(b.temp(any(v)), x, where));
		}
		var s = p.shape(shape);
		return b.temp(ENewAnon(s, Vector.fromArrayCopy([for (k in 0...s.fields.length) values.get(s.fields[k].name)])));
	}

	function nullish(v:Ex):Ex return b.temp(ECall(interop("isNullish"), Vector.fromArrayCopy([any(v)])));

	function any(e:Ex):Ex return b.coerce(e, TRef(RAny));

	// a JavaScript function as a closure of signature s (args and ret: the
	// Haxe function type's), null for null or undefined: its arguments made
	// JavaScript's, its result Haxe's
	public function adapter(e:Ex, s:SigInfo, args:Array<HArg>, ret:HType, where:String):Ex {
		var js = b.local("function", TRef(RAny));
		b.out.push(SSet(js, any(e)));
		var fi = Builder.func(p, "adapter" + serial++, s.ret);
		fi.args = [new Local(0, "closure", TRef(RAny))].concat([for (i in 0...s.args.length) new Local(i + 1, "a" + i, s.args[i])]);
		var li = new LambdaInfo(p.lambdas.length, s, Vector.fromArrayCopy([js]), fi);
		p.lambdas.push(li);
		fi.lambda = li;
		var outer = f.b;
		f.b = new Builder(p, fi);
		var target = b.temp(ECapture(li, 0, ELocal(fi.args[0])));
		var list = b.temp(ENewArr(TRef(RAny), Vector.fromArrayCopy([for (i in 0...s.args.length) any(toJs(ELocal(fi.args[i + 1]), i < args.length ? args[i].t : HDynamic))])));
		var r = b.temp(ECall(interop("call"), Vector.fromArrayCopy([target, list])));
		if (s.ret == TVoid) b.out.push(SReturn(null)); else b.out.push(SReturn(b.coerce(toHaxe(r, ret, s.ret, where), s.ret)));
		b.finish();
		f.b = outer;
		var l = b.local("closure", TRef(RClos(s)));
		b.out.push(SIf(nullish(ELocal(js)), b.block(() -> b.out.push(SSet(l, ENull(TRef(RClos(s)))))), b.block(() -> b.out.push(SSet(l, ENewClos(li, Vector.fromArrayCopy([ELocal(js)])))))));
		return ELocal(l);
	}

	// ---- Haxe into JavaScript

	// a Haxe value of type t as the program's
	public function toJs(e:Ex, t:HType):Ex {
		var from = Ir.typeOf(e);
		return switch [from, HTypes.bare(t)] {
			case [TVoid, _]: b.runtime("getUndefined", []);
			case [TI32, _]: EConv(I2F, e);
			case [TF64 | TBool, _]: e;
			case [TRef(RStr), _]: e;
			case _: call(interop("toJs"), [any(e)]);
		}
	}

	// ---- calls

	// a static of class c called with the program's values (null: not given)
	// (converted: the arguments are Haxe's values already)
	public function callStatic(c:MClass, m:MMember, args:Array<Null<Ex>>, where:String, converted = false):Ex {
		var fi = fn(c.ident + "_" + m.name);
		return invoke(fi, null, m.type, args, where, converted);
	}

	// a method of the instance obj (a Haxe value)
	public function callMethod(c:MClass, m:MMember, obj:Ex, args:Array<Null<Ex>>, where:String):Ex {
		var fi = fn(c.ident + "_" + m.name);
		return invoke(fi, obj, m.type, args, where);
	}

	function invoke(fi:FuncInfo, self:Null<Ex>, t:HType, args:Array<Null<Ex>>, where:String, converted = false):Ex {
		var params = switch t {
			case HFn(a, _): a;
			case _: [];
		}
		var ret = switch t {
			case HFn(_, r): r;
			case _: HDynamic;
		}
		var skip = self == null ? 0 : 1;
		var xs:Array<Ex> = self == null ? [] : [b.coerce(self, fi.args[0].ty)];
		for (i in skip...fi.args.length) {
			var k = i - skip;
			var to = fi.args[i].ty;
			var a = k < args.length ? args[k] : null;
			var h = k < params.length ? params[k].t : HDynamic;
			xs.push(a == null ? zero(to) : b.coerce(converted ? a : toHaxe(a, h, to, where), to));
		}
		var call:Ex = self != null && fi.selfClass != null && dispatched(fi) ? ECallDispatch(fi.dispatchSel, p.selectors[fi.dispatchSel].sig, Vector.fromArrayCopy(xs)) : ECall(fi,
			Vector.fromArrayCopy(xs));
		if (fi.ret == TVoid) {
			b.out.push(SExpr(call));
			return b.runtime("getUndefined", []);
		}
		return toJs(b.temp(call), ret);
	}

	// (a method a subclass of its class overrides: called through its selector)
	function dispatched(fi:FuncInfo):Bool {
		if (fi.dispatchSel < 0) return false;
		var name = p.selectors[fi.dispatchSel].name;
		for (c in p.classes) if (c != fi.selfClass && c.methods.exists(name)) {
			var k = c.sup;
			while (k != null && k != fi.selfClass) k = k.sup;
			if (k != null) return true;
		}
		return false;
	}

	// a new instance of class c
	public function construct(c:MClass, args:Array<Null<Ex>>, where:String):Ex {
		var ci = classInfo(c.path);
		if (ci == null) throw "TSHX004: helder's class " + c.path + " is not in the program";
		var o = b.temp(ENewObj(ci));
		var fi = fn(c.ident + "_new");
		var params = switch c.ctor {
			case HFn(a, _): a;
			case _: [];
		}
		var xs:Array<Ex> = [b.coerce(o, fi.args[0].ty)];
		for (i in 1...fi.args.length) {
			var a = i - 1 < args.length ? args[i - 1] : null;
			var h = i - 1 < params.length ? params[i - 1].t : HDynamic;
			xs.push(a == null ? zero(fi.args[i].ty) : b.coerce(toHaxe(a, h, fi.args[i].ty, where), fi.args[i].ty));
		}
		b.out.push(SExpr(ECall(fi, Vector.fromArrayCopy(xs))));
		return call(interop("toJs"), [any(o)]);
	}

	// the program's value as an instance of class c (checked), or null
	public function instance(c:MClass, v:Ex, where:String):Ex {
		var ci = classInfo(c.path);
		if (ci == null) throw "TSHX004: helder's class " + c.path + " is not in the program";
		return checked(ci, v, where);
	}

	// (the program's value, unwrapped, as an instance of ci: null, or checked)
	function checked(ci:ClassInfo, e:Ex, where:String):Ex {
		var v = b.temp(call(interop("unwrap"), [any(e)]));
		b.out.push(SIf(EBin(RefNe, v, ENull(TRef(RAny))), b.block(() -> b.out.push(SIf(ENot(EInstOf(ci, v)),
			b.block(() -> b.runtime("diverge", [EStr("a " + ci.name), v, EStr(where)])), new Vector(0)))), new Vector(0)));
		return b.temp(ECast(TRef(RObj(ci)), v));
	}

	// a member read: a field, a property's getter, a constant, a method as a function
	public function getMember(c:MClass, m:MMember, obj:Null<Ex>, where:String):Ex {
		if (m.kind == "const") return constant(m);
		if (m.get != null) {
			var g = fn(c.ident + "_" + m.get);
			return toJs(obj == null ? call(g, []) : call(g, [instance(c, obj, where)]), m.type);
		}
		if (m.kind == "method") return call(interop("toJs"), [obj == null ? staticClosure(c.ident + "_" + m.name) : fail(where, "a method of helder's read as a value: call it")]);
		if (obj == null) {
			var g = global(c.ident + "_" + m.name);
			if (g == null) throw "TSHX004: helder's " + c.path + "." + m.name + " is not in the program";
			return toJs(b.temp(EGlobal(g, p.globals[g].ty)), m.type);
		}
		var ci = classInfo(c.path);
		var o = b.temp(instance(c, obj, where));
		return toJs(b.temp(EField(ci, ci.fieldIndex(m.name), o)), m.type);
	}

	// a member written
	public function setMember(c:MClass, m:MMember, obj:Null<Ex>, v:Ex, where:String) {
		if (m.kind != "var" || m.readonly) fail(where, c.path + "." + m.name + " is read only");
		if (m.set != null) {
			var s = fn(c.ident + "_" + m.set);
			var to = s.args[s.args.length - 1].ty;
			call(s, obj == null ? [toHaxe(v, m.type, to, where)] : [instance(c, obj, where), toHaxe(v, m.type, to, where)]);
			return;
		}
		if (obj == null) {
			var g = global(c.ident + "_" + m.name);
			if (g == null) throw "TSHX004: helder's " + c.path + "." + m.name + " is not in the program";
			b.out.push(SSetGlobal(g, b.coerce(toHaxe(v, m.type, p.globals[g].ty, where), p.globals[g].ty)));
			return;
		}
		var ci = classInfo(c.path);
		var o = b.temp(instance(c, obj, where));
		var i = ci.fieldIndex(m.name);
		b.out.push(SSetField(ci, i, o, b.coerce(toHaxe(v, m.type, ci.fields[i].ty, where), ci.fields[i].ty)));
	}

	function constant(m:MMember):Ex
		return Std.isOfType(m.value, String) ? EStr(m.value) : Std.isOfType(m.value, Bool) ? ECast(TBool, EInt(m.value ? 1 : 0)) : EF64(m.value);

	static function fail(where:String, message:String):Dynamic throw where + ": TSHX001: " + message;
}
