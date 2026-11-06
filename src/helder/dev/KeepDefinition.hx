package helder.dev;

import helder.definition.Kernel;

// keep(key, () -> initial)'s handler (src/helder/compiler/DESIGN.md 4), the
// same for both languages (Haxe's helder.dev.Keep, TypeScript's helder/dev):
// its arguments, a key literal and a function of no arguments making the
// initial value, checked at their positions. What each adapter generates of
// it is a dev-reload slot: under -D hxmc.dev the value the last build kept
// under the key (in Hot's scope), unless the type or the initial value's
// source changed, else init(); saved on each snapshot. Without -D hxmc.dev,
// init() alone.
class KeepDefinition implements Definition<Adapter, KeepSlot> {
	public final name = "keep";

	public function new() {}

	// (the arguments as one array: the key, the initial value's function)
	public function generate(arg:KNode, a:Adapter):KeepSlot {
		var args = switch arg.value {
			case KArray(xs): xs;
			case _: a.error("takes a key and a function making the initial value", arg.pos);
		}
		if (args.length != 2) a.error("takes a key and a function making the initial value, keep(\"key\", () => initial)", arg.pos);
		var key = switch args[0].value {
			case KString(s) if (s != ""): s;
			case KString(_): a.error("the key is empty", args[0].pos);
			case _: a.error('the key is a string literal, not ${args[0].describe()}', args[0].pos);
		}
		var init = switch args[1].value {
			case KFunction(f) if (f.params.length == 0): f;
			case KFunction(f): a.error('the initial value is made by a function of no arguments (() => value), not of ${f.params.length}', args[1].pos);
			case _: a.error('the initial value is made by a function of no arguments (() => value), not ${args[1].describe()}', args[1].pos);
		}
		return {key: key, init: init};
	}
}

typedef KeepSlot = {
	key:String,
	init:KFunction
}
