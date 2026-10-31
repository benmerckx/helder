// helder.os.audio on a phone (CI's emulator and simulator jobs,
// tests/pack/android.sh and ios.sh): an output opened on the system's
// default (AAudio on Android, RemoteIO on iOS), a quiet tone for two
// seconds, then a line of what the system pulled: the mix's callbacks
// (each a period; the ring holds a few before the stream starts, so more
// than those is the device pulling), the system's own data callbacks where
// the back end counts them (Android), the frames and the rate. "audio:
// started" when the device pulled at least half a second's worth.
class AudioCheck {
	static var calls = 0;
	static var frames = 0;
	static var phase = 0.0;

	static function main() {
		#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		helder.os.android.Activity.activity;
		#end
		var out = try helder.os.audio.Audio.open({sampleRate: 48000, channels: 2, frames: 256}, (buffer, n) -> {
			calls++;
			frames += n;
			for (i in 0...n) {
				var v = 0.05 * Math.sin(phase);
				buffer[i * 2] = v;
				buffer[i * 2 + 1] = v;
				phase += 2 * Math.PI * 440 / 48000;
			}
		}) catch (e:Dynamic) {
			Sys.println('audio: no output: $e');
			return;
		}
		out.start();
		var t0 = Sys.time();
		Sys.sleep(2);
		var seconds = Sys.time() - t0;
		var c = calls, f = frames, sys = out.systemCalls();
		out.stop();
		out.close();
		var ok = f >= out.sampleRate / 2;
		Sys.println('audio: ${ok ? "started" : "stalled"}: $c callbacks, $f frames in ${Math.round(seconds * 10) / 10} s at ${out.sampleRate} Hz, system callbacks $sys, latency ${Math.round(out.latency * 1000)} ms');
	}
}
