package helder.pack.android;

import haxe.io.Bytes;
import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

// The debug key (DebugKey): its file read back, made on first use from the
// system's random source (Entropy) and kept, a file of another kind refused
function tests() {
	final d = Bytes.ofHex("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721");
	final cert = Apk.certificate(d, Bytes.ofHex("01"), new Date(2026, 0, 1, 0, 0, 0), 30);

	test("its file: the header, the scalar in hex, the certificate in base64", () -> {
		var text = DebugKey.format({d: d, cert: cert});
		equals(text.split("\n")[0], "helder-android-debug-key 1");
		equals(text.split("\n")[1], d.toHex());
		var k = DebugKey.parse(text, "key");
		equals(k.d.toHex(), d.toHex());
		equals(k.cert.toHex(), cert.toHex());
	});
	test("another file refused", () -> {
		equals(Std.string(throws(() -> DebugKey.parse("hxmc-android-debug-key 1\n" + d.toHex() + "\nAA==\n", "k"))),
			"k is not a debug key of helder's (helder-android-debug-key 1)");
		equals(Std.string(throws(() -> DebugKey.parse("helder-android-debug-key 1\n" + StringTools.lpad("", "0", 64) + "\nAA==\n", "k"))), "k: not a P-256 private key");
	});

	// (the system's random source: natively; wasm32-wasi has none here)
	#if (target.name != "hxmc" || hxmc.target != "wasm32-wasi")
	test("random bytes: the system's, not the same twice", () -> {
		var a = Entropy.bytes(32), b = Entropy.bytes(32);
		equals(a.length, 32);
		assert(a.compare(b) != 0);
		equals(Entropy.bytes(0).length, 0);
	});
	test("made on first use, then kept", () -> {
		var dir = "bin/test/pack-key";
		var path = '$dir/sub/debug-key';
		if (FileSystem.exists(path)) FileSystem.deleteFile(path);
		var k = DebugKey.load(path);
		assert(P256.validPrivate(k.d));
		assert(FileSystem.exists(path));
		var again = DebugKey.load(path);
		equals(again.d.toHex(), k.d.toHex());
		equals(again.cert.toHex(), k.cert.toHex());
		// (its certificate: the key's own point in it)
		assert(k.cert.toHex().indexOf(P256.publicKey(k.d).toHex()) > 0);
		var other = DebugKey.make(Date.now());
		assert(other.d.compare(k.d) != 0);
		File.saveContent(path, "nonsense\n");
		assert(Std.string(throws(() -> DebugKey.load(path))).indexOf("is not a debug key of helder's") > 0);
		FileSystem.deleteFile(path);
	});
	#end
}
