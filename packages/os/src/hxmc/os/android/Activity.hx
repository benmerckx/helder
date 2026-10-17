package hxmc.os.android;

import hxmc.os.android.Native;
import hxmc.unsafe.*;

// The NativeActivity glue (what the NDK's android_native_app_glue does in
// C, in no-GC Haxe): Android loads the app's lib<name>.so and calls its
// export ANativeActivity_onCreate on the activity's main (UI) thread, which
// sets the activity's callbacks, sends what the app prints (stdout,
// stderr) to logcat, and starts a thread of its own for the program: the
// runtime starts there (hxmc's generated main: rt_init, the program's main
// on its big stack), with a looper (ALooper) watching a pipe of commands
// from the callbacks. The callbacks run on the UI thread, which the runtime
// does not know: they write a command and, for the ones whose state the
// program must have taken (a window created or about to go, an input queue,
// pause, destroy), wait until the program's thread has handled it
// (AndroidWindow.command: Window, App). Everything here is plain memory
// and C calls: the collector is not involved.
@:hxmc.android @:keep
class Activity {
	// the commands (one byte each through the pipe)
	public static inline var WINDOW_CREATED = 1;
	public static inline var WINDOW_DESTROYED = 2;
	public static inline var INPUT_CREATED = 3;
	public static inline var INPUT_DESTROYED = 4;
	public static inline var RESIZED = 5;
	public static inline var REDRAW = 6;
	public static inline var CONTENT_RECT = 7;
	public static inline var CONFIG = 8;
	public static inline var PAUSE = 9;
	public static inline var RESUME = 10;
	public static inline var START = 11;
	public static inline var STOP = 12;
	public static inline var FOCUS_GAINED = 13;
	public static inline var FOCUS_LOST = 14;
	public static inline var LOW_MEMORY = 15;
	public static inline var DESTROY = 16;

	// the looper's identifiers of the pipe and of the input queue
	public static inline var LOOPER_COMMANDS = 1;
	public static inline var LOOPER_INPUT = 2;

	public static var activity:Ptr;
	// the native window and input queue the last command handed over
	// (under the lock; read by the program's thread when it handles it)
	public static var pendingWindow:Ptr;
	public static var pendingQueue:Ptr;
	public static var looper:Ptr;
	// the main thread's (MainThread)
	public static var mainLooper:Ptr;
	public static var commandRead:Int;
	static var commandWrite:Int;
	static var lock:Ptr;
	static var cond:Ptr;
	// commands sent, and handled by the program's thread
	static var sent:Int;
	static var handled:Int;
	// the program's thread runs (its looper is ready), its main has returned
	static var running:Int;
	static var done:Int;
	public static var destroyed:Int;
	static var logRead:Int;
	static var logWrite:Int;
	static var logThreadId:Int64;

	// ---- the UI thread

	// the library's entry: NativeActivity calls it with the activity (its
	// saved state is not kept: a restarted activity starts afresh)
	@:hxmc.export("ANativeActivity_onCreate") @:hxmc.noGc static function onCreate(a:Ptr, saved:Ptr, savedSize:Int64):Void {
		var cb = Mem.getPtr(a, 0); // ANativeActivity.callbacks
		// (ANativeActivityCallbacks: onStart, onResume, onSaveInstanceState,
		// onPause, onStop, onDestroy, onWindowFocusChanged,
		// onNativeWindowCreated, onNativeWindowResized,
		// onNativeWindowRedrawNeeded, onNativeWindowDestroyed,
		// onInputQueueCreated, onInputQueueDestroyed, onContentRectChanged,
		// onConfigurationChanged, onLowMemory)
		Mem.setPtr(cb, 0, Callback.addr(onStart));
		Mem.setPtr(cb, 8, Callback.addr(onResume));
		Mem.setPtr(cb, 16, Callback.addr(onSaveInstanceState));
		Mem.setPtr(cb, 24, Callback.addr(onPause));
		Mem.setPtr(cb, 32, Callback.addr(onStop));
		Mem.setPtr(cb, 40, Callback.addr(onDestroy));
		Mem.setPtr(cb, 48, Callback.addr(onWindowFocusChanged));
		Mem.setPtr(cb, 56, Callback.addr(onNativeWindowCreated));
		Mem.setPtr(cb, 64, Callback.addr(onNativeWindowResized));
		Mem.setPtr(cb, 72, Callback.addr(onNativeWindowRedrawNeeded));
		Mem.setPtr(cb, 80, Callback.addr(onNativeWindowDestroyed));
		Mem.setPtr(cb, 88, Callback.addr(onInputQueueCreated));
		Mem.setPtr(cb, 96, Callback.addr(onInputQueueDestroyed));
		Mem.setPtr(cb, 104, Callback.addr(onContentRectChanged));
		Mem.setPtr(cb, 112, Callback.addr(onConfigurationChanged));
		Mem.setPtr(cb, 120, Callback.addr(onLowMemory));
		activity = a;
		if (lock.isNull()) {
			// (once per process: the runtime starts once; the manifest keeps
			// configuration changes from recreating the activity)
			lock = LibC.malloc(64);
			mainLooper = Android.ALooper_forThread();
			Android.ALooper_acquire(mainLooper);
			cond = LibC.malloc(64);
			Threads.pthread_mutex_init(lock, Ptr.nil());
			Threads.pthread_cond_init(cond, Ptr.nil());
			var fds = Mem.stack(8);
			Posix.pipe(fds);
			commandRead = Mem.getI32(fds, 0);
			commandWrite = Mem.getI32(fds, 4);
			// stdout and stderr: lines to logcat, from a thread of their own
			Posix.pipe(fds);
			logRead = Mem.getI32(fds, 0);
			logWrite = Mem.getI32(fds, 4);
			Posix.dup2(logWrite, 1);
			Posix.dup2(logWrite, 2);
			var t = Mem.stack(16);
			Threads.pthread_create(t, Ptr.nil(), Callback.addr(logThread), Ptr.nil());
			logThreadId = Mem.getI64(t, 0);
			Threads.pthread_create(t, Ptr.nil(), Callback.addr(programThread), Ptr.nil());
			// (until its looper is ready: the commands below have a reader)
			Threads.pthread_mutex_lock(lock);
			while (running == 0)
				Threads.pthread_cond_wait(cond, lock);
			Threads.pthread_mutex_unlock(lock);
		} else {
			destroyed = 0;
		}
	}

	// a command to the program's thread; wait: until it has handled it
	// (or its main has returned)
	@:hxmc.noGc static function send(cmd:Int, wait:Bool) {
		Threads.pthread_mutex_lock(lock);
		sent++;
		var mine = sent;
		var b = Mem.stack(8);
		Mem.setI8(b, 0, cmd);
		Posix.write(commandWrite, b, 1);
		if (wait)
			while (handled < mine && done == 0)
				Threads.pthread_cond_wait(cond, lock);
		Threads.pthread_mutex_unlock(lock);
	}

	@:hxmc.callback @:hxmc.noGc static function onStart(a:Ptr):Void
		send(START, false);

	@:hxmc.callback @:hxmc.noGc static function onResume(a:Ptr):Void
		send(RESUME, false);

	@:hxmc.callback @:hxmc.noGc static function onSaveInstanceState(a:Ptr, outSize:Ptr):Ptr {
		Mem.setI64(outSize, 0, 0);
		return Ptr.nil();
	}

	@:hxmc.callback @:hxmc.noGc static function onPause(a:Ptr):Void
		send(PAUSE, true);

	@:hxmc.callback @:hxmc.noGc static function onStop(a:Ptr):Void
		send(STOP, false);

	@:hxmc.callback @:hxmc.noGc static function onDestroy(a:Ptr):Void {
		destroyed = 1;
		send(DESTROY, true);
	}

	@:hxmc.callback @:hxmc.noGc static function onWindowFocusChanged(a:Ptr, focused:Int):Void
		send(focused != 0 ? FOCUS_GAINED : FOCUS_LOST, false);

	@:hxmc.callback @:hxmc.noGc static function onNativeWindowCreated(a:Ptr, w:Ptr):Void {
		Threads.pthread_mutex_lock(lock);
		pendingWindow = w;
		Threads.pthread_mutex_unlock(lock);
		send(WINDOW_CREATED, true);
	}

	@:hxmc.callback @:hxmc.noGc static function onNativeWindowResized(a:Ptr, w:Ptr):Void
		send(RESIZED, false);

	@:hxmc.callback @:hxmc.noGc static function onNativeWindowRedrawNeeded(a:Ptr, w:Ptr):Void
		send(REDRAW, false);

	// (the window stays valid until this returns: the program lets go of it first)
	@:hxmc.callback @:hxmc.noGc static function onNativeWindowDestroyed(a:Ptr, w:Ptr):Void
		send(WINDOW_DESTROYED, true);

	@:hxmc.callback @:hxmc.noGc static function onInputQueueCreated(a:Ptr, q:Ptr):Void {
		Threads.pthread_mutex_lock(lock);
		pendingQueue = q;
		Threads.pthread_mutex_unlock(lock);
		send(INPUT_CREATED, true);
	}

	@:hxmc.callback @:hxmc.noGc static function onInputQueueDestroyed(a:Ptr, q:Ptr):Void
		send(INPUT_DESTROYED, true);

	@:hxmc.callback @:hxmc.noGc static function onContentRectChanged(a:Ptr, rect:Ptr):Void
		send(CONTENT_RECT, false);

	@:hxmc.callback @:hxmc.noGc static function onConfigurationChanged(a:Ptr):Void
		send(CONFIG, false);

	@:hxmc.callback @:hxmc.noGc static function onLowMemory(a:Ptr):Void
		send(LOW_MEMORY, false);

	// ---- the program's thread

	// its first function: the looper, then the runtime and the program
	@:hxmc.callback @:hxmc.noGc static function programThread(arg:Ptr):Ptr {
		looper = Android.ALooper_prepare(1); // ALOOPER_PREPARE_ALLOW_NON_CALLBACKS
		Android.ALooper_addFd(looper, commandRead, LOOPER_COMMANDS, 1, Ptr.nil(), Ptr.nil()); // ALOOPER_EVENT_INPUT
		Threads.pthread_mutex_lock(lock);
		running = 1;
		Threads.pthread_cond_broadcast(cond);
		Threads.pthread_mutex_unlock(lock);
		var argv = Mem.stack(16);
		Mem.setPtr(argv, 0, Mem.cstr("app"));
		Mem.setPtr(argv, 8, Ptr.nil());
		Threads.main(1, argv);
		// main returned: the waits end, the activity finishes, the process with it
		Threads.pthread_mutex_lock(lock);
		done = 1;
		Threads.pthread_cond_broadcast(cond);
		Threads.pthread_mutex_unlock(lock);
		if (destroyed == 0) Android.ANativeActivity_finish(activity);
		// (what it printed reaches logcat first: the pipe's writers closed, its reader to the end)
		Posix.close(1);
		Posix.close(2);
		Posix.close(logWrite);
		Threads.pthread_join(logThreadId, Ptr.nil());
		Posix._exit(0); // (not exit: the system's libraries' destructors, with their threads still running)
		return Ptr.nil();
	}

	// the program's thread has handled command number `handled + 1`
	@:hxmc.noGc public static function acknowledge() {
		Threads.pthread_mutex_lock(lock);
		handled++;
		Threads.pthread_cond_broadcast(cond);
		Threads.pthread_mutex_unlock(lock);
	}

	// the next command (-1: none ready), and what it hands over, taken under the lock
	@:hxmc.noGc public static function next():Int {
		var b = Mem.stack(8);
		if (Posix.read(commandRead, b, 1).toInt() != 1) return -1;
		return Mem.getU8(b, 0);
	}

	@:hxmc.noGc public static function take(window:Bool):Ptr {
		Threads.pthread_mutex_lock(lock);
		var p = window ? pendingWindow : pendingQueue;
		Threads.pthread_mutex_unlock(lock);
		return p;
	}

	// ---- logcat

	// stdout and stderr, a line at a time (or 1000 bytes), at the info level under the tag "hxmc"
	@:hxmc.callback @:hxmc.noGc static function logThread(arg:Ptr):Ptr {
		var buf = Mem.stack(1024);
		var n = 0;
		while (true) {
			var r = Posix.read(logRead, buf.add(n), 1).toInt();
			if (r <= 0) return Ptr.nil();
			var c = Mem.getU8(buf, n);
			if (c == "\n".code || n == 1000) {
				Mem.setI8(buf, c == "\n".code ? n : n + 1, 0);
				Log.__android_log_write(4, Mem.cstr("hxmc"), buf);
				n = 0;
			} else n++;
		}
	}
}
