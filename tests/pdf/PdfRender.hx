import helder.pdf.Pdf;

// The pdf lane's renderings: page 1 of each corpus PDF (tests/pdf/corpus)
// by helder.pdf on the CPU at 1.5 pixels a point, and its text, into
// bin/pdf/ours (the lane compares them with pdf.js's, tests/pdf/ref: check.mjs)
class PdfRender {
	static function main() {
		var dir = "tests/pdf/corpus", out = "bin/pdf/ours";
		sys.FileSystem.createDirectory(out);
		var failed = 0;
		for (f in sys.FileSystem.readDirectory(dir)) {
			if (!StringTools.endsWith(f, ".pdf")) continue;
			try {
				var t = haxe.Timer.stamp();
				var doc = Pdf.open(sys.io.File.getBytes('$dir/$f'));
				var b = Pdf.render(doc, 0, 1.5);
				sys.io.File.saveBytes('$out/${f.substr(0, f.length - 4)}.png', helder.image.PngEncoder.encode(b.straight(), b.width, b.height));
				sys.io.File.saveContent('$out/${f.substr(0, f.length - 4)}.txt', Pdf.text(doc.pages[0]));
				Sys.println('$f: ${doc.pages.length} pages${doc.repaired ? " (repaired: " + doc.repairReason + ")" : ""}, page 1 in ${Math.round((haxe.Timer.stamp() - t) * 1000)} ms');
			} catch (e:Dynamic) {
				failed++;
				Sys.println('$f: FAIL ${Std.string(e)}');
			}
		}
		if (failed > 0) Sys.exit(1);
	}
}
