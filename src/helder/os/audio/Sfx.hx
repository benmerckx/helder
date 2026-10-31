package helder.os.audio;

import hxmc.unsafe.*;

// Short sound effects, played at once: one-shots (a hit, a bounce, a
// chime) mixed into one Audio output by a few voices, each a sound's
// samples (mono, at the output's rate: Sfx.RATE), a gain and a rate (pitch).
// The sounds are made up front (procedurally, or a WAV file decoded by
// Wav: `sfx.add(Wav.decode(bytes).mono(Sfx.RATE))`), play only sets a voice's fields, and the mix allocates
// nothing on the audio thread. Where there is no output (a machine without
// a device) it plays nothing.
//
//   var sfx = Sfx.open();
//   var tock = sfx.add([for (i in 0...4800) Math.sin(i * 0.12) * Math.exp(-i / 600)]);
//   sfx.play(tock, 0.8);            // gain
//   sfx.play(tock, 0.5, 1.3);       // and a rate: higher, shorter
//
// In the browser the output starts at the page's first click or key (the
// browsers' rule): a sound played before is lost.
class Sfx {
	public static inline var RATE = 48000;
	public static inline var VOICES = 8;

	// whether there is an output (false: play does nothing)
	public final playing:Bool;
	final out:Null<Audio>;
	final sounds:Array<Array<Float>> = [];
	// the voices: their sound (-1: silent), position (samples), gain and rate
	final voiceSound:Array<Int> = [for (_ in 0...VOICES) -1];
	final voicePos:Array<Float> = [for (_ in 0...VOICES) 0.0];
	final voiceGain:Array<Float> = [for (_ in 0...VOICES) 0.0];
	final voiceRate:Array<Float> = [for (_ in 0...VOICES) 1.0];
	var next = 0;
	// the master gain
	public var volume = 0.8;

	function new(output:Bool, ?device:String) {
		var o:Null<Audio> = null;
		if (output)
			o = try Audio.open({sampleRate: RATE, channels: 2, frames: 512, device: device}, mix) catch (_:Dynamic) null;
		out = o;
		playing = o != null || !output;
		if (o != null) o.start();
	}

	// effects on the default output (device: another, Audio's names; none
	// where there is no output)
	public static function open(?device:String):Sfx
		return new Sfx(true, device);

	// effects without an output: mixed by hand, mix(buffer, frames) (tests, a recording)
	public static function offline():Sfx
		return new Sfx(false);

	// a sound of mono samples (-1 to 1) at RATE: its id
	public function add(samples:Array<Float>):Int {
		sounds.push(samples);
		return sounds.length - 1;
	}

	// sound id on the next voice (the oldest one taken when all play), at gain and rate
	public function play(id:Int, gain = 1.0, rate = 1.0) {
		if (!playing || id < 0 || id >= sounds.length) return;
		var v = next;
		next = (next + 1) % VOICES;
		// (silent while its fields change: the audio thread skips it)
		voiceSound[v] = -1;
		voicePos[v] = 0;
		voiceGain[v] = gain;
		voiceRate[v] = rate;
		voiceSound[v] = id;
	}

	public function close()
		if (out != null) out.close();

	// (the audio thread: the voices summed into the interleaved stereo
	// buffer, clipped; offline, the caller's)
	public function mix(buffer:Ptr<Float32>, frames:Int) {
		var c = out == null ? 2 : out.channels;
		for (v in 0...VOICES) {
			var id = voiceSound[v];
			if (id < 0) continue;
			var s = sounds[id], pos = voicePos[v], rate = voiceRate[v], g = voiceGain[v] * volume, n = s.length;
			for (i in 0...frames) {
				var k = Std.int(pos);
				if (k + 1 >= n) {
					voiceSound[v] = -1;
					break;
				}
				var f = pos - k, x = (s[k] + (s[k + 1] - s[k]) * f) * g;
				for (ch in 0...c)
					buffer[i * c + ch] = buffer[i * c + ch] + x;
				pos += rate;
			}
			voicePos[v] = pos;
		}
		for (i in 0...frames * c) {
			var x:Float = buffer[i];
			if (x > 1) buffer[i] = 1 else if (x < -1) buffer[i] = -1;
		}
	}
}
