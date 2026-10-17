import haxe.io.Bytes;
import hxmc.os.audio.Audio;
import hxmc.unsafe.*;

// Audio output through each back end's real API, checked without speakers
// (make audio-check, packages/os/test/audio.sh):
//
//   AudioTest <device> <frames> [--rate] [--expect <file>]
//     opens the output (device: "default", "file:PATH", or an ALSA PCM
//     name), plays `frames` frames of a known signal (a 440 Hz sine left,
//     660 Hz right), then stops; checks that each callback asked for at most
//     Audio.frames frames and that the callbacks covered all of them; with
//     --rate, that they came at the sample rate (within RATE_TOLERANCE,
//     once the buffer is full: a device or a sink that paces); with
//     --expect, that <file> (raw interleaved floats: an ALSA file plugin's or
//     the "file:" device's) holds the signal, from its first sample, within
//     SAMPLE_TOLERANCE (exact through ALSA alone; Wine converts and mixes)
//
// Exit codes: 0 passed, 1 failed, 3 no output device (the system says so:
// a runner without audio).
class AudioTest {
	static inline var RATE = 48000;
	static inline var CHANNELS = 2;
	static inline var RATE_TOLERANCE = 0.1;
	static inline var SAMPLE_TOLERANCE = 1e-3;

	// the callback's state, read by the main thread when it ends
	static var out:Audio;
	static var wanted = 0;
	static var produced = 0;
	static var calls = 0;
	static var tooMany = 0;
	static var firstCall = 0.0;
	static var lastCall = 0.0;
	static var silence = 0;
	static var finished = false;
	static var rate = false;
	static var expect:Null<String>;

	public static inline function sample(n:Int, ch:Int):Float
		return ch == 0 ? 0.5 * Math.sin(2 * Math.PI * 440 * n / RATE) : 0.25 * Math.sin(2 * Math.PI * 660 * n / RATE);

	// the audio thread: the signal until `wanted` frames, then silence
	static function fill(buffer:Ptr<Float32>, frames:Int) {
		var now = Sys.time();
		if (calls == 0) firstCall = now;
		calls++;
		if (frames > out.frames) tooMany++;
		if (produced >= wanted) {
			// (then silence, until what was queued has played; once that is done,
			// a sink that does not pace need not spin until the main thread sees it)
			if (finished && Mem.os() != 3) Sys.sleep(0.001);
			silence += frames;
			if (silence >= out.latency * RATE + 2 * out.frames && !finished) {
				finished = true;
				// (the browser: no thread waits for the end, the callback reports)
				if (Mem.os() == 3) end();
			}
			return;
		}
		lastCall = now;
		var n = frames < wanted - produced ? frames : wanted - produced;
		for (i in 0...n)
			for (ch in 0...CHANNELS)
				buffer[i * CHANNELS + ch] = sample(produced + i, ch);
		produced += n;
	}

	static function main() {
		var args = Sys.args();
		if (args.length < 2) {
			Sys.println("usage: AudioTest <device> <frames> [--rate] [--expect <file>]");
			Sys.exit(2);
		}
		var device = args[0] == "default" ? null : args[0];
		wanted = Std.parseInt(args[1]);
		rate = args.indexOf("--rate") >= 0;
		var e = args.indexOf("--expect");
		expect = e >= 0 ? args[e + 1] : null;
		try {
			out = Audio.open({sampleRate: RATE, channels: CHANNELS, frames: 512, device: device}, fill);
		} catch (e:Dynamic) {
			var s = Std.string(e);
			Sys.println("AudioTest: " + s);
			// (no endpoint: AUDCLNT_E_DEVICE_INVALIDATED, E_NOTFOUND; CoreAudio: no default device)
			Sys.exit(s.indexOf("no output device") >= 0 ? 3 : 1);
		}
		Sys.println('AudioTest: ${device == null ? "default" : device}: ${out.sampleRate} Hz, ${out.channels} channels, ${out.frames} frames a callback, latency ${Math.round(out.latency * 1000)} ms');
		var t0 = Sys.time();
		out.start();
		if (Mem.os() == 3) return;
		var limit = wanted / RATE + out.latency + 10;
		while (!finished && Sys.time() - t0 < limit)
			Sys.sleep(0.01);
		end();
	}

	static function end() {
		out.close();
		var ok = true;
		function fail(s:String) {
			Sys.println("AudioTest: FAILED: " + s);
			ok = false;
		}
		Sys.println('AudioTest: ${calls} callbacks, ${produced} frames in ${Math.round((lastCall - firstCall) * 1000)} ms');
		if (out.sampleRate != RATE) fail('the rate is ${out.sampleRate}, not $RATE');
		if (produced < wanted) fail('the callbacks produced $produced frames of $wanted');
		if (tooMany > 0) fail('$tooMany callbacks asked for more than ${out.frames} frames');
		if (rate) {
			// (the first buffer's length comes at once; the rest at the device's pace)
			var paced = wanted - out.latency * RATE, measured = paced / (lastCall - firstCall);
			Sys.println('AudioTest: ${Math.round(measured)} frames per second');
			if (Math.abs(measured / RATE - 1) > RATE_TOLERANCE) fail('callbacks came at $measured frames per second, not $RATE');
		}
		if (expect != null && !compare(expect)) ok = false;
		Sys.println(ok ? "AudioTest: passed" : "AudioTest: failed");
		Sys.exit(ok ? 0 : 1);
	}

	// the signal in a file of raw floats, from its first sample that is not
	// silence (Wine's mixer starts with some)
	static function compare(path:String):Bool {
		var b = sys.io.File.getBytes(path), n = b.length >> 2;
		var start = 0;
		while (start < n && b.getFloat(start * 4) == 0)
			start++;
		// (the signal's first sample is 0 on both channels: one frame back)
		start = start - start % CHANNELS - CHANNELS;
		if (start < 0) start = 0;
		var frames = Std.int((n - start) / CHANNELS);
		Sys.println('AudioTest: $path: ${n >> 1} frames, the signal from frame ${start >> 1}');
		if (frames < wanted) {
			Sys.println('AudioTest: FAILED: $path has $frames frames of the signal, not $wanted');
			return false;
		}
		var worst = 0.0, at = 0;
		for (i in 0...wanted)
			for (ch in 0...CHANNELS) {
				var d = Math.abs(b.getFloat((start + i * CHANNELS + ch) * 4) - sample(i, ch));
				if (d > worst) {
					worst = d;
					at = i;
				}
			}
		Sys.println('AudioTest: largest difference $worst (frame $at)');
		if (worst > SAMPLE_TOLERANCE) {
			Sys.println('AudioTest: FAILED: $path differs from the signal by $worst at frame $at');
			return false;
		}
		return true;
	}
}
