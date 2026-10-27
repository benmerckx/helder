// title: Tone
// summary: A 440 Hz sine for two seconds from an audio callback that allocates nothing: WebAudio here, ALSA, Core Audio or WASAPI natively
// tags: os, audio
// demo: sound
import helder.os.audio.Audio;
import hxmc.unsafe.*;

// A 440 Hz sine for two seconds, on the default output:
//
//   haxe -cp src -cp examples -main Tone
//     --custom-target hxmc=tone -D hxmc.libc=glibc
//
// (macOS and Windows: without -D hxmc.libc=glibc. The browser: -D
// hxmc.target=wasm32-wasi, run by src/helder/os/browser.mjs with
// src/helder/os/imports.mjs: main returns at once, so the callback ends the
// tone; a page starts audio after a click or a key, the browsers' rule.)
// The callback runs on the audio thread: it keeps its phase in a field and
// allocates nothing.
class Tone {
	static inline var FREQUENCY = 440.0;
	static inline var SECONDS = 2.0;

	var phase = 0.0;
	var played = 0;
	var out:Audio;

	function new() {
		out = Audio.open({sampleRate: 48000, channels: 2, frames: 512}, fill);
		trace('${out.sampleRate} Hz, ${out.channels} channels, ${out.frames} frames a callback, latency ${Math.round(out.latency * 1000)} ms');
		out.start();
	}

	function fill(buffer:Ptr<Float32>, frames:Int) {
		var step = 2 * Math.PI * FREQUENCY / out.sampleRate, c = out.channels;
		for (i in 0...frames) {
			var v = 0.25 * Math.sin(phase);
			for (ch in 0...c)
				buffer[i * c + ch] = v;
			phase += step;
			if (phase > 2 * Math.PI) phase -= 2 * Math.PI;
		}
		played += frames;
		// (the browser's callback runs on the main thread: it may close the
		// output; a native one must not, close waits for the audio thread)
		if (Mem.os() == 3 && played >= SECONDS * out.sampleRate) out.close();
	}

	static function main() {
		var tone = new Tone();
		if (Mem.os() == 3) return;
		Sys.sleep(SECONDS);
		tone.out.close();
	}
}
