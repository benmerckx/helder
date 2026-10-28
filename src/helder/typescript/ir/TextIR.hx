package helder.typescript.ir;

import hxmc.ir.Ir;
import haxe.ds.Vector;

// The text form is JSON with named IR constructors and symbolic references.
// Runtime functions/classes are external declarations in the supplied linked program.
// Parsing replaces only experiment-owned function bodies; it never deserializes code.
class TextIR {
	static function encode(x:Dynamic):Dynamic {
		if (Std.isOfType(x, String)) {
			var value:String = x, at = 0, unpaired = false;
			while (at < value.length) {
				var unit = value.charCodeAt(at++);
				if (unit >= 0xd800 && unit <= 0xdbff) {
					if (at < value.length && value.charCodeAt(at) >= 0xdc00 && value.charCodeAt(at) <= 0xdfff) at++; else unpaired = true;
				} else if (unit >= 0xdc00 && unit <= 0xdfff) unpaired = true;
			}
			if (unpaired || value.length > 0 && value.charCodeAt(0) == 65279) return {utf16: [for (i in 0...value.length) value.charCodeAt(i)]};
		}
		if (x != null && Std.isOfType(x, Float)) {
			var n:Float = x;
			if (Math.isNaN(n)) return {number: "NaN"};
			if (n == Math.POSITIVE_INFINITY) return {number: "Infinity"};
			if (n == Math.NEGATIVE_INFINITY) return {number: "-Infinity"};
			if (n == 0 && 1 / n < 0) return {number: "-0"};
		}
		if (x == null || Std.isOfType(x, String) || Std.isOfType(x, Int) || Std.isOfType(x, Float) || Std.isOfType(x, Bool)) return x;
		if (Std.isOfType(x, FuncInfo)) return {fn: (x : FuncInfo).name};
		if (Std.isOfType(x, Local)) return {local: (x : Local).id};
		if (Std.isOfType(x, ClassInfo)) return {cls: (x : ClassInfo).name};
		if (Std.isOfType(x, ShapeInfo)) return {shape: (x : ShapeInfo).id};
		if (Std.isOfType(x, SigInfo)) return {sig: (x : SigInfo).id};
		if (Std.isOfType(x, LambdaInfo)) return {lambda: (x : LambdaInfo).id};
		if (Std.isOfType(x, Array)) return [for (v in (x : Array<Dynamic>)) encode(v)];
		if (Std.isOfType(x, hxmc.NativeArray)) {
			var v:Vector<Dynamic> = cast x;
			return {vector: [for (e in v) encode(e)]};
		}
		return switch (Type.typeof(x)) {
			case TEnum(e): {enumType: Type.getEnumName(e), op: Type.enumConstructor(x), args: [for (v in Type.enumParameters(x)) encode(v)]};
			case TObject:
				var record:Dynamic = {};
				for (k in Reflect.fields(x)) Reflect.setField(record, k, encode(Reflect.field(x, k))); {record: record};
			case _: throw "TSHXIR001: unsupported text value " + Type.typeof(x);
		};
	}

	public static function dump(p:Program):String {
		var fs = [];
		for (f in p.funcs) if (f.module == "helder.typescript.program") fs.push({name: f.name, ret: encode(f.ret), args: [for (a in f.args) {id: a.id, name: a.name, ty: encode(a.ty)}], locals: [for (a in f.locals) {id: a.id, name: a.name, ty: encode(a.ty)}], body: encode(f.body)});
		return haxe.Json.stringify({format: "helder-ts-ir-1", functions: fs}, null, "  ") + "\n";
	}

	static function decode(x:Dynamic, p:Program, locals:Map<Int, Local>):Dynamic {
		if (x == null || Std.isOfType(x, String) || Std.isOfType(x, Int) || Std.isOfType(x, Float) || Std.isOfType(x, Bool)) return x;
		if (Std.isOfType(x, Array)) return [for (v in (x : Array<Dynamic>)) decode(v, p, locals)];
		if (Reflect.hasField(x, "utf16")) {
			var units:Array<Int> = x.utf16;
			var buffer = new StringBuf();
			for (unit in units) {
				if (unit < 0 || unit > 65535) throw "TSHXIR002: invalid UTF-16 unit";
				buffer.addChar(unit);
			}
			return buffer.toString();
		}
		if (Reflect.hasField(x, "number")) return switch ((x.number : String)) {
			case "NaN": Math.NaN;
			case "Infinity": Math.POSITIVE_INFINITY;
			case "-Infinity": Math.NEGATIVE_INFINITY;
			case "-0": -0.0;
			case _: throw "TSHXIR002: invalid floating literal";
		};
		if (Reflect.hasField(x, "record")) {
			var record:Dynamic = {};
			for (k in Reflect.fields(x.record)) Reflect.setField(record, k, decode(Reflect.field(x.record, k), p, locals));
			return record;
		}
		if (Reflect.hasField(x, "fn")) {
			for (f in p.funcs) if (f.name == x.fn) return f;
			throw "TSHXIR002: unknown function " + x.fn;
		}
		if (Reflect.hasField(x, "local")) {
			if (!locals.exists(x.local)) throw "TSHXIR002: unknown local";
			return locals.get(x.local);
		}
		if (Reflect.hasField(x, "cls")) {
			for (c in p.classes) if (c.name == x.cls) return c;
			throw "TSHXIR002: unknown class";
		}
		if (Reflect.hasField(x, "shape")) return p.shapes[x.shape];
		if (Reflect.hasField(x, "sig")) return p.sigs[x.sig];
		if (Reflect.hasField(x, "lambda")) return p.lambdas[x.lambda];
		if (Reflect.hasField(x, "vector")) return Vector.fromArrayCopy([for (v in (x.vector : Array<Dynamic>)) decode(v, p, locals)]);
		var allowed = ["hxmc.ir.Ty", "hxmc.ir.RefTy", "hxmc.ir.Ex", "hxmc.ir.Stmt", "hxmc.ir.BinOp", "hxmc.ir.ConvOp", "hxmc.ir.TypeRef"];
		if (allowed.indexOf(x.enumType) < 0) throw "TSHXIR002: invalid enum type " + x.enumType;
		var e = Type.resolveEnum(x.enumType);
		if (e == null) throw "TSHXIR002: unresolved enum " + x.enumType;
		return Type.createEnum(e, x.op, [for (v in (x.args : Array<Dynamic>)) decode(v, p, locals)]);
	}

	public static function parse(p:Program, s:String) {
		var data:Dynamic = haxe.Json.parse(s);
		if (data.format != "helder-ts-ir-1") throw "TSHXIR002: unknown IR version";
		for (def in (data.functions : Array<Dynamic>)) {
			var f:FuncInfo = null;
			for (fn in p.funcs) if (fn.name == def.name && fn.module == "helder.typescript.program") f = fn;
			if (f == null) throw "TSHXIR002: unknown experiment function " + def.name;
			if (haxe.Json.stringify(def.ret) != haxe.Json.stringify(encode(f.ret))) throw "TSHXIR002: signature mismatch";
			var locals:Map<Int, Local> = [];
			for (l in f.args.concat(f.locals)) locals.set(l.id, l);
			f.body = decode(def.body, p, locals);
		}
	}
}
