package helder.os.audio;

import haxe.crypto.Base64;
import helder.os.audio.VorbisFixture;
import helder.test.Test;
import hxmc.unsafe.*;

// Sfx, short effects mixed by voices: a sound at its gain and the master
// volume, on both channels; a rate reading it faster; voices summed and
// clipped; a voice silent at its sound's end; the oldest voice taken when
// all play; a pan; a loop until stopped, its gain changed; music streamed
// from Vorbis, faded in, crossfaded, looping, stopped; nothing allocated in
// a mix, music's decoding included (offline: no output, mixed by hand;
// natively and as wasm32-wasi).
function tests() {
	describe("Sfx", () -> {
		var buf:Ptr<Float32> = LibC.malloc(4 * 2 * 4096);
		function mix(s:Sfx, frames:Int) {
			LibC.memset(buf, 0, 4 * 2 * frames);
			s.mix(buf, frames);
		}
		// the largest |sample| of a channel over a mix of `frames`
		function peak(s:Sfx, frames:Int, ch:Int):Float {
			mix(s, frames);
			var m = 0.0;
			for (i in 0...frames)
				m = Math.max(m, Math.abs(buf[i * 2 + ch]));
			return m;
		}
		test("a sound at its gain, on both channels", () -> {
			var s = Sfx.offline();
			s.volume = 1;
			var id = s.add([for (i in 0...100) i / 100]);
			s.play(id, 0.5);
			mix(s, 10);
			approx(buf[2 * 4], 0.5 * 0.04, 1e-6);
			approx(buf[2 * 4 + 1], 0.5 * 0.04, 1e-6);
		});
		test("a rate of 2 reads it twice as fast", () -> {
			var s = Sfx.offline();
			s.volume = 1;
			var id = s.add([for (i in 0...100) i / 100]);
			s.play(id, 1, 2);
			mix(s, 10);
			approx(buf[2 * 4], 0.08, 1e-6);
		});
		test("voices summed, clipped at 1", () -> {
			var s = Sfx.offline();
			s.volume = 1;
			var id = s.add([for (_ in 0...100) 0.6]);
			s.play(id);
			mix(s, 1);
			approx(buf[0], 0.6, 1e-6);
			s.play(id);
			mix(s, 1);
			approx(buf[0], 1, 1e-6);
		});
		test("silent after its end; the oldest voice taken when all play", () -> {
			var s = Sfx.offline();
			s.volume = 1;
			var short = s.add([1, 1, 1, 1]);
			s.play(short);
			mix(s, 10);
			mix(s, 10);
			equals((buf[0] : Float), 0.0);
			var long = s.add([for (_ in 0...1000) 0.01]);
			for (_ in 0...Sfx.VOICES + 3)
				s.play(long);
			mix(s, 1);
			approx(buf[0], 0.01 * Sfx.VOICES, 1e-6);
		});
		test("a pan: the other side down", () -> {
			var s = Sfx.offline();
			s.volume = 1;
			var id = s.add([for (_ in 0...100) 0.5]);
			s.play(id, 1, 1, -0.5);
			mix(s, 1);
			approx(buf[0], 0.5, 1e-6);
			approx(buf[1], 0.25, 1e-6);
		});
		test("a loop until stopped; its gain changed", () -> {
			var s = Sfx.offline();
			s.volume = 1;
			var id = s.add([for (_ in 0...10) 0.5]);
			var h = s.loop(id);
			mix(s, 64);
			approx(buf[63 * 2], 0.5, 1e-6);
			assert(s.active(h));
			s.gain(h, 0.5);
			mix(s, 1);
			approx(buf[0], 0.25, 1e-6);
			s.stop(h);
			mix(s, 1);
			equals((buf[0] : Float), 0.0);
			assert(!s.active(h));
			// (a stale handle: another voice's play not stopped)
			var other = s.play(id);
			s.stop(h);
			assert(s.active(other));
		});
		test("music: faded in, crossfaded, looping, stopped", () -> {
			var s = Sfx.offline();
			s.musicVolume = 1;
			s.music(Base64.decode(MONO_OGG), 0.01);
			assert(s.musicPlaying());
			// (the sweep at 0.3: faded in within a hundredth of a second)
			var p = peak(s, 4096, 0);
			assert(p > 0.2 && p < 0.35, 'peak $p');
			s.music(Base64.decode(STEREO_OGG), 0.5);
			// (both at once while they cross)
			mix(s, 2048);
			equals(s.musicTracks(), 2);
			// (the first gone after the fade; the second looping on past its 0.75 s)
			for (_ in 0...30)
				mix(s, 2048);
			equals(s.musicTracks(), 1);
			assert(peak(s, 2048, 0) > 0.3);
			s.stopMusic(0.01);
			mix(s, 2048);
			equals(peak(s, 256, 0), 0.0);
			assert(!s.musicPlaying());
		});
		test("music at another rate: resampled", () -> {
			var s = Sfx.offline();
			s.musicVolume = 1;
			s.music(Base64.decode(STEREO_OGG), 0, 1, false);
			// (0.75 s at 44.1 kHz: 36000 frames at 48 kHz, then silence)
			var frames = 0;
			for (_ in 0...12) {
				mix(s, 4096);
				for (i in 0...4096)
					if (buf[i * 2] != 0) frames = Std.int(Math.max(frames, (_ * 4096) + i + 1));
			}
			assert(Math.abs(frames - 36000) < 50, 'frames $frames');
		});
		test("a mix allocates nothing", () -> {
			var s = Sfx.offline();
			var id = s.add([for (i in 0...10000) Math.sin(i * 0.1)]);
			s.play(id, 0.8, 1.3);
			mix(s, 64);
			s.music(Base64.decode(STEREO_OGG), 0.1);
			var l = s.loop(id, 0.5, 1, 0.3);
			mix(s, 512);
			for (_ in 0...200)
				mix(s, 512);
			s.music(Base64.decode(MONO_OGG), 0.1);
			var made = hxmc.GcStats.bytesAllocated();
			for (_ in 0...200)
				mix(s, 512);
			equals(hxmc.GcStats.bytesAllocated() - made, 0.0);
		});
	});
}
