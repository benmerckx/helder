package hxmc.os;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

// The build macro of a library loaded at run time (dlopen: the program
// starts without it; hxmc.os.audio.Alsa): each function declared without a
// body becomes a pointer slot (p_<name>), a C call through it
// (@:hxmc.indirect, in a safe region: such calls may block) and an inline
// wrapper of the declared name; load(path) opens the library and fills the
// slots (dlsym), returning null or what failed.
class Dl {
	public static function build():Array<Field> {
		var out:Array<Field> = [];
		var loads:Array<Expr> = [];
		var ptr = macro :hxmc.unsafe.Ptr;
		for (f in Context.getBuildFields())
			switch f.kind {
				case FFun(fn) if (fn.expr == null):
					var name = f.name, slot = "p_" + f.name, raw = "c_" + f.name;
					out.push({name: slot, access: [AStatic], kind: FVar(ptr, macro hxmc.unsafe.Ptr.nil()), pos: f.pos});
					out.push({
						name: raw,
						access: [AStatic, AExtern],
						meta: [{name: ":hxmc.indirect", pos: f.pos}],
						kind: FFun({args: [{name: "fn", type: ptr}].concat(fn.args), ret: fn.ret, expr: null}),
						pos: f.pos
					});
					var args = [macro $i{slot}].concat([for (a in fn.args) macro $i{a.name}]);
					out.push({
						name: name,
						access: [APublic, AStatic, AInline],
						kind: FFun({args: fn.args, ret: fn.ret, expr: macro return $i{raw}($a{args})}),
						pos: f.pos
					});
					loads.push(macro {
						$i{slot} = hxmc.unsafe.Posix.dlsym(lib, hxmc.unsafe.Mem.cstr($v{name}));
						if ($i{slot}.isNull()) return path + " has no " + $v{name};
					});
				case _:
					out.push(f);
			}
		loads.unshift(macro if (lib.isNull()) return "cannot load " + path);
		loads.unshift(macro var lib = hxmc.unsafe.Arena.scopedValue(a -> hxmc.unsafe.Posix.dlopen(a.cstring(path), 2))); // (RTLD_NOW)
		loads.push(macro return null);
		out.push({
			name: "load",
			access: [APublic, AStatic],
			kind: FFun({args: [{name: "path", type: macro :String}], ret: macro :Null<String>, expr: macro $b{loads}}),
			pos: Context.currentPos()
		});
		return out;
	}
}
#end
