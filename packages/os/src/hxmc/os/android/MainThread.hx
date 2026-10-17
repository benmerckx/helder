package hxmc.os.android;

import hxmc.NativeThread;
import hxmc.os.android.Native;
import hxmc.unsafe.*;

// The activity's main thread (Java's UI thread, where Android's views
// live) from the program's thread (Activity): functions handed to it
// through a pipe its looper watches (run waits until they ran, handling the
// activity's commands meanwhile, so that a callback waiting for one is not
// stuck; post does not wait). The first makes it a Haxe thread
// (NativeThread.attach): Java's calls into the app (the natives of
// classes.dex, hxmc.android.Glue) run Haxe there from then on, while the
// program's thread waits. Frames are Choreographer's on that thread
// (AChoreographer, at the display's vsync), posted while onFrame asks for
// another. What runs there from the system's looper calls Java in a local
// reference frame of its own (Jni).
@:hxmc.android
class MainThread {
	static final lock = new sys.thread.Mutex();
	static var tasks:Array<Void->Void> = [];
	// tasks queued, and run (under the lock)
	static var queued = 0;
	static var finished = 0;
	static var pipeWrite = -1;
	// the main thread's Haxe id, once attached
	static var mainId = 0;
	static var choreographer = Ptr.nil();
	static var framePosted = false;

	// a frame on the main thread: true asks for another
	public static var onFrame:Null<Void->Bool> = null;

	public static function isMain():Bool
		return mainId != 0 && NativeThread.current() == mainId;

	// runs f on the main thread and waits for it (an exception comes back
	// here); on the main thread, at once
	public static function run(f:Void->Void) {
		if (isMain()) {
			f();
			return;
		}
		var error:Dynamic = null, failed = false;
		var mine = enqueue(() -> try f() catch (e:Dynamic) {
			error = e;
			failed = true;
		});
		while (true) {
			lock.acquire();
			var done = finished >= mine;
			lock.release();
			if (done) break;
			AndroidWindow.pump(-1, null);
		}
		if (failed) throw error;
	}

	// runs f on the main thread later
	public static function post(f:Void->Void)
		enqueue(() -> try f() catch (e:Dynamic) Sys.println("hxmc.os: on the main thread: " + Std.string(e)));

	// (the program's thread) the activity's commands, waiting up to seconds (< 0: until something comes)
	public static function wait(seconds:Float)
		AndroidWindow.pump(seconds < 0 ? -1 : Std.int(seconds * 1000), null);

	// wakes the program's thread in wait (something it waits for changed)
	public static function wake()
		Android.ALooper_wake(Activity.looper);

	static function enqueue(f:Void->Void):Int {
		lock.acquire();
		if (pipeWrite < 0) {
			var fds = Mem.stack(8);
			Posix.pipe(fds);
			pipeWrite = Mem.getI32(fds, 4);
			// (ALOOPER_POLL_CALLBACK, ALOOPER_EVENT_INPUT)
			Android.ALooper_addFd(Activity.mainLooper, Mem.getI32(fds, 0), -2, 1, Callback.addr(onTasks), Ptr.nil());
		}
		tasks.push(f);
		var n = ++queued;
		lock.release();
		var b = Mem.stack(8);
		Mem.setI8(b, 0, 1);
		Posix.write(pipeWrite, b, 1);
		return n;
	}

	// the looper's callback (the main thread, not yet a Haxe thread the first time)
	@:hxmc.callback @:hxmc.noGc static function onTasks(fd:Int, events:Int, data:Ptr):Int {
		var b = Mem.stack(64);
		Posix.read(fd, b, 64);
		NativeThread.attach();
		Indirect.call0(Callback.addr(runTasks));
		return 1;
	}

	@:hxmc.callback static function runTasks():Void {
		if (mainId == 0) mainId = NativeThread.current();
		lock.acquire();
		var batch = tasks;
		tasks = [];
		lock.release();
		Jni.pushFrame();
		for (t in batch)
			t();
		Jni.popFrame();
		lock.acquire();
		finished += batch.length;
		lock.release();
		wake();
		if (onFrame != null) requestFrame();
	}

	// a frame on the next vsync (the main thread)
	public static function requestFrame() {
		if (framePosted) return;
		framePosted = true;
		if (choreographer.isNull()) choreographer = Android.AChoreographer_getInstance();
		Android.AChoreographer_postFrameCallback64(choreographer, Callback.addr(frame), Ptr.nil());
	}

	@:hxmc.callback static function frame(nanos:Int64, data:Ptr):Void {
		framePosted = false;
		var f = onFrame;
		if (f == null) return;
		Jni.pushFrame();
		var again = try f() catch (e:Dynamic) {
			Sys.println("hxmc.os: a frame: " + Std.string(e));
			false;
		}
		Jni.popFrame();
		if (again) requestFrame();
	}
}
