package helder.os.audio;

import hxmc.unsafe.*;

// AAudio (the NDK's audio, libaaudio.so, API 26 and later), loaded at run
// time (helder.os.Dl): the calls a playback stream with a data callback
// needs. Builders and streams are Ptr; results are aaudio_result_t (0 OK,
// negative an error: AAudio_convertResultToText names it).
@:build(helder.os.Dl.build())
class AAudio {
	static function AAudio_createStreamBuilder(builder:Ptr<Ptr>):Int;
	static function AAudio_convertResultToText(result:Int):CString;
	static function AAudioStreamBuilder_setSampleRate(builder:Ptr, rate:Int):Void;
	static function AAudioStreamBuilder_setChannelCount(builder:Ptr, channels:Int):Void;
	static function AAudioStreamBuilder_setFormat(builder:Ptr, format:Int):Void;
	static function AAudioStreamBuilder_setPerformanceMode(builder:Ptr, mode:Int):Void;
	static function AAudioStreamBuilder_setSharingMode(builder:Ptr, mode:Int):Void;
	static function AAudioStreamBuilder_setUsage(builder:Ptr, usage:Int):Void;
	static function AAudioStreamBuilder_setDataCallback(builder:Ptr, callback:Ptr, user:Ptr):Void;
	static function AAudioStreamBuilder_setErrorCallback(builder:Ptr, callback:Ptr, user:Ptr):Void;
	static function AAudioStreamBuilder_openStream(builder:Ptr, stream:Ptr<Ptr>):Int;
	static function AAudioStreamBuilder_delete(builder:Ptr):Int;
	static function AAudioStream_requestStart(stream:Ptr):Int;
	static function AAudioStream_requestStop(stream:Ptr):Int;
	static function AAudioStream_close(stream:Ptr):Int;
	static function AAudioStream_getSampleRate(stream:Ptr):Int;
	static function AAudioStream_getFramesPerBurst(stream:Ptr):Int;
	static function AAudioStream_getBufferSizeInFrames(stream:Ptr):Int;
	static function AAudioStream_setBufferSizeInFrames(stream:Ptr, frames:Int):Int;
}

class AA {
	public static inline var FORMAT_PCM_FLOAT = 2;
	public static inline var SHARING_MODE_SHARED = 1;
	public static inline var PERFORMANCE_MODE_LOW_LATENCY = 12;
	public static inline var USAGE_GAME = 14;
	public static inline var CALLBACK_RESULT_CONTINUE = 0;
	public static inline var ERROR_DISCONNECTED = -899;
}

// Bionic's semaphores: the data callback (AAudio's thread, no GC) posts,
// the audio thread waits (in a safe region: it blocks)
@:hxmc.c @:hxmc.fast extern class Sem {
	static function sem_init(sem:Ptr, shared:Int, value:Int):Int;
	static function sem_post(sem:Ptr):Int;
	static function sem_destroy(sem:Ptr):Int;
	static function clock_gettime(id:Int, ts:Ptr):Int;
}

@:hxmc.c extern class SemWait {
	static function sem_timedwait(sem:Ptr, abs:Ptr):Int;
}
