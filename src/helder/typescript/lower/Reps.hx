package helder.typescript.lower;

import haxe.ds.Vector;
import hxmc.ir.Ir;
import helder.typescript.check.Types;
import helder.typescript.check.Types.TsType;
import helder.typescript.ir.Builder;
import helder.typescript.lower.Classes.ClassLayout;

// What values look like in compiled code, by their TypeScript types: a
// number is an F64, an instance of a class with a layout is that class's
// hxmc object, an array the runtime's JsArray; anything else is a dynamic
// value (Dynamic, the runtime's JS values). A typed slot (a binding, a
// parameter, a result, a field) holds what its type says: a value enters
// it through store, which checks it and throws (TSHX100) where the types
// do not describe the program's values.
class Reps {
	final p:Program;
	final types:Types;
	final classes:Classes;
	final layouts:Map<ClassInfo, ClassLayout> = [];
	public final arrayClass:ClassInfo;
	final holeClass:ClassInfo;
	final objectBase:ClassInfo;
	var link:Null<FuncInfo> = null;

	public function new(p:Program, types:Types, classes:Classes) {
		this.p = p;
		this.types = types;
		this.classes = classes;
		arrayClass = runtimeClass("helder.typescript.js.JsArray");
		holeClass = runtimeClass("helder.typescript.js.Hole");
		objectBase = runtimeClass("helder.typescript.js.JsObject");
		if (classes.all.length == 0) return;
		for (fn in p.funcs) if (fn.name == "helder_typescript_js_Seed_libTypedClass") link = fn;
		if (link == null) throw "TSHX004: runtime helper not linked: libTypedClass";
		// (the hxmc classes first, then their fields: a field's type can be any of them)
		for (c in classes.all) {
			var sup = c.parent == null ? objectBase : c.parent.info;
			var ci = new ClassInfo("ts.C" + c.index + "_" + c.name, "ts_class" + c.index + "_" + ~/[^A-Za-z0-9_]/g.replace(c.name, "_"), sup);
			ci.ifaces = sup.ifaces.copy();
			ci.derived = sup.derived.copy();
			p.classes.push(ci);
			c.info = ci;
			layouts.set(ci, c);
		}
		for (c in classes.all) {
			c.info.fields = c.info.sup.fields.copy();
			for (name in c.names) c.info.fields.push({name: "ts_field" + c.info.fields.length, ty: rep(name.tsType)});
		}
	}

	function runtimeClass(name:String):ClassInfo {
		for (c in p.classes) if (c.name == name) return c;
		throw "TSHX004: runtime class not linked: " + name;
	}

	// ---- representations

	public function rep(t:Null<TsType>):Ty {
		if (types.isNumber(t)) return TF64;
		if (types.isArray(t)) return TRef(RObj(arrayClass));
		var c = t == null || t.isThis ? null : classes.of(types.instanceOf(t));
		return c == null ? TRef(RAny) : TRef(RObj(c.info));
	}

	// the class with a layout whose instances a type's values are (its `this` type's too)
	public function layoutOf(t:Null<TsType>):Null<ClassLayout> return classes.of(types.instanceOf(t));

	// a value into a slot of type t: checked where its own type does not prove it
	public function store(b:Builder, e:Ex, t:Ty, where:String):Ex {
		var from = Ir.typeOf(e);
		if (Type.enumEq(from, t)) return e;
		return switch [from, t] {
			case [TI32, TF64]: EConv(I2F, e);
			case [_, TF64]: b.runtime("expectNumber", [b.coerce(e, TRef(RAny)), EStr(where)]);
			case [TRef(RObj(d)), TRef(RObj(c))] if (isA(d, c)): ECast(t, e);
			case [_, TRef(RObj(c))]:
				var v = b.temp(b.coerce(e, TRef(RAny)));
				b.out.push(SIf(ENot(EInstOf(c, v)), b.block(() -> b.runtime("diverge", [EStr(describe(c)), v, EStr(where)])), new Vector(0)));
				ECast(t, v);
			case _: b.coerce(e, t);
		}
	}

	function isA(d:ClassInfo, c:ClassInfo):Bool {
		var k = d;
		while (k != null) {
			if (k == c) return true;
			k = k.sup;
		}
		return false;
	}

	function describe(c:ClassInfo):String return c == arrayClass ? "an array" : "an instance of " + layouts.get(c).name;

	// whether a value is statically of class c (no test needed)
	function exact(e:Ex, c:ClassInfo):Bool return switch Ir.typeOf(e) {
		case TRef(RObj(d)): isA(d, c);
		case _: false;
	}

	// (if the value is of class c: fast, else slow)
	function guarded(b:Builder, o:Ex, c:ClassInfo, fast:() -> Void, slow:() -> Void) {
		if (exact(o, c)) fast();
		else b.out.push(SIf(EInstOf(c, o), b.block(fast), b.block(slow)));
	}

	// ---- fields of classes with layouts
	// a field's slot in its class's hxmc class (and in its subclasses')
	public function slot(c:ClassLayout, name:String):Int return objectBase.fields.length + c.fields().indexOf(name);

	public function fieldGet(b:Builder, c:ClassLayout, obj:Ex, name:String, where:String):Ex {
		var i = slot(c, name), ty = c.info.fields[i].ty;
		var l = b.local("field", ty);
		var o = exact(obj, c.info) ? obj : b.temp(b.coerce(obj, TRef(RAny)));
		guarded(b, o, c.info, () -> b.out.push(SSet(l, EField(c.info, i, ECast(TRef(RObj(c.info)), o)))),
			() -> b.out.push(SSet(l, store(b, b.runtime("libGet", [o, EStr(name)]), ty, where))));
		return ELocal(l);
	}

	public function fieldSet(b:Builder, c:ClassLayout, o:Ex, name:String, v:Ex, where:String) {
		var i = slot(c, name);
		guarded(b, o, c.info, () -> b.out.push(SSetField(c.info, i, ECast(TRef(RObj(c.info)), o), store(b, v, c.info.fields[i].ty, where))),
			() -> b.runtime("libPut", [b.coerce(o, TRef(RAny)), EStr(name), b.coerce(v, TRef(RAny))]));
	}

	// (a class's value: its layout, by field number, and its allocator)
	public function linkClass(b:Builder, c:ClassLayout, cls:Ex) {
		var ci = c.info, names = c.fields();
		var self = TRef(RObj(ci));
		var tys = [for (a in link.args) a.ty];
		var get = linkLambda(b, closureSig(tys[2]), (b, args) -> {
			var o = b.temp(ECast(self, ELocal(args[0])));
			for (k in 0...names.length)
				b.out.push(SIf(EBin(Eq, ELocal(args[1]), EInt(k)), b.block(() -> b.out.push(SReturn(b.coerce(EField(ci, slot(c, names[k]), o), TRef(RAny))))), new Vector(0)));
			b.out.push(SReturn(b.runtime("getUndefined", [])));
		});
		var set = linkLambda(b, closureSig(tys[3]), (b, args) -> {
			var o = b.temp(ECast(self, ELocal(args[0])));
			for (k in 0...names.length) {
				var i = slot(c, names[k]);
				b.out.push(SIf(EBin(Eq, ELocal(args[1]), EInt(k)), b.block(() -> b.out.push(SSetField(ci, i, o, store(b, ELocal(args[2]), ci.fields[i].ty, c.name + "." + names[k])))), new Vector(0)));
			}
			b.out.push(SReturn(null));
		});
		var alloc = linkLambda(b, closureSig(tys[4]), (b, args) -> {
			var o = b.temp(ENewObj(ci));
			b.out.push(SExpr(ECall(objectBase.ctor, Vector.fromArrayCopy([o, ELocal(args[0])]))));
			// (dynamic fields start undefined; typed ones are set before they are read)
			for (f in names) {
				var i = slot(c, f);
				if (ci.fields[i].ty.match(TRef(RAny))) b.out.push(SSetField(ci, i, o, b.runtime("getUndefined", [])));
			}
			b.out.push(SReturn(b.coerce(o, closureSig(tys[4]).ret)));
		});
		var elem = switch tys[1] {
			case TRef(RArr(t)): t;
			case t: throw "TSHX004: not an array type: " + t;
		};
		b.runtime("libTypedClass", [cls, ENewArr(elem, Vector.fromArrayCopy([for (f in names) b.coerce(EStr(f), elem)])), get, set, alloc]);
	}

	// a function of the runtime's type (a closure of signature s) built here
	function linkLambda(outer:Builder, s:SigInfo, build:(Builder, Array<Local>) -> Void):Ex {
		var f = Builder.func(p, "layout" + p.funcs.length, s.ret);
		f.args = [new Local(0, "closure", TRef(RAny))].concat([for (i in 0...s.args.length) new Local(i + 1, "a" + i, s.args[i])]);
		var li = new LambdaInfo(p.lambdas.length, s, new Vector(0), f);
		p.lambdas.push(li);
		f.lambda = li;
		var b = new Builder(p, f);
		build(b, f.args.slice(1));
		b.finish();
		return outer.temp(ENewClos(li, new Vector(0)));
	}

	static function closureSig(t:Ty):SigInfo return switch t {
		case TRef(RClos(s)): s;
		case _: throw "TSHX004: not a function type: " + t;
	}

	// ---- arrays: length, and elements by number

	public function arrayLength(b:Builder, o:Ex):Ex {
		var l = b.local("length", TF64);
		guarded(b, o, arrayClass, () -> b.out.push(SSet(l, EField(arrayClass, arrayClass.fieldIndex("length"), ECast(TRef(RObj(arrayClass)), o)))),
			() -> b.out.push(SSet(l, b.coerce(b.runtime("libGet", [b.coerce(o, TRef(RAny)), EStr("length")]), TF64))));
		return ELocal(l);
	}

	// (an element stored densely at a number index, not a hole: hit with the
	// items and the index; otherwise miss, the runtime's way)
	function denseElement(b:Builder, o:Ex, k:Ex, hit:(Local, Ex) -> Void, miss:() -> Void) {
		var found = b.local("dense", TBool);
		b.out.push(SSet(found, ECast(TBool, EInt(0))));
		function inside() {
			var items = b.local("items", TRef(RArr(TRef(RAny))));
			b.out.push(SSet(items, EField(arrayClass, arrayClass.fieldIndex("items"), ECast(TRef(RObj(arrayClass)), o))));
			when(b, EBin(FGe, k, EF64(0)), () -> when(b, EBin(FLt, k, EConv(I2F, EArrLen(ELocal(items)))), () -> {
				var i = b.temp(EConv(F2I, k));
				when(b, EBin(FEq, EConv(I2F, i), k), () -> {
					var v = b.temp(EArrGet(TRef(RAny), ELocal(items), i));
					when(b, ENot(EInstOf(holeClass, v)), () -> {
						b.out.push(SSet(found, ECast(TBool, EInt(1))));
						hit(items, i);
					});
				});
			}));
		}
		if (exact(o, arrayClass)) inside(); else when(b, EInstOf(arrayClass, o), inside);
		when(b, ENot(ELocal(found)), miss);
	}

	static function when(b:Builder, cond:Ex, then:() -> Void) b.out.push(SIf(cond, b.block(then), new Vector(0)));

	public function arrayGet(b:Builder, o:Ex, k:Ex):Ex {
		var l = b.local("element", TRef(RAny));
		denseElement(b, o, k, (items, i) -> b.out.push(SSet(l, EArrGet(TRef(RAny), ELocal(items), i))),
			() -> b.out.push(SSet(l, b.runtime("libGet", [b.coerce(o, TRef(RAny)), b.coerce(k, TRef(RAny))]))));
		return ELocal(l);
	}

	public function arraySet(b:Builder, o:Ex, k:Ex, v:Ex) {
		var value = b.temp(b.coerce(v, TRef(RAny)));
		denseElement(b, o, k, (items, i) -> b.out.push(SArrSet(TRef(RAny), items, i, value)),
			() -> b.runtime("libPut", [b.coerce(o, TRef(RAny)), b.coerce(k, TRef(RAny)), value]));
	}
}
