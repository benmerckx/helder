package helder.pack.android;

import haxe.io.Bytes;
import helder.pack.android.Axml.el;

// An Android app without the SDK, around the program's shared library
// (hxmc's output for android-arm64 or android-x86_64, named libmain.so: its
// soname): lib/<abi>/libmain.so, which NativeActivity loads (the
// framework's activity: hasCode="false", no classes.dex; with Java's
// listeners Glue's classes.dex, and with views its org.hxmc.Activity, a
// NativeActivity whose window draws views, in the system's DayNight
// theme), and an AndroidManifest.xml in binary XML (Axml) naming it; no
// resources.arsc (the label is a plain string, the theme a framework
// resource). The zip stores everything uncompressed, the library aligned to
// 16 KB (loaded in place: extractNativeLibs="false"; Android 15's 16 KB
// pages) and the rest to 4 bytes, as zipalign -P 16 does; then the APK
// Signature Scheme v2 block before the central directory, signed with ECDSA
// P-256 and SHA-256 (P256) by a key (DebugKey: the user's debug key, made
// on first use). The app is debuggable (no release signing yet). Pure: the
// bytes in, the APK's out (helder.cli.Android writes it). Ported from hxmc
// (hxmc.android.Apk), MIT.
class Apk {
	static inline var LIB = "main";
	static inline var PAGE = 16384;
	// the v2 signature scheme's block id, the algorithm (ECDSA with SHA2-256)
	static inline var V2_ID = 0x7109871a;
	static inline var ECDSA_SHA256 = 0x0201;

	// the APK's library, as hxmc names it (its soname) and NativeActivity loads it
	public static inline var LIBRARY = "libmain.so";

	// the ABI's directory in the APK
	public static function abiDir(target:String):String
		return switch target {
			case "android-arm64": "arm64-v8a";
			case "android-x86_64": "x86_64";
			case t: throw 'no Android ABI for $t';
		}

	// whether id is an application id (a.b.c, each part a Java identifier)
	public static function validId(id:String):Bool
		return ~/^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$/.match(id);

	// the signed APK: the library for the target's ABI, classes.dex (dex:
	// Glue's, when the program has listeners; views: org.hxmc.Activity the
	// activity), the manifest of the app's options, signed with the key
	public static function write(so:Bytes, target:String, dex:Null<Bytes>, views:Bool, app:ApkOptions, key:{d:Bytes, cert:Bytes}):Bytes {
		if (!validId(app.id)) throw 'the application id ${app.id} is not one (a.b.c: letters, digits, _)';
		var m = manifest(app.id, app.label, app.versionCode, app.versionName, app.minSdk, app.targetSdk, dex != null, views, app.permissions, app.orientation);
		var entries:Array<helder.pack.Zip.ZipEntry> = [{name: "AndroidManifest.xml", data: m, align: 4}];
		if (dex != null) entries.push({name: "classes.dex", data: dex, align: 4});
		entries.push({name: "lib/" + abiDir(target) + "/" + LIBRARY, data: so, align: PAGE});
		return sign(helder.pack.Zip.stored(entries), key.d, key.cert);
	}

	// ---- the manifest

	// (orientation: "portrait" (screenOrientation portrait), "landscape"
	// (sensorLandscape: either way up, as the phone is held), else any: none
	// written, the sensor's and the user's rotation lock's)
	public static function manifest(pkg:String, label:String, versionCode:Int, versionName:String, minSdk:Int, targetSdk:Int, code = false, views = false,
			?permissions:Array<String>, ?orientation:String):Bytes {
		inline function s(n:String, v:String):Axml.Attr
			return {android: true, name: n, type: Axml.STRING, string: v};
		inline function i(n:String, v:Int, hex = false):Axml.Attr
			return {android: true, name: n, type: hex ? Axml.INT_HEX : Axml.INT_DEC, value: v};
		inline function b(n:String, v:Bool):Axml.Attr
			return {android: true, name: n, type: Axml.BOOLEAN, value: v ? -1 : 0};
		// orientation, screenSize, screenLayout, smallestScreenSize, keyboard,
		// keyboardHidden, navigation, uiMode, density, layoutDirection: the
		// activity stays (the program's thread keeps its window)
		var configChanges = 0x80 | 0x400 | 0x100 | 0x800 | 0x10 | 0x20 | 0x40 | 0x200 | 0x1000 | 0x2000;
		var uses = [];
		if (permissions != null)
			for (n in permissions)
				uses.push(el("uses-permission", [s("name", n.indexOf(".") < 0 ? "android.permission." + n : n)]));
		var activity:Array<Axml.Attr> = [
			s("name", views ? Glue.ACTIVITY : "android.app.NativeActivity"),
			s("label", label),
			b("exported", true),
			i("configChanges", configChanges, true),
			// @android:style/Theme.NoTitleBar.Fullscreen; with views
			// Theme.DeviceDefault.DayNight (API 29: the system's look, light or dark)
			{android: true, name: "theme", type: Axml.REFERENCE, value: views ? 0x010302e3 : 0x01030007}
		];
		if (orientation == "portrait") activity.push(i("screenOrientation", 1)) else if (orientation == "landscape") activity.push(i("screenOrientation", 6));
		var root = el("manifest", [
			{android: false, name: "package", type: Axml.STRING, string: pkg},
			i("versionCode", versionCode),
			s("versionName", versionName)
		], [
			el("uses-sdk", [i("minSdkVersion", minSdk), i("targetSdkVersion", targetSdk)]),
		].concat(uses).concat([
			el("uses-feature", [i("glEsVersion", 0x30000, true), b("required", true)]),
			el("application", [s("label", label), b("hasCode", code), b("debuggable", true), b("extractNativeLibs", false)], [
				el("activity", activity, [
					el("meta-data", [s("name", "android.app.lib_name"), s("value", LIB)]),
					el("intent-filter", [], [
						el("action", [s("name", "android.intent.action.MAIN")]),
						el("category", [s("name", "android.intent.category.LAUNCHER")])
					])
				])
			])
		]));
		return Axml.encode(root);
	}

	// ---- the signature (APK Signature Scheme v2)

	// a length-prefixed (uint32 little-endian) blob
	static function lp(b:Bytes):Bytes {
		var o = new helder.pack.Buf(b.length + 4);
		o.u32(b.length);
		o.bytes(b);
		return o.toBytes();
	}

	static function cat(parts:Array<Bytes>):Bytes {
		var b = new haxe.io.BytesBuffer();
		for (p in parts)
			b.add(p);
		return b.getBytes();
	}

	// the digest of the v2 scheme over sections of the file: each split into
	// 1 MB chunks, SHA-256(0xa5, length, chunk) per chunk, then
	// SHA-256(0x5a, count, the chunks' digests)
	public static function contentDigest(sections:Array<Bytes>):Bytes {
		var digests = new haxe.io.BytesBuffer(), count = 0;
		for (s in sections) {
			var at = 0;
			while (at < s.length) {
				var n = s.length - at < 1 << 20 ? s.length - at : 1 << 20;
				var c = Bytes.alloc(5 + n);
				c.set(0, 0xa5);
				c.setInt32(1, n);
				c.blit(5, s, at, n);
				digests.add(haxe.crypto.Sha256.make(c));
				count++;
				at += n;
			}
		}
		var d = digests.getBytes();
		var top = Bytes.alloc(5 + d.length);
		top.set(0, 0x5a);
		top.setInt32(1, count);
		top.blit(5, d, 0, d.length);
		return haxe.crypto.Sha256.make(top);
	}

	// the key's SubjectPublicKeyInfo (id-ecPublicKey, prime256v1)
	public static function publicKeyInfo(d:Bytes):Bytes
		return Der.seq([Der.seq([Der.oid("1.2.840.10045.2.1"), Der.oid("1.2.840.10045.3.1.7")]), Der.bitString(P256.publicKey(d))]);

	// a self-signed X.509 v3 certificate of the key (CN=Android Debug, O=Android, C=US, as the SDK's debug key)
	public static function certificate(d:Bytes, serial:Bytes, from:Date, years:Int):Bytes {
		var name = Der.seq([
			Der.set([Der.seq([Der.oid("2.5.4.6"), Der.printable("US")])]),
			Der.set([Der.seq([Der.oid("2.5.4.10"), Der.utf8("Android")])]),
			Der.set([Der.seq([Der.oid("2.5.4.3"), Der.utf8("Android Debug")])])
		]);
		var alg = Der.seq([Der.oid("1.2.840.10045.4.3.2")]); // ecdsa-with-SHA256
		var until = new Date(from.getFullYear() + years, from.getMonth(), from.getDate(), from.getHours(), from.getMinutes(), from.getSeconds());
		var tbs = Der.seq([
			Der.explicit(0, Der.small(2)), Der.integer(serial), alg, name, Der.seq([Der.time(from), Der.time(until)]), name, publicKeyInfo(d)
		]);
		return Der.seq([tbs, alg, Der.bitString(P256.sign(d, tbs))]);
	}

	// the zip with its v2 signing block before the central directory
	public static function sign(zip:Bytes, d:Bytes, cert:Bytes):Bytes {
		// the end of central directory (no comment: the last 22 bytes) and the directory's offset
		var eocdAt = zip.length - 22;
		if (zip.getInt32(eocdAt) != 0x06054b50) throw "APK: no end of central directory";
		var cdAt = zip.getInt32(eocdAt + 16);
		var contents = zip.sub(0, cdAt), cd = zip.sub(cdAt, eocdAt - cdAt), eocd = zip.sub(eocdAt, 22);
		// (the digest sees the directory's offset as the block's: the unsigned zip's)
		var digest = contentDigest([contents, cd, eocd]);
		var spki = publicKeyInfo(d);
		var digests = lp(lp(cat([int(ECDSA_SHA256), lp(digest)])));
		var signedData = cat([digests, lp(lp(cert)), lp(Bytes.alloc(0))]);
		var signatures = lp(lp(cat([int(ECDSA_SHA256), lp(P256.sign(d, signedData))])));
		var signer = cat([lp(signedData), signatures, lp(spki)]);
		var value = lp(lp(signer));
		// the block: size, pairs (length, id, value), size, magic
		var pair = new helder.pack.Buf(value.length + 12);
		pair.u64(value.length + 4, 0);
		pair.u32(V2_ID);
		pair.bytes(value);
		var size = pair.len + 8 + 16;
		var block = new helder.pack.Buf(size + 8);
		block.u64(size, 0);
		block.buf(pair);
		block.u64(size, 0);
		block.str("APK Sig Block 42");
		var out = new helder.pack.Buf(zip.length + block.len);
		out.bytes(contents);
		out.buf(block);
		out.bytes(cd);
		var e = eocd.sub(0, 22);
		e.setInt32(16, cdAt + block.len);
		out.bytes(e);
		return out.toBytes();
	}

	static function int(v:Int):Bytes {
		var b = Bytes.alloc(4);
		b.setInt32(0, v);
		return b;
	}
}

// what the manifest says (helder.cli.Android: package.json's "helder" key)
typedef ApkOptions = {
	// the application id (package), the launcher's label
	id:String,
	label:String,
	versionCode:Int,
	versionName:String,
	// 29 (Bionic's ELF TLS) and 35 by default
	minSdk:Int,
	targetSdk:Int,
	// uses-permission: android.permission.<name> unless it has a dot
	permissions:Array<String>,
	// "portrait", "landscape" or "any" (null: any)
	?orientation:String,
}
