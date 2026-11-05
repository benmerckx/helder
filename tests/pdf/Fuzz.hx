import haxe.io.Bytes;
import helder.pdf.Pdf;
import helder.pdf.PdfError;

// The pdf-fuzz lane: the corpus mutated (bytes flipped, runs cut out or
// repeated, the file truncated, numbers made huge) and each mutant opened
// and its first page drawn under small limits, for FUZZ_SECONDS (args[0],
// 30 by default) from FUZZ_SEED (args[1]): each ends in pixels or a
// PdfError, never another exception or a crash (natively)
class Fuzz {
	static function main() {
		var args = Sys.args();
		var seconds = args.length > 0 ? Std.parseFloat(args[0]) : 30, seed = args.length > 1 ? Std.parseInt(args[1]) : 1;
		var dir = "tests/pdf/corpus";
		var files = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".pdf")) sys.io.File.getBytes('$dir/$f')];
		var limits = new helder.pdf.PdfLimits();
		limits.maxDecoded = 64 << 20;
		limits.maxStream = 16 << 20;
		limits.maxOperators = 200000;
		limits.maxImagePixels = 4000000;
		var state = seed, runs = 0, errors = 0, bad = 0;
		inline function rand(n:Int):Int {
			state ^= state << 13;
			state ^= state >>> 17;
			state ^= state << 5;
			return ((state >>> 1) % (n < 1 ? 1 : n));
		}
		var start = haxe.Timer.stamp();
		while (haxe.Timer.stamp() - start < seconds) {
			var src = files[rand(files.length)];
			var b = src.sub(0, src.length);
			if (b.length < 16) continue;
			for (_ in 0...1 + rand(8))
				if (b.length > 16) switch rand(5) {
					case 0: if (b.length > 0) b.set(rand(b.length), rand(256));
					case 1:
						var at = rand(b.length), n = rand(64);
						var c = Bytes.alloc(b.length - Std.int(Math.min(n, b.length - at)));
						c.blit(0, b, 0, at);
						c.blit(at, b, at + Std.int(Math.min(n, b.length - at)), b.length - at - Std.int(Math.min(n, b.length - at)));
						b = c;
					case 2: b = b.sub(0, rand(b.length) + 1);
					case 3:
						// (a digit made a run of nines: huge counts, lengths and offsets)
						var at = rand(b.length);
						if (b.get(at) >= "0".code && b.get(at) <= "9".code) for (k in 0...Std.int(Math.min(9, b.length - at))) if (b.get(at + k) >= "0".code && b.get(at + k) <= "9".code) b.set(at + k, "9".code);
					case _:
						var at = rand(b.length), n = Std.int(Math.min(rand(200), b.length - at));
						var c = Bytes.alloc(b.length + n);
						c.blit(0, b, 0, at + n);
						c.blit(at + n, b, at, b.length - at);
						b = c;
				}
			runs++;
			if (Sys.getEnv("FUZZ_DUMP") != null) sys.io.File.saveBytes("bin/pdf/last.pdf", b);
			try {
				var doc = Pdf.open(b, "", limits);
				if (doc.pages.length > 0) Pdf.render(doc, 0, 0.25);
			} catch (e:PdfError) {
				errors++;
			} catch (e:Dynamic) {
				bad++;
				if (bad == 1) sys.io.File.saveBytes("bin/pdf/bad.pdf", b);
				if (bad <= 5) Sys.println('fuzz: run $runs (seed $seed): ${Std.string(e)}');
			}
		}
		Sys.println('fuzz: $runs mutants in ${Math.round(seconds)} s, $errors ended in a PdfError, $bad in another exception');
		if (bad > 0) Sys.exit(1);
	}
}
