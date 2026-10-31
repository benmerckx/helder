package helder.os.audio;

import helder.os.audio.CoreAudio;
import hxmc.unsafe.*;
import sys.thread.Lock;
import sys.thread.Thread;

// helder.os.audio.Audio on macOS: the default output unit (an AudioUnit of
// AudioToolbox, kAudioUnitSubType_DefaultOutput), 32-bit floats at the rate
// asked for (the unit converts). CoreAudio pulls, but from its own I/O
// thread, which the runtime does not know: Haxe code that may collect
// cannot run there. Its render callback is @:hxmc.noGc and only copies from
// a ring of samples in native memory (single producer, single consumer:
// positions in frames, atomics), then signals a semaphore; the audio thread
// is ours, waiting on it and filling the ring a period (Audio.frames) at a
// time. The ring holds four periods or more (a power of two of frames): the
// latency, with the device's buffer.
// "file:PATH": the generic output unit (kAudioUnitSubType_GenericOutput, no
// device), rendered by a third thread at the clock's pace (AudioUnitRender,
// which calls the same render callback), what it renders written to PATH;
// it waits for a period in the ring rather than render silence, so the
// file holds what the callback gave, whatever the machine's load.
@:allow(helder.os.audio)
class CoreAudioOutput {
	// the ring's header (native memory, the render callback's refCon)
	static inline var DATA = 0; // Ptr<Float32>
	static inline var SEM = 8; // the semaphore
	static inline var CAPACITY = 16; // frames, a power of two
	static inline var CHANNELS = 20;
	static inline var READ = 24; // frames read (wrapping Int32), the callback's
	static inline var WRITTEN = 28; // frames written, the audio thread's
	static inline var UNDERRUNS = 32;
	static inline var HEADER = 40;

	final owner:Audio;
	var unit = Ptr.nil();
	final ring:Ptr;
	final capacity:Int;
	final buffer:Ptr<Float32>; // a period, filled by the callback
	final path:Null<String>;
	var quit = false;
	final done = new Lock();
	var error:Null<String>;

	function new(owner:Audio, device:Null<String>) {
		this.owner = owner;
		path = device != null && StringTools.startsWith(device, "file:") ? device.substr(5) : null;
		if (device != null && path == null) throw "helder.os.audio: CoreAudio plays on the default output only (device " + device + ")";
		// (iOS: RemoteIO, the session's route; its category first)
		if (Mem.platform() >= 1) AudioSession.setup(owner.session, owner.sampleRate, owner.frames) else if (path == null) {
			// (no default device: a Mac mini without speakers, a CI runner)
			var id = Arena.scopedValue(a -> {
				var addr = a.make(AudioObjectPropertyAddress);
				addr.value.mSelector = CA.kAudioHardwarePropertyDefaultOutputDevice;
				addr.value.mScope = CA.kAudioObjectPropertyScopeGlobal;
				var size:Ptr<Int32> = a.alloc(4), id:Ptr<Int32> = a.alloc(4);
				size.value = 4;
				var st = CoreAudioHw.AudioObjectGetPropertyData(CA.kAudioObjectSystemObject, addr, 0, Ptr.nil(), size, id);
				st == 0 ? id.value : 0;
			});
			if (id == 0) throw "helder.os.audio: no output device (CoreAudio: no default output device)";
		}
		var cap = 1;
		while (cap < owner.frames * 4)
			cap <<= 1;
		capacity = cap;
		var bytes = owner.channels * 4;
		ring = LibC.malloc(HEADER);
		LibC.memset(ring, 0, HEADER);
		Mem.setPtr(ring, DATA, LibC.malloc((capacity * bytes : Int64)));
		Mem.setPtr(ring, SEM, Dispatch.dispatch_semaphore_create(0));
		Mem.setI32(ring, CAPACITY, capacity);
		Mem.setI32(ring, CHANNELS, owner.channels);
		buffer = LibC.malloc((owner.frames * bytes : Int64));
		Arena.scoped(a -> {
			var desc = a.make(AudioComponentDescription);
			desc.value.componentType = CA.kAudioUnitType_Output;
			desc.value.componentSubType = path != null ? CA.kAudioUnitSubType_GenericOutput : Mem.platform() >= 1 ? CA.kAudioUnitSubType_RemoteIO : CA.kAudioUnitSubType_DefaultOutput;
			desc.value.componentManufacturer = CA.kAudioUnitManufacturer_Apple;
			var component = AudioToolbox.AudioComponentFindNext(Ptr.nil(), desc);
			if (component.isNull()) fail("no output unit (AudioComponentFindNext)");
			var p:Ptr<Ptr> = a.alloc(8);
			check(AudioToolbox.AudioComponentInstanceNew(component, p), "AudioComponentInstanceNew");
			unit = p.value;
			var f = a.make(AudioStreamBasicDescription);
			f.value.mSampleRate = owner.sampleRate;
			f.value.mFormatID = CA.kAudioFormatLinearPCM;
			f.value.mFormatFlags = CA.kAudioFormatFlagIsFloat | CA.kAudioFormatFlagIsPacked;
			f.value.mBytesPerPacket = bytes;
			f.value.mFramesPerPacket = 1;
			f.value.mBytesPerFrame = bytes;
			f.value.mChannelsPerFrame = owner.channels;
			f.value.mBitsPerChannel = 32;
			check(AudioToolbox.AudioUnitSetProperty(unit, CA.kAudioUnitProperty_StreamFormat, CA.kAudioUnitScope_Input, 0, f, 40), "the stream format");
			if (path != null)
				check(AudioToolbox.AudioUnitSetProperty(unit, CA.kAudioUnitProperty_StreamFormat, CA.kAudioUnitScope_Output, 0, f, 40),
					"the stream format (output)");
			var cb = a.make(AURenderCallbackStruct);
			cb.value.inputProc = Callback.addr(render);
			cb.value.inputProcRefCon = ring;
			check(AudioToolbox.AudioUnitSetProperty(unit, CA.kAudioUnitProperty_SetRenderCallback, CA.kAudioUnitScope_Input, 0, cb, 16),
				"the render callback");
			var n:Ptr<Int32> = a.alloc(4), size:Ptr<Int32> = a.alloc(4);
			if (path == null) {
				// (the device's I/O buffer: a period, if the device takes it)
				n.value = owner.frames;
				AudioToolbox.AudioUnitSetProperty(unit, CA.kAudioDevicePropertyBufferFrameSize, CA.kAudioUnitScope_Global, 0, n, 4);
			} else {
				n.value = owner.frames;
				AudioToolbox.AudioUnitSetProperty(unit, CA.kAudioUnitProperty_MaximumFramesPerSlice, CA.kAudioUnitScope_Global, 0, n, 4);
			}
			check(AudioToolbox.AudioUnitInitialize(unit), "AudioUnitInitialize");
			var io = owner.frames;
			size.value = 4;
			if (path == null && AudioToolbox.AudioUnitGetProperty(unit, CA.kAudioDevicePropertyBufferFrameSize, CA.kAudioUnitScope_Global, 0, n, size) == 0)
				io = n.value;
			owner.latency = (capacity + io) / owner.sampleRate;
		});
	}

	function check(status:Int, what:String)
		if (status != 0) fail(what + " failed (OSStatus " + status + ")");

	function fail(s:String) {
		if (!unit.isNull()) AudioToolbox.AudioComponentInstanceDispose(unit);
		unit = Ptr.nil();
		throw "helder.os.audio: " + s;
	}

	// CoreAudio's I/O thread (or the "file:" renderer): frames from the ring
	// into the unit's buffer (one, interleaved), silence when it runs dry
	@:hxmc.callback @:hxmc.noGc static function render(ring:Ptr, flags:Ptr, time:Ptr, bus:Int, frames:Int, list:Ptr):Int {
		var out:Ptr<UInt8> = Mem.getPtr(list, 16); // (mBuffers[0].mData)
		var data:Ptr<UInt8> = Mem.getPtr(ring, DATA);
		var cap = Mem.getI32(ring, CAPACITY), bytes = Mem.getI32(ring, CHANNELS) * 4;
		var read = Atomic.load32(ring.add(READ));
		var n = Atomic.load32(ring.add(WRITTEN)) - read;
		if (n > frames) n = frames;
		var at = read & (cap - 1), first = cap - at < n ? cap - at : n;
		LibC.memcpy(out, data.add(at * bytes), (first * bytes : Int64));
		if (n > first) LibC.memcpy(out.add(first * bytes), data, ((n - first) * bytes : Int64));
		if (n < frames) {
			LibC.memset(out.add(n * bytes), 0, ((frames - n) * bytes : Int64));
			Mem.setI32(ring, UNDERRUNS, Mem.getI32(ring, UNDERRUNS) + 1);
		}
		Atomic.store32(ring.add(READ), read + n);
		Dispatch.dispatch_semaphore_signal(Mem.getPtr(ring, SEM));
		return 0;
	}

	function start() {
		quit = false;
		Atomic.store32(ring.add(READ), 0);
		Atomic.store32(ring.add(WRITTEN), 0);
		// (the ring full before the unit starts)
		while (produce()) {}
		Thread.create(run);
		if (path != null) Thread.create(renderFile) else check(AudioToolbox.AudioOutputUnitStart(unit), "AudioOutputUnitStart");
	}

	// a period into the ring, if it has room
	function produce():Bool {
		var written = Atomic.load32(ring.add(WRITTEN));
		if (capacity - (written - Atomic.load32(ring.add(READ))) < owner.frames) return false;
		owner.pull(buffer, owner.frames);
		var data:Ptr<UInt8> = Mem.getPtr(ring, DATA), bytes = owner.channels * 4;
		// (capacity is a multiple of a period when the period is a power of two; else two copies)
		var at = written & (capacity - 1), n = owner.frames, first = capacity - at < n ? capacity - at : n;
		LibC.memcpy(data.add(at * bytes), buffer, (first * bytes : Int64));
		if (n > first) LibC.memcpy(data, buffer.add(first * bytes), ((n - first) * bytes : Int64));
		Atomic.store32(ring.add(WRITTEN), written + n);
		return true;
	}

	// the audio thread
	function run() {
		var sem = Mem.getPtr(ring, SEM);
		try {
			while (!quit)
				if (!produce()) DispatchWait.dispatch_semaphore_wait(sem, Dispatch.dispatch_time(0, 100000000));
		} catch (e:Dynamic) {
			error = Std.string(e);
		}
		done.release();
	}

	// "file:": the generic unit rendered a period at a time, at the clock's
	// pace, into the file
	function renderFile() {
		var n = owner.frames, count = n * owner.channels;
		var out = sys.io.File.write(path);
		var bytes = haxe.io.Bytes.alloc(count * 4);
		var list = LibC.malloc(24), time = LibC.malloc(64), flags:Ptr<Int32> = LibC.malloc(4);
		var target:Ptr<Float32> = LibC.malloc((count * 4 : Int64));
		var rendered = 0, t0 = Sys.time();
		try {
			while (!quit) {
				while (!quit && Atomic.load32(ring.add(WRITTEN)) - Atomic.load32(ring.add(READ)) < n)
					Sys.sleep(0.001);
				if (quit) break;
				Mem.setI32(list, 0, 1); // mNumberBuffers
				Mem.setI32(list, 8, owner.channels);
				Mem.setI32(list, 12, count * 4);
				Mem.setPtr(list, 16, target);
				LibC.memset(time, 0, 64);
				Mem.setF64(time, 0, rendered); // mSampleTime
				Mem.setI32(time, 56, CA.kAudioTimeStampSampleTimeValid); // mFlags
				flags.value = 0;
				var st = AudioToolbox.AudioUnitRender(unit, flags, time, 0, n, list);
				if (st != 0) throw "AudioUnitRender failed (OSStatus " + st + ")";
				var p:Ptr<Float32> = Mem.getPtr(list, 16);
				for (i in 0...count)
					bytes.setFloat(i * 4, p[i]);
				out.writeBytes(bytes, 0, bytes.length);
				rendered += n;
				var wait = t0 + rendered / owner.sampleRate - Sys.time();
				if (wait > 0) Sys.sleep(wait);
			}
		} catch (e:Dynamic) {
			error = Std.string(e);
		}
		out.close();
		LibC.free(list);
		LibC.free(time);
		LibC.free(flags);
		LibC.free(target);
		done.release();
	}

	function stop() {
		quit = true;
		Dispatch.dispatch_semaphore_signal(Mem.getPtr(ring, SEM));
		if (path == null) AudioToolbox.AudioOutputUnitStop(unit);
		done.wait();
		if (path != null) done.wait();
		if (error != null) throw "helder.os.audio: " + error;
	}

	function close() {
		AudioToolbox.AudioUnitUninitialize(unit);
		AudioToolbox.AudioComponentInstanceDispose(unit);
		Dispatch.dispatch_release(Mem.getPtr(ring, SEM));
		LibC.free(Mem.getPtr(ring, DATA));
		LibC.free(ring);
		LibC.free(buffer);
	}
}
