import Compiler;

// The messages between the page (Main) and the compiler's worker
// (CompilerWorker). Each build or display request carries the example's
// edited files (path under /lib/src => text): the worker's file system then
// has them, and every other file as shipped.

typedef Edits = haxe.DynamicAccess<String>;

enum abstract ToWorker(String) {
	// {module}: download the compiler (reactor.wasm or reactor-legacy.wasm), the std and the sources; start the compiler
	var Init = "init";
	// {id, example, target, dev, edits}
	var Build = "build";
	// {id, example, method, file, offset, extra, edits}
	var Display = "display";
}

enum abstract FromWorker(String) {
	// {what, loaded, total}: a download, as it goes
	var Progress = "progress";
	var Ready = "ready";
	// {files: [[path, writing], ...]}: what the compiler opened, batched
	var Files = "files";
	// {id, ok, bytes, file, assets, messages, log, stdout, ms}
	var Built = "built";
	// {id, json, ms}
	var Displayed = "displayed";
	// {id}: a newer request of the same kind replaced it
	var Superseded = "superseded";
	// {id?, message}
	var Failed = "failed";
}

typedef Request = {
	type:ToWorker,
	?id:Int,
	?example:Example,
	?target:String,
	?dev:Bool,
	?edits:Edits,
	?method:String,
	?file:String,
	?offset:Int,
	?extra:Dynamic,
	?module:String,
}

typedef Reply = {
	type:FromWorker,
	?id:Int,
	?what:String,
	?loaded:Int,
	?total:Int,
	?files:Array<Array<Dynamic>>,
	?ok:Bool,
	?bytes:js.lib.Uint8Array,
	?file:String,
	?assets:Array<Array<Dynamic>>,
	?messages:Array<Message>,
	?log:Array<String>,
	?stdout:Array<String>,
	?json:Dynamic,
	?ms:Float,
	?message:String,
}
