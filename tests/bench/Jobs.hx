import haxe.Timer;
import haxe.io.Bytes;
import hxmc.unsafe.BytesPtr;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;
import sys.thread.Lock;
import sys.thread.Thread;

// Background work against the main thread's frames (README, phase 3, "To
// prototype first"): a frame loop at 60 fps (JobsFrame: a ui of 2,000 nodes
// laid out in full, plus user code's garbage, GARBAGE_KB a frame) while a 4K
// PNG (tests/bench/photo.mjs) is decoded:
//
//   a    on the main thread, between two frames
//   b    a GC job: PngDecoder on a worker thread, its Bytes handed back
//   d    a GC-free job: OffHeapPng, malloc'ed memory, in a safe region
//   d0   d without the safe region
//   none the frames alone
//
// The worker thread exists in every variant (the runtime takes its locks
// once a second thread starts). The decode starts at frame 60; the window
// is the 90 frames from there (and on until the pixels are back). With
// `probe`, the main thread also collects at the end of every frame until
// the pixels are back (its nursery full then): the longest the job makes a
// collection wait, over its phases, at a frame's resolution. One line:
//
//   jobs <variant> <frames> <median ms> <p99> <max> <longest pause ms> <pauses ms> <GCs> <majors> <decode ms> <longest stop ms> <GC heap KB/frame> <check>
//
// a frame's pause: the collector's time in it and the time it waited for
// the world to stop (hxmc.rt.Gc's and Threads' counters); the longest
// stop: the longest wait for every thread to stop, over the run; the GC
// heap's growth in the window, all threads', by whole allocation buffers
// (heapBytes), a frame's share. The pixels reach the main thread as Bytes
// (b), as a pointer it frees (d). (c, the same job on helder.scoped's memory,
// was measured too: tests/bench/results/jobs.md; scoped is archived, tag
// archive/scoped.)
//
//   Jobs <DejaVuSans.ttf> <photo.png> <variant> [probe]
//   Jobs <DejaVuSans.ttf> <photo.png> alone <b|d>     (the job with an idle main thread: ms, GC heap bytes)
//   Jobs <DejaVuSans.ttf> <photo.png> check            (b and d give PngDecoder's pixels)
//
// Built with -D jobs_only=<variant>: that variant alone; -D jobs_bare: no ui
// (the sizes: what a variant adds, to this program and to one without the
// ui).
@:access(hxmc.rt.Gc) @:access(hxmc.rt.Threads)
class Jobs {
	static inline var WARM = 60;
	static inline var WINDOW = 90;
	static inline var FRAME = 1 / 60;

	static var png:Bytes;
	static var pngPtr:Ptr;

	// --- main

	static function main() {
		var args = Sys.args();
		var font = sys.io.File.getBytes(args[0]);
		png = sys.io.File.getBytes(args[1]);
		// (d's input: the file in malloc'ed memory, as an I/O buffer would hold it)
		pngPtr = LibC.malloc((png.length : hxmc.I64));
		LibC.memcpy(pngPtr, BytesPtr.of(png, 0, png.length), (png.length : hxmc.I64));
		JobsFrame.garbageKb = Std.parseInt(Sys.getEnv("GARBAGE_KB") ?? "") ?? JobsFrame.garbageKb;
		hxmc.rt.Gc.stats = true;
		hxmc.rt.Threads.thrStats = true;
		Thread.create(worker);
		switch args[2] {
			case "alone": alone(args[3]);
			#if !jobs_only
			case "check": verify();
			#end
			case v: frames(v, font, args[3] == "probe");
		}
	}

	// --- the frames

	static function frames(variant:String, font:Bytes, probe:Bool) {
		JobsFrame.setup(font);
		var times = [], pauses = [], gcs = 0, majors = 0, decode = 0.0, started = 0.0, back = false, bytes = 0.0;
		var next = Timer.stamp();
		var k = 0;
		while (k < WARM + WINDOW || (k >= WARM && !back && variant != "none")) {
			var c0 = hxmc.rt.Gc.collections, m0 = hxmc.rt.Gc.majors, s0 = gcSecs();
			var t0 = Timer.stamp();
			JobsFrame.frame();
			if (k == WARM) {
				bytes = heapBytes();
				started = t0;
				start(variant);
				if (variant == "a") {
					decode = (Timer.stamp() - started) * 1000;
					back = true;
				}
			}
			if (k > WARM && !back && variant != "a" && done.wait(0.0)) {
				decode = (jobEnd - jobStart) * 1000;
				receive(variant);
				back = true;
			}
			// (probe: the nursery full at every frame of the job, a collection the main thread asks for)
			if (probe && k >= WARM && !back) hxmc.rt.Gc.collect(false);
			var t = Timer.stamp() - t0;
			if (k >= WARM) {
				times.push(t * 1000);
				pauses.push((gcSecs() - s0) * 1000);
				gcs += hxmc.rt.Gc.collections - c0;
				majors += hxmc.rt.Gc.majors - m0;
			}
			k++;
			// (to the next frame's start: asleep, in a safe region)
			next += FRAME;
			var now = Timer.stamp();
			if (next > now) Sys.sleep(next - now) else next = now;
		}
		var total = 0.0;
		for (p in pauses)
			total += p;
		var sorted = times.copy();
		sorted.sort(Reflect.compare);
		pauses.sort(Reflect.compare);
		inline function at(q:Float)
			return sorted[Std.int(Math.min(sorted.length - 1, Math.ceil(q * sorted.length) - 1))];
		Sys.println([
			"jobs", variant, Std.string(times.length), fixed(at(0.5)), fixed(at(0.99)), fixed(sorted[sorted.length - 1]), fixed(pauses[pauses.length - 1]),
			fixed(total), Std.string(gcs), Std.string(majors), fixed(decode), fixed(hxmc.rt.Threads.stStwMaxUs / 1000),
			Std.string(Math.round((heapBytes() - bytes) / times.length / 1024)), Std.string(Math.round(JobsFrame.check))
		].join(" "));
	}

	// (the collector's seconds and those waiting for the world to stop)
	static inline function gcSecs():Float
		return hxmc.rt.Gc.minorSecs + hxmc.rt.Gc.majorSecs + hxmc.rt.Threads.stStwSecs;

	// --- the jobs: one worker thread, waiting for a request (in a safe region)

	static final request = new Lock();
	static final done = new Lock();
	static var job = "";
	static var jobStart = 0.0;
	static var jobEnd = 0.0;
	static var gcPixels:Bytes;
	static var pixelsAt:Ptr;
	static var pixelsLen = 0;
	static var failed = 0;
	static var tlab0:Ptr;
	static var tlabMoved = 0.0;

	static function worker() {
		while (true) {
			request.wait();
			jobStart = Timer.stamp();
			tlab0 = hxmc.rt.Gc.yptr;
			switch job {
				#if (!jobs_only || jobs_only == "b")
				case "b":
					gcPixels = helder.image.PngDecoder.decode(png).rgba;
					finish();
				#end
				#if (!jobs_only || jobs_only == "d" || jobs_only == "d0")
				case "d" | "d0":
					var safe = job == "d";
					if (safe) Safe.enter();
					failed = OffHeapPng.decode(pngPtr, png.length);
					if (safe) Safe.leave();
					pixelsAt = OffHeapPng.pixels;
					pixelsLen = OffHeapPng.width * OffHeapPng.height * 4;
					finish();
				#end
				case _:
			}
		}
	}

	// (the job's end: its time, how far the worker's allocation buffer moved)
	static function finish() {
		jobEnd = Timer.stamp();
		var t = hxmc.rt.Gc.yptr;
		tlabMoved = t.isNull() || tlab0.isNull() ? -1 : cast t.diff(tlab0);
		done.release();
	}


	static function start(variant:String) {
		switch variant {
			#if (!jobs_only || jobs_only == "a")
			case "a":
				var px = helder.image.PngDecoder.decode(png).rgba;
				JobsFrame.check += sample(i -> px.get(i), px.length);
			#end
			case "none":
			case v:
				job = v;
				request.release();
		}
	}

	// the pixels back on the main thread: read (an upload would), then let go
	static function receive(variant:String) {
		if (failed != 0) throw 'job $variant failed: $failed';
		switch variant {
			#if (!jobs_only || jobs_only == "b")
			case "b":
				JobsFrame.check += sample(i -> gcPixels.get(i), gcPixels.length);
				gcPixels = null;
			#end
			#if (!jobs_only || jobs_only == "d" || jobs_only == "d0")
			case "d" | "d0":
				var p = pixelsAt;
				JobsFrame.check += sample(i -> Mem.getU8(p, i), pixelsLen);
				LibC.free(p);
			#end
			case _:
		}
	}

	// (every 4099th byte: a GPU upload's read, without one)
	static inline function sample(get:Int->Int, n:Int):Float {
		var s = 0, i = 0;
		while (i < n) {
			s += get(i);
			i += 4099;
		}
		return s;
	}

	// --- the job alone, the main thread waiting: its time, the GC heap's
	// growth (the nursery's, by whole allocation buffers, and the old
	// space's, less what minor collections promoted; -1 after a major
	// collection) and how far the worker's allocation buffer moved (exact
	// below a buffer; -1 when it was refilled or collected)

	static function alone(variant:String) {
		var times = [], bytes = [], moved = [];
		for (_ in 0...5) {
			var m0 = hxmc.rt.Gc.majors, c0 = hxmc.rt.Gc.collections, b0 = heapBytes();
			job = variant;
			request.release();
			done.wait();
			var b = heapBytes() - b0;
			receive(variant);
			times.push((jobEnd - jobStart) * 1000);
			bytes.push(hxmc.rt.Gc.majors == m0 ? b : -1);
			moved.push(hxmc.rt.Gc.collections == c0 ? tlabMoved : -1);
		}
		times.sort(Reflect.compare);
		bytes.sort(Reflect.compare);
		moved.sort(Reflect.compare);
		Sys.println('alone $variant ${fixed(times[2])} ${fixed(times[0])} ${fixed(times[4])} ${Math.round(bytes[4])} ${Math.round(moved[4])}');
	}

	static function heapBytes():Float {
		var young:Float = cast hxmc.rt.Gc.youngBytes;
		var used:Float = cast hxmc.rt.Gc.youngNext.diff(hxmc.rt.Gc.youngStart);
		var old:Float = cast hxmc.rt.Gc.oldPtr.diff(hxmc.rt.Gc.oldStart);
		var promoted:Float = cast hxmc.rt.Gc.promotedBytes;
		return young + used + old - promoted;
	}

	#if !jobs_only
	// --- b and d give PngDecoder's pixels
	static function verify() {
		var want = helder.image.PngDecoder.decode(png).rgba;
		for (v in ["b", "d"]) {
			job = v;
			request.release();
			done.wait();
			if (failed != 0) throw '$v: error $failed';
			var p = pixelsAt, got = v == "b" ? gcPixels : null;
			var n = v == "b" ? got.length : pixelsLen;
			if (n != want.length) throw '$v: $n bytes, not ${want.length}';
			for (i in 0...n) {
				var x = v == "b" ? got.get(i) : Mem.getU8(p, i);
				if (x != want.get(i)) throw '$v: byte $i is $x, not ${want.get(i)}';
			}
			receive(v);
			Sys.println('$v: the same ${want.length} bytes');
		}
	}
	#end

	static function fixed(v:Float):String
		return Std.string(Math.round(v * 1000) / 1000);
}

// A safe region the collector does not wait for: the runtime's own markers
// (hxmc.rt.Leaf, as its blocking natives use them; hxmc 025cb79 has them as
// hxmc.unsafe.Blocking.enter and leave). Between them the thread must
// allocate nothing and touch no GC object: a collection may run and move
// them meanwhile. Entering publishes the thread's shadow stack; leaving
// waits for a collection in progress.
class Safe {
	public static inline function enter()
		hxmc.rt.C.Leaf.rt_blocking_enter();

	public static inline function leave()
		hxmc.rt.C.Leaf.rt_blocking_leave();
}
