package hxmc.dev;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

// (-D hxmc.dev-host) A class whose static variables are what a dev host
// keeps across builds (Android's activity glue: hxmc.os.android.Activity,
// AndroidWindow): each static variable of a plain type (Ptr, Int, Int64,
// Bool), not inline, becomes a property stored in the host's state block
// (hxmc.dev.Hosted) at its slot, from base on, so that every build loaded
// into the process reads and writes the same ones: the first build's
// callbacks (the activity's, on the UI thread) and the running build's
// program thread. Their initial values must be zero (the block starts
// zeroed). Plain memory: usable before the runtime starts and without the
// collector (@:hxmc.noGc code).
class HostedMacro {
	public static function shared(base:Int, count:Int):Array<Field> {
		var fields = Context.getBuildFields();
		var out:Array<Field> = [];
		var slot = base;
		for (f in fields) {
			var plain = switch f.kind {
				case FVar(TPath({name: n, pack: _, params: []}), _) if (["Ptr", "Int", "Int64", "Bool"].indexOf(n) >= 0):
					f.access.indexOf(AStatic) >= 0 && f.access.indexOf(AInline) < 0 && f.access.indexOf(AFinal) < 0;
				case _: false;
			}
			if (!plain) {
				out.push(f);
				continue;
			}
			var t:ComplexType, init:Null<Expr>;
			switch f.kind {
				case FVar(ct, e):
					t = ct;
					init = e;
				case _:
					throw "unreachable";
			}
			if (init != null) switch init.expr {
				case EConst(CInt("0")) | EConst(CIdent("false")) | ECall({expr: EField(_, "nil")}, []):
				case _:
					Context.error("hxmc.dev: a static kept by the dev host starts at zero, not " + haxe.macro.ExprTools.toString(init), init.pos);
			}
			if (slot >= base + count) Context.error("hxmc.dev: more than " + count + " statics kept by the dev host", f.pos);
			var off = slot * 8;
			slot++;
			var name = switch t {
				case TPath(p): p.name;
				case _: "";
			}
			var get:Expr, set:Expr;
			var at = macro hxmc.dev.Hosted.block();
			switch name {
				case "Ptr":
					get = macro hxmc.unsafe.Mem.getPtr($at, $v{off});
					set = macro hxmc.unsafe.Mem.setPtr($at, $v{off}, v);
				case "Int":
					get = macro hxmc.unsafe.Mem.getI32($at, $v{off});
					set = macro hxmc.unsafe.Mem.setI32($at, $v{off}, v);
				case "Int64":
					get = macro hxmc.unsafe.Mem.getI64($at, $v{off});
					set = macro hxmc.unsafe.Mem.setI64($at, $v{off}, v);
				case _: // Bool
					get = macro hxmc.unsafe.Mem.getI32($at, $v{off}) != 0;
					set = macro hxmc.unsafe.Mem.setI32($at, $v{off}, v ? 1 : 0);
			}
			var access = [for (a in f.access) a];
			out.push({name: f.name, access: access, kind: FProp("get", "set", t, null), pos: f.pos, meta: f.meta, doc: f.doc});
			var noGc = [{name: ":hxmc.noGc", pos: f.pos}];
			out.push({
				name: "get_" + f.name,
				access: [AStatic, AInline],
				kind: FFun({args: [], ret: t, expr: macro return $get}),
				pos: f.pos,
				meta: noGc
			});
			out.push({
				name: "set_" + f.name,
				access: [AStatic, AInline],
				kind: FFun({args: [{name: "v", type: t}], ret: t, expr: macro {
					$set;
					return v;
				}}),
				pos: f.pos,
				meta: noGc
			});
		}
		return out;
	}
}
#end
