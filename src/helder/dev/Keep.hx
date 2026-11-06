package helder.dev;

import haxe.macro.Expr;
#if macro
import haxe.macro.Context;
import helder.definition.HaxeAdapter;
import helder.definition.Kernel;
#end

// keep(key, () -> initial): a value kept as it is across a reload under
// `helder dev` (fast refresh), a definition (src/helder/compiler/DESIGN.md
// 4; its handler KeepDefinition, TypeScript's helder/dev the same):
//
//   import helder.dev.Keep;
//   var clock = keep("clock", () -> new FixedStep(1 / 60));
//
// The key is a string literal, relative to Hot's scope (a component's
// instance: Hot.scope), the initial value made by a function of no
// arguments. Under -D hxmc.dev: the value the last build kept under the key
// when its type (HotMacro.hash) and the initial value's source are the same
// (an edit to it starts afresh, said so, as a signal's: helder.view.Refresh),
// else init(); saved on each snapshot. Without it: init() alone.
@:definition macro function keep(key:Expr, init:Expr):Expr {
	var a = new HaxeAdapter("keep");
	var slot = new KeepDefinition().generate(new KNode(KArray([a.node(key), a.node(init)]), Context.currentPos()), a);
	if (!Context.defined("hxmc.dev")) return body(init);
	var t = switch Context.follow(Context.typeof(init)) {
		case TFun(_, ret): ret;
		case t: a.error("the initial value is made by a function of no arguments (() => value), not " + haxe.macro.TypeTools.toString(t), init.pos);
	}
	var source = haxe.crypto.Md5.encode(haxe.macro.ExprTools.toString(init)).substr(0, 8);
	return macro @:pos(Context.currentPos()) helder.dev.Hot.keepValue($v{slot.key}, $v{HotMacro.hash(t)}, $v{source}, $init);
}

#if macro
// (f's body: f is a function literal of no arguments)
private function body(f:Expr):Expr {
	return switch f.expr {
		case EFunction(_, {args: [], expr: e}) if (e != null):
			switch e.expr {
				case EMeta({name: ":implicitReturn"}, {expr: EReturn(r)}) | EReturn(r) if (r != null): r;
				case _: macro $f();
			}
		case EParenthesis(x) | EMeta(_, x): body(x);
		case _: macro $f();
	}
}
#end
