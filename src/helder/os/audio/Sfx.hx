package helder.os.audio;

import haxe.ds.Vector;
import haxe.io.Bytes;
import hxmc.unsafe.*;

// Sound effects and music, mixed into one Audio output. Effects: sounds
// made up front (mono samples at the output's rate, Sfx.RATE: made
// procedurally, or a file decoded whole by Sound.decode, WAV or Ogg
// Vorbis), played on a few voices, each at a gain, a rate (pitch) and a pan;
// once, or looping until stopped. Music: an Ogg Vorbis file streamed
// (decoded a packet at a time on the audio thread from its compressed
// bytes, never whole: Vorbis), looping or not, at its gain; a new one
// crossfades from what plays. play, loop and music only set fields the
// audio thread reads, and the mix allocates nothing. Where there is no
// output (a machine without a device) it plays nothing.
//
//   var sfx = Sfx.open();
//   var tock = sfx.add([for (i in 0...4800) Math.sin(i * 0.12) * Math.exp(-i / 600)]);
//   sfx.play(tock, 0.8);                  // gain
//   sfx.play(tock, 0.5, 1.3, -0.5);       // a rate (higher, shorter) and a pan (left)
//   var hum = sfx.loop(engine, 0.3);      // until sfx.stop(hum); sfx.gain(hum, 0.1) meanwhile
//   sfx.music(Asset.sound("music/menu.ogg").load(), 2);    // in over 2 seconds
//   sfx.music(Asset.sound("music/battle.ogg").load(), 3);  // crossfaded over 3
//   sfx.stopMusic(1);
//   sfx.volume = 0.8; sfx.musicVolume = 0.5;               // the effects', the music's
//
// In the browser the output starts at the page's first click or key (the
// browsers' rule): a sound played before is lost. On phones the app's
// lifecycle pauses the output (Audio.hold).
class Sfx {
	public static inline var RATE = 48000;
	public static inline var VOICES = 12;
	// music tracks at once: the one playing, those fading out
	public static inline var TRACKS = 3;
	// (a track's decoded frames ahead: a power of two, over two packets of the largest blocks)
	static inline var RING = 16384;
	static inline var CHUNK = 1024;

	// whether there is an output (false: play does nothing)
	public final playing:Bool;
	public final output:Null<Audio>;
	final out:Null<Audio>;
	final sounds:Array<Array<Float>> = [];
	// the voices: their sound (-1: silent), position (samples), gain, rate,
	// pan, whether they loop, their generation (a handle's high part)
	final voiceSound:Vector<Int> = filledInt(VOICES, -1);
	final voicePos:Vector<Float> = filled(VOICES, 0);
	final voiceGain:Vector<Float> = filled(VOICES, 0);
	final voiceRate:Vector<Float> = filled(VOICES, 1);
	final voicePan:Vector<Float> = filled(VOICES, 0);
	final voiceLoop:Vector<Bool> = new Vector(VOICES);
	final voiceGen:Vector<Int> = filledInt(VOICES, 0);
	var next = 0;
	final tracks:Vector<Track>;
	// the effects' gain
	public var volume = 0.8;
	// the music's gain
	public var musicVolume = 0.6;

	function new(output:Bool, ?device:String, ?session:String) {
		var o:Null<Audio> = null;
		if (output)
			o = try Audio.open({sampleRate: RATE, channels: 2, frames: 512, device: device, session: session}, mix) catch (_:Dynamic) null;
		out = o;
		this.output = o;
		playing = o != null || !output;
		tracks = new Vector(TRACKS);
		for (i in 0...TRACKS)
			tracks[i] = new Track();
		for (i in 0...VOICES)
			voiceLoop[i] = false;
		if (o != null) o.start();
	}

	static function filled(n:Int, v:Float):Vector<Float> {
		var a = new Vector<Float>(n);
		for (i in 0...n)
			a[i] = v;
		return a;
	}

	static function filledInt(n:Int, v:Int):Vector<Int> {
		var a = new Vector<Int>(n);
		for (i in 0...n)
			a[i] = v;
		return a;
	}

	// effects on the default output (device: another, Audio's names; none
	// where there is no output; session: iOS's category, AudioConfig.session)
	public static function open(?device:String, ?session:String):Sfx
		return new Sfx(true, device, session);

	// effects without an output: mixed by hand, mix(buffer, frames) (tests, a recording)
	public static function offline():Sfx
		return new Sfx(false);

	// a sound of mono samples (-1 to 1) at RATE: its id
	public function add(samples:Array<Float>):Int {
		sounds.push(samples);
		return sounds.length - 1;
	}

	// sound id on the next voice (the oldest one taken when all play, a
	// looping one last), at gain, rate and pan (-1 left, 1 right): the
	// voice's handle (-1: nothing played)
	public function play(id:Int, gain = 1.0, rate = 1.0, pan = 0.0):Int
		return start(id, gain, rate, pan, false);

	// sound id looping until stop(handle)
	public function loop(id:Int, gain = 1.0, rate = 1.0, pan = 0.0):Int
		return start(id, gain, rate, pan, true);

	function start(id:Int, gain:Float, rate:Float, pan:Float, looping:Bool):Int {
		if (!playing || id < 0 || id >= sounds.length) return -1;
		var v = -1;
		// (a free voice, else the oldest one-shot, else the oldest)
		for (k in 0...VOICES) {
			var c = (next + k) % VOICES;
			if (voiceSound[c] < 0) {
				v = c;
				break;
			}
		}
		if (v < 0)
			for (k in 0...VOICES) {
				var c = (next + k) % VOICES;
				if (!voiceLoop[c]) {
					v = c;
					break;
				}
			}
		if (v < 0) v = next;
		next = (v + 1) % VOICES;
		// (silent while its fields change: the audio thread skips it)
		voiceSound[v] = -1;
		voicePos[v] = 0;
		voiceGain[v] = gain;
		voiceRate[v] = rate;
		voicePan[v] = pan < -1 ? -1 : pan > 1 ? 1 : pan;
		voiceLoop[v] = looping;
		voiceGen[v]++;
		voiceSound[v] = id;
		return voiceGen[v] * VOICES + v;
	}

	inline function voice(handle:Int):Int {
		var v = handle % VOICES;
		return handle < 0 || Std.int(handle / VOICES) != voiceGen[v] ? -1 : v;
	}

	// a voice stopped (a handle of play or loop; one already over: nothing)
	public function stop(handle:Int) {
		var v = voice(handle);
		if (v >= 0) voiceSound[v] = -1;
	}

	// a voice's gain, and pan, changed while it plays
	public function gain(handle:Int, gain:Float) {
		var v = voice(handle);
		if (v >= 0) voiceGain[v] = gain;
	}

	public function pan(handle:Int, pan:Float) {
		var v = voice(handle);
		if (v >= 0) voicePan[v] = pan < -1 ? -1 : pan > 1 ? 1 : pan;
	}

	// whether a voice still plays
	public function active(handle:Int):Bool {
		var v = voice(handle);
		return v >= 0 && voiceSound[v] >= 0;
	}

	// an Ogg Vorbis file's bytes as the music, faded in over `fade`
	// seconds while what played fades out, at gain, looping or not; it
	// throws (Vorbis's String) on a file it cannot read
	public function music(bytes:Bytes, fade = 1.0, gain = 1.0, loop = true) {
		var v = Vorbis.open(bytes);
		if (!playing) return;
		fadeOut(fade);
		// (a free track, else the quietest)
		var t:Null<Track> = null;
		for (k in tracks)
			if (!k.on) {
				t = k;
				break;
			}
		if (t == null) {
			t = tracks[0];
			for (k in tracks)
				if (k.gain < t.gain) t = k;
		}
		var rate = out == null ? RATE : out.sampleRate;
		t.on = false;
		t.vorbis = v;
		t.loop = loop;
		t.ended = false;
		t.written = 0;
		t.pos = 0;
		t.step = v.rate / rate;
		t.gain = 0;
		t.target = gain;
		t.delta = fade <= 0 ? gain : gain / (fade * rate);
		t.on = true;
	}

	// the music faded out over `fade` seconds
	public function stopMusic(fade = 1.0)
		fadeOut(fade);

	function fadeOut(fade:Float) {
		var rate = out == null ? RATE : out.sampleRate;
		for (t in tracks)
			if (t.on) {
				t.target = 0;
				t.delta = fade <= 0 ? 1 : (t.gain > 0 ? t.gain : 1) / (fade * rate);
			}
	}

	// whether music plays (a track not faded out yet)
	public function musicPlaying():Bool {
		for (t in tracks)
			if (t.on && t.target > 0) return true;
		return false;
	}

	// the tracks mixed now (fading ones too)
	public function musicTracks():Int {
		var n = 0;
		for (t in tracks)
			if (t.on) n++;
		return n;
	}

	public function close()
		if (out != null) out.close();

	// (the audio thread: the voices and the tracks summed into the
	// interleaved buffer, clipped; offline, the caller's)
	public function mix(buffer:Ptr<Float32>, frames:Int) {
		var c = out == null ? 2 : out.channels;
		for (v in 0...VOICES) {
			var id = voiceSound[v];
			if (id < 0) continue;
			var s = sounds[id], pos = voicePos[v], rate = voiceRate[v], g = voiceGain[v] * volume, n = s.length, p = voicePan[v];
			var gl = p > 0 ? g * (1 - p) : g, gr = p < 0 ? g * (1 + p) : g;
			var looping = voiceLoop[v];
			if (n < 2) {
				voiceSound[v] = -1;
				continue;
			}
			for (i in 0...frames) {
				var k = Std.int(pos);
				if (k + 1 >= n) {
					if (!looping) {
						voiceSound[v] = -1;
						break;
					}
					pos -= n - 1;
					k = Std.int(pos);
					if (k + 1 >= n) {
						pos = 0;
						k = 0;
					}
				}
				var f = pos - k, x = s[k] + (s[k + 1] - s[k]) * f;
				if (c == 2) {
					buffer[i * 2] = buffer[i * 2] + x * gl;
					buffer[i * 2 + 1] = buffer[i * 2 + 1] + x * gr;
				} else
					for (ch in 0...c)
						buffer[i * c + ch] = buffer[i * c + ch] + x * g;
				pos += rate;
			}
			voicePos[v] = pos;
		}
		for (t in tracks)
			if (t.on) mixTrack(t, buffer, frames, c);
		for (i in 0...frames * c) {
			var x:Float = buffer[i];
			if (x > 1) buffer[i] = 1 else if (x < -1) buffer[i] = -1;
		}
	}

	function mixTrack(t:Track, buffer:Ptr<Float32>, frames:Int, c:Int) {
		var done = 0;
		while (done < frames && t.on) {
			var n = frames - done < CHUNK ? frames - done : CHUNK;
			// (the frames this chunk reads, decoded ahead)
			var need = Std.int(t.pos + n * t.step) + 2;
			if (!t.fill(need) && t.written <= Std.int(t.pos) + 1) {
				t.on = false;
				break;
			}
			var l = t.left, r = t.right, mv = musicVolume;
			for (i in 0...n) {
				var k = Std.int(t.pos);
				if (k + 1 >= t.written) {
					if (t.ended) {
						t.on = false;
						break;
					}
					continue;
				}
				var f = t.pos - k, a = k & (RING - 1), b = (k + 1) & (RING - 1);
				var g = t.gain;
				if (g != t.target) {
					if (g < t.target) {
						g += t.delta;
						if (g > t.target) g = t.target;
					} else {
						g -= t.delta;
						if (g < t.target) g = t.target;
					}
					t.gain = g;
				}
				g *= mv;
				var xl = (l[a] + (l[b] - l[a]) * f) * g, xr = (r[a] + (r[b] - r[a]) * f) * g;
				var o = (done + i) * c;
				if (c == 2) {
					buffer[o] = buffer[o] + xl;
					buffer[o + 1] = buffer[o + 1] + xr;
				} else
					for (ch in 0...c)
						buffer[o + ch] = buffer[o + ch] + (ch & 1 == 0 ? xl : xr);
				t.pos += t.step;
			}
			done += n;
			// (faded out: the track free)
			if (t.target == 0 && t.gain == 0) t.on = false;
		}
	}
}

// A music track: its decoder, the frames decoded ahead (a ring, absolute
// frame positions), where it reads (fractional: resampled to the output's
// rate), its gain going toward its target by delta a frame.
@:allow(helder.os.audio.Sfx)
private class Track {
	var on = false;
	var vorbis:Null<Vorbis> = null;
	var loop = true;
	var ended = false;
	final left = new Vector<Float>(16384);
	final right = new Vector<Float>(16384);
	var written = 0;
	var pos = 0.0;
	var step = 1.0;
	var gain = 0.0;
	var target = 0.0;
	var delta = 0.0;

	function new() {}

	// frames decoded until `need` are (false: the stream ended first)
	function fill(need:Int):Bool {
		var v = vorbis;
		if (v == null) return false;
		// (the positions kept small: moved back together by whole rings)
		if (written > 1 << 30) {
			var shift = Std.int(pos) & ~(16384 - 1);
			written -= shift;
			pos -= shift;
			need -= shift;
		}
		var empties = 0;
		while (written < need) {
			if (ended) return false;
			var n = v.next();
			if (n < 0) {
				if (!loop || empties > 2) {
					ended = true;
					return false;
				}
				v.rewind();
				empties++;
				continue;
			}
			if (n > 0) empties = 0;
			var l = v.out[0], r = v.channels > 1 ? v.out[1] : v.out[0];
			for (i in 0...n) {
				var k = (written + i) & (16384 - 1);
				left[k] = l[i];
				right[k] = r[i];
			}
			written += n;
		}
		return true;
	}
}
