package hxmc.dev;

import hxmc.unsafe.*;

// The dev host (hxmc dev natively; docs/dev.md, "No reloads"): one process
// for the whole session, which loads each build of the program as a shared
// library and runs it (hxmc.dev.Hosted). It knows nothing of windows or
// GPUs: it keeps a state block that the builds hand over to each other (the
// window, the GPU context and surface, the display connection, made by the
// first build and kept by the host's process), and the libraries loaded.
//   host <first library>
// A build that hands over names the next library in the state block; the
// host opens it (before closing the old one, so that the system libraries
// they share, X11's, EGL's, the GPU driver, stay loaded), closes the old one
// and runs the new one. A build that ends by itself (its window closed)
// names none: the host ends. Built once per session by dev.mjs (-D
// hxmc.libc=glibc).
class DevHost {
	// the state block: slots of 8 bytes (hxmc.dev.Hosted's), then the next
	// build's library, a C string at NEXT
	public static inline var NEXT = 128;
	public static inline var NEXT_BYTES = 1024;
	public static inline var BYTES = NEXT + NEXT_BYTES;

	static function main() {
		var path = Sys.args()[0];
		var state = LibC.malloc((BYTES : Int64));
		LibC.memset(state, 0, (BYTES : Int64));
		var old = Ptr.nil();
		while (path != null && path != "") {
			var lib = Arena.scopedValue(a -> Posix.dlopen(a.cstring(path), 2)); // (RTLD_NOW)
			if (lib.isNull()) {
				Sys.stderr().writeString("hxmc dev host: " + ((cast Posix.dlerror() : CString).toString()) + "\n");
				Sys.exit(1);
			}
			if (!old.isNull()) Posix.dlclose(old);
			old = lib;
			var slot = Posix.dlsym(lib, Mem.cstr("hxmc_dev_state")), run = Posix.dlsym(lib, Mem.cstr("hxmc_dev_run"));
			if (slot.isNull() || run.isNull()) {
				Sys.stderr().writeString("hxmc dev host: " + path + " is not a program for a dev host (hxmc_dev_state, hxmc_dev_run)\n");
				Sys.exit(1);
			}
			Mem.setPtr(slot, 0, state);
			Mem.setI8(state, NEXT, 0);
			HostCall.run(run, 0);
			path = (cast state.add(NEXT) : CString).toString();
		}
	}
}

@:hxmc.c extern class HostCall {
	@:hxmc.indirect static function run(f:Ptr, arg:Int):Int;
}
