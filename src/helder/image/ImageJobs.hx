package helder.image;

#if (target.name == "hxmc")
import haxe.io.Bytes;
import helder.jobs.Job;
import helder.jobs.JobError;
import helder.jobs.Jobs;
import hxmc.ReadOnlySpan;
import hxmc.Span;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;
import hxmc.unsafe.UInt8;

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
		var input = job.input, info:Ptr<UInt8> = cast Mem.stack(PngCore.INFO);
		var e = PngCore.info(ReadOnlySpan.unsafeOf(input.ptr, input.length), Span.unsafeOf(info, PngCore.INFO));
		if (e != 0) return e;
		var w = Mem.getI32(info, PngCore.WIDTH), h = Mem.getI32(info, PngCore.HEIGHT);
		var len = PngCore.bufferLength(ReadOnlySpan.unsafeOf(info, PngCore.INFO), w, h), out = job.output(len);
		if (out.isNull()) return PngCore.ERR_MEMORY;
		e = PngCore.decode(ReadOnlySpan.unsafeOf(input.ptr, input.length), Span.unsafeOf(info, PngCore.INFO), Span.unsafeOf(out, len));
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
		var info = Bytes.alloc(PngCore.INFO);
		var e = PngCore.info(ReadOnlySpan.ofIoBuffer(file), Span.ofBytes(info));
		var w = info.getInt32(PngCore.WIDTH), h = info.getInt32(PngCore.HEIGHT);
		if (e != 0) {
			file.free();
			throw PngCore.message(e, info);
		}
		var rgba = try Jobs.run(ImageJobs.png, file) catch (j:JobError) {
			throw new JobError(j.code, PngCore.message(j.code, Bytes.alloc(PngCore.INFO)));
		}
		return {width: w, height: h, rgba: rgba};
	}
}
#end
