package helder.os.android;

import helder.os.android.Native;
import hxmc.unsafe.*;

// The display's frames on the program's thread (App.run on Android):
// Choreographer's (the NDK's AChoreographer, API 29: postFrameCallback64,
// no Java), the instance of the thread's own looper, so its callback runs
// inside ALooper_pollOnce there, where AndroidWindow.wait sleeps. One frame
// is asked for at a time (request), only while a frame can be drawn; its
// callback keeps the vsync's time (CLOCK_MONOTONIC's ns) for the frame,
// which App.run then draws (take: the time in haxe.Timer.stamp()'s
// seconds). A callback cannot be taken back: before the program's main
// returns (hxmc dev's hand-over to the next build) the one asked for is
// waited for (drain), so that it never calls into a library gone.
// Statics without initializers, plain stores: nothing allocated a frame.
@:hxmc.android
class Vsync {
	static var choreographer:Ptr;
	// asked for, not come yet; come, its frame not drawn yet (1: yes)
	static var pending:Int;
	static var due:Int;
	static var nanos:Int64;
	static var ts:Ptr;

	// whether a vsync came whose frame is not drawn yet
	public static inline function ready():Bool
		return due != 0;

	// the next vsync's callback (nothing if one is asked for or waits to be drawn)
	public static function request() {
		if (pending != 0 || due != 0) return;
		if (choreographer.isNull()) choreographer = Android.AChoreographer_getInstance();
		if (choreographer.isNull()) return;
		pending = 1;
		Android.AChoreographer_postFrameCallback64(choreographer, Callback.addr(frame), Ptr.nil());
	}

	@:hxmc.callback static function frame(frameTimeNanos:Int64, data:Ptr):Void {
		nanos = frameTimeNanos;
		pending = 0;
		due = 1;
	}

	// the vsync's frame drawn now: its time in haxe.Timer.stamp()'s seconds
	public static function take():Float {
		due = 0;
		if (ts.isNull()) ts = LibC.malloc(16);
		PosixClock.clock_gettime(1, ts);
		var now:Int64 = Mem.getI64(ts, 0) * 1000000000 + Mem.getI64(ts, 8);
		// (how long ago the display's vsync was: ns, under a second)
		var ago = now - nanos;
		var s = ago < 0 || ago > 1000000000 ? 0.0 : ago.toInt() / 1e9;
		return FrameClock.toStamp(0, s, haxe.Timer.stamp());
	}

	// the vsync asked for, waited for (at most 100 ms: none comes while the
	// window is gone), so that no callback is left behind
	public static function drain() {
		// (the looper's other sources may answer at once, ready: a deadline, not a count)
		var until = haxe.Timer.stamp() + 0.1;
		while (pending != 0 && haxe.Timer.stamp() < until)
			Looper.ALooper_pollOnce(10, Ptr.nil(), Ptr.nil(), Ptr.nil());
		pending = 0;
		due = 0;
	}
}
