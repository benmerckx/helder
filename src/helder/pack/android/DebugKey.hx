package helder.pack.android;

import haxe.io.Bytes;
import helder.pack.Entropy;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The key APKs are signed with until release signing comes: the user's own
// debug key, made on first use and kept, so that reinstalls keep the
// signature (Android refuses an update signed by another key). Not a
// keystore: a text file, "helder-android-debug-key 1", the private P-256
// scalar in hex, its self-signed certificate (Apk.certificate: CN=Android
// Debug, 30 years) in base64. Where it is: HELDER_ANDROID_KEY, else
// package.json's "helder": {"android": {"key"}}, else
// <cache>/android/debug-key in helder's cache (helder.cli.Android). Its
// scalar and the certificate's serial come from the system's random source
// (helder.pack.Entropy). Ported from hxmc (hxmc.android.Apk's debug key),
// MIT; hxmc's fell back to the time and Math.random on Windows.
class DebugKey {
	public static inline var HEADER = "helder-android-debug-key 1";

	// the key at path, made there when missing
	public static function load(path:String):{d:Bytes, cert:Bytes} {
		if (FileSystem.exists(path)) return parse(File.getContent(path), path);
		var k = make(Date.now());
		var dir = haxe.io.Path.directory(path);
		if (dir != "") FileSystem.createDirectory(dir);
		File.saveContent(path, format(k));
		return k;
	}

	// a new key: a scalar in [1, n), a certificate from the given date
	public static function make(from:Date):{d:Bytes, cert:Bytes} {
		var d = Entropy.bytes(32);
		while (!P256.validPrivate(d))
			d = Entropy.bytes(32);
		var serial = Entropy.bytes(8);
		serial.set(0, serial.get(0) & 0x7f);
		return {d: d, cert: Apk.certificate(d, serial, from, 30)};
	}

	public static function format(k:{d:Bytes, cert:Bytes}):String
		return HEADER + "\n" + k.d.toHex() + "\n" + haxe.crypto.Base64.encode(k.cert) + "\n";

	public static function parse(text:String, path:String):{d:Bytes, cert:Bytes} {
		var l = text.trim().split("\n");
		if (l.length < 3 || l[0].trim() != HEADER) throw '$path is not a debug key of helder\'s ($HEADER)';
		var d = try Bytes.ofHex(l[1].trim()) catch (_:Dynamic) null;
		if (d == null || !P256.validPrivate(d)) throw '$path: not a P-256 private key';
		return {d: d, cert: haxe.crypto.Base64.decode(l[2].trim())};
	}
}
