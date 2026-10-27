import haxe.io.Bytes;
import hxmc.unsafe.BytesPtr;
import hxmc.unsafe.Callback;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// The host of tests/bench/jobs.mjs (imports of the module "hxmc_jobs")
@:hxmc.c @:hxmc.lib("hxmc_jobs") extern class JobsHost {
	// the main instance's callbacks: a frame, the decode on the spot (a), the
	// collections so far, room for n bytes, the pixels at p read and freed
	static function main(frame:Ptr, here:Ptr, collections:Ptr, alloc:Ptr, take:Ptr):Void;
	// a worker instance's: the job (the pixels' address), their length
	static function worker(job:Ptr, length:Ptr):Void;
}

// Jobs.hx's measurement as wasm32-wasi (tests/bench/jobs.mjs): the main
// instance's frames (JobsFrame) while the 4K PNG is decoded by PngDecoder
// on the main instance between frames (a) or in a worker's instance of the
// same module, with a heap of its own (b'), its pixels copied out of the
// worker's memory into an ArrayBuffer, transferred, and copied into the main
// instance's. The frames are the host's (setTimeout, as requestAnimationFrame
// would call them).
//   JobsWasm <DejaVuSans.ttf> <photo.png> main|worker
class JobsWasm {
	static var png:Bytes;
	static var pixels:Bytes;

	static function main() {
		var args = Sys.args();
		png = sys.io.File.getBytes(args[1]);
		JobsFrame.garbageKb = Std.parseInt(Sys.getEnv("GARBAGE_KB") ?? "") ?? JobsFrame.garbageKb;
		if (args[2] == "worker") {
			JobsHost.worker(Callback.addr(job), Callback.addr(length));
			return;
		}
		JobsFrame.setup(sys.io.File.getBytes(args[0]));
		JobsHost.main(Callback.addr(frame), Callback.addr(here), Callback.addr(collections), Callback.addr(alloc), Callback.addr(take));
	}

	@:hxmc.callback static function frame():Int {
		JobsFrame.frame();
		return 0;
	}

	@:hxmc.callback static function here():Int {
		var px = helder.image.PngDecoder.decode(png).rgba;
		return sample(px);
	}

	@:hxmc.callback static function collections():Int
		return GcStats.collections();

	@:hxmc.callback static function alloc(n:Int):Int
		return LibC.malloc((n : hxmc.I64)).toI64().toInt();

	// (every 4099th byte: a GPU upload's read, without one)
	@:hxmc.callback static function take(p:Int, n:Int):Int {
		var at:Ptr = Ptr.ofI64(p), s = 0, i = 0;
		while (i < n) {
			s += Mem.getU8(at, i);
			i += 4099;
		}
		LibC.free(at);
		return s;
	}

	// (the pixels' address: valid until the next GC point, the host copies them first)
	@:hxmc.callback static function job():Int {
		pixels = helder.image.PngDecoder.decode(png).rgba;
		return BytesPtr.of(pixels, 0, pixels.length).toI64().toInt();
	}

	@:hxmc.callback static function length():Int
		return pixels.length;

	static function sample(px:Bytes):Int {
		var s = 0, i = 0;
		while (i < px.length) {
			s += px.get(i);
			i += 4099;
		}
		return s;
	}
}
