package helder.os;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

// The build macro of function tables reached through an object whose first
// word points at them: COM's interfaces (helder.os.win32.Com: WASAPI, Direct3D
// 11, UI Automation) and JNI's JNIEnv and JavaVM (helder.os.android.Jni). Each
// function declared without a body and with @:slot(n) is the entry at index
// n of the table (the order of the official headers' C structs), its first
// argument the object. It becomes a C call through that slot (c_<name>,
// @:hxmc.indirect: in a safe region, since methods may block or call back)
// and an inline wrapper of the declared name that reads the slot from the
// object's table.
class VTable {
	public static function build():Array<Field> {
		var out:Array<Field> = [];
		var ptr = macro :hxmc.unsafe.Ptr;
		for (f in Context.getBuildFields())
			switch f.kind {
				case FFun(fn) if (fn.expr == null):
					var slot = Lambda.find(f.meta, m -> m.name == ":slot");
					if (slot == null) Context.error("a table's function needs @:slot(index)", f.pos);
					var raw = "c_" + f.name;
					out.push({
						name: raw,
						access: [AStatic, AExtern],
						meta: [{name: ":hxmc.indirect", pos: f.pos}],
						kind: FFun({args: [{name: "fn", type: ptr}].concat(fn.args), ret: fn.ret, expr: null}),
						pos: f.pos
					});
					var self = fn.args[0].name;
					var args = [macro helder.os.VTable.method($i{self}, ${slot.params[0]})].concat([for (a in fn.args) macro $i{a.name}]);
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

class VTable {
	// the function at a slot of an object's table
	public static inline function method(self:Ptr, slot:Int):Ptr {
		var vtable:Ptr<Ptr> = (self : Ptr<Ptr>).value;
		return vtable[slot];
	}
}
#end
