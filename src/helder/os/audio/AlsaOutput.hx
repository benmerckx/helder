package helder.os.audio;

import helder.os.audio.Alsa;
import hxmc.unsafe.*;
import sys.thread.Lock;
import sys.thread.Thread;

// helder.os.audio.Audio on Linux: an ALSA playback stream (the device's name,
// "default" by default: PipeWire's or PulseAudio's ALSA plugin on most
// desktops), 32-bit floats through ALSA's plug layer at the rate asked for.
// ALSA is pushed to (snd_pcm_writei blocks while its buffer is full), so the
// audio thread is ours: a loop that pulls a period from the callback and
// writes it, recovering from underruns. The buffer is four periods.
// "file:PATH" is ALSA's file plugin over its null device (what the stream
// is given, written to PATH as it is: raw floats); neither paces: writes
// return at once.
@:allow(helder.os.audio)
class AlsaOutput {
	static var loaded:Null<String>;

	final owner:Audio;
	var pcm = Ptr.nil();
	final buffer:Ptr<Float32>;
	var quit = false;
	final done = new Lock();
	var error:Null<String>;

	function new(owner:Audio, device:Null<String>) {
		this.owner = owner;
		if (loaded == null) {
			var e = Alsa.load("libasound.so.2");
			loaded = e == null ? "" : e;
		}
		if (loaded != "") throw "helder.os.audio: " + loaded + " (ALSA)";
		var name = device == null ? "default" : StringTools.startsWith(device, "file:") ? "file:'" + device.substr(5) + "',raw" : device;
		Arena.scoped(a -> {
			var p:Ptr<Ptr> = a.alloc(8);
			check(Alsa.snd_pcm_open(p, a.cstring(name), SND.PCM_STREAM_PLAYBACK, 0), "snd_pcm_open(" + name + ")");
			pcm = p.value;
			var latency = Math.round(owner.frames * 4 * 1e6 / owner.sampleRate);
			check(Alsa.snd_pcm_set_params(pcm, SND.PCM_FORMAT_FLOAT_LE, SND.PCM_ACCESS_RW_INTERLEAVED, owner.channels, owner.sampleRate, 1, latency),
				"snd_pcm_set_params");
			var sizes:Ptr<Int64> = a.alloc(16);
			check(Alsa.snd_pcm_get_params(pcm, sizes, sizes.offset(1)), "snd_pcm_get_params");
			owner.frames = sizes[1].toInt();
			owner.latency = sizes[0].toInt() / owner.sampleRate;
		});
		buffer = LibC.malloc((owner.frames * owner.channels * 4 : Int64));
	}

	function check(r:Int, what:String) {
		if (r >= 0) return;
		var e = Alsa.snd_strerror(r).toString();
		if (!pcm.isNull()) Alsa.snd_pcm_close(pcm);
		pcm = Ptr.nil();
		throw "helder.os.audio: " + what + " failed: " + e;
	}

	function start() {
		quit = false;
		Thread.create(run);
	}

	// the audio thread
	function run() {
		var n = owner.frames, bytes = owner.channels * 4;
		try {
			while (!quit) {
				owner.pull(buffer, n);
				var done = 0;
				while (done < n && !quit) {
					var r = Alsa.snd_pcm_writei(pcm, buffer.add(done * bytes), n - done).toInt();
					// (an underrun, EPIPE: prepared again; a suspend, ESTRPIPE: resumed)
					if (r < 0) r = Alsa.snd_pcm_recover(pcm, r, 1);
					if (r < 0) throw "snd_pcm_writei failed: " + Alsa.snd_strerror(r).toString();
					done += r;
				}
			}
		} catch (e:Dynamic) {
			error = Std.string(e);
		}
		this.done.release();
	}

	function stop() {
		quit = true;
		done.wait();
		Alsa.snd_pcm_drop(pcm);
		Alsa.snd_pcm_prepare(pcm);
		if (error != null) throw "helder.os.audio: " + error;
	}

	function close() {
		Alsa.snd_pcm_close(pcm);
		LibC.free(buffer);
	}
}
