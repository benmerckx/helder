package helder.scoped;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.Tools;
using Lambda;
#end

// Struct types in scoped memory: an abstract over Addr with plain fields,
// laid out by this build macro.
//
//   @:build(helder.scoped.Struct.build())
//   abstract Particle(helder.scoped.Addr) {
//     var pos:Vec2;     // a value (Value.build) or another struct: in place
//     var speed:Float;  // Int, Float, Bool, U8
//     var alive:Bool;
//   }
//
// Each field becomes a property reading and writing the struct's memory (a
// value field reads as a value and writes each of its fields; a struct field
// reads as the inner struct in place; writing one copies it).
// `new Particle()` is a zeroed one in the current scope; `Particle.SIZE` and
// `Particle.ALIGN` its layout (natural alignment, fields in their order);
// `p.copyFrom(q)` copies q's bytes.
class Struct {
	#if macro
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var pos = Context.currentPos();
		var abs:AbstractType = switch Context.getLocalType() {
			case TAbstract(_.get() => a, _): a;
			case TInst(_.get() => {kind: KAbstractImpl(a)}, _): a.get();
			default: Context.error("Struct.build: on an abstract over helder.scoped.Addr", pos);
		}
		var self:ComplexType = TPath({pack: abs.pack, name: abs.module.split(".").pop(), sub: abs.name});
		var out:Array<Field> = [];
		var offset = 0, align = 1;
		for (f in fields) {
			switch f.kind {
				case FVar(t, null) if (t != null && !f.access.contains(AStatic)):
					var k = kindOf(t, f.pos);
					offset = (offset + k.align - 1) & ~(k.align - 1);
					if (k.align > align)
						align = k.align;
					accessors(out, f, t, k, offset);
					offset += k.size;
				default:
					out.push(f);
			}
		}
		var size = (offset + align - 1) & ~(align - 1);
		if (size == 0)
			size = align;
		// (the layout, for macros that need it before the statics are typed:
		// Elems, Struct.kindOf)
		abs.meta.add(":structLayout", [macro $v{size}, macro $v{align}], pos);
		out.push({
			name: "SIZE",
			access: [APublic, AStatic, AInline],
			kind: FVar(macro :Int, macro $v{size}),
			pos: pos
		});
		out.push({
			name: "ALIGN",
			access: [APublic, AStatic, AInline],
			kind: FVar(macro :Int, macro $v{align}),
			pos: pos
		});
		out.push({
			name: "new",
			access: [APublic, AInline],
			kind: FFun({args: [], ret: null, expr: macro this = helder.scoped.Memory.alloc($v{size})}),
			pos: pos
		});
		out.push({
			name: "copyFrom",
			access: [APublic, AInline],
			kind: FFun({args: [{name: "o", type: self}], ret: macro :Void, expr: macro helder.scoped.Memory.copy(this, (cast o : Int), $v{size})}),
			pos: pos
		});
		return out;
	}

	// (values: a Value.build class's fields, which hold no Struct)
	@:noCompletion public static function kindOf(t:ComplexType, pos:Position, values = false):{size:Int, align:Int, ?scalar:String, ?struct:ComplexType, ?value:Array<String>} {
		var type = try Context.resolveType(t, pos) catch (e:Dynamic) Context.error("Struct.build: unknown type " + t.toString(), pos);
		switch type.follow() {
			case TAbstract(_.get() => {pack: [], name: "Int"}, _):
				return {size: 4, align: 4, scalar: "I32"};
			case TAbstract(_.get() => {pack: [], name: "Float"}, _):
				return {size: 8, align: 8, scalar: "F64"};
			case TAbstract(_.get() => {pack: [], name: "Bool"}, _):
				return {size: 1, align: 1, scalar: "Bool"};
			default:
		}
		switch type {
			case TAbstract(_.get() => {pack: ["helder", "scoped"], name: "U8"}, _):
				return {size: 1, align: 1, scalar: "U8"};
			case TAbstract(_.get() => {pack: ["helder", "scoped"], name: "F32"}, _):
				return {size: 4, align: 4, scalar: "F32"};
			case TInst(_.get() => c, _) if (c.meta.has(":valueLayout")):
				// (Value.build's layout, in metadata: its statics may not be typed yet)
				var l = c.meta.extract(":valueLayout")[0].params.map(e -> switch e.expr {
					case EConst(CInt(v)): Std.parseInt(v);
					default: 0;
				});
				return {size: l[0], align: l[1], value: c.pack.concat([c.module.split(".").pop(), c.name])};
			case TAbstract(_.get() => a, _) if (a.impl != null && !values):
				var size = staticInt(a, "SIZE"), al = staticInt(a, "ALIGN");
				if (size == null || al == null)
					Context.error("Struct.build: " + t.toString() + " is not a struct (Int, Float, Bool, U8 or a Struct.build abstract)", pos);
				return {size: size, align: al, struct: t};
			default:
				return Context.error("field type " + t.toString() + (values ? " (Int, Float, F32, Bool, U8 or a Value.build class)" : " (Int, Float, F32, Bool, U8, a Struct.build abstract or a Value.build class)"), pos);
		}
	}

	static function staticInt(a:AbstractType, name:String):Null<Int> {
		for (f in a.impl.get().statics.get())
			if (f.name == name)
				switch f.expr() {
					case {expr: TConst(TInt(v))}: return v;
					case {expr: TCast({expr: TConst(TInt(v))}, _)}: return v;
					default:
				}
		return null;
	}

	static function accessors(out:Array<Field>, f:Field, t:ComplexType, k:{size:Int, align:Int, ?scalar:String, ?struct:ComplexType, ?value:Array<String>}, off:Int) {
		var at = macro((this : Int) + $v{off});
		var get:Expr, set:Expr;
		switch k.scalar {
			case "I32":
				get = macro helder.scoped.Memory.getI32($at);
				set = macro helder.scoped.Memory.setI32($at, v);
			case "F64":
				get = macro helder.scoped.Memory.getF64($at);
				set = macro helder.scoped.Memory.setF64($at, v);
			case "Bool":
				get = macro helder.scoped.Memory.getU8($at) != 0;
				set = macro helder.scoped.Memory.setU8($at, v ? 1 : 0);
			case "U8":
				get = macro helder.scoped.Memory.getU8($at);
				set = macro helder.scoped.Memory.setU8($at, v);
			case "F32":
				// (read and written as a Float)
				t = macro :Float;
				get = macro helder.scoped.Memory.getF32($at);
				set = macro helder.scoped.Memory.setF32($at, v);
			case _ if (k.value != null):
				var p = k.value;
				get = macro $p{p}.load($at);
				set = macro $p{p}.store($at, v);
			default:
				get = macro cast $at;
				set = macro helder.scoped.Memory.copy($at, (cast v : Int), $v{k.size});
		}
		out.push({
			name: f.name,
			doc: f.doc,
			meta: f.meta,
			access: [APublic],
			kind: FProp("get", "set", t),
			pos: f.pos
		});
		out.push({
			name: "get_" + f.name,
			access: [AInline],
			kind: FFun({args: [], ret: t, expr: macro return $get}),
			pos: f.pos
		});
		out.push({
			name: "set_" + f.name,
			access: [AInline],
			kind: FFun({args: [{name: "v", type: t}], ret: t, expr: macro {$set; return v;}}),
			pos: f.pos
		});
	}
	#end
}
