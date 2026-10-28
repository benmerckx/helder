package helder.jobs;

import hxmc.unsafe.Atomic;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;
import hxmc.unsafe.UInt8;

// A job's run as its function sees it: a record in malloc'ed memory, so
// that a GC-free job reads it in a safe region. Its input (moved into the
// run, freed after it), its output (the job's to allocate: the awaiting
// task's to free), whether the awaiting task was cancelled.
//
//   @:hxmc.unsafe @:hxmc.callback static function invert(job:Job):Int {
//     var n = job.input.length, src = job.input.ptr, out = job.output(n);
//     if (out.isNull()) return -1;
//     for (i in 0...n) {
//       if (i & 0xFFFF == 0 && job.cancelled) return -2;
//       Mem.setI8(out, i, 255 - Mem.getU8(src, i));
//     }
//     return 0;                                  // < 0: an error, JobError's code
//   }
abstract Job(Ptr) {
	// (the record: the input and output buffers' slots, the cancel flag, the status)
	static inline var INPUT = 0;
	static inline var OUTPUT = 8;
	static inline var CANCEL = 16;
	static inline var STATUS = 20;
	public static inline var SIZE = 24;

	inline function new(p:Ptr)
		this = p;

	@:allow(helder.jobs) static function make(input:IoBuffer):Job {
		var p = LibC.malloc(SIZE);
		LibC.memset(p, 0, SIZE);
		Mem.setPtr(p, INPUT, cast input);
		return new Job(p);
	}

	// the input (an empty buffer's address is nil)
	public var input(get, never):IoBuffer;

	@:hxmc.unsafe inline function get_input():IoBuffer
		return cast Mem.getPtr(this, INPUT);

	// whether the awaiting task was cancelled (natively at any time: a long
	// job checks it now and then and returns; in a browser's worker never, the
	// worker is ended instead)
	public var cancelled(get, never):Bool;

	@:hxmc.unsafe inline function get_cancelled():Bool
		return Atomic.load32(this.add(CANCEL)) != 0;

	// the result: n bytes (not zeroed) the awaiting task gets as an
	// IoBuffer, replacing an earlier one; the address of the first, nil when
	// out of memory
	@:hxmc.unsafe public function output(n:Int):Ptr<UInt8> {
		var old = Mem.getPtr(this, OUTPUT);
		if (!old.isNull()) LibC.free(old);
		var b = Buffers.alloc(n);
		Mem.setPtr(this, OUTPUT, b);
		return b.isNull() ? Ptr.nil() : b.add(Buffers.HEADER);
	}

	// (the output so far as an IoBuffer, nil for none; taken: the run no longer owns it)
	@:allow(helder.jobs) @:hxmc.unsafe function takeOutput():IoBuffer {
		var b = Mem.getPtr(this, OUTPUT);
		Mem.setPtr(this, OUTPUT, Ptr.nil());
		return cast b;
	}

	@:allow(helder.jobs) @:hxmc.unsafe function setOutput(b:IoBuffer)
		Mem.setPtr(this, OUTPUT, cast b);

	@:allow(helder.jobs) @:hxmc.unsafe function cancel()
		Atomic.store32(this.add(CANCEL), 1);

	@:allow(helder.jobs) var status(get, set):Int;

	@:hxmc.unsafe inline function get_status():Int
		return Mem.getI32(this, STATUS);

	@:hxmc.unsafe inline function set_status(v:Int):Int {
		Mem.setI32(this, STATUS, v);
		return v;
	}

	// (the record and what it still owns: the input, an output nobody took)
	@:allow(helder.jobs) @:hxmc.unsafe function free() {
		var i = Mem.getPtr(this, INPUT), o = Mem.getPtr(this, OUTPUT);
		if (!i.isNull()) LibC.free(i);
		if (!o.isNull()) LibC.free(o);
		LibC.free(this);
	}

	// (the input freed now: the job is over)
	@:allow(helder.jobs) @:hxmc.unsafe function dropInput() {
		var i = Mem.getPtr(this, INPUT);
		if (!i.isNull()) LibC.free(i);
		Mem.setPtr(this, INPUT, Ptr.nil());
	}

	@:allow(helder.jobs) inline function ptr():Ptr
		return this;
}
