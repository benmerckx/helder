package helder.typescript.lower;

import haxe.ds.Vector;
import hxmc.ir.Ir;
import hxmc.ir.CInterop;
import helder.typescript.check.Ast;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;
import helder.typescript.ir.Builder;

// helder/native's definitions (src/helder/native/index.ts): native.c's C
// functions, native.objc's messages, native.com's interfaces and
// native.jni's Java classes, each function of the definition's object a
// direct function of the program whose parameters' and result's
// annotations are their C types (helder/native's i8 ... u64, isize, usize,
// f32, f64, bool, cstring, pointer, buffer, id, jstring, Java<"...">), its
// body never run. The calls go through hxmc's extern machinery, as Haxe's
// do (hxmc.ir.CInterop's tables): native.c's to the symbol (a Haxe
// @:hxmc.c extern's), the others through a function's address (an
// @:hxmc.indirect extern's): objc_msgSend's (helder.os.objc.Msg's), a
// vtable's slot (helder.os.VTable's, COM's and JNIEnv's). Values cross as
// helder.native.Script converts them (helder/native/runtime).
@:access(helder.typescript.lower.Frontend)
class Natives {
	final f:Frontend;

	var b(get, never):Builder;

	inline function get_b():Builder return f.b;

	public function new(f:Frontend) this.f = f;

	static final TYPES = [
		"i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "isize", "usize", "f32", "f64", "bool", "cstring", "pointer", "buffer", "id", "jstring"
	];

	static final FIELDS = [
		"c" => ["lib", "fns"],
		"objc" => ["class", "lib", "statics", "methods"],
		"com" => ["iid", "clsid", "base", "methods"],
		"jni" => ["class", "statics", "methods", "fields", "staticFields"]
	];

	function fail(n:Node, s:String):Dynamic return f.fail(n, s);

	function script(name:String):FuncInfo return f.bridge.fn("helder_native_Script_" + name);

	function call(fi:FuncInfo, args:Array<Ex>):Ex return f.bridge.call(fi, args);

	// native.<kind>(def): an object of the program's functions (and, for
	// some kinds, values: com's iid)
	public function library(n:Node, kind:String, def:Null<Node>):Ex {
		var fields = FIELDS.get(kind);
		if (f.bridge == null) fail(n, 'native.$kind: helder/native is not declared to the program');
		if (def == null || def.kind != KindObjectLiteralExpression) fail(n, 'native.$kind takes one argument, an object literal: {${fields.join(", ")}}');
		var given = new Map<String, Node>();
		for (p in def.properties()) {
			var key = p.name() == null ? "" : p.name().text;
			if (p.kind != KindPropertyAssignment) fail(p, 'native.$kind: $key is a field of the object literal ($key: ...)');
			if (!fields.contains(key)) fail(p, 'native.$kind: no field $key (${fields.join(", ")})');
			given.set(key, p.initializer());
		}
		var keys:Array<Ex> = [], values:Array<Ex> = [];
		function add(name:String, at:Node, v:Ex) {
			for (k in keys) if (Type.enumEq(k, EStr(name))) fail(at, 'native.$kind: $name is declared twice');
			keys.push(EStr(name));
			values.push(v);
		}
		function fn(name:String, fi:FuncInfo, at:Node) add(name, at, f.functionValue(fi, name));
		var os = hxmc.ir.Lower.targetOs, code = hxmc.ir.Lower.targetCode;
		switch kind {
			case "c":
				var lib = string(given.get("lib"), "lib", kind, true);
				if (!given.exists("fns")) fail(n, "native.c: fns, the functions, is missing");
				for (x in functions(given.get("fns"), kind, "fns")) fn(x.name, cFunction(lib, x.name, x.fn), x.fn);
			case "objc":
				if (os != 1) fail(n, "native.objc: Objective-C is Apple's (macOS, iOS): call it under a platform test (helder/platform)");
				var name = string(given.get("class"), "class", kind, false);
				if (name == null) fail(n, "native.objc: class, the class's name, is missing");
				var lib = string(given.get("lib"), "lib", kind, true);
				if (lib != null) CInterop.LOADS.set(lib, true);
				for (x in functions(given.get("statics"), kind, "statics")) fn(x.name, objcMessage(name, x.name, x.fn, true), x.fn);
				for (x in functions(given.get("methods"), kind, "methods")) fn(x.name, objcMessage(name, x.name, x.fn, false), x.fn);
				add("class", n, b.temp(objcClass(name)));
			case "com":
				if (os != 2) fail(n, "native.com: COM is Windows': call it under a platform test (helder/platform)");
				var iid = string(given.get("iid"), "iid", kind, false);
				if (iid == null) fail(n, "native.com: iid, the interface's IID, is missing");
				guidText(iid, given.get("iid"));
				var base = 3;
				var bn = given.get("base");
				if (bn != null) {
					if (bn.kind != KindNumericLiteral) fail(bn, "native.com: base is a number literal (the slots before the methods: IUnknown's 3)");
					var parsed:Null<Int> = Std.parseInt(bn.text);
					base = parsed ?? 0;
					if (base < 3) fail(bn, "native.com: base is 3 or more (IUnknown's three slots come first)");
				}
				var unknown = [
					{name: "QueryInterface", params: ["self", "iid", "out"], kinds: ["pointer", "pointer", "buffer"], ret: "i32"},
					{name: "AddRef", params: ["self"], kinds: ["pointer"], ret: "u32"},
					{name: "Release", params: ["self"], kinds: ["pointer"], ret: "u32"}
				];
				for (slot in 0...3) {
					var u = unknown[slot];
					fn(u.name, comMethod(u.name, u.params, u.kinds, u.ret, slot, n), n);
				}
				var slot = base;
				for (x in functions(given.get("methods"), kind, "methods")) {
					var s = signature(x.name, x.fn, kind);
					if (s.kinds.length == 0 || s.kinds[0] != "pointer" && s.kinds[0] != "id")
						fail(x.fn, 'native.com: ${x.name} takes the interface\'s pointer first (self: pointer)');
					fn(x.name, comMethod(x.name, s.params, s.kinds, s.ret, slot++, x.fn), x.fn);
				}
				var iidAt = guid(iid);
				add("iid", n, b.temp(EGlobal(iidAt, TF64)));
				var clsid = string(given.get("clsid"), "clsid", kind, true);
				if (clsid != null) {
					guidText(clsid, given.get("clsid"));
					fn("create", comCreate(guid(clsid), iidAt, n), n);
				}
			case "jni":
				if (code != 9 && code != 10) fail(n, "native.jni: JNI is Android's: call it under a platform test (helder/platform)");
				var name = string(given.get("class"), "class", kind, false);
				if (name == null) fail(n, "native.jni: class, the Java class's name, is missing");
				var cls = cached("jclass", () -> call(script("jniClass"), [EStr(StringTools.replace(name, "/", "."))]));
				for (part in [{key: "methods", kind: 0}, {key: "statics", kind: 1}, {key: "fields", kind: 2}, {key: "staticFields", kind: 3}])
					for (x in functions(given.get(part.key), kind, part.key)) fn(x.name, jniMember(cls, name, x.name, x.fn, part.kind), x.fn);
				add("class", n, b.temp(EGlobal(cls, TF64)));
			case _:
		}
		return b.runtime("libObject", [f.pack(keys), f.pack(values)]);
	}

	// (a field that is a string literal: lib, class, iid; null where it may be left out)
	function string(v:Null<Node>, key:String, kind:String, optional:Bool):Null<String> {
		if (v == null) return null;
		if (v.kind != KindStringLiteral && v.kind != KindNoSubstitutionTemplateLiteral) fail(v, 'native.$kind: $key is a string literal');
		return v.text;
	}

	// (an object literal's functions: its fields' arrow functions, function expressions or methods)
	function functions(o:Null<Node>, kind:String, key:String):Array<{name:String, fn:Node}> {
		if (o == null) return [];
		if (o.kind != KindObjectLiteralExpression) fail(o, 'native.$kind: $key is an object literal of functions');
		return [for (p in o.properties()) {
			var name = p.name() == null ? "" : p.name().text;
			var fn = p.kind == KindPropertyAssignment ? p.initializer() : p.kind == KindMethodDeclaration ? p : null;
			if (fn == null || (fn.kind != KindArrowFunction && fn.kind != KindFunctionExpression && fn.kind != KindMethodDeclaration))
				fail(p, 'native.$kind: $name is not a function (its parameters and result annotated with helder/native\'s C types)');
			{name: name, fn: fn};
		}];
	}

	function signature(name:String, fn:Node, kind:String):{params:Array<String>, kinds:Array<String>, ret:String} {
		var params = fn.parameters();
		var kinds = [for (q in params) nativeType(q.type(), q, "parameter " + q.name().text, kind)];
		for (k in kinds) if (k == "void") fail(fn, 'native.$kind: $name takes void');
		return {
			params: [for (i in 0...params.length) params[i].name().kind == KindIdentifier ? params[i].name().text : "a" + i],
			kinds: kinds,
			ret: nativeType(fn.type(), fn, name + "'s result", kind)
		};
	}

	// (a C type of helder/native's, by an annotation: the name it is imported as
	// from there, or number, boolean, string, void; Java<"a/b/C">, a Java
	// object of that class: "L<class>;" after its kind)
	function nativeType(t:Null<Node>, at:Node, what:String, kind:String):String {
		if (t == null) fail(at, 'native.$kind: $what has no type (helder/native\'s C types: ${TYPES.join(", ")}, void)');
		switch t.kind {
			case KindNumberKeyword: return "f64";
			case KindBooleanKeyword: return "bool";
			case KindStringKeyword: return kind == "jni" ? "jstring" : "cstring";
			case KindVoidKeyword: return "void";
			case KindTypeReference if (t.typeName().kind == KindIdentifier):
				var from = Definitions.Scope.imported(t.file, t.typeName().text);
				if (from != null && from.module == "helder/native" && TYPES.contains(from.name)) return from.name;
				if (from != null && from.module == "helder/native" && from.name == "Java") {
					var args = t.typeArguments() ?? [];
					var lit = args.length == 1 && args[0].kind == KindLiteralType ? args[0].literal() : null;
					if (lit == null || lit.kind != KindStringLiteral) fail(t, 'native.$kind: Java<"a/b/C"> names its class by a string literal');
					return "L" + StringTools.replace(lit.text, ".", "/") + ";";
				}
			case _:
		}
		return fail(t, 'native.$kind: $what\'s type is not a C type (helder/native\'s: ${TYPES.join(", ")}; number, boolean, string, void)');
	}

	static function cType(k:String):CTy
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
	static function irType(c:CTy):Ty
		return switch c {
			case CI8 | CU8 | CI16 | CU16 | CI32: TI32;
			case CF32 | CF64: TF64;
			case CBool: TBool;
			case CVoid: TVoid;
			case _: TI64;
		}

	// (a TypeScript parameter's or result's representation)
	static function rep(k:String):Ty
		return switch k {
			case "bool": TBool;
			case "cstring" | "buffer" | "jstring": TRef(RAny);
			case "void": TVoid;
			case _: TF64;
		}

	// a direct function of the program: its parameters (the TypeScript
	// values, reps), `body` making the C call from them (given each
	// converted to C, a C string's and a buffer's memory freed after it) and
	// returning the C result (null: void), that result made the program's
	function wrap(name:String, params:Array<String>, kinds:Array<String>, ret:String, at:Node, body:(xs:Array<Ex>, raw:Array<Ex>) -> Null<Ex>):FuncInfo {
		var fi = Builder.func(f.p, "native_" + name + "_" + f.serial++, rep(ret));
		fi.args = [for (i in 0...params.length) new Local(i, params[i], rep(kinds[i]))];
		var outer = f.b;
		f.b = new Builder(f.p, fi);
		var where = Project.relative(at.file.path) + ":" + at.file.line(at.file.skipTrivia(at.pos));
		var xs:Array<Ex> = [], after:Array<() -> Void> = [];
		for (i in 0...kinds.length) {
			var x = ELocal(fi.args[i]);
			xs.push(switch kinds[i] {
				case "i8" | "u8" | "i16" | "u16" | "i32" | "u32": b.temp(EConv(L2I, EConv(F2L, x)));
				case "f32" | "f64" | "bool": x;
				case "cstring":
					var p = b.temp(call(script("cstring"), [x]));
					after.push(() -> call(script("free"), [p]));
					b.temp(EConv(F2L, p));
				case "buffer":
					var bytes = b.temp(call(f.bridge.interop("bytes"), [x, EStr(where)]));
					var p = b.temp(call(script("bytesIn"), [bytes]));
					after.push(() -> call(script("bytesBack"), [p, bytes]));
					b.temp(EConv(F2L, p));
				case "jstring": b.temp(EConv(F2L, call(script("jniString"), [x])));
				case _: b.temp(EConv(F2L, x));
			});
		}
		var r = body(xs, [for (a in fi.args) (ELocal(a) : Ex)]);
		if (r != null) r = b.temp(r);
		for (g in after) g();
		switch ret {
			case "void": b.out.push(SReturn(null));
			case "u32":
				var l = b.local("unsigned", TF64);
				b.out.push(SSet(l, EConv(I2F, r)));
				b.out.push(SIf(EBin(FLt, ELocal(l), EF64(0)), Vector.fromArrayCopy([SSet(l, EBin(FAdd, ELocal(l), EF64(4294967296.0)))]), new Vector(0)));
				b.out.push(SReturn(ELocal(l)));
			case "i8" | "u8" | "i16" | "u16" | "i32": b.out.push(SReturn(EConv(I2F, r)));
			case "f32" | "f64": b.out.push(SReturn(r));
			case "bool": b.out.push(SReturn(Ir.typeOf(r) == TBool ? r : b.temp(EBin(Ne, r, EInt(0)))));
			case "cstring": b.out.push(SReturn(b.coerce(call(script("string"), [EConv(L2F, r)]), TRef(RAny))));
			case "jstring": b.out.push(SReturn(b.coerce(call(script("jniText"), [EConv(L2F, r)]), TRef(RAny))));
			case "buffer": fail(at, 'native: $name returns a buffer: return a pointer (native.bytes reads it)');
			case _: b.out.push(SReturn(EConv(L2F, r)));
		}
		b.finish();
		f.b = outer;
		return fi;
	}

	// a C function by its symbol (hxmc's tables of C functions, as
	// CInterop.declare fills them for Haxe's externs), called with xs
	function cCall(sym:String, lib:Null<String>, args:Array<CTy>, ret:CTy, xs:Array<Ex>, at:Node):Ex {
		var sig:CSig = {args: args, ret: ret};
		var prev = CInterop.SIGS.get(sym);
		if (prev != null && (prev.ret != sig.ret || prev.args.length != sig.args.length || [for (i in 0...sig.args.length) prev.args[i] != sig.args[i]].contains(true)))
			fail(at, 'native: $sym is declared with another signature (by helder\'s Haxe or hxmc\'s runtime)');
		if (prev == null) CInterop.SIGS.set(sym, sig);
		// (a call in a safe region, as a Haxe extern's that is not @:hxmc.fast; one the runtime declares fast stays so)
		if (!hxmc.ir.FnLower.C_EXTERNS.exists(sym)) CInterop.BLOCKING.set(sym, true);
		if (lib != null) CInterop.LIBS.set(sym, lib);
		CInterop.USER.set(sym, true);
		return ECallHost(sym, Vector.fromArrayCopy(xs), irType(ret));
	}

	// a call through a C function's address (an @:hxmc.indirect extern's:
	// one per signature, the address first), in a safe region
	function indirect(fn:Ex, args:Array<CTy>, ret:CTy, xs:Array<Ex>):Ex {
		var cargs = [CPtr].concat(args);
		var key = CInterop.INDIRECT + "ts(" + [for (a in cargs) CInterop.shape(a)].join(",") + ")" + CInterop.shape(ret);
		if (!CInterop.SIGS.exists(key)) {
			CInterop.SIGS.set(key, {args: cargs, ret: ret});
			CInterop.BLOCKING.set(key, true);
		}
		return ECallHost(key, Vector.fromArrayCopy([fn].concat(xs)), irType(ret));
	}

	// a value computed once, where it is first needed (a class, a selector,
	// a method's ID: a global, 0 until then), a number
	function cached(name:String, compute:() -> Ex):Int {
		var g = global(name);
		lazy(g, compute);
		return g;
	}

	// (a number's global, 0 until set)
	function global(name:String):Int {
		var g = f.p.globals.length;
		f.p.globals.push({ty: TF64, init: null, name: "ts_native_" + name + "_" + g});
		return g;
	}

	function lazy(g:Int, compute:() -> Ex) {
		b.out.push(SIf(EBin(FEq, EGlobal(g, TF64), EF64(0)), b.block(() -> b.out.push(SSetGlobal(g, b.temp(compute())))), new Vector(0)));
	}

	// (a global cached in the function being built: its value)
	function read(g:Int, compute:() -> Ex):Ex {
		lazy(g, compute);
		return b.temp(EGlobal(g, TF64));
	}

	// a C string for a call (a literal's: freed after)
	function withCString(s:String, use:Ex -> Ex):Ex {
		var p = b.temp(call(script("cstring"), [EStr(s)]));
		var r = b.temp(use(EConv(F2L, p)));
		call(script("free"), [p]);
		return r;
	}

	// ---- native.c

	function cFunction(lib:Null<String>, name:String, fn:Node):FuncInfo {
		var s = signature(name, fn, "c");
		var sym = name;
		var os = hxmc.ir.Lower.targetOs;
		// (WebAssembly: a library's function the import (lib, name))
		if (os == 3 && lib == null) fail(fn, 'native.c: wasm32-wasi has no C library: lib names the module its host imports $name from');
		if (os == 3 && lib != null && lib != "env") {
			sym = "@import:" + lib.length + ":" + lib + "." + name;
			CInterop.IMPORT_NAMES.set(sym, name);
		}
		// (Linux's glibc mode: libc's functions the runtime does not import are the program's, libc.so.6's)
		var code = hxmc.ir.Lower.targetCode;
		var glibc = os == 0 && f.definitions.define("hxmc.libc") == "glibc" && code != 9 && code != 10;
		// (and libm and libc by their short names, their files: libm.so is a linker script)
		if (glibc && (lib == "m" || lib == "c")) lib = 'lib$lib.so.6';
		if (lib == null && glibc && !CInterop.LIBS.exists(sym)) lib = "libc.so.6";
		return wrap(name, s.params, s.kinds, s.ret, fn, (xs, _) -> {
			var c = cCall(sym, lib, [for (k in s.kinds) cType(k)], cType(s.ret), xs, fn);
			if (s.ret == "void") {
				b.out.push(SExpr(c));
				return null;
			}
			return c;
		});
	}

	// ---- native.objc: objc_msgSend's address (dlsym's), the class and the
	// selector (libobjc's), each found once

	static inline final OBJC = "/usr/lib/libobjc.A.dylib";

	var msgSend = -1;
	final classes = new Map<String, Int>();
	final selectors = new Map<String, Int>();

	function objcClass(name:String):Ex {
		if (!classes.exists(name)) classes.set(name, global("objc_class"));
		return read(classes.get(name), () -> EConv(L2F, withCString(name, s -> cCall("objc_getClass", OBJC, [CPtr], CPtr, [s], null))));
	}

	function objcSelector(sel:String):Ex {
		if (!selectors.exists(sel)) selectors.set(sel, global("objc_sel"));
		return read(selectors.get(sel), () -> EConv(L2F, withCString(sel, s -> cCall("sel_registerName", OBJC, [CPtr], CPtr, [s], null))));
	}

	function objcSend():Ex {
		if (msgSend < 0) msgSend = global("objc_msgSend");
		// (RTLD_DEFAULT: libobjc is loaded, objc_getClass is linked from it)
		return read(msgSend, () -> EConv(L2F, withCString("objc_msgSend", s -> cCall("dlsym", null, [CPtr, CPtr], CPtr, [EConv(I2L, EInt(-2)), s], null))));
	}

	// a message: `name`'s selector (each _ a colon: initWithUTF8String_ is
	// initWithUTF8String:; a quoted key as it is) sent to the class (a
	// static) or to the first argument (a method), its other arguments the
	// method's
	function objcMessage(cls:String, name:String, fn:Node, isStatic:Bool):FuncInfo {
		var s = signature(name, fn, "objc");
		if (!isStatic && (s.kinds.length == 0 || s.kinds[0] != "id" && s.kinds[0] != "pointer"))
			fail(fn, 'native.objc: the method $name takes its receiver first (self: id)');
		var sel = name.indexOf(":") >= 0 ? name : StringTools.replace(name, "_", ":");
		return wrap(name, s.params, s.kinds, s.ret, fn, (xs, _) -> {
			var send = EConv(F2L, objcSend());
			var self = isStatic ? EConv(F2L, objcClass(cls)) : xs[0];
			var rest = isStatic ? xs : xs.slice(1);
			var kinds = isStatic ? s.kinds : s.kinds.slice(1);
			var c = indirect(b.temp(send), [CPtr, CPtr].concat([for (k in kinds) cType(k)]), cType(s.ret), [b.temp(self), b.temp(EConv(F2L, objcSelector(sel)))].concat(rest));
			if (s.ret == "void") {
				b.out.push(SExpr(c));
				return null;
			}
			return c;
		});
	}

	// ---- native.com: the method at a slot of the object's vtable

	function comMethod(name:String, params:Array<String>, kinds:Array<String>, ret:String, slot:Int, at:Node):FuncInfo {
		return wrap(name, params, kinds, ret, at, (xs, raw) -> {
			var word = script("word");
			var table = b.temp(call(word, [raw[0], EInt(0)]));
			var fn = b.temp(EConv(F2L, call(word, [table, EInt(slot)])));
			var c = indirect(fn, [for (k in kinds) cType(k)], cType(ret), xs);
			if (ret == "void") {
				b.out.push(SExpr(c));
				return null;
			}
			return c;
		});
	}

	// (a GUID's text checked: Script.guid's form)
	function guidText(s:String, at:Node) {
		var h = StringTools.replace(StringTools.replace(StringTools.replace(s, "{", ""), "}", ""), "-", "");
		if (h.length != 32 || !~/^[0-9a-fA-F]+$/.match(h)) fail(at, 'native.com: "$s" is no GUID ("{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}")');
	}

	// a GUID in C's memory, made where the definition runs (kept: its address in a global)
	function guid(s:String):Int {
		var g = global("com_guid");
		b.out.push(SSetGlobal(g, b.temp(call(script("guid"), [EStr(s)]))));
		return g;
	}

	// create(): an object of the CLSID by the interface (Script.comCreate)
	function comCreate(clsid:Int, iid:Int, at:Node):FuncInfo
		return wrap("create", [], [], "pointer", at, (_, _) -> EConv(F2L, call(script("comCreate"), [EGlobal(clsid, TF64), EGlobal(iid, TF64)])));

	// ---- native.jni: methods and fields by their IDs (found once), called
	// through JNIEnv's table with their arguments as jvalues

	// (a kind's JNI descriptor: L...; a Java object's own)
	function descriptor(k:String, at:Node):String
		return switch k {
			case "bool": "Z";
			case "i8": "B";
			case "u16": "C";
			case "i16": "S";
			case "i32": "I";
			case "i64": "J";
			case "f32": "F";
			case "f64": "D";
			case "void": "V";
			case "jstring": "Ljava/lang/String;";
			case "pointer" | "id": "Ljava/lang/Object;";
			case k if (StringTools.startsWith(k, "L")): k;
			case _: fail(at, 'native.jni: $k is no Java type (boolean, i8, u16, i16, i32, i64, f32, number, string, Java<"a/b/C">, void)');
		}

	// (JNIEnv's slots: Call<T>MethodA, CallStatic<T>MethodA, Get<T>Field, GetStatic<T>Field by the result's descriptor)
	static function jniSlot(kind:Int, d:String):Int {
		var order = ["L", "Z", "B", "C", "S", "I", "J", "F", "D", "V"];
		var i = order.indexOf(d.charAt(0));
		return switch kind {
			case 0: 36 + 3 * i;
			case 1: 116 + 3 * i;
			case 2: 95 + i;
			case _: 145 + i;
		}
	}

	// (a Java value's C type: a reference a pointer, a jboolean a byte)
	static function jniC(d:String):CTy
		return switch d.charAt(0) {
			case "Z": CU8;
			case "B": CI8;
			case "C": CU16;
			case "S": CI16;
			case "I": CI32;
			case "J": CI64;
			case "F": CF32;
			case "D": CF64;
			case "V": CVoid;
			case _: CPtr;
		}

	// a method (kind 0, its object first; 1, static: `new` a constructor) or a field's read (2, its object first; 3, static)
	function jniMember(cls:Int, className:String, name:String, fn:Node, kind:Int):FuncInfo {
		var s = signature(name, fn, "jni");
		var kinds = s.kinds.map(k -> k == "cstring" ? "jstring" : k);
		var ret = s.ret == "cstring" ? "jstring" : s.ret;
		var self = kind == 0 || kind == 2;
		if (self && (kinds.length == 0 || descriptor(kinds[0], fn).charAt(0) != "L"))
			fail(fn, 'native.jni: $name takes its object first (o: Java<"$className">)');
		var args = self ? kinds.slice(1) : kinds;
		if (kind >= 2 && args.length > 0) fail(fn, 'native.jni: a field\'s read takes ${self ? "its object only" : "nothing"}');
		if (args.length > 16) fail(fn, 'native.jni: $name takes more than 16 arguments');
		var ctor = kind == 1 && name == "new";
		var d = kind >= 2 ? descriptor(ret, fn) : "(" + [for (k in args) descriptor(k, fn)].join("") + ")" + (ctor ? "V" : descriptor(ret, fn));
		if (ctor && descriptor(ret, fn).charAt(0) != "L") fail(fn, 'native.jni: new returns the object (Java<"$className">)');
		var id = global("jni_member");
		return wrap(name, s.params, kinds, ret, fn, (xs, raw) -> {
			var c = b.temp(EGlobal(cls, TF64));
			var member = read(id, () -> call(script("jniMember"), [c, EStr(ctor ? "<init>" : name), EStr(d), EInt(kind)]));
			var env = b.temp(call(script("jniEnv"), []));
			var target = self ? xs[0] : EConv(F2L, c);
			var at = 0;
			for (i in (self ? 1 : 0)...kinds.length) {
				var k = kinds[i];
				var code = switch descriptor(k, fn).charAt(0) {
					case "F": 1;
					case "D": 2;
					case "Z": 3;
					case _: 0;
				}
				// (a number as it is, a reference's or a string's address, a boolean 0 or 1)
				var value:Ex = rep(k) == TF64 ? raw[i] : EConv(L2F, xs[i]);
				if (k == "bool") {
					var l = b.local("jboolean", TF64);
					b.out.push(SIf(raw[i], b.block(() -> b.out.push(SSet(l, EF64(1)))), b.block(() -> b.out.push(SSet(l, EF64(0))))));
					value = ELocal(l);
				}
				call(script("jniArg"), [EInt(at++), EInt(code), value]);
			}
			var table = b.temp(call(script("word"), [env, EInt(0)]));
			var rd = ctor ? "L" : descriptor(ret, fn);
			var slot = ctor ? 30 : jniSlot(kind, rd);
			var fnp = b.temp(EConv(F2L, call(script("word"), [table, EInt(slot)])));
			var cargs = kind >= 2 ? [CPtr, CPtr, CPtr] : [CPtr, CPtr, CPtr, CPtr];
			var xargs:Array<Ex> = [b.temp(EConv(F2L, env)), b.temp(target), b.temp(EConv(F2L, member))];
			if (kind < 2) xargs.push(b.temp(EConv(F2L, call(script("jniArgs"), []))));
			var cr = jniC(rd);
			var r:Null<Ex> = null;
			var callEx = indirect(fnp, cargs, cr, xargs);
			if (cr == CVoid) b.out.push(SExpr(callEx)) else r = b.temp(callEx);
			call(script("jniCheck"), []);
			return r;
		});
	}
}
