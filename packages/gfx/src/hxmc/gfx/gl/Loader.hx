package hxmc.gfx.gl;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

// The build macro of GL: each function declared without a body becomes a
// pointer slot (p_<name>), a C call through it (@:hxmc.indirect, @:hxmc.fast
// unless the declaration says @:wait: calls that block) and an inline
// wrapper of the declared name; load(get) fills the slots from a
// GetProcAddress (eglGetProcAddress, wglGetProcAddress later), whose
// argument is the name as a C string. On WebAssembly (-D
// hxmc.target=wasm32-wasi) each one is instead an import of that name from
// the module "hxmc_gl", WebGL2 through packages/gfx/imports.mjs, and load
// has nothing to fill.
class Loader {
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var out:Array<Field> = [];
		var loads:Array<Expr> = [];
		var pos = Context.currentPos();
		var ptr = macro :hxmc.unsafe.Ptr;
		var wasm = Context.definedValue("hxmc.target") == "wasm32-wasi";
		for (f in fields)
			switch f.kind {
				case FFun(fn) if (fn.expr == null && wasm):
					// (a browser blocks no thread: no @:wait there)
					var meta = [
						{name: ":hxmc.c", params: [macro $v{f.name}], pos: f.pos},
						{name: ":hxmc.lib", params: [macro "hxmc_gl"], pos: f.pos},
						{name: ":hxmc.fast", pos: f.pos}
					];
					out.push({name: f.name, access: [APublic, AStatic, AExtern], meta: meta, kind: FFun(fn), pos: f.pos});
				case FFun(fn) if (fn.expr == null):
					var name = f.name, slot = "p_" + f.name, raw = "c_" + f.name;
					var wait = Lambda.exists(f.meta, m -> m.name == ":wait");
					out.push({name: slot, access: [AStatic], kind: FVar(ptr, macro hxmc.unsafe.Ptr.nil()), pos: f.pos});
					var meta = [{name: ":hxmc.indirect", pos: f.pos}];
					if (!wait) meta.push({name: ":hxmc.fast", pos: f.pos});
					out.push({
						name: raw,
						access: [AStatic, AExtern],
						meta: meta,
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
						$i{slot} = get(hxmc.unsafe.Mem.cstr($v{name}));
						if ($i{slot}.isNull()) return $v{name};
					});
				case _:
					out.push(f);
			}
		loads.push(macro return null);
		out.push({
			name: "load",
			access: [APublic, AStatic],
			kind: FFun({args: [{name: "get", type: macro :hxmc.unsafe.Ptr->hxmc.unsafe.Ptr}], ret: macro :Null<String>, expr: macro $b{loads}}),
			pos: pos,
			doc: "fills the function pointers: null, or the first name `get` did not find"
		});
		return out;
	}
}
#end
