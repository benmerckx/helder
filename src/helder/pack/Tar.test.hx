package helder.pack;

import haxe.io.Bytes;
import helder.test.Test;

// The desktop releases' archives: Deflate's raw stream and gzip's file
// inflated back (haxe.zip's inflate), Zip's deflated entries read back,
// Tar's ustar headers (names, modes, sizes, kinds, the checksum, a long
// name split into its prefix), the same bytes for the same input.
function tests() {
	final text = Bytes.ofString([for (i in 0...400) 'line $i of a text that repeats itself\n'].join(""));
	final noise = Bytes.alloc(3000);
	// (xorshift's bytes: nothing for deflate to find)
	var x = 0x2545F491;
	for (i in 0...noise.length) {
		x ^= x << 13;
		x ^= x >>> 17;
		x ^= x << 5;
		noise.set(i, x & 0xff);
	}

	function inflate(raw:Bytes, n:Int):Bytes {
		var out = Bytes.alloc(n);
		var got = new haxe.zip.InflateImpl(new haxe.io.BytesInput(raw), false, false).readBytes(out, 0, n);
		equals(got, n);
		return out;
	}
	function octal(b:Bytes, at:Int, n:Int):Int {
		var v = 0;
		for (i in 0...n) {
			var c = b.get(at + i);
			if (c < "0".code || c > "7".code) break;
			v = v * 8 + c - "0".code;
		}
		return v;
	}

	test("deflate: raw and gzip, inflated back", () -> {
		var raw = Deflate.raw(text);
		assert(raw.length < text.length / 4, "a text shrinks");
		equals(inflate(raw, text.length).compare(text), 0);
		var gz = Deflate.gzip(text);
		equals([gz.get(0), gz.get(1), gz.get(2)], [0x1f, 0x8b, 8]);
		equals(gz.getInt32(gz.length - 8), haxe.crypto.Crc32.make(text));
		equals(gz.getInt32(gz.length - 4), text.length);
		equals(inflate(gz.sub(10, gz.length - 18), text.length).compare(text), 0);
	});
	test("zip: deflated entries read back, the incompressible stored", () -> {
		var z = Zip.stored([
			{name: "a.txt", data: text, align: 1, mode: 0x1a4, deflate: true},
			{name: "noise", data: noise, align: 1, deflate: true},
			{name: "plain", data: text, align: 1}
		]);
		var es = Zip.read(z);
		equals([for (e in es) e.method], [8, 0, 0]);
		equals(es[0].data.compare(text), 0);
		equals(es[0].mode, 0x1a4);
		equals(es[1].data.compare(noise), 0);
		assert(z.length < text.length * 2 + noise.length, "smaller than stored");
	});
	test("tar: ustar headers, data padded to 512, the end", () -> {
		var long = "dir/" + [for (_ in 0...30) "abcd"].join("") + "/file.txt";
		var t = Tar.write([
			{name: "dir"},
			{name: "dir/run", data: Bytes.ofString("#!/bin/sh\n"), mode: 0x1ed},
			{name: "dir/link", link: "run"},
			{name: long, data: text}
		]);
		equals(t.length % 512, 0);
		equals(t.getString(0, 4), "dir/");
		equals(t.get(156), "5".code);
		equals(t.getString(257, 5), "ustar");
		var h = 512;
		equals(t.getString(h, 7), "dir/run");
		equals([octal(t, h + 100, 7), octal(t, h + 124, 11), t.get(h + 156)], [0x1ed, 10, "0".code]);
		var sum = 0;
		for (i in 0...512)
			sum += i >= 148 && i < 156 ? " ".code : t.get(h + i);
		equals(octal(t, h + 148, 6), sum);
		equals(t.getString(h + 512, 10), "#!/bin/sh\n");
		h += 1024;
		equals(t.get(h + 156), "2".code);
		equals(t.getString(h + 157, 3), "run");
		h += 512;
		equals(t.getString(h, 8), "file.txt");
		equals(t.getString(h + 345, long.length - 9), long.substr(0, long.length - 9));
		equals(octal(t, h + 124, 11), text.length);
		equals(t.compare(Tar.write([{name: "dir"}, {name: "dir/run", data: Bytes.ofString("#!/bin/sh\n"), mode: 0x1ed}, {name: "dir/link", link: "run"}, {name: long, data: text}])), 0);
	});
}
