package helder.image;

#if (target.name == "hxmc")
import haxe.io.Bytes;
import helder.jobs.Job;
import helder.jobs.Jobs;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// Images decoded as GC-free jobs (helder.jobs: natively on a pool's thread
// in a safe region, in a browser on a worker), so that a large one leaves
// the frames alone: a PNG by OffHeapPng; an interlaced PNG, a JPEG, a GIF
// and a WebP by Image.decode on the calling thread, for now. The rest of
// helder.image depends on nothing; this module on helder.jobs.
//
//   var image = ImageJobs.decode(bytes);                  // in a coroutine
//   var p = ImageJobs.pixels(IoBuffer.ofBytes(bytes));    // {width, height, rgba: an IoBuffer to upload and free}
class ImageJobs {
	// the PNG job: its input the file, its output the RGBA8 pixels (the
	// size: the header's, OffHeapPng.info)
	@:hxmc.unsafe @:hxmc.callback public static function png(job:Job):Int {
		var input = job.input;
		var p = input.ptr, n = input.length, info = Mem.stack(OffHeapPng.INFO);
		var e = OffHeapPng.info(p, n, info);
		if (e != 0) return e;
		var out = job.output(OffHeapPng.bufferLength(info));
		if (out.isNull()) return OffHeapPng.ERR_MEMORY;
		e = OffHeapPng.decode(p, n, info, out);
		if (e != 0) return e;
		job.truncate(Mem.getI32(info, OffHeapPng.WIDTH) * Mem.getI32(info, OffHeapPng.HEIGHT) * 4);
		return 0;
	}

	// an image file decoded, a PNG as a job; its pixels a Bytes over the
	// job's IoBuffer (no copy), which the Image keeps for good (no collector
	// frees native memory on WebAssembly: pixels gives the buffer instead)
	@:coroutine public static function decode(bytes:Bytes):Image {
		var file = isPng(bytes) ? IoBuffer.ofBytes(bytes) : cast Ptr.nil();
		var size = (cast file : Ptr).isNull() ? -1 : header(file);
		if (size < 0) {
			if (!(cast file : Ptr).isNull()) file.free();
			return Image.decode(bytes);
		}
		var px = Jobs.run(ImageJobs.png, file);
		var image = new Image(size >>> 16, size & 0xFFFF, px.view());
		@:privateAccess image.source = {bytes: bytes, type: "png"};
		return image;
	}

	// a PNG file's pixels (the file moved into the job): RGBA8, rows top to
	// bottom, straight alpha, in an IoBuffer the caller frees; an interlaced
	// one through PngDecoder, here
	@:coroutine public static function pixels(file:IoBuffer):{width:Int, height:Int, rgba:IoBuffer} {
		var size = header(file);
		if (size < 0) {
			var d = PngDecoder.decode(file.getBytes(0, file.length));
			file.free();
			return {width: d.width, height: d.height, rgba: IoBuffer.ofBytes(d.rgba)};
		}
		return {width: size >>> 16, height: size & 0xFFFF, rgba: Jobs.run(ImageJobs.png, file)};
	}

	// (the size, width << 16 | height, of a PNG the job decodes; -1 if it does not)
	static function header(file:IoBuffer):Int {
		var info = LibC.malloc(OffHeapPng.INFO);
		var e = OffHeapPng.info(file.ptr, file.length, info);
		var w = Mem.getI32(info, OffHeapPng.WIDTH), h = Mem.getI32(info, OffHeapPng.HEIGHT);
		LibC.free(info);
		return e != 0 || w > 0xFFFF || h > 0xFFFF ? -1 : (w << 16) | h;
	}

	static function isPng(b:Bytes):Bool
		return b.length >= 8 && b.get(0) == 0x89 && b.get(1) == 0x50 && b.get(2) == 0x4E && b.get(3) == 0x47;
}
#end
