package helder.os.audio;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.test.Test;

// Wav: PCM of each width and floats read to -1...1, interleaved; chunks
// before the data skipped (an odd one's pad too); EXTENSIBLE's sub
// format; mono(rate) averaging the channels and resampling; what it
// cannot read refused
function tests() {
	function wav(format:Int, channels:Int, rate:Int, bits:Int, data:Bytes, ?extra:Bytes, extensible = false):Bytes {
		var fmt = new BytesBuffer();
		fmt.addInt32(0); // (patched below)
		var body = new BytesBuffer();
		body.addString("WAVE");
		if (extra != null) {
			body.addString("LIST");
			body.addInt32(extra.length);
			body.add(extra);
			if (extra.length & 1 == 1) body.addByte(0);
		}
		body.addString("fmt ");
		body.addInt32(extensible ? 40 : 16);
		body.addByte((extensible ? 0xFFFE : format) & 0xff);
		body.addByte((extensible ? 0xFFFE : format) >> 8);
		body.addByte(channels);
		body.addByte(0);
		body.addInt32(rate);
		body.addInt32(rate * channels * (bits >> 3));
		body.addByte(channels * (bits >> 3));
		body.addByte(0);
		body.addByte(bits);
		body.addByte(0);
		if (extensible) {
			body.addByte(22);
			body.addByte(0);
			body.addByte(bits);
			body.addByte(0);
			body.addInt32(0);
			body.addByte(format);
			body.addByte(0);
			for (_ in 0...14) body.addByte(0);
		}
		body.addString("data");
		body.addInt32(data.length);
		body.add(data);
		var b = body.getBytes(), out = new BytesBuffer();
		out.addString("RIFF");
		out.addInt32(b.length);
		out.add(b);
		return out.getBytes();
	}
	function bytes(values:Array<Int>):Bytes {
		var b = Bytes.alloc(values.length);
		for (i in 0...values.length) b.set(i, values[i] & 0xff);
		return b;
	}
	describe("Wav", () -> {
		test("16-bit PCM, stereo", () -> {
			var w = Wav.decode(wav(1, 2, 44100, 16, bytes([0x00, 0x40, 0x00, 0xC0, 0xFF, 0x7F, 0x00, 0x80])));
			equals([w.rate, w.channels, w.frames], [44100, 2, 2]);
			equals(w.samples, [0.5, -0.5, 32767 / 32768, -1.0]);
		});
		test("8, 24 and 32 bits", () -> {
			equals(Wav.decode(wav(1, 1, 8000, 8, bytes([128, 192, 0]))).samples, [0.0, 0.5, -1.0]);
			equals(Wav.decode(wav(1, 1, 8000, 24, bytes([0, 0, 0x40, 0, 0, 0xC0]))).samples, [0.5, -0.5]);
			equals(Wav.decode(wav(1, 1, 8000, 32, bytes([0, 0, 0, 0x40]))).samples, [0.5]);
		});
		test("floats", () -> {
			var b = Bytes.alloc(8);
			b.setFloat(0, 0.25);
			b.setFloat(4, -0.75);
			equals(Wav.decode(wav(3, 1, 48000, 32, b)).samples, [0.25, -0.75]);
		});
		test("chunks before the data skipped, an odd one's pad too", () ->
			equals(Wav.decode(wav(1, 1, 8000, 8, bytes([192]), bytes([1, 2, 3]))).samples, [0.5]));
		test("EXTENSIBLE's sub format", () -> equals(Wav.decode(wav(1, 1, 8000, 16, bytes([0x00, 0x40]), null, true)).samples, [0.5]));
		test("mono: the channels averaged, resampled", () -> {
			var w = Wav.decode(wav(1, 2, 1000, 16, bytes([0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40])));
			equals(w.mono(1000), [0.25, 0.25]);
			var up = Wav.decode(wav(1, 1, 1000, 8, bytes([128, 192]))).mono(2000);
			equals(up.length, 4);
			approx(up[1], 0.25, 1e-9);
		});
		test("what it cannot read", () -> {
			throws(() -> Wav.decode(Bytes.ofString("not a wave file")));
			throws(() -> Wav.decode(wav(2, 1, 8000, 4, bytes([0]))));
		});
	});
}
