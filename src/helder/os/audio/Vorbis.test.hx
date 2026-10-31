package helder.os.audio;

import haxe.crypto.Base64;
import haxe.io.Bytes;
import helder.os.audio.VorbisFixture;
import helder.test.Test;

// Vorbis: two files ffmpeg's libvorbis wrote (VorbisFixture: stereo at
// 44.1 kHz with short and long blocks, mono at 48 kHz) decoded to what
// ffmpeg's decoder gives, within a float's rounding; the length from the
// last page's granule position; rewind decoding the same again; next()
// allocating nothing; Sound.decode picking Vorbis or WAV by the first
// bytes; what it cannot read refused (natively and as wasm32-wasi)
function tests() {
	function check(ogg:String, ref:Array<Float>, step:Int, rate:Int, channels:Int, frames:Int) {
		var w = Vorbis.decode(Base64.decode(ogg));
		equals([w.rate, w.channels, w.frames], [rate, channels, frames]);
		var worst = 0.0;
		for (k in 0...Std.int(ref.length / channels))
			for (c in 0...channels) {
				var d = Math.abs(w.samples[k * step * channels + c] - ref[k * channels + c]);
				if (d > worst) worst = d;
			}
		assert(worst < 2e-6, 'largest difference $worst');
	}
	describe("Vorbis", () -> {
		test("stereo, short and long blocks, as ffmpeg decodes it", () -> check(STEREO_OGG, STEREO_REF, STEREO_STEP, 44100, 2, 33075));
		test("mono at 48 kHz", () -> check(MONO_OGG, MONO_REF, MONO_STEP, 48000, 1, 19200));
		test("rewind: the same samples again", () -> {
			var v = Vorbis.open(Base64.decode(STEREO_OGG));
			var first = [], n;
			while ((n = v.next()) >= 0)
				for (i in 0...n)
					first.push(v.out[1][i]);
			v.rewind();
			var again = [];
			while ((n = v.next()) >= 0)
				for (i in 0...n)
					again.push(v.out[1][i]);
			equals(again.length, first.length);
			equals(again[20000], first[20000]);
			equals(v.length, 33075);
		});
		test("a packet decoded allocates nothing", () -> {
			var v = Vorbis.open(Base64.decode(STEREO_OGG));
			for (_ in 0...4)
				v.next();
			var before = hxmc.GcStats.bytesAllocated();
			var frames = 0;
			for (_ in 0...20)
				frames += v.next();
			v.rewind();
			v.next();
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
			assert(frames > 0);
		});
		test("Sound.decode: Vorbis or WAV by the first bytes", () -> {
			equals(Sound.decode(Base64.decode(MONO_OGG)).frames, 19200);
			throws(() -> Sound.decode(Bytes.ofString("neither")));
		});
		test("what it cannot read", () -> {
			throws(() -> Vorbis.open(Bytes.ofString("OggS but nothing after it, not a page at all")));
			var b = Base64.decode(MONO_OGG);
			// (the setup header's codebook sync pattern broken)
			var cut = b.sub(0, 120);
			throws(() -> Vorbis.open(cut));
		});
	});
}
