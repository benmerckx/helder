package image;

#if (target.name == "hxmc")
import helder.async.*;
import helder.image.*;
import hxmc.unsafe.*;
import helder.test.Test;

// helder.image's PNGs decoded as GC-free jobs (ImageJobs, OffHeapPng)
// against the pixels tests/image/png-cases.mjs wrote, as ImageTest checks
// PngDecoder's: natively and on wasm32-wasi (`bun run helder test
// tests/image --target host,wasm`).
function tests() {
	describe("ImageJobs", () -> {
		var dir = "tests/image/png";
		var names = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".png")) f.substr(0, f.length - 4)];
		names.sort(Reflect.compare);
		test("every case, through the job (interlaced ones by PngDecoder)", async(() -> {
			assert(names.length >= 20, '${names.length} cases');
			var jobs = 0;
			for (n in names) {
				var file = sys.io.File.getBytes('$dir/$n.png'), want = sys.io.File.getBytes('$dir/$n.rgba');
				var info = LibC.malloc(OffHeapPng.INFO);
				var byJob = OffHeapPng.info(IoBuffer.ofBytes(file).ptr, file.length, info) == 0;
				LibC.free(info);
				if (byJob) jobs++;
				var p = ImageJobs.pixels(IoBuffer.ofBytes(file));
				equals({w: p.width, h: p.height}, {w: 13, h: 11}, n);
				var got = p.rgba.getBytes(0, p.rgba.length);
				p.rgba.free();
				equals(got.toHex(), want.toHex(), n);
			}
			assert(jobs >= names.length - 4, '$jobs of ${names.length} by the job');
		}));
		test("decode: an Image over the job's pixels", async(() -> {
			var file = sys.io.File.getBytes('$dir/${names[names.length - 1]}.png');
			var image = ImageJobs.decode(file);
			equals(image.pixels.toHex(), Image.decode(file).pixels.toHex());
			equals(image.source.type, "png");
		}));
		test("a broken file: the job's error", async(() -> {
			// (the image data's first bytes after zlib's header garbled)
			var file = sys.io.File.getBytes('$dir/${names.filter(n -> n.indexOf("interlaced") < 0)[0]}.png');
			var at = file.toString().indexOf("IDAT") + 6;
			for (i in 0...6)
				file.set(at + i, 0xFF);
			var e:helder.jobs.JobError = throwsAsync(() -> ImageJobs.pixels(IoBuffer.ofBytes(file)));
			assert(e.code == OffHeapPng.ERR_DATA || e.code == OffHeapPng.ERR_FORMAT, 'code ${e.code}');
		}));
	});
}
#else
function tests() {}
#end
