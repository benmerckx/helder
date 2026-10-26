package hxmc.scoped;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.Tools;
#end

// Value structs: small structs computed with, in locals rather than memory
// (Goose's structs by value). A class whose fields this build macro makes
// final, with an inline constructor taking them in order:
//
//   @:build(hxmc.scoped.Value.build())
//   class Vec2 {
//     var x:Float;
//     var y:Float;
//     public inline function add(o:Vec2) return new Vec2(x + o.x, y + o.y);
//   }
//
// Haxe's inline constructors turn a value that does not escape (stored in a
// field, an array, a closure, Dynamic) into its fields' locals, on every
// target: `a.add(b).scale(2)` allocates nothing. One that escapes is an
// ordinary object, with the same meaning: values cannot be changed, so a
// copy and the original never differ.
//
// A Struct.build field, a Slice or a Grow of a value type holds its fields
// in place: reading one is a load of each field into a new value, writing
// one a store of each (`Vec2.load(a)`, `Vec2.store(a, v)`). Fields: Int,
// Float, Bool, U8 or another value type. `Vec2.SIZE`, `Vec2.ALIGN`: its
// layout in memory, as Struct's.
class Value {
	#if macro
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var pos = Context.currentPos();
		var cls = Context.getLocalClass().get();
		var self:ComplexType = TPath({pack: cls.pack, name: cls.module.split(".").pop(), sub: cls.name});
		var out:Array<Field> = [];
		var args:Array<FunctionArg> = [], assigns:Array<Expr> = [], loads:Array<Expr> = [], stores:Array<Expr> = [];
		var offset = 0, align = 1;
		for (f in fields) {
			switch f.kind {
				case FVar(t, null) if (t != null && !f.access.contains(AStatic)):
					var k = Struct.kindOf(t, f.pos, true);
					// (an F32 field holds a Float: stored rounded to f32)
					if (k.scalar == "F32")
						t = macro :Float;
					offset = (offset + k.align - 1) & ~(k.align - 1);
					if (k.align > align)
						align = k.align;
					var at = macro a + $v{offset};
					var name = f.name;
					out.push({
						name: name,
						doc: f.doc,
						meta: f.meta,
						access: [APublic, AFinal],
						kind: FVar(t, null),
						pos: f.pos
					});
					args.push({name: name, type: t});
					assigns.push(macro this.$name = $i{name});
					switch k.scalar {
						case "I32":
							loads.push(macro hxmc.scoped.Memory.getI32($at));
							stores.push(macro hxmc.scoped.Memory.setI32($at, v.$name));
						case "F64":
							loads.push(macro hxmc.scoped.Memory.getF64($at));
							stores.push(macro hxmc.scoped.Memory.setF64($at, v.$name));
						case "Bool":
							loads.push(macro hxmc.scoped.Memory.getU8($at) != 0);
							stores.push(macro hxmc.scoped.Memory.setU8($at, v.$name ? 1 : 0));
						case "U8":
							loads.push(macro hxmc.scoped.Memory.getU8($at));
							stores.push(macro hxmc.scoped.Memory.setU8($at, v.$name));
						case "F32":
							loads.push(macro hxmc.scoped.Memory.getF32($at));
							stores.push(macro hxmc.scoped.Memory.setF32($at, v.$name));
						default:
							var p = k.value;
							loads.push(macro $p{p}.load($at));
							stores.push(macro $p{p}.store($at, v.$name));
					}
					offset += k.size;
				case FVar(_, _) if (!f.access.contains(AStatic)):
					Context.error("Value.build: " + f.name + " needs a type and no initializer", f.pos);
				default:
					out.push(f);
			}
		}
		var size = (offset + align - 1) & ~(align - 1);
		if (size == 0)
			size = align;
		cls.meta.add(":valueLayout", [macro $v{size}, macro $v{align}], pos);
		out.push({
			name: "new",
			access: [APublic, AInline],
			kind: FFun({args: args, ret: null, expr: macro $b{assigns}}),
			pos: pos
		});
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
			name: "load",
			access: [APublic, AStatic, AInline],
			kind: FFun({args: [{name: "a", type: macro :Int}], ret: self, expr: macro return ${{expr: ENew({pack: cls.pack, name: cls.module.split(".").pop(), sub: cls.name}, loads), pos: pos}}}),
			pos: pos
		});
		out.push({
			name: "store",
			access: [APublic, AStatic, AInline],
			kind: FFun({args: [{name: "a", type: macro :Int}, {name: "v", type: self}], ret: macro :Void, expr: macro $b{stores}}),
			pos: pos
		});
		return out;
	}
	#end
}
