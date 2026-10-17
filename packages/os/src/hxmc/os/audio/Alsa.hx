package hxmc.os.audio;

import hxmc.unsafe.*;

// ALSA's PCM API (libasound.so.2), loaded at run time (hxmc.os.Dl: a
// program that never opens audio starts without the library): the calls a
// playback stream needs. A snd_pcm_t* is a Ptr; frame counts
// (snd_pcm_uframes_t, snd_pcm_sframes_t) are C's long: Int64; negative
// results are -errno. Calls run in a safe region (writei blocks).
@:build(hxmc.os.Dl.build())
class Alsa {
	static function snd_pcm_open(pcm:Ptr<Ptr>, name:Ptr, stream:Int, mode:Int):Int;
	static function snd_pcm_close(pcm:Ptr):Int;
	// format, access, rate and a latency in µs at once, through ALSA's plug
	// layer (conversions, resampling when softResample is 1)
	static function snd_pcm_set_params(pcm:Ptr, format:Int, access:Int, channels:Int, rate:Int, softResample:Int, latency:Int):Int;
	static function snd_pcm_get_params(pcm:Ptr, bufferSize:Ptr<Int64>, periodSize:Ptr<Int64>):Int;
	static function snd_pcm_writei(pcm:Ptr, buffer:Ptr, frames:Int64):Int64;
	static function snd_pcm_recover(pcm:Ptr, err:Int, silent:Int):Int;
	static function snd_pcm_drop(pcm:Ptr):Int;
	static function snd_pcm_drain(pcm:Ptr):Int;
	static function snd_pcm_prepare(pcm:Ptr):Int;
	static function snd_strerror(err:Int):CString;
}

class SND {
	public static inline var PCM_STREAM_PLAYBACK = 0;
	public static inline var PCM_FORMAT_FLOAT_LE = 14;
	public static inline var PCM_ACCESS_RW_INTERLEAVED = 3;
}
