package helder.compiler;

// A frontend of helder's compiler (helder.compiler.Compiler.plugins): what
// it adds to hxmc's compiler, at the compiler's three points.
interface Plugin {
	// The compiler's short form (`<compiler> <entry> ...`): the command line
	// for args whose entry is this frontend's, else null. Throws what is wrong
	// with them (reported, exit code 2).
	function direct(args:Array<String>):Null<Array<String>>;

	// Before Haxe types the program (hxmc's beforeTypingHook).
	function beforeTyping(com:context.Common.CommonContext, actx:compiler.ParsedArg.ArgContext):Void;

	// Whether this build is this frontend's: it generates it (also under
	// --no-output, so its errors are reported).
	function owns(com:context.Common.CommonContext):Bool;

	// Its generation, in hxmc.Main.generate's place, for a build it owns.
	// Throws its errors (`file:line: ...` lines, as the compiler's messages).
	function generate(com:context.Common.CommonContext):Void;
}
