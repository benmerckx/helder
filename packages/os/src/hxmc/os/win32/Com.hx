package hxmc.os.win32;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

// The build macro of COM interfaces (hxmc.os.audio.Wasapi; hxmc.gfx's
// Direct3D 11 has its own copy): each function declared without a body and
// with @:slot(n) is the method at index n of the interface's vtable (the
// order of the official headers' C vtables, the base interfaces' methods
// first), its first argument the object. It becomes a C call through that
// slot (c_<name>, @:hxmc.indirect: in a safe region, since methods may
// block) and an inline wrapper of the declared name that reads the slot
// from the object's vtable.
class Com {
	public static function build():Array<Field> {
		var out:Array<Field> = [];
		var ptr = macro :hxmc.unsafe.Ptr;
		for (f in Context.getBuildFields())
			switch f.kind {
				case FFun(fn) if (fn.expr == null):
					var slot = Lambda.find(f.meta, m -> m.name == ":slot");
					if (slot == null) Context.error("a COM method needs @:slot(index)", f.pos);
					var raw = "c_" + f.name;
					out.push({
						name: raw,
						access: [AStatic, AExtern],
						meta: [{name: ":hxmc.indirect", pos: f.pos}],
						kind: FFun({args: [{name: "fn", type: ptr}].concat(fn.args), ret: fn.ret, expr: null}),
						pos: f.pos
					});
					var self = fn.args[0].name;
					var args = [macro hxmc.os.win32.Com.method($i{self}, ${slot.params[0]})].concat([for (a in fn.args) macro $i{a.name}]);
					out.push({
						name: f.name,
						access: [APublic, AStatic, AInline],
						kind: FFun({args: fn.args, ret: fn.ret, expr: macro return $i{raw}($a{args})}),
						pos: f.pos
					});
				case _:
					out.push(f);
			}
		return out;
	}
}
#else
import hxmc.unsafe.*;

class Com {
	// the method at a slot of a COM object's vtable
	public static inline function method(self:Ptr, slot:Int):Ptr {
		var vtable:Ptr<Ptr> = (self : Ptr<Ptr>).value;
		return vtable[slot];
	}

	// IUnknown::Release, when there is an object
	public static inline function release(o:Ptr)
		if (!o.isNull()) IUnknown.Release(o);

	// a GUID in native memory, kept for the process, as the headers write it
	public static function guid(d1:Int, d2:Int, d3:Int, d4:Array<Int>):Ptr {
		var p:Ptr<UInt8> = LibC.malloc(16), d:Ptr<Int32> = p.raw(), w:Ptr<UInt16> = p.raw();
		d.value = d1;
		w[2] = d2;
		w[3] = d3;
		for (i in 0...8)
			p[8 + i] = d4[i];
		return p;
	}
}

@:build(hxmc.os.win32.Com.build())
class IUnknown {
	@:slot(0) static function QueryInterface(self:Ptr, iid:Ptr, out:Ptr<Ptr>):Int;
	@:slot(1) static function AddRef(self:Ptr):Int;
	@:slot(2) static function Release(self:Ptr):Int;
}
#end
