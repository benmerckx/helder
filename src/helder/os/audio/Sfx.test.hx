package helder.os.audio;

import helder.test.Test;
import hxmc.unsafe.*;

// Sfx, short effects mixed by voices: a sound at its gain and the master
// volume, on both channels; a rate reading it faster; voices summed and
// clipped; a voice silent at its sound's end; the oldest voice taken when
// all play; nothing allocated in a mix (offline: no output, mixed by hand;
// natively and as wasm32-wasi).
function tests() {
	describe("Sfx", () -> {
		var buf:Ptr<Float32> = LibC.malloc(4 * 2 * 64);
		function mix(s:Sfx, frames:Int) {
			LibC.memset(buf, 0, 4 * 2 * 64);
			s.mix(buf, frames);
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
		test("a mix allocates nothing", () -> {
			var s = Sfx.offline();
			var id = s.add([for (i in 0...10000) Math.sin(i * 0.1)]);
			s.play(id, 0.8, 1.3);
			mix(s, 64);
			var before = hxmc.GcStats.bytesAllocated();
			for (_ in 0...20)
				mix(s, 64);
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
		});
	});
}
