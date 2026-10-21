import js.Syntax;

// An error as a line a person can read, whatever was thrown or rejected: a
// string; an Error (its name and message); a program's own exception, which
// leaves WebAssembly as a WebAssembly.Exception without a message; a WebGPU
// error or a device's loss (its message, its reason); any other object as
// JSON. The error itself goes to the console too, for a bug report.
class Fail {
	public static function describe(e:Dynamic):String {
		if (e == null) return "an unknown error";
		if (Syntax.typeof(e) == "string") return e;
		Syntax.code("console.error({0})", e);
		if (Syntax.code("typeof WebAssembly.Exception == 'function' && {0} instanceof WebAssembly.Exception", e))
			return "the program threw an exception it did not catch";
		if (Syntax.typeof(e.message) == "string" && e.message != "") {
			var name:String = Syntax.typeof(e.name) == "string" && e.name != "Error" ? e.name + ": " : "";
			var reason:String = Syntax.typeof(e.reason) == "string" ? ' (${e.reason})' : "";
			return name + e.message + reason;
		}
		if (e.error != null) return describe(e.error);
		if (Syntax.typeof(e.reason) == "string") return e.reason;
		var json = try haxe.Json.stringify(e) catch (_:Dynamic) null;
		if (json != null && json != "{}") return json;
		var tag:String = Syntax.code("Object.prototype.toString.call({0})", e);
		return tag == "[object Object]" ? "an error without a message (the browser's console has it)" : tag;
	}
}
