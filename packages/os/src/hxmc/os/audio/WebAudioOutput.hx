package hxmc.os.audio;

import hxmc.unsafe.*;

// hxmc.os.audio.Audio in the browser (WebAssembly): an AudioContext whose
// AudioWorklet node plays chunks of samples the page posts it, through the
// imports of WebAudio (packages/os/imports.mjs). The module's memory is not
// shared with the worklet's thread (no threads: no SharedArrayBuffer), so
// the samples are copied: the main thread calls fill (a callback through the
// module's function table) for a chunk of Audio.frames frames whenever the
// worklet has played one, keeping `latency` of them queued; a chunk late
// (the main thread busy) is silence. In an OfflineAudioContext (browser.mjs's
// option audioContext: tests) start fills its whole length at once.
@:allow(hxmc.os.audio)
class WebAudioOutput {
	static final open:Array<WebAudioOutput> = [];

	final owner:Audio;
	final handle:Int;
	final buffer:Ptr<Float32>;

	function new(owner:Audio, device:Null<String>) {
		this.owner = owner;
		if (device != null) throw "hxmc.os.audio: WebAudio plays on the page's output only (device " + device + ")";
		buffer = LibC.malloc((owner.frames * owner.channels * 4 : Int64));
		handle = WebAudio.audio_open(owner.sampleRate, owner.channels, owner.frames, buffer, Callback.addr(fill));
		if (handle == 0) throw "hxmc.os.audio: no WebAudio (AudioContext, AudioWorklet)";
		owner.sampleRate = WebAudio.audio_rate(handle);
		owner.latency = WebAudio.audio_latency(handle);
		open.push(this);
	}

	// a chunk for the worklet, into buffer
	@:hxmc.callback static function fill(handle:Int, frames:Int):Int {
		for (o in open)
			if (o.handle == handle) {
				o.owner.pull(o.buffer, frames);
				// (what the callback printed, now: the module's stdout is buffered)
				Sys.stdout().flush();
			}
		return 0;
	}

	function start()
		WebAudio.audio_start(handle);

	function stop()
		WebAudio.audio_stop(handle);

	function close() {
		open.remove(this);
		WebAudio.audio_close(handle);
		LibC.free(buffer);
	}
}

// The browser's side of hxmc.os.audio: imports of the module "hxmc_os"
// (packages/os/imports.mjs). Outputs are handles into the loader's table.
@:hxmc.c @:hxmc.lib("hxmc_os") extern class WebAudio {
	// an output of `channels` channels at sampleRate: fill (a @:hxmc.callback
	// (handle, frames):Int) writes a chunk of `frames` frames at buffer
	// (interleaved floats); 0: no WebAudio
	static function audio_open(sampleRate:Int, channels:Int, frames:Int, buffer:Ptr<Float32>, fill:Ptr):Int;
	// the context's rate (it may not take the one asked for)
	static function audio_rate(output:Int):Int;
	// seconds: the chunks kept queued, and the context's own latency
	static function audio_latency(output:Int):Float;
	static function audio_start(output:Int):Void;
	static function audio_stop(output:Int):Void;
	static function audio_close(output:Int):Void;
}
