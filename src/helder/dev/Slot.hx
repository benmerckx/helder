package helder.dev;

// keep(key, () => initial) as TypeScript programs import it (helder/dev:
// helder.dev.TypeScript): a definition, its calls compiled by
// helder.typescript.lower's Definitions (KeepDefinition, as Haxe's
// helder.dev.Keep): under -D hxmc.dev the value the last build kept under
// the key, unless the initial value's source changed, saved on each
// snapshot (a program's data: numbers, strings, booleans, null, arrays and
// plain objects of them, as its signals'); else init().
class Slot {
	// a value kept across a reload under `helder dev`: the key a string
	// literal, the initial value made by a function of no arguments
	public static function keep<T>(key:String, init:() -> T):T
		return init();
}
