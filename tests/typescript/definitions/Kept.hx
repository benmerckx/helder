import helder.dev.Keep;

// keep(key, () -> initial) in Haxe: kept.ts prints the same.
class Kept {
	static function main() {
		var state = keep("state", () -> {count: 0, label: "ticks"});
		state.count += 2;
		Sys.println('${state.label} ${state.count}');
		var steps = keep("steps", () -> [1, 2, 3]);
		steps.push(4);
		Sys.println(steps.join(","));
		Sys.println('made ${made()} ${made()}');
	}

	static function made():Int
		return keep("made", () -> 40) + 2;
}
