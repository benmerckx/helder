// The messages between the page (Playground.hx) and the compiler worker (Worker.hx).

/** to the worker */
typedef Request = {
	/** "module" (the compiled hih.wasm, once), "warmup", "compile" (mode "run" or "hxb"), "display" or "check" */
	type:String,
	?id:Int,
	?module:js.lib.webassembly.Module,
	?mode:String,
	?file:String,
	?main:String,
	?code:String,
	/** a JSON-RPC display request */
	?request:Dynamic,
}

/** from the worker */
typedef Reply = {
	/** "ready", "out", "err", "done", "display", "check" or "failed" */
	type:String,
	?id:Int,
	?text:String,
	?status:Int,
	?output:String,
	?ms:Float,
	?zip:js.lib.ArrayBuffer,
	?message:String,
}
