package helder.image;

import haxe.io.Bytes;

// Where a decode's large buffers live: on the collected heap (gc, the
// default), or natively off it (offHeap(): IoBuffers, each a Bytes view
// without a copy), so that a decode as a GC job (the viewer's prefetch)
// leaves the heap small and its collections short, and its pixels move to
// the caller instead of being copied. A decoder given one allocates its
// planes, coefficients and pixels through bytes(); the caller keeps the
// result's buffer (take) and frees the rest (free). Elsewhere (Eval, the
// web) offHeap is gc's.
class ImageMemory {
	public static final gc = new ImageMemory(false);

	public final offHeap:Bool;

	#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
	final buffers:Array<hxmc.unsafe.IoBuffer> = [];
	final views:Array<Bytes> = [];
	#end

	function new(offHeap:Bool)
		this.offHeap = offHeap;

	// a memory of its own, off the heap where it can be
	public static function offHeapMemory():ImageMemory
		return new ImageMemory(#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi") true #else false #end);

	// n zeroed bytes
	public function bytes(n:Int):Bytes {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		if (offHeap) {
			var b = hxmc.unsafe.IoBuffer.alloc(n), v = b.view();
			buffers.push(b);
			views.push(v);
			return v;
		}
		#end
		return Bytes.alloc(n);
	}

	#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
	// bytes as a buffer of the caller's: the one under the view when bytes()
	// gave it (no longer this memory's, not copied), else a copy
	public function take(v:Bytes):hxmc.unsafe.IoBuffer {
		var i = views.indexOf(v);
		if (i < 0) return hxmc.unsafe.IoBuffer.ofBytes(v);
		var b = buffers[i];
		buffers.splice(i, 1);
		views.splice(i, 1);
		return b;
	}
	#end

	// what it gave and was not kept, freed (its views invalid from here)
	public function free() {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		for (b in buffers)
			b.free();
		buffers.resize(0);
		views.resize(0);
		#end
	}
}
