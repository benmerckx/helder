package helder.compiler;

// Where a build's time goes (-D helder.phases=<file>): its phases' times,
// written as JSON when the build ends, `{"phases": [{"name", "ms"}],
// "ms"}` (ms: from the start of typing to the end). The compiler marks
// typing (Haxe's, its macros and markup included: helder.compiler.Compiler),
// lowering (hxmc's IR) and generation (codegen and link); a frontend adds
// its own (helder.typescript's: tsgo's check, the TypeScript program's
// lowering). `helder dev` reads it (HELDER_DEV_PHASES=1: helder.cli.BuildPhases)
// for the edit-loop lane.
class Phases {
	static var file:Null<String> = null;
	static var last = 0.0;
	static var first = 0.0;
	static var marks:Array<{name:String, ms:Float}> = [];

	// a build's start (beforeTyping): on when it names a file
	public static function begin(com:context.Common.CommonContext) {
		file = core.Define.rawDefined(com.defines, "helder.phases") ? core.Define.rawDefinedValue(com.defines, "helder.phases") : null;
		marks = [];
		first = last = haxe.Timer.stamp();
	}

	// the phase that ends now
	public static function mark(name:String) {
		if (file == null) return;
		var now = haxe.Timer.stamp();
		marks.push({name: name, ms: Math.round((now - last) * 10000) / 10});
		last = now;
	}

	// the build's end: the file written
	public static function end() {
		if (file == null) return;
		var f = file;
		file = null;
		try sys.io.File.saveContent(f, haxe.Json.stringify({phases: marks, ms: Math.round((haxe.Timer.stamp() - first) * 10000) / 10})) catch (_:Dynamic) {}
	}
}
