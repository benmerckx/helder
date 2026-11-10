package helder.compiler;

// The packages Haxe's null safety checks in every build of helder's
// compiler (Compiler.nullSafety) and of its CLI (src/helder/cli/run.mjs
// reads this list): Strict where each one passed it, Loose where Strict
// asked too much (README: Null safety)
class NullSafety {
	public static final packages:Map<String, String> = [
		"helder.asset" => "Strict",
		"helder.compiler" => "Strict",
		"helder.definition" => "Strict",
		"helder.dev" => "Strict",
		"helder.devtools" => "Strict",
		"helder.jobs" => "Strict",
		"helder.native" => "Strict",
		"helder.physics" => "Strict",
		"helder.sprite" => "Strict",
		"helder.story" => "Strict",
		"helder.web" => "Strict"
	];
}
