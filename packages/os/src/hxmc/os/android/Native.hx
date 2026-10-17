package hxmc.os.android;

import hxmc.unsafe.*;

// What packages/os uses of the NDK's libraries (Android's own, written as
// imports by hxmc: no NDK at build time): libandroid's looper, input queue,
// native window and activity, liblog. ALooper_pollOnce blocks, so it is no
// fast call (a collection may run while the thread waits in it).
@:hxmc.c @:hxmc.fast @:hxmc.lib("libandroid.so") extern class Android {
	static function ALooper_prepare(opts:Int):Ptr;
	static function ALooper_forThread():Ptr;
	static function ALooper_acquire(looper:Ptr):Void;
	static function ALooper_wake(looper:Ptr):Void;
	static function ALooper_addFd(looper:Ptr, fd:Int, ident:Int, events:Int, callback:Ptr, data:Ptr):Int;
	static function AInputQueue_attachLooper(queue:Ptr, looper:Ptr, ident:Int, callback:Ptr, data:Ptr):Void;
	static function AInputQueue_detachLooper(queue:Ptr):Void;
	static function AInputQueue_getEvent(queue:Ptr, out:Ptr):Int;
	static function AInputQueue_preDispatchEvent(queue:Ptr, event:Ptr):Int;
	static function AInputQueue_finishEvent(queue:Ptr, event:Ptr, handled:Int):Void;
	static function AInputEvent_getType(event:Ptr):Int;
	static function AMotionEvent_getAction(event:Ptr):Int;
	static function AMotionEvent_getPointerCount(event:Ptr):Int64;
	static function AMotionEvent_getX(event:Ptr, index:Int64):Float32;
	static function AMotionEvent_getY(event:Ptr, index:Int64):Float32;
	static function AMotionEvent_getAxisValue(event:Ptr, axis:Int, index:Int64):Float32;
	static function AKeyEvent_getAction(event:Ptr):Int;
	static function AKeyEvent_getKeyCode(event:Ptr):Int;
	static function AKeyEvent_getMetaState(event:Ptr):Int;
	static function ANativeWindow_getWidth(window:Ptr):Int;
	static function ANativeWindow_getHeight(window:Ptr):Int;
	static function ANativeWindow_acquire(window:Ptr):Void;
	static function ANativeWindow_release(window:Ptr):Void;
	static function ANativeWindow_fromSurface(env:Ptr, surface:Ptr):Ptr;
	static function ANativeActivity_finish(activity:Ptr):Void;
	static function AChoreographer_getInstance():Ptr;
	static function AChoreographer_postFrameCallback64(choreographer:Ptr, callback:Ptr, data:Ptr):Void;
	static function AConfiguration_new():Ptr;
	static function AConfiguration_fromAssetManager(config:Ptr, assets:Ptr):Void;
	static function AConfiguration_getDensity(config:Ptr):Int;
	static function AConfiguration_getUiModeNight(config:Ptr):Int;
	static function AConfiguration_delete(config:Ptr):Void;
}

@:hxmc.c @:hxmc.lib("libandroid.so") extern class Looper {
	// (blocks: a safe region around it)
	static function ALooper_pollOnce(timeoutMillis:Int, outFd:Ptr, outEvents:Ptr, outData:Ptr):Int;
}

// a call through a C function pointer from no-GC code (MainThread: a
// @:hxmc.callback, whose wrapper leaves the thread's safe region)
@:hxmc.c @:hxmc.fast extern class Indirect {
	@:hxmc.indirect static function call0(f:Ptr):Void;
}

@:hxmc.c @:hxmc.fast @:hxmc.lib("liblog.so") extern class Log {
	// prio: 3 debug, 4 info, 5 warn, 6 error
	static function __android_log_write(prio:Int, tag:Ptr, text:Ptr):Int;
}

@:hxmc.c @:hxmc.fast extern class Threads {
	static function pthread_create(t:Ptr, attr:Ptr, entry:Ptr, arg:Ptr):Int;
	static function pthread_join(t:Int64, ret:Ptr):Int;
	static function pthread_mutex_init(m:Ptr, attr:Ptr):Int;
	static function pthread_mutex_lock(m:Ptr):Int;
	static function pthread_mutex_unlock(m:Ptr):Int;
	static function pthread_cond_init(c:Ptr, attr:Ptr):Int;
	static function pthread_cond_wait(c:Ptr, m:Ptr):Int;
	static function pthread_cond_broadcast(c:Ptr):Int;
	static function exit(code:Int):Void;
	// the program's main (hxmc's generated one, C's convention)
	static function main(argc:Int, argv:Ptr):Int;
}
