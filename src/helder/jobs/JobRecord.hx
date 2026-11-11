package helder.jobs;

import hxmc.unsafe.Atomic;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// A job's run as the pool keeps it: a record in malloc'ed memory, so that a
// GC-free job reads it in a safe region (through its Job). Its input (moved
// into the run, freed after it), its output (the job's to allocate: the
// awaiting task's to free), the cancel flag, the status. A GC job's entry
// (Sendable) reads and writes it here.
abstract JobRecord(Ptr) {
	// (the record: the input and output buffers' slots, the cancel flag, the status)
	public static inline var INPUT = 0;
	public static inline var OUTPUT = 8;
	public static inline var CANCEL = 16;
	static inline var STATUS = 20;
	static inline var SIZE = 24;

	inline function new(p:Ptr)
		this = p;

	@:allow(helder.jobs) static function make(input:IoBuffer):JobRecord {
		var p = LibC.malloc(SIZE);
		LibC.memset(p, 0, SIZE);
		Mem.setPtr(p, INPUT, cast input);
		return new JobRecord(p);
	}

	// the input (an empty buffer's address is nil)
	public var input(get, never):IoBuffer;

	inline function get_input():IoBuffer
		return cast Mem.getPtr(this, INPUT);

	// (the output so far as an IoBuffer, nil for none; taken: the run no longer owns it)
	@:allow(helder.jobs) function takeOutput():IoBuffer {
		var b = Mem.getPtr(this, OUTPUT);
		Mem.setPtr(this, OUTPUT, Ptr.nil());
		return cast b;
	}

	@:allow(helder.jobs) function setOutput(b:IoBuffer)
		Mem.setPtr(this, OUTPUT, cast b);

	@:allow(helder.jobs) function cancel()
		Atomic.store32(this.add(CANCEL), 1);

	@:allow(helder.jobs) var cancelled(get, never):Bool;

	inline function get_cancelled():Bool
		return Atomic.load32(this.add(CANCEL)) != 0;

	@:allow(helder.jobs) var status(get, set):Int;

	inline function get_status():Int
		return Mem.getI32(this, STATUS);

	inline function set_status(v:Int):Int {
		Mem.setI32(this, STATUS, v);
		return v;
	}

	// (the record and what it still owns: the input, an output nobody took)
	@:allow(helder.jobs) function free() {
		var i = Mem.getPtr(this, INPUT), o = Mem.getPtr(this, OUTPUT);
		if (!i.isNull()) LibC.free(i);
		if (!o.isNull()) LibC.free(o);
		LibC.free(this);
	}

	// (the input freed now: the job is over)
	@:allow(helder.jobs) function dropInput() {
		var i = Mem.getPtr(this, INPUT);
		if (!i.isNull()) LibC.free(i);
		Mem.setPtr(this, INPUT, Ptr.nil());
	}

	@:allow(helder.jobs) inline function ptr():Ptr
		return this;
}
