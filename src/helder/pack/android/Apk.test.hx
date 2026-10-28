package helder.pack.android;

import haxe.io.Bytes;
import helder.pack.Zip;
import helder.pack.android.Apk.ApkOptions;
import helder.test.Test;

using StringTools;

// The APK (Apk): the zip's layout and alignment, the manifest read back
// (Axml.dump), the debug key's certificate parsed back, the v2 signing
// block found and its digest recomputed (the signature too: RFC 6979's is
// deterministic, so the same bytes again), classes.dex's structure (Dex.check)
function tests() {
	final d = Bytes.ofHex("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721");
	final cert = Apk.certificate(d, Bytes.ofHex("0102030405060708"), new Date(2026, 0, 1, 0, 0, 0), 30);
	final app:ApkOptions = {
		id: "org.example.hello",
		label: "Hello",
		versionCode: 3,
		versionName: "1.2",
		minSdk: 29,
		targetSdk: 35,
		permissions: ["INTERNET", "com.example.permission.X"]
	};
	// (a library's stand-in: what the zip stores is its bytes, whatever they are)
	final so = Bytes.alloc(70000);
	for (i in 0...so.length) so.set(i, (i * 7) & 0xff);

	describe("the certificate", () -> {
		test("an X.509 v3 certificate of the key, parsed back", () -> {
			var c = Der.read(cert, 0);
			equals(c.tag, 0x30);
			equals(c.end, cert.length);
			var parts = Der.children(cert, c);
			equals(parts.length, 3);
			var tbs = Der.children(cert, parts[0]);
			// [0] { INTEGER 2 }: v3
			equals(tbs[0].tag, 0xa0);
			equals(cert.sub(tbs[0].start, tbs[0].end - tbs[0].start).toHex(), "020102");
			equals(cert.sub(tbs[1].start, tbs[1].end - tbs[1].start).toHex(), "0102030405060708");
			// ecdsa-with-SHA256, the issuer the subject (self-signed)
			equals(cert.sub(tbs[2].start, tbs[2].end - tbs[2].start).toHex(), "06082a8648ce3d040302");
			equals(cert.sub(tbs[3].at, tbs[3].end - tbs[3].at).toHex(), cert.sub(tbs[5].at, tbs[5].end - tbs[5].at).toHex());
			assert(cert.sub(tbs[5].at, tbs[5].end - tbs[5].at).toString().indexOf("Android Debug") >= 0);
			var validity = Der.children(cert, tbs[4]);
			// (30 years: until 2056, a GeneralizedTime)
			equals([for (v in validity) cert.getString(v.start, v.end - v.start)], ["260101000000Z", "20560101000000Z"]);
			equals([for (v in validity) v.tag], [0x17, 0x18]);
			// the key: id-ecPublicKey on prime256v1, the uncompressed point
			var spki = Der.children(cert, tbs[6]);
			equals(cert.sub(spki[0].start, spki[0].end - spki[0].start).toHex(), "06072a8648ce3d020106082a8648ce3d030107");
			equals(cert.sub(spki[1].start, spki[1].end - spki[1].start).toHex(), "00" + P256.publicKey(d).toHex());
			// the signature: of the tbsCertificate, by the key
			equals(cert.sub(parts[2].start + 1, parts[2].end - parts[2].start - 1).toHex(),
				P256.sign(d, cert.sub(parts[0].at, parts[0].end - parts[0].at)).toHex());
		});
		test("UTCTime before 2050, GeneralizedTime from then", () -> {
			equals(Der.time(new Date(2049, 11, 31, 23, 59, 59)).toString().substr(2), "491231235959Z");
			equals(Der.time(new Date(2050, 0, 1, 0, 0, 0)).toString().substr(2), "20500101000000Z");
		});
	});

	describe("the APK", () -> {
		final apk = Apk.write(so, "android-x86_64", Glue.dex(), true, app, {d: d, cert: cert});
		test("stored entries: the manifest and classes.dex 4-byte aligned, the library 16 KB", () -> {
			var es = Zip.read(apk);
			equals([for (e in es) e.name], ["AndroidManifest.xml", "classes.dex", "lib/x86_64/libmain.so"]);
			equals([for (e in es) e.method], [0, 0, 0]);
			equals([for (e in es) e.dataAt % (e.name.endsWith(".so") ? 16384 : 4)], [0, 0, 0]);
			equals(es[2].data.compare(so), 0);
		});
		test("the same input, the same bytes", () -> {
			equals(Apk.write(so, "android-x86_64", Glue.dex(), true, app, {d: d, cert: cert}).compare(apk), 0);
		});
		test("the manifest, read back", () -> {
			var xml = Axml.dump(Zip.entry(apk, "AndroidManifest.xml"));
			var lines = [for (l in xml.split("\n")) l.trim()];
			equals(lines[0], '<manifest android:versionCode(0x0101021b)=3 android:versionName(0x0101021c)="1.2" package="org.example.hello">');
			equals(lines[1], "<uses-sdk android:minSdkVersion(0x0101020c)=29 android:targetSdkVersion(0x01010270)=35>");
			equals(lines[2], '<uses-permission android:name(0x01010003)="android.permission.INTERNET">');
			equals(lines[3], '<uses-permission android:name(0x01010003)="com.example.permission.X">');
			equals(lines[4], "<uses-feature android:glEsVersion(0x01010281)=0x30000 android:required(0x0101028e)=true>");
			equals(lines[5], '<application android:label(0x01010001)="Hello" android:hasCode(0x0101000c)=true android:debuggable(0x0101000f)=true android:extractNativeLibs(0x010104ea)=false>');
			assert(lines[6].startsWith('<activity android:theme(0x01010000)=@0x010302e3 android:label(0x01010001)="Hello" android:name(0x01010003)="org.hxmc.Activity" android:exported(0x01010010)=true'), lines[6]);
			equals(lines[7], '<meta-data android:name(0x01010003)="android.app.lib_name" android:value(0x01010024)="main">');
			equals(lines.slice(8, 11), [
				"<intent-filter>",
				'<action android:name(0x01010003)="android.intent.action.MAIN">',
				'<category android:name(0x01010003)="android.intent.category.LAUNCHER">'
			]);
		});
		test("without views or listeners: NativeActivity, no code, the full-screen theme", () -> {
			var plain = Apk.write(so, "android-arm64", null, false, app, {d: d, cert: cert});
			equals([for (e in Zip.read(plain)) e.name], ["AndroidManifest.xml", "lib/arm64-v8a/libmain.so"]);
			var xml = Axml.dump(Zip.entry(plain, "AndroidManifest.xml"));
			assert(xml.indexOf('android:name(0x01010003)="android.app.NativeActivity"') >= 0);
			assert(xml.indexOf("android:theme(0x01010000)=@0x01030007") >= 0);
			assert(xml.indexOf("android:hasCode(0x0101000c)=false") >= 0);
		});
		test("the orientation: screenOrientation portrait, sensorLandscape, none for any", () -> {
			var o = (orientation:Null<String>) -> {
				var a = Reflect.copy(app);
				a.orientation = orientation;
				var xml = Axml.dump(Zip.entry(Apk.write(so, "android-arm64", null, false, a, {d: d, cert: cert}), "AndroidManifest.xml"));
				var r = ~/android:screenOrientation\(0x0101001e\)=(\d+)/;
				r.match(xml) ? r.matched(1) : "none";
			};
			equals([o("portrait"), o("landscape"), o("any"), o(null)], ["1", "6", "none", "none"]);
		});
		test("the v2 signing block: its digest recomputed, its signature the key's", () -> {
			var eocd = apk.length - 22;
			equals(apk.getInt32(eocd), 0x06054b50);
			var cdAt = apk.getInt32(eocd + 16);
			equals(apk.getString(cdAt - 16, 16), "APK Sig Block 42");
			var size = apk.getInt32(cdAt - 24), blockAt = cdAt - size - 8;
			equals(apk.getInt32(blockAt), size);
			// (one pair: the v2 scheme's)
			equals(apk.getInt32(blockAt + 16), 0x7109871a);
			var v2 = apk.sub(blockAt + 20, apk.getInt32(blockAt + 8) - 4);
			var signer = v2.sub(8, v2.getInt32(4));
			var signed = signer.sub(4, signer.getInt32(0));
			var digests = signed.sub(4, signed.getInt32(0));
			var digest = digests.sub(4, digests.getInt32(0));
			equals(digest.getInt32(0), 0x0201);
			// (the digest sees the end of central directory with the block's offset)
			var end = apk.sub(eocd, 22);
			end.setInt32(16, blockAt);
			equals(Apk.contentDigest([apk.sub(0, blockAt), apk.sub(cdAt, eocd - cdAt), end]).toHex(), digest.sub(8, digest.getInt32(4)).toHex());
			// the certificate, the signature over the signed data, the key
			var certs = signed.sub(4 + digests.length, signed.length - 4 - digests.length);
			equals(certs.sub(8, certs.getInt32(4)).toHex(), cert.toHex());
			var rest = signer.sub(4 + signed.length, signer.length - 4 - signed.length);
			var sigs = rest.sub(4, rest.getInt32(0));
			var sig = sigs.sub(4, sigs.getInt32(0));
			equals(sig.getInt32(0), 0x0201);
			equals(sig.sub(8, sig.getInt32(4)).toHex(), P256.sign(d, signed).toHex());
			var keyAt = 4 + rest.getInt32(0);
			equals(rest.sub(keyAt + 4, rest.getInt32(keyAt)).toHex(), Apk.publicKeyInfo(d).toHex());
		});
		test("an application id is checked", () -> {
			var e = throws(() -> Apk.write(so, "android-arm64", null, false, {
				id: "hello",
				label: "x",
				versionCode: 1,
				versionName: "1",
				minSdk: 29,
				targetSdk: 35,
				permissions: []
			}, {d: d, cert: cert}));
			equals(Std.string(e), "the application id hello is not one (a.b.c: letters, digits, _)");
			equals(Std.string(throws(() -> Apk.abiDir("android-arm"))), "no Android ABI for android-arm");
		});
	});

	describe("classes.dex", () -> {
		test("Glue's classes: the structure, the methods Java calls", () -> {
			var methods = [];
			equals(Dex.check(Glue.dex(), methods), []);
			for (m in [
				"Lorg/hxmc/Activity; onCreate(Landroid/os/Bundle;)V", "Lorg/hxmc/Glue; <init>(I)V", "Lorg/hxmc/Glue; event(IILjava/lang/Object;II)I",
				"Lorg/hxmc/Glue; onClick(Landroid/view/View;)V", "Lorg/hxmc/Glue; afterTextChanged(Landroid/text/Editable;)V",
				"Lorg/hxmc/Glue; onCheckedChanged(Landroid/widget/CompoundButton;Z)V", "Lorg/hxmc/Glue; onProgressChanged(Landroid/widget/SeekBar;IZ)V",
				"Lorg/hxmc/Glue; onLayoutChange(Landroid/view/View;IIIIIIII)V", "Lorg/hxmc/Glue; surfaceChanged(Landroid/view/SurfaceHolder;III)V",
				"Lorg/hxmc/Glue; onKey(Landroid/view/View;ILandroid/view/KeyEvent;)Z"
			])
				assert(methods.contains(m), m);
		});
		test("a broken file is found out", () -> {
			var b = Glue.dex();
			b.set(b.length - 1, b.get(b.length - 1) ^ 1);
			var errors = Dex.check(b);
			assert(errors.contains("checksum") && errors.contains("signature"), errors.join("; "));
		});
	});
}
