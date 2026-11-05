package helder.image;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.test.Test;

// Hostile headers, decoder by decoder: the largest sides each format
// writes, products that overflow an Int, frames larger than their screen,
// chunks past the file's end, and every test image cut short. Each ends in
// a decode or an ImageError (TooLarge, Corrupt), never another exception,
// a crash or an allocation of the header's size. Natively and on wasm32.
function tests() {
	describe("ImageLimits", () -> {
		test("JPEG: 65535x65535 (the product overflows an Int) and a strip within the pixels but not the memory", () -> {
			equals(outcome(() -> JpegDecoder.decode(jpeg(65535, 65535))), "too large");
			equals(outcome(() -> JpegDecoder.decode(jpeg(65535, 4096))), "too large");
			equals(outcome(() -> Image.decode(jpeg(65535, 65535))), "too large");
			// (a frame header cut short, a segment past the end)
			var cut = jpeg(16, 16).sub(0, 12);
			equals(outcome(() -> JpegDecoder.decode(cut)), "corrupt");
		});
		test("PNG: the largest sides, a width past an Int, past maxSide", () -> {
			equals(outcome(() -> PngDecoder.decode(png(65535, 65535))), "too large");
			equals(outcome(() -> PngDecoder.decode(png(0x7FFFFFFF, 1))), "too large");
			equals(outcome(() -> PngDecoder.decode(png(70000, 10))), "too large");
			equals(outcome(() -> PngDecoder.frames(png(65535, 65535))), "too large");
		});
		test("APNG: a frame whose x + width overflows", () -> {
			var b = new BytesBuffer();
			b.add(Bytes.ofHex("89504e470d0a1a0a"));
			chunk(b, "IHDR", be([4, 4]).toHex() + "0806000000");
			chunk(b, "acTL", be([1, 0]).toHex());
			chunk(b, "fcTL", be([0, 0x7FFFFFF0, 4, 0x20, 0]).toHex() + "000100640000");
			chunk(b, "IDAT", "789c030000000001");
			chunk(b, "IEND", "");
			equals(outcome(() -> PngDecoder.frames(b.getBytes())), "corrupt");
		});
		test("GIF: the largest screen, a frame larger than its screen, a cut table", () -> {
			equals(outcome(() -> GifDecoder.decode(gif(65535, 65535, 1, 1))), "too large");
			equals(outcome(() -> GifDecoder.frames(gif(1, 1, 65535, 65535))), "too large");
			// (larger than the screen but within the limits: its outside cut)
			var d = GifDecoder.decode(gif(10, 10, 300, 300));
			equals([d.width, d.height, d.rgba.length], [10, 10, 400]);
			equals(outcome(() -> GifDecoder.decode(gif(10, 10, 1, 1).sub(0, 15))), "corrupt");
		});
		test("WebP: VP8L and VP8 at their largest, a VP8X canvas of 2^24, a chunk past the end", () -> {
			equals(outcome(() -> WebpDecoder.decode(riff("VP8L", vp8l(16384, 16384)))), "too large");
			equals(outcome(() -> WebpDecoder.decode(riff("VP8 ", vp8(16383, 16383)))), "too large");
			var x = Bytes.alloc(10);
			x.set(0, 0x02);
			for (i in 4...10)
				x.set(i, 0xFF);
			var anim = new BytesBuffer();
			anim.add(sub("VP8X", x));
			anim.add(sub("ANMF", Bytes.alloc(16)));
			equals(outcome(() -> WebpDecoder.frames(riffOf(anim.getBytes()))), "too large");
			equals(outcome(() -> WebpDecoder.decode(riffOf(anim.getBytes()))), "too large");
			var past = riff("VP8L", vp8l(4, 4));
			past.setInt32(16, 0x7FFFFFF0);
			equals(outcome(() -> WebpDecoder.decode(past)), "corrupt");
			equals(outcome(() -> WebpDecoder.decode(riff("VP8 ", Bytes.alloc(4)))), "corrupt");
		});
		test("the limits are the caller's: pixels, a side, the memory", () -> {
			var file = sys.io.File.getBytes("tests/image/png/rgb8.png");
			var keep = [ImageLimits.maxPixels, ImageLimits.maxSide, ImageLimits.maxMemory];
			try {
				ImageLimits.maxPixels = 100;
				equals(outcome(() -> Image.decode(file)), "too large");
				ImageLimits.maxPixels = keep[0];
				ImageLimits.maxSide = 12;
				equals(outcome(() -> Image.decode(file)), "too large");
				ImageLimits.maxSide = Std.int(keep[1]);
				ImageLimits.maxMemory = 400;
				equals(outcome(() -> Image.decode(file)), "too large");
				ImageLimits.maxMemory = keep[2];
				equals(outcome(() -> Image.decode(file)), "ok");
			} catch (e:Dynamic) {
				ImageLimits.maxPixels = keep[0];
				ImageLimits.maxSide = Std.int(keep[1]);
				ImageLimits.maxMemory = keep[2];
				throw e;
			}
		});
		test("not an image: Unsupported", () -> {
			equals(outcome(() -> Image.decode(Bytes.ofString("hello, world"))), "unsupported");
			equals(outcome(() -> AnimatedImage.decode(Bytes.ofString("GIF89a"))), "corrupt");
		});
		test("every test image cut short: a decode or an ImageError", () -> {
			var n = 0;
			for (dir in ["png", "jpeg", "gif", "webp", "apng"]) {
				var path = 'tests/image/$dir';
				for (f in sys.FileSystem.readDirectory(path)) {
					if (StringTools.endsWith(f, ".rgba") || StringTools.endsWith(f, ".json")) continue;
					var file = sys.io.File.getBytes('$path/$f');
					if (file.length > 60000) continue;
					var step = Std.int(Math.max(1, file.length / 12));
					var at = 1;
					while (at < file.length) {
						var cut = file.sub(0, at);
						outcome(() -> Image.decode(cut));
						if (dir != "jpeg") outcome(() -> AnimatedImage.decode(cut));
						at += step;
						n++;
					}
				}
			}
			assert(n > 400, '$n cuts');
		});
	});
}

// (a decode's end: "ok", or the ImageError's kind; anything else thrown fails the test)
private function outcome(f:() -> Dynamic):String {
	try {
		f();
		return "ok";
	} catch (e:ImageError) {
		return Std.string(e.kind);
	}
}

// (a JPEG of a frame header alone: SOI, SOF0 of three components, EOI)
private function jpeg(w:Int, h:Int):Bytes
	return Bytes.ofHex("ffd8ffc00011" + "08" + hex16(h) + hex16(w) + "03011100021100031100" + "ffd9");

private function hex16(v:Int):String
	return StringTools.hex((v >> 8) & 255, 2) + StringTools.hex(v & 255, 2);

private function be(vs:Array<Int>):Bytes {
	var b = Bytes.alloc(4 * vs.length);
	for (i in 0...vs.length) {
		b.set(4 * i, vs[i] >>> 24);
		b.set(4 * i + 1, (vs[i] >> 16) & 255);
		b.set(4 * i + 2, (vs[i] >> 8) & 255);
		b.set(4 * i + 3, vs[i] & 255);
	}
	return b;
}

private function chunk(b:BytesBuffer, name:String, hex:String) {
	var data = Bytes.ofHex(hex), body = new BytesBuffer();
	body.addString(name);
	body.add(data);
	var crc = haxe.crypto.Crc32.make(body.getBytes());
	b.add(be([data.length]));
	b.addString(name);
	b.add(data);
	b.add(be([crc]));
}

// (a PNG of RGBA8 whose image data is one empty stored block)
private function png(w:Int, h:Int):Bytes {
	var b = new BytesBuffer();
	b.add(Bytes.ofHex("89504e470d0a1a0a"));
	chunk(b, "IHDR", be([w, h]).toHex() + "0806000000");
	chunk(b, "IDAT", "789c030000000001");
	chunk(b, "IEND", "");
	return b.getBytes();
}

// (a GIF of a w x h screen, two colours, and one frame of fw x fh)
private function gif(w:Int, h:Int, fw:Int, fh:Int):Bytes {
	inline function le(v:Int)
		return StringTools.hex(v & 255, 2) + StringTools.hex((v >> 8) & 255, 2);
	return Bytes.ofHex("474946383961" + le(w) + le(h) + "800000" + "000000ffffff" + "2c" + "00000000" + le(fw) + le(fh) + "00" + "02" + "024c01" + "00" + "3b");
}

// (a VP8L header: w x h, no alpha, version 0; then no data)
private function vp8l(w:Int, h:Int):Bytes {
	var b = Bytes.alloc(5), v = (w - 1) | ((h - 1) << 14);
	b.set(0, 0x2F);
	b.setInt32(1, v);
	return b;
}

// (a VP8 key frame's header: w x h, its first partition empty)
private function vp8(w:Int, h:Int):Bytes {
	var b = Bytes.alloc(10);
	b.set(0, 0x10);
	b.set(3, 0x9D);
	b.set(4, 0x01);
	b.set(5, 0x2A);
	b.setUInt16(6, w);
	b.setUInt16(8, h);
	return b;
}

private function sub(tag:String, data:Bytes):Bytes {
	var b = new BytesBuffer();
	b.addString(tag);
	var n = Bytes.alloc(4);
	n.setInt32(0, data.length);
	b.add(n);
	b.add(data);
	if (data.length & 1 == 1) b.addByte(0);
	return b.getBytes();
}

private function riffOf(chunks:Bytes):Bytes {
	var b = new BytesBuffer();
	b.addString("RIFF");
	var n = Bytes.alloc(4);
	n.setInt32(0, chunks.length + 4);
	b.add(n);
	b.addString("WEBP");
	b.add(chunks);
	return b.getBytes();
}

private function riff(tag:String, data:Bytes):Bytes
	return riffOf(sub(tag, data));
