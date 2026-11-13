package helder.jobs.script;

import helder.jobs.Wire;
import helder.typescript.js.Interop;

// A TypeScript program's jobs on helder.jobs (JobRecord): each a GC job whose
// input is the job's number, the constants its function reads and its
// input, Haxe's serialization of their values (Sendable's: numbers,
// strings, booleans, null, Uint8Array's bytes, arrays and plain objects of
// them, as helder.jobs.JobDefinition checked their types), its result the
// same. On the worker the program's function is called by its number
// (call: its body written by helder.typescript.lower, the JavaScript
// runtime started in a browser worker's own instance, the constants set
// there).
@:access(helder.jobs)
class Entry {
	@:coroutine public static function run(index:Int, captures:Array<Dynamic>, input:Dynamic):Dynamic {
		var w = new Writer();
		w.int(index);
		w.string(haxe.Serializer.run([captures, input]));
		var r = Jobs.runGc(fn(), w);
		var v:Dynamic = haxe.Unserializer.run(r.string() ?? "n");
		r.free();
		return Interop.toJs(v);
	}

	// (the entry's address, as a number)
	@:hxmc.unsafe static function fn():hxmc.I64
		return hxmc.unsafe.Callback.addr(entry).toI64();

	@:hxmc.unsafe(gc) @:hxmc.callback static function entry(p:hxmc.unsafe.Ptr):Int {
		var job:helder.jobs.JobRecord = cast p;
		return try {
			var r = new Reader(job.input);
			var index = r.int();
			var data:Array<Dynamic> = haxe.Unserializer.run(r.string() ?? "n");
			var captures:Array<Dynamic> = data[0];
			var v = Interop.toHaxe(call(index, Interop.toJs(captures), Interop.toJs(data[1])));
			var w = new Writer();
			w.string(haxe.Serializer.run(v));
			job.setOutput(w.done());
			0;
		} catch (e:Dynamic) Jobs.failed(job, e);
	}

	// the program's job of that number called with input (its constants
	// set first where the instance is a worker's own): written by
	// helder.typescript.lower for a program with jobs
	@:noCompletion static function call(index:Int, captures:Dynamic, input:Dynamic):Dynamic
		throw "helder.jobs: the program has no TypeScript job " + index;
}
