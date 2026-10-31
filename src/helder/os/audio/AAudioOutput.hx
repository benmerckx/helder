package helder.os.audio;

import helder.os.audio.AAudio;
import hxmc.unsafe.*;
import sys.thread.Lock;
import sys.thread.Thread;

// helder.os.audio.Audio on Android: an AAudio output stream (libaaudio.so,
// loaded when an output opens), low-latency, shared, 32-bit floats at the
// rate asked for (AAudio converts), usage "game". AAudio pulls from its
// own thread (a data callback), which the runtime does not know: as
// CoreAudio's render callback, it is @:hxmc.noGc and only copies from a
// ring of samples in native memory (single producer, single consumer,
// positions in frames, atomics), then posts a semaphore; the audio thread
// is ours, waiting on it and filling the ring a period at a time. The ring
// holds four periods or more (a power of two of frames).
// A stream disconnected (headphones unplugged, a Bluetooth device gone:
// AAudio's error callback with AAUDIO_ERROR_DISCONNECTED) cannot be used
// again: the error callback, on AAudio's thread, only flags it, and the
// audio thread closes it and opens another on the device the system routes
// to now (retrying every half a second while it cannot). Audio's
// lifecycle hold (the activity paused: stop; resumed: start) is Audio's.
@:allow(helder.os.audio)
class AAudioOutput {
	static var loaded:Null<String>;

	// the ring's header (native memory, the callbacks' user data)
	static inline var DATA = 0; // Ptr<Float32>
	static inline var CAPACITY = 8; // frames, a power of two
	static inline var CHANNELS = 12;
	static inline var READ = 16; // frames read (wrapping Int32), the callback's
	static inline var WRITTEN = 20; // frames written, the audio thread's
	static inline var UNDERRUNS = 24;
	static inline var CALLS = 28; // data callbacks
	static inline var DISCONNECTED = 32; // 1: the error callback's flag
	static inline var SEM = 64; // sem_t (16 bytes on LP64; room for more)
	static inline var HEADER = 128;

	final owner:Audio;
	var stream = Ptr.nil();
	final ring:Ptr;
	var capacity = 0;
	final buffer:Ptr<Float32>;
	var quit = false;
	final done = new Lock();
	var error:Null<String>;
	// streams reopened after a disconnect
	public var reopened(default, null) = 0;

	function new(owner:Audio, device:Null<String>) {
		this.owner = owner;
		if (device != null) throw "helder.os.audio: AAudio plays on the default output only (device " + device + ")";
		if (loaded == null) {
			var e = AAudio.load("libaaudio.so");
			loaded = e == null ? "" : e;
		}
		if (loaded != "") throw "helder.os.audio: no output device (" + loaded + ")";
		ring = LibC.malloc(HEADER);
		LibC.memset(ring, 0, HEADER);
		Sem.sem_init(ring.add(SEM), 0, 0);
		var e = openStream();
		if (e != null) {
			Sem.sem_destroy(ring.add(SEM));
			LibC.free(ring);
			throw "helder.os.audio: no output device (AAudio: " + e + ")";
		}
		var burst = AAudio.AAudioStream_getFramesPerBurst(stream);
		var cap = 1;
		while (cap < owner.frames * 4 || cap < burst * 4)
			cap <<= 1;
		capacity = cap;
		Mem.setPtr(ring, DATA, LibC.malloc((capacity * owner.channels * 4 : Int64)));
		Mem.setI32(ring, CAPACITY, capacity);
		Mem.setI32(ring, CHANNELS, owner.channels);
		buffer = LibC.malloc((owner.frames * owner.channels * 4 : Int64));
		owner.latency = (capacity + AAudio.AAudioStream_getBufferSizeInFrames(stream)) / owner.sampleRate;
	}

	// a stream on the system's output now (null, or what failed); the rate it took
	function openStream():Null<String> {
		return Arena.scopedValue(a -> {
			var p:Ptr<Ptr> = a.alloc(8);
			var r = AAudio.AAudio_createStreamBuilder(p);
			if (r != 0) return "AAudio_createStreamBuilder: " + AAudio.AAudio_convertResultToText(r).toString();
			var b = p.value;
			AAudio.AAudioStreamBuilder_setFormat(b, AA.FORMAT_PCM_FLOAT);
			AAudio.AAudioStreamBuilder_setChannelCount(b, owner.channels);
			AAudio.AAudioStreamBuilder_setSampleRate(b, owner.sampleRate);
			AAudio.AAudioStreamBuilder_setPerformanceMode(b, AA.PERFORMANCE_MODE_LOW_LATENCY);
			AAudio.AAudioStreamBuilder_setSharingMode(b, AA.SHARING_MODE_SHARED);
			AAudio.AAudioStreamBuilder_setUsage(b, AA.USAGE_GAME);
			AAudio.AAudioStreamBuilder_setDataCallback(b, Callback.addr(data), ring);
			AAudio.AAudioStreamBuilder_setErrorCallback(b, Callback.addr(errored), ring);
			r = AAudio.AAudioStreamBuilder_openStream(b, p);
			AAudio.AAudioStreamBuilder_delete(b);
			if (r != 0) return "AAudioStreamBuilder_openStream: " + AAudio.AAudio_convertResultToText(r).toString();
			stream = p.value;
			var rate = AAudio.AAudioStream_getSampleRate(stream);
			if (rate > 0) owner.sampleRate = rate;
			// (two bursts: AAudio's advice for low latency without glitches)
			var burst = AAudio.AAudioStream_getFramesPerBurst(stream);
			if (burst > 0) AAudio.AAudioStream_setBufferSizeInFrames(stream, burst * 2);
			return null;
		});
	}

	// AAudio's thread: frames from the ring into the stream's buffer,
	// silence when it runs dry
	@:hxmc.callback @:hxmc.noGc static function data(stream:Ptr, ring:Ptr, out:Ptr, frames:Int):Int {
		var data:Ptr<UInt8> = Mem.getPtr(ring, DATA);
		var cap = Mem.getI32(ring, CAPACITY), bytes = Mem.getI32(ring, CHANNELS) * 4;
		var read = Atomic.load32(ring.add(READ));
		var n = Atomic.load32(ring.add(WRITTEN)) - read;
		if (n > frames) n = frames;
		if (n < 0) n = 0;
		var at = read & (cap - 1), first = cap - at < n ? cap - at : n;
		LibC.memcpy(out, data.add(at * bytes), (first * bytes : Int64));
		if (n > first) LibC.memcpy(out.add(first * bytes), data, ((n - first) * bytes : Int64));
		if (n < frames) {
			LibC.memset(out.add(n * bytes), 0, ((frames - n) * bytes : Int64));
			Mem.setI32(ring, UNDERRUNS, Mem.getI32(ring, UNDERRUNS) + 1);
		}
		Atomic.store32(ring.add(READ), read + n);
		Atomic.add32(ring.add(CALLS), 1);
		Sem.sem_post(ring.add(SEM));
		return AA.CALLBACK_RESULT_CONTINUE;
	}

	// AAudio's thread (another than the data callback's): the stream is
	// unusable; the audio thread reopens it
	@:hxmc.callback @:hxmc.noGc static function errored(stream:Ptr, ring:Ptr, error:Int):Void {
		Atomic.store32(ring.add(DISCONNECTED), 1);
		Sem.sem_post(ring.add(SEM));
	}

	// the data callbacks so far (tests: the stream started)
	public function calls():Int
		return Atomic.load32(ring.add(CALLS));

	function start() {
		quit = false;
		Atomic.store32(ring.add(READ), 0);
		Atomic.store32(ring.add(WRITTEN), 0);
		while (produce()) {}
		if (!stream.isNull()) {
			var r = AAudio.AAudioStream_requestStart(stream);
			if (r != 0) Atomic.store32(ring.add(DISCONNECTED), 1);
		}
		Thread.create(run);
	}

	// a period into the ring, if it has room
	function produce():Bool {
		var written = Atomic.load32(ring.add(WRITTEN));
		if (capacity - (written - Atomic.load32(ring.add(READ))) < owner.frames) return false;
		owner.pull(buffer, owner.frames);
		var data:Ptr<UInt8> = Mem.getPtr(ring, DATA), bytes = owner.channels * 4;
		var at = written & (capacity - 1), n = owner.frames, first = capacity - at < n ? capacity - at : n;
		LibC.memcpy(data.add(at * bytes), buffer, (first * bytes : Int64));
		if (n > first) LibC.memcpy(data, buffer.add(first * bytes), ((n - first) * bytes : Int64));
		Atomic.store32(ring.add(WRITTEN), written + n);
		return true;
	}

	// a wait for the semaphore, `ms` at most
	function wait(ms:Int) {
		var ts = Mem.stack(16);
		Sem.clock_gettime(0, ts); // (CLOCK_REALTIME: sem_timedwait's)
		// (two 64-bit fields, little-endian: seconds fit 31 bits until 2038, nanoseconds 30)
		var ns = Mem.getI32(ts, 8) + ms * 1000000;
		Mem.setI32(ts, 0, Mem.getI32(ts, 0) + Std.int(ns / 1000000000));
		Mem.setI32(ts, 8, ns % 1000000000);
		Mem.setI32(ts, 12, 0);
		SemWait.sem_timedwait(ring.add(SEM), ts);
	}

	// the audio thread
	function run() {
		try {
			while (!quit) {
				if (Atomic.load32(ring.add(DISCONNECTED)) != 0) {
					reopen();
					continue;
				}
				if (!produce()) wait(100);
			}
		} catch (e:Dynamic) {
			error = Std.string(e);
		}
		done.release();
	}

	// (the audio thread) the disconnected stream closed, another opened and started
	function reopen() {
		if (!stream.isNull()) {
			AAudio.AAudioStream_requestStop(stream);
			AAudio.AAudioStream_close(stream);
			stream = Ptr.nil();
		}
		var rate = owner.sampleRate;
		if (openStream() != null) {
			// (no output yet: again in a while)
			wait(500);
			return;
		}
		owner.sampleRate = rate; // (the mix's rate stays: AAudio converts)
		Atomic.store32(ring.add(DISCONNECTED), 0);
		Atomic.store32(ring.add(READ), Atomic.load32(ring.add(WRITTEN)));
		reopened++;
		if (AAudio.AAudioStream_requestStart(stream) != 0) Atomic.store32(ring.add(DISCONNECTED), 1);
	}

	function stop() {
		quit = true;
		Sem.sem_post(ring.add(SEM));
		done.wait();
		if (!stream.isNull()) AAudio.AAudioStream_requestStop(stream);
		if (error != null) throw "helder.os.audio: " + error;
	}

	function close() {
		if (!stream.isNull()) AAudio.AAudioStream_close(stream);
		stream = Ptr.nil();
		Sem.sem_destroy(ring.add(SEM));
		LibC.free(Mem.getPtr(ring, DATA));
		LibC.free(ring);
		LibC.free(buffer);
	}
}
