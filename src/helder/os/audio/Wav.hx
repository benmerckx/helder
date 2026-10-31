package helder.os.audio;

import haxe.io.Bytes;

// A RIFF WAVE file decoded: PCM of 8, 16, 24 or 32 bits, or IEEE floats of
// 32 or 64 (WAVE_FORMAT_PCM, _IEEE_FLOAT, and _EXTENSIBLE naming either),
// any number of channels; other chunks (LIST, fact, cue, pads) skipped,
// odd chunks' pad byte too. The samples are floats from -1 to 1,
// interleaved; mono(rate) mixes them down and resamples them (linearly)
// for Sfx, whose sounds are mono at Sfx.RATE:
//
//   var laser = sfx.add(Wav.decode(Asset.sound("audio/laser.wav").load()).mono(Sfx.RATE));
//
// A file it cannot read throws a String naming why.
class Wav {
	public final rate:Int;
	public final channels:Int;
	// the frames (samples a channel)
	public final frames:Int;
	// the samples, interleaved: frames * channels
	public final samples:Array<Float>;

	function new(rate, channels, frames, samples) {
		this.rate = rate;
		this.channels = channels;
		this.frames = frames;
		this.samples = samples;
	}

	// samples already decoded (Vorbis.decode)
	public static function of(rate:Int, channels:Int, frames:Int, samples:Array<Float>):Wav
		return new Wav(rate, channels, frames, samples);

	public static function decode(b:Bytes):Wav {
		if (b.length < 12 || b.getString(0, 4) != "RIFF" || b.getString(8, 4) != "WAVE") throw "helder.os.audio.Wav: not a RIFF WAVE file";
		var format = -1, channels = 0, rate = 0, bits = 0, align = 0;
		var i = 12;
		while (i + 8 <= b.length) {
			var id = b.getString(i, 4), size = b.getInt32(i + 4), body = i + 8;
			if (size < 0 || body + size > b.length) size = b.length - body;
			if (id == "fmt ") {
				if (size < 16) throw "helder.os.audio.Wav: a short fmt chunk";
				format = b.getUInt16(body);
				channels = b.getUInt16(body + 2);
				rate = b.getInt32(body + 4);
				align = b.getUInt16(body + 12);
				bits = b.getUInt16(body + 14);
				// (WAVE_FORMAT_EXTENSIBLE: its sub format's first two bytes are the format)
				if (format == 0xFFFE && size >= 26) format = b.getUInt16(body + 24);
			} else if (id == "data") {
				if (format < 0) throw "helder.os.audio.Wav: data before fmt";
				return read(b, body, size, format, channels, rate, bits, align);
			}
			i = body + size + (size & 1);
		}
		throw "helder.os.audio.Wav: no data chunk";
	}

	static function read(b:Bytes, at:Int, size:Int, format:Int, channels:Int, rate:Int, bits:Int, align:Int):Wav {
		if (channels <= 0) throw "helder.os.audio.Wav: no channels";
		var bytes = bits >> 3;
		if (align < bytes * channels) align = bytes * channels;
		var pcm = format == 1, float = format == 3;
		if (!(pcm && (bits == 8 || bits == 16 || bits == 24 || bits == 32)) && !(float && (bits == 32 || bits == 64)))
			throw 'helder.os.audio.Wav: format $format at $bits bits (PCM of 8, 16, 24 or 32 bits, or floats of 32 or 64)';
		var frames = Std.int(size / align);
		var out = new Array<Float>();
		out.resize(frames * channels);
		for (f in 0...frames) {
			var o = at + f * align;
			for (c in 0...channels) {
				var p = o + c * bytes;
				out[f * channels + c] = if (float) bits == 32 ? b.getFloat(p) : b.getDouble(p) else switch bits {
					case 8: (b.get(p) - 128) / 128;
					case 16:
						var v = b.getUInt16(p);
						(v >= 0x8000 ? v - 0x10000 : v) / 32768;
					case 24:
						var v = b.get(p) | (b.get(p + 1) << 8) | (b.get(p + 2) << 16);
						(v >= 0x800000 ? v - 0x1000000 : v) / 8388608;
					default: b.getInt32(p) / 2147483648.0;
				}
			}
		}
		return new Wav(rate, channels, frames, out);
	}

	// the channels averaged, resampled to rate (linear interpolation)
	public function mono(rate:Int):Array<Float> {
		var n = frames == 0 ? 0 : Std.int(Math.max(1, Math.round(frames * rate / this.rate)));
		var out = new Array<Float>();
		out.resize(n);
		var step = this.rate / rate, k = 1 / channels;
		inline function at(f:Int):Float {
			var s = 0.0;
			for (c in 0...channels)
				s += samples[f * channels + c];
			return s * k;
		}
		for (i in 0...n) {
			var t = i * step, f = Std.int(t), w = t - f;
			out[i] = f + 1 < frames ? at(f) * (1 - w) + at(f + 1) * w : at(frames - 1);
		}
		return out;
	}
}
