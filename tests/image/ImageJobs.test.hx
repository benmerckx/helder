package image;

#if (target.name == "hxmc")
import helder.async.*;
import helder.image.*;
import hxmc.unsafe.*;
import helder.test.Test;

// helder.image's PNGs decoded as GC-free jobs (ImageJobs: PngCore's)
// against the pixels tests/image/png-cases.mjs wrote, as ImageTest checks
// PngDecoder's: natively and on wasm32-wasi (`bun run helder test
// tests/image --target host,wasm`).
function tests() {
	describe("ImageJobs", () -> {
		var dir = "tests/image/png";
		var names = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".png")) f.substr(0, f.length - 4)];
		names.sort(Reflect.compare);
		test("every case, through the job", async(() -> {
			assert(names.length >= 20, '${names.length} cases');
			for (n in names) {
				var file = sys.io.File.getBytes('$dir/$n.png'), want = sys.io.File.getBytes('$dir/$n.rgba');
				var p = ImageJobs.pixels(IoBuffer.ofBytes(file));
				equals({w: p.width, h: p.height}, {w: 13, h: 11}, n);
				var got = p.rgba.getBytes(0, p.rgba.length);
				p.rgba.free();
				equals(got.toHex(), want.toHex(), n);
			}
		}));
		test("every case at once, on several workers (each thread's own tables)", async(() -> {
			var files = [for (n in names) sys.io.File.getBytes('$dir/$n.png')];
			var got = Async.scope(task -> Async.all([for (k in 0...3) for (f in files) task.async(_ -> {
				var p = ImageJobs.pixels(IoBuffer.ofBytes(f));
				var b = p.rgba.getBytes(0, p.rgba.length);
				p.rgba.free();
				b.toHex();
			})]));
			for (k in 0...got.length)
				equals(got[k], sys.io.File.getBytes('$dir/${names[k % names.length]}.rgba').toHex(), names[k % names.length]);
		}));
		test("decode: an Image over the job's pixels", async(() -> {
			var file = sys.io.File.getBytes('$dir/${names[names.length - 1]}.png');
			var image = ImageJobs.decode(file);
			equals(image.pixels.toHex(), Image.decode(file).pixels.toHex());
			equals(image.source.type, "png");
		}));
		test("a broken file: the job's error", async(() -> {
			// (the image data's first bytes after zlib's header garbled)
			var file = sys.io.File.getBytes('$dir/${names[0]}.png');
			var at = file.toString().indexOf("IDAT") + 6;
			for (i in 0...6)
				file.set(at + i, 0xFF);
			var e:helder.jobs.JobError = throwsAsync(() -> ImageJobs.pixels(IoBuffer.ofBytes(file)));
			assert(e.code == PngCore.ERR_DATA || e.code == PngCore.ERR_SHORT, 'code ${e.code}');
			assert(StringTools.startsWith(e.message, "PngDecoder: "), e.message);
		}));
	});
}
#else
function tests() {}
#end
