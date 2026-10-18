package hxmc.dev;

#if (hxmc.dev_host && !macro)
import hxmc.unsafe.*;

// A program run by a dev host (hxmc dev natively; docs/dev.md, "No
// reloads"): built as a shared library (-D hxmc.shared -D hxmc.dev_host,
// dev.mjs adds them), loaded by the host (hxmc.dev.DevHost) with a fresh
// name per build, the old one closed once it has handed over. The host
// writes its state block's address into the export hxmc_dev_state and calls
// hxmc_dev_run, which runs the program's main on a thread of its own (as an
// Android app's entry does) and returns when main has. The state block
// outlives every program: what must survive a swap (the window, the GPU
// context and surface, the display connection) is left there by the build
// handing over (instead of destroyed) and taken by the next one (instead of
// made): hxmc.os's windows and hxmc.gfx's back ends look here first. Only
// these handles and the snapshot cross: each build has its own runtime and
// heap.
class Hosted {
	// the state block's slots (8 bytes each)
	public static inline var X11_DISPLAY = 1;
	public static inline var X11_WINDOW = 2;
	public static inline var EGL_DISPLAY = 3;
	public static inline var EGL_CONFIG = 4;
	public static inline var EGL_CONTEXT = 5;
	public static inline var EGL_SURFACE = 6;
	// (the window's size when it was handed over)
	public static inline var WIDTH = 7;
	public static inline var HEIGHT = 8;
	// the next build's library: a C string at DevHost.NEXT (empty: none, the host ends)
	static inline var NEXT = DevHost.NEXT;
	static inline var NEXT_BYTES = DevHost.NEXT_BYTES;

	@:keep @:hxmc.export("hxmc_dev_state") static var state:Ptr;

	// true while this build hands over: what the host keeps is left, not destroyed
	public static var handingOver(default, null) = false;

	public static inline function get(slot:Int):Ptr
		return Mem.getPtr(state, slot * 8);

	public static inline function set(slot:Int, v:Ptr)
		Mem.setPtr(state, slot * 8, v);

	public static function hosted():Bool
		return !state.isNull();

	// this build hands over to the library at path (Hot, at a reload)
	public static function handOver(path:String) {
		handingOver = true;
		var b = haxe.io.Bytes.ofString(path);
		var n = b.length < NEXT_BYTES - 1 ? b.length : NEXT_BYTES - 1;
		for (i in 0...n)
			Mem.setI8(state, NEXT + i, b.get(i));
		Mem.setI8(state, NEXT + n, 0);
	}

	// the host's call: main on a thread of its own (a large stack, as the
	// runtime's main thread has), joined
	@:keep @:hxmc.export("hxmc_dev_run") @:hxmc.noGc static function run(arg:Int):Int {
		var attr = Mem.stack(128), t = Mem.stack(16);
		HostThreads.pthread_attr_init(attr);
		HostThreads.pthread_attr_setstacksize(attr, (256 : Int64) << 20);
		if (HostThreads.pthread_create(t, attr, Callback.addr(thread), Ptr.nil()) != 0) return -1;
		HostThreads.pthread_join(Mem.getI64(t, 0), Ptr.nil());
		return 0;
	}

	@:hxmc.callback @:hxmc.noGc static function thread(arg:Ptr):Ptr {
		var argv = Mem.stack(16);
		Mem.setPtr(argv, 0, Mem.cstr("app"));
		Mem.setPtr(argv, 8, Ptr.nil());
		HostThreads.main(1, argv);
		// (the heap given back: the host closes the library next)
		hxmc.rt.Gc.releaseHeap();
		return Ptr.nil();
	}
}

@:hxmc.c @:hxmc.fast extern class HostThreads {
	static function pthread_attr_init(a:Ptr):Int;
	static function pthread_attr_setstacksize(a:Ptr, n:Int64):Int;
	static function pthread_create(t:Ptr, attr:Ptr, entry:Ptr, arg:Ptr):Int;
	static function pthread_join(t:Int64, ret:Ptr):Int;
	static function getpid():Int;
	// the program's main (hxmc's generated one, C's convention)
	static function main(argc:Int, argv:Ptr):Int;
}
#end
