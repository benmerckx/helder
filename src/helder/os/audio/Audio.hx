package helder.os.audio;

import hxmc.unsafe.*;

typedef AudioConfig = {
	// frames per second (default 48000)
	@:optional var sampleRate:Int;
	// interleaved channels (default 2)
	@:optional var channels:Int;
	// the frames of a callback, a hint (default 512): the system rounds it
	@:optional var frames:Int;
	// the output: null, the system's default; "file:PATH", no device: what
	// the system's API renders goes to PATH as raw interleaved 32-bit floats
	// (tests: Linux and macOS, see below); on Linux another name is ALSA's
	// (a PCM such as "null" or "hw:0")
	@:optional var device:String;
	// iOS: the AVAudioSession's category, set before the first output
	// opens: "ambient" (default: mixed with other apps, silent with the
	// ring/silent switch) or "playback" (heard with the switch on silent)
	@:optional var session:String;
}

// The callback: fill `frames` frames of interleaved samples (channels
// Float32 each, -1 to 1) at `buffer`, zeroed before the call.
typedef AudioFill = (buffer:Ptr<Float32>, frames:Int) -> Void;

// Audio output, pull model: once started, the system asks for samples as
// it needs them and fill runs on the audio thread, for as many frames as
// it asks (at most `frames`). Back ends: ALSA on Linux (AlsaOutput;
// libasound.so.2, loaded at run time, so the glibc mode, -D
// hxmc.libc=glibc: a static build does not link dlopen), CoreAudio's output
// unit on macOS (CoreAudioOutput) and RemoteIO on iOS (the same, with
// AudioSession), AAudio on Android (AAudioOutput; libaaudio.so, loaded at
// run time), WASAPI in shared mode on Windows
// (WasapiOutput), WebAudio in the browser (WebAudioOutput).
//
// The audio thread is one of the runtime's (sys.thread.Thread), made by
// start: fill is ordinary Haxe and may touch GC objects, but it runs
// against a deadline (frames / sampleRate seconds), so it should not
// allocate (an allocation can start a collection; any thread's collection
// stops this one too, briefly), lock what other threads hold long, block or
// print. Preallocate, and pass state through fields or atomics. It must not
// stop or close the output itself (both wait for the audio thread to end).
// The system's own audio threads, where it has them (CoreAudio's render
// callback), never run Haxe code that may collect: they only copy what the
// audio thread filled, in @:hxmc.noGc code (hxmc's docs/plans/lowlevel.md, "Callbacks").
// In the browser fill runs on the main thread (no threads there), when the
// audio worklet has played a chunk, ahead of the output by `latency`; there
// it may close the output.
@:allow(helder.os.audio)
class Audio {
	public var sampleRate(default, null):Int;
	public var channels(default, null):Int;
	// the most frames a callback fills (the system's period)
	public var frames(default, null):Int;
	// seconds from a callback's samples to the output: the buffer ahead of
	// the device, as the system reports it
	public var latency(default, null):Float = 0;
	public var running(default, null) = false;
	public var closed(default, null) = false;

	// iOS's session category (AudioConfig.session)
	public final session:Null<String>;
	// held by the app's lifecycle (Android's activity paused, iOS's app in
	// the background or interrupted): stopped, to start again on the way back
	public var held(default, null) = false;

	// the outputs open (the lifecycle's hold reaches them)
	static var outputs:Null<Array<Audio>>;

	final fill:AudioFill;
	// the back end, the target's (as Window's: Mem.os() is known when compiling)
	final native:Any;

	public static function open(config:AudioConfig, fill:AudioFill):Audio
		return new Audio(config, fill);

	function new(config:AudioConfig, fill:AudioFill) {
		this.fill = fill;
		sampleRate = config.sampleRate != null ? config.sampleRate : 48000;
		channels = config.channels != null ? config.channels : 2;
		frames = config.frames != null ? config.frames : 512;
		session = config.session;
		if (sampleRate <= 0 || channels <= 0 || frames <= 0) throw "helder.os.audio: bad config";
		native = Mem.target() >= 9 ? new AAudioOutput(this, config.device) : Mem.os() == 1 ? new CoreAudioOutput(this, config.device) : Mem.os() == 2 ? new WasapiOutput(this,
			config.device) : Mem.os() == 3 ? new WebAudioOutput(this, config.device) : new AlsaOutput(this, config.device);
		track();
	}

	public function start() {
		if (running || closed) return;
		running = true;
		if (Mem.target() >= 9) (cast native : AAudioOutput).start() else if (Mem.os() == 1) (cast native : CoreAudioOutput).start() else if (Mem.os() == 2) (cast native : WasapiOutput).start() else if (Mem.os() == 3)
			(cast native : WebAudioOutput).start() else (cast native : AlsaOutput).start();
	}

	// stops the output (what the system has queued is dropped); start plays again
	public function stop() {
		held = false;
		if (!running) return;
		running = false;
		if (Mem.target() >= 9) (cast native : AAudioOutput).stop() else if (Mem.os() == 1) (cast native : CoreAudioOutput).stop() else if (Mem.os() == 2) (cast native : WasapiOutput).stop() else if (Mem.os() == 3)
			(cast native : WebAudioOutput).stop() else (cast native : AlsaOutput).stop();
	}

	public function close() {
		if (closed) return;
		stop();
		closed = true;
		if (outputs != null) outputs.remove(this);
		if (Mem.target() >= 9) (cast native : AAudioOutput).close() else if (Mem.os() == 1) (cast native : CoreAudioOutput).close() else if (Mem.os() == 2) (cast native : WasapiOutput).close() else if (Mem.os() == 3)
			(cast native : WebAudioOutput).close() else (cast native : AlsaOutput).close();
	}

	// the data callbacks the system made so far, where the back end counts
	// them (Android; elsewhere -1): tests, the stream started
	public function systemCalls():Int
		return Mem.target() >= 9 ? (cast native : AAudioOutput).calls() : -1;

	function track() {
		if (outputs == null) outputs = [];
		outputs.push(this);
		if (Mem.target() >= 9 || Mem.platform() >= 1) helder.os.AppAudio.hold = hold;
	}

	// the app's lifecycle (helder.os.AppAudio.hold: Android's activity
	// paused and resumed, iOS's app in the background and back): the
	// running outputs stopped, those held started again
	public static function hold(on:Bool) {
		if (outputs == null) return;
		for (o in outputs.copy())
			if (on && o.running) {
				o.stop();
				o.held = true;
			} else if (!on && o.held) {
				o.held = false;
				o.start();
			}
	}

	// iOS: an interruption (a call) began or ended (AudioSession): the
	// system stopped the units; held as by the lifecycle, then started again
	static function interrupted(began:Bool)
		hold(began);

	// (the back ends: the callback, on the audio thread, over a zeroed buffer)
	inline function pull(buffer:Ptr<Float32>, n:Int) {
		LibC.memset(buffer, 0, (n * channels * 4 : Int64));
		fill(buffer, n);
	}
}
