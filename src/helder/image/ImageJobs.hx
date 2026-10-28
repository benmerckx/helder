package helder.image;

#if (target.name == "hxmc")
import haxe.io.Bytes;
import helder.jobs.Job;
import helder.jobs.JobError;
import helder.jobs.Jobs;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.Mem;

// Images decoded as GC-free jobs (helder.jobs: natively on a pool's thread
// in a safe region, in a browser on a worker), so that a large one leaves
// the frames alone: a PNG by PngCore, the decoder PngDecoder runs on the
// calling thread; a JPEG, a GIF and a WebP by Image.decode on the calling
// thread, for now. The rest of helder.image depends on nothing; this
// module on helder.jobs.
//
//   var image = ImageJobs.decode(bytes);                  // in a coroutine
//   var p = ImageJobs.pixels(IoBuffer.ofBytes(bytes));    // {width, height, rgba: an IoBuffer to upload and free}
class ImageJobs {
	// the PNG job: its input the file, its output the RGBA8 pixels (the
	// size: the header's, PngCore.info)
	@:hxmc.unsafe @:hxmc.callback public static function png(job:Job):Int {
		var input = job.input;
		var p:Raw = input.ptr, n = input.length, info:Raw = Mem.stack(PngCore.INFO);
		var e = PngCore.info(p, n, info);
		if (e != 0) return e;
		var w = info.i32(PngCore.WIDTH), h = info.i32(PngCore.HEIGHT);
		var out = job.output(PngCore.bufferLength(info, w, h));
		if (out.isNull()) return PngCore.ERR_MEMORY;
		e = PngCore.decode(p, n, info, out);
		if (e != 0) return e;
		job.truncate(w * h * 4);
		return 0;
	}

	// an image file decoded, a PNG as a job; its pixels a Bytes over the
	// job's IoBuffer (no copy), which the Image keeps for good (no collector
	// frees native memory on WebAssembly: pixels gives the buffer instead)
	@:coroutine public static function decode(bytes:Bytes):Image {
		if (!(bytes.length >= 8 && bytes.get(0) == 0x89 && bytes.get(1) == 0x50 && bytes.get(2) == 0x4E && bytes.get(3) == 0x47))
			return Image.decode(bytes);
		var p = pixels(IoBuffer.ofBytes(bytes));
		var image = new Image(p.width, p.height, p.rgba.view());
		@:privateAccess image.source = {bytes: bytes, type: "png"};
		return image;
	}

	// a PNG file's pixels (the file moved into the job): RGBA8, rows top to
	// bottom, straight alpha, in an IoBuffer the caller frees; its header's
	// errors thrown here (PngDecoder's), the data's as a JobError (PngCore's
	// code, PngDecoder's message)
	@:coroutine public static function pixels(file:IoBuffer):{width:Int, height:Int, rgba:IoBuffer} {
		var info = Raw.malloc(PngCore.INFO);
		var e = PngCore.info(file.ptr, file.length, info);
		var w = info.i32(PngCore.WIDTH), h = info.i32(PngCore.HEIGHT);
		var m = e != 0 ? PngCore.message(e, info) : null;
		info.free();
		if (m != null) {
			file.free();
			throw m;
		}
		var rgba = try Jobs.run(ImageJobs.png, file) catch (j:JobError) {
			var i = Raw.malloc(PngCore.INFO);
			i.fill(0, PngCore.INFO);
			var m = PngCore.message(j.code, i);
			i.free();
			throw new JobError(j.code, m);
		}
		return {width: w, height: h, rgba: rgba};
	}
}
#end
