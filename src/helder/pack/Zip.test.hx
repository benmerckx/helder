package helder.pack;

import haxe.io.Bytes;
import helder.test.Test;

// Zip's stored archives: read back, each entry's data at its alignment
// (Android's 0xd935 extra field), Unix modes, the same bytes for the same input
function tests() {
	final a = Bytes.ofString("hello"), b = Bytes.alloc(5000);
	for (i in 0...b.length) b.set(i, i & 0xff);

	test("entries read back, stored, in order", () -> {
		var z = Zip.stored([{name: "a.txt", data: a, align: 1}, {name: "dir/b.bin", data: b, align: 1}]);
		var es = Zip.read(z);
		equals([for (e in es) e.name], ["a.txt", "dir/b.bin"]);
		equals([for (e in es) e.method], [0, 0]);
		equals(es[0].data.toString(), "hello");
		equals(es[1].data.compare(b), 0);
		equals(Zip.entry(z, "dir/b.bin").length, 5000);
		equals(Zip.entry(z, "c"), null);
	});
	test("aligned data: the extra field padded (0xd935)", () -> {
		for (align in [4, 4096, 16384]) {
			var z = Zip.stored([{name: "a", data: a, align: 4}, {name: "lib/x/libmain.so", data: b, align: align}]);
			var es = Zip.read(z);
			equals(es[0].dataAt % 4, 0);
			equals(es[1].dataAt % align, 0);
			// (the local header's extra: id 0xd935, its length, the alignment)
			var at = 0;
			while (z.getInt32(at) != 0x04034b50 || z.getString(at + 30, z.getUInt16(at + 26)) != "lib/x/libmain.so")
				at++;
			var extraAt = at + 30 + z.getUInt16(at + 26);
			equals(z.getUInt16(extraAt), 0xd935);
			equals(z.getUInt16(extraAt + 4), align);
			equals(extraAt + z.getUInt16(at + 28), es[1].dataAt, "the data after the extra field");
		}
	});
	test("Unix modes (an .ipa's executable)", () -> {
		var z = Zip.stored([{name: "x", data: a, align: 1, mode: 0x1ed}, {name: "y", data: a, align: 1, mode: 0x1a4}, {name: "z", data: a, align: 1}]);
		equals([for (e in Zip.read(z)) e.mode], [0x1ed, 0x1a4, null]);
	});
	test("the same input, the same bytes (a fixed date)", () -> {
		var x = Zip.stored([{name: "a", data: a, align: 4}]), y = Zip.stored([{name: "a", data: a, align: 4}]);
		equals(x.compare(y), 0);
	});
	test("not an archive; a CRC that differs", () -> {
		equals(Std.string(throws(() -> Zip.read(Bytes.ofString("nothing here at all, not a zip")))), "not a zip archive: no end of central directory");
		var z = Zip.stored([{name: "a", data: a, align: 1}]);
		z.set(30 + 1, "x".code);
		equals(Std.string(throws(() -> Zip.read(z))), "a: its CRC-32 differs");
	});
}
