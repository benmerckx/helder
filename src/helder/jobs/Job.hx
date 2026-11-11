package helder.jobs;

import hxmc.I64;
import hxmc.ReadOnlySpan;
import hxmc.Span;
import hxmc.unsafe.Atomic;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;
import hxmc.unsafe.UInt8;

// A GC-free job's run as its function sees it: a checked kernel over spans.
// Its input (moved into the run, freed after it), its output (the job's to
// allocate: the awaiting task's to free), whether the awaiting task was
// cancelled.
//
//   @:hxmc.kernel @:hxmc.callback static function invert(job:Job):Int {
//     var src = job.input(), out = job.output(src.length);
//     if (out.length < src.length) return -1;     // out of memory
//     for (i in 0...src.length) {
//       if (i & 0xFFFF == 0 && job.cancelled) return -2;
//       out[i] = 255 - src[i];
//     }
//     return 0;                                    // < 0: an error, JobError's code
//   }
//
// A proof (@:hxmc.proof): only the pool hands one out, the address of the
// run's record (JobRecord) as it calls the job, so no other code calls a
// job, and these accessors (the one trusted part: the record's and an
// IoBuffer's layout) read it without a check.
@:hxmc.proof abstract Job(I64) {
	// the input; empty for none
	@:hxmc.kernel @:hxmc.unsafe public function input():ReadOnlySpan<UInt8> {
		var b = Mem.getPtr(record(), JobRecord.INPUT);
		return b.isNull() ? ReadOnlySpan.unsafeOf(cast b, 0) : ReadOnlySpan.unsafeOf(cast b.add(Buffers.HEADER), Mem.getI32(b, 12));
	}

	// whether the awaiting task was cancelled (natively at any time: a long
	// job checks it now and then and returns; in a browser's worker never, the
	// worker is ended instead)
	public var cancelled(get, never):Bool;

	@:hxmc.kernel @:hxmc.unsafe function get_cancelled():Bool
		return Atomic.load32(record().add(JobRecord.CANCEL)) != 0;

	// the result: n bytes (not zeroed) the awaiting task gets as an
	// IoBuffer, replacing an earlier one; empty when out of memory
	@:hxmc.kernel @:hxmc.unsafe public function output(n:Int):Span<UInt8> {
		var r = record(), old = Mem.getPtr(r, JobRecord.OUTPUT);
		if (!old.isNull()) LibC.free(old);
		var b = Buffers.alloc(n);
		Mem.setPtr(r, JobRecord.OUTPUT, b);
		return b.isNull() ? Span.unsafeOf(cast b, 0) : Span.unsafeOf(cast b.add(Buffers.HEADER), n);
	}

	// the result's length cut to n bytes (no more than it has: a buffer
	// decoded in place, its tail no longer needed)
	@:hxmc.kernel @:hxmc.unsafe public function truncate(n:Int) {
		var b = Mem.getPtr(record(), JobRecord.OUTPUT);
		if (!b.isNull() && n >= 0 && n <= Mem.getI32(b, 12)) Buffers.header(b, n);
	}

	inline function record():Ptr
		return Ptr.ofI64(this);
}
