import haxe.io.Bytes;
import helder.image.*;
import sys.FileSystem;
import sys.io.File;

// A time-boxed mutation fuzzer of helder.image's decoders (the image-fuzz
// lane, natively): the seed corpus (tests/image's PNG suite, JPEG, GIF,
// WebP and APNG cases) mutated (bits flipped, bytes set to edge values,
// header ints made huge, runs cut, repeated or spliced from another seed),
// each input decoded by Image.decode and AnimatedImage.decode with
// ImageLimits lowered to a small budget. Passes only if every input ends
// in a decode or an ImageError, each within the time budget, every read
// past the end the checked reader (ByteReader) refused surfacing as an
// ImageError (none swallowed into a decode), and the
// process's peak memory stays within its budget (Linux: VmHWM); the input
// that failed is kept in bin/image/fuzz/.
//
//   Fuzz [seconds=20] [seed=1] [per-input seconds=2] [peak MB=768]
class Fuzz {
	static var current = Bytes.alloc(0);
	static var started = 0.0;
	static var limit = 2.0;
	static var state = 1;

	static function main() {
		var args = Sys.args();
		var seconds = args.length > 0 ? Std.parseFloat(args[0]) : 20.0;
		state = args.length > 1 ? Std.parseInt(args[1]) : 1;
		limit = args.length > 2 ? Std.parseFloat(args[2]) : 2.0;
		var peakMb = args.length > 3 ? Std.parseFloat(args[3]) : 768.0;
		// (a small budget: a hostile header's largest legal image is quick to refuse)
		ImageLimits.maxPixels = 4194304;
		ImageLimits.maxSide = 8192;
		ImageLimits.maxMemory = 96 * 1048576.0;
		var seeds:Array<Bytes> = [];
		for (dir in ["png", "jpeg", "gif", "webp", "apng"])
			for (f in FileSystem.readDirectory('tests/image/$dir')) {
				if (StringTools.endsWith(f, ".rgba") || StringTools.endsWith(f, ".json")) continue;
				var b = File.getBytes('tests/image/$dir/$f');
				if (b.length <= 65536) seeds.push(b);
			}
		FileSystem.createDirectory("bin/image/fuzz");
		// (a watchdog: an input that runs past the budget is a hang)
		started = -1;
		sys.thread.Thread.create(() -> while (true) {
			Sys.sleep(0.1);
			var s = started;
			if (s > 0 && Sys.time() - s > limit) {
				File.saveBytes("bin/image/fuzz/hang.bin", current);
				Sys.println('fuzz: an input took over $limit s (bin/image/fuzz/hang.bin)');
				Sys.exit(3);
			}
		});
		var end = Sys.time() + seconds, n = 0, decoded = 0, errors = [0, 0, 0];
		while (Sys.time() < end) {
			var input = mutate(seeds[next(seeds.length)], seeds);
			current = input;
			// (kept for a crash the process cannot report: a native fault)
			File.saveBytes("bin/image/fuzz/current.bin", input);
			for (animated in [false, true]) {
				started = Sys.time();
				var before = ByteReader.refused;
				try {
					if (animated) AnimatedImage.decode(input) else Image.decode(input);
					decoded++;
					// (a read past the end the reader refused, yet a decode: swallowed somewhere)
					if (ByteReader.refused != before) {
						File.saveBytes("bin/image/fuzz/swallowed.bin", input);
						Sys.println('fuzz: a read past the end refused, and still decoded (bin/image/fuzz/swallowed.bin)');
						Sys.exit(5);
					}
				} catch (e:ImageError) {
					errors[cast e.kind]++;
				} catch (e:Dynamic) {
					File.saveBytes("bin/image/fuzz/escaped.bin", input);
					Sys.println('fuzz: not an ImageError: $e (bin/image/fuzz/escaped.bin)');
					Sys.exit(2);
				}
				started = -1;
			}
			n++;
		}
		var peak = peakMemory();
		Sys.println('fuzz: $n inputs in $seconds s: $decoded decoded, ${errors[0]} unsupported, ${errors[1]} corrupt, ${errors[2]} too large, ${ByteReader.refused} reads past the end refused (each an ImageError); peak ${peak < 0 ? "?" : Std.string(Math.round(peak)) + " MB"}');
		if (peak > peakMb) {
			Sys.println('fuzz: peak memory over $peakMb MB');
			Sys.exit(4);
		}
	}

	// (xorshift32)
	static function next(n:Int):Int {
		var x = state;
		x ^= x << 13;
		x ^= x >>> 17;
		x ^= x << 5;
		state = x;
		return ((x >>> 1) % n);
	}

	static function mutate(seed:Bytes, seeds:Array<Bytes>):Bytes {
		var b = seed.sub(0, seed.length);
		for (_ in 0...1 + next(4)) {
			var len = b.length;
			if (len == 0) break;
			switch next(8) {
				case 0: // a bit flipped
					var p = next(len);
					b.set(p, b.get(p) ^ (1 << next(8)));
				case 1: // an edge value
					b.set(next(len), [0, 0xFF, 0x7F, 0x80, 1][next(5)]);
				case 2: // a huge 16- or 32-bit int, near the start (the headers)
					var p = next(Std.int(Math.min(len, 64)));
					for (i in 0...(next(2) == 0 ? 2 : 4))
						if (p + i < len) b.set(p + i, next(2) == 0 ? 0xFF : 0x7F);
				case 3: // cut short
					b = b.sub(0, next(len));
				case 4: // a run repeated
					var p = next(len), n = 1 + next(Std.int(Math.min(64, len - p)));
					var o = new haxe.io.BytesBuffer();
					o.add(b.sub(0, p + n));
					o.add(b.sub(p, len - p));
					b = o.getBytes();
				case 5: // a run of another seed spliced in
					var other = seeds[next(seeds.length)];
					var p = next(len), q = next(other.length), n = Std.int(Math.min(Math.min(len - p, other.length - q), 1 + next(256)));
					b.blit(p, other, q, n);
				case 6: // a run zeroed
					var p = next(len), n = Std.int(Math.min(len - p, 1 + next(32)));
					b.fill(p, n, 0);
				case _: // a byte set at random
					b.set(next(len), next(256));
			}
		}
		return b;
	}

	// the process's peak resident memory in MB (Linux), -1 elsewhere
	static function peakMemory():Float {
		if (!FileSystem.exists("/proc/self/status")) return -1;
		for (line in File.getContent("/proc/self/status").split("\n"))
			if (StringTools.startsWith(line, "VmHWM:")) return Std.parseFloat(StringTools.trim(line.substr(6)).split(" ")[0]) / 1024;
		return -1;
	}
}
