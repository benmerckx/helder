package hxmc.os.objc;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

// The build macro of Msg: each function declared without a body is a shape
// of objc_msgSend (the receiver, the selector, the method's arguments and
// result in C types), turned into a C call through objc_msgSend's address
// (c_<name>, @:hxmc.indirect: in a safe region, since Cocoa calls back into
// Haxe from inside many messages) and an inline wrapper of the declared name.
// Any class can take it: Msg has AppKit's shapes, hxmc.gfx.metal.MtlMsg Metal's.
class Sender {
	public static function build():Array<Field> {
		var out:Array<Field> = [];
		var ptr = macro :hxmc.unsafe.Ptr;
		for (f in Context.getBuildFields())
			switch f.kind {
				case FFun(fn) if (fn.expr == null):
					var raw = "c_" + f.name;
					out.push({
						name: raw,
						access: [AStatic, AExtern],
						meta: [{name: ":hxmc.indirect", pos: f.pos}],
						kind: FFun({args: [{name: "fn", type: ptr}].concat(fn.args), ret: fn.ret, expr: null}),
						pos: f.pos
					});
					var args = [macro hxmc.os.objc.Msg.send].concat([for (a in fn.args) macro $i{a.name}]);
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
#end
