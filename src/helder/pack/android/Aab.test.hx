package helder.pack.android;

import haxe.io.Bytes;
import helder.pack.Zip;
import helder.test.Test;

// The App Bundle (Aab): the base module's layout, the manifest as aapt2's
// XmlNode and the resource table as its ResourceTable read back (Pb), the
// JAR signature's manifest digests and long names' continuation lines.
// jarsigner, openssl and bundletool check a built one (tests/pack/PackCheck.hx)
function tests() {
	final d = Bytes.ofHex("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721");
	final key = Apk.debugSigner({d: d, cert: Apk.certificate(d, Bytes.ofHex("01"), new Date(2026, 0, 1, 0, 0, 0), 30)});
	final app:Apk.ApkOptions = {
		id: "org.example.hello",
		label: "Hello",
		versionCode: 3,
		versionName: "1.2",
		minSdk: 29,
		targetSdk: 36,
		permissions: [],
		debuggable: false
	};
	final t = new Arsc("org.example.hello");
	final bg = t.add("color", "bg", Argb(0xff112233));
	t.add("style", "Theme.Helder", Style(Apk.THEME, [{attr: 0x01010054, value: Ref(bg)}]));
	final icon = Axml.el("adaptive-icon", [], [Axml.el("background", [{android: true, name: "drawable", type: Axml.REFERENCE, value: bg}])]);
	final long = "assets/" + StringTools.lpad("", "a", 90) + ".txt";
	final aab = Aab.write([{target: "android-arm64", so: Bytes.ofString("so")}, {target: "android-x86_64", so: Bytes.ofString("so64")}], null,
		Apk.manifestOf(app, false, false), {
			table: t,
			files: [{name: "res/mipmap-anydpi-v26/ic_launcher.xml", data: Axml.encode(icon)}],
			xml: ["res/mipmap-anydpi-v26/ic_launcher.xml" => icon]
		}, [{name: long, data: Bytes.ofString("x")}], key);
	final files = [for (e in Zip.read(aab)) e.name => e.data];
	final field = (fs:Array<{field:Int, wire:Int, value:Int, data:Null<Bytes>}>, n:Int) -> Lambda.find(fs, f -> f.field == n);

	test("the base module's layout", () -> {
		equals([for (e in Zip.read(aab)) e.name], [
			"META-INF/MANIFEST.MF", "META-INF/HELDER.SF", "META-INF/HELDER.EC", "BundleConfig.pb", "base/manifest/AndroidManifest.xml", "base/resources.pb",
			"base/res/mipmap-anydpi-v26/ic_launcher.xml", "base/lib/arm64-v8a/libmain.so", "base/lib/x86_64/libmain.so", 'base/$long'
		]);
		equals(field(Pb.read(field(Pb.read(files.get("BundleConfig.pb")), 1).data), 2).data.toString(), Aab.BUNDLETOOL);
	});
	test("the manifest: an XmlNode, android: attributes with their ids and compiled values", () -> {
		var el = Pb.read(field(Pb.read(files.get("base/manifest/AndroidManifest.xml")), 1).data);
		equals(field(el, 3).data.toString(), "manifest");
		var ns = Pb.read(field(el, 1).data);
		equals([field(ns, 1).data.toString(), field(ns, 2).data.toString()], ["android", Axml.ANDROID]);
		var attrs = [for (f in el) if (f.field == 4) Pb.read(f.data)];
		var code = Lambda.find(attrs, a -> field(a, 2).data.toString() == "versionCode");
		equals(field(code, 5).value, 0x0101021b);
		equals(field(Pb.read(field(Pb.read(field(code, 6).data), 7).data), 6).value, 3);
		var app = Lambda.find([for (f in el) if (f.field == 5) Pb.read(field(Pb.read(f.data), 1).data)], c -> field(c, 3).data.toString() == "application");
		var dbg = Lambda.find([for (f in app) if (f.field == 4) Pb.read(f.data)], a -> field(a, 2).data.toString() == "debuggable");
		// (false still written: a oneof's)
		equals(field(Pb.read(field(Pb.read(field(dbg, 6).data), 7).data), 8).value, 0);
	});
	test("the resource table: the package, its types and entries, a colour, a style", () -> {
		var pkg = Pb.read(field(Pb.read(files.get("base/resources.pb")), 2).data);
		equals(field(Pb.read(field(pkg, 1).data), 1).value, 0x7f);
		equals(field(pkg, 2).data.toString(), "org.example.hello");
		var types = [for (f in pkg) if (f.field == 3) Pb.read(f.data)];
		equals([for (ty in types) field(ty, 2).data.toString()], ["color", "style"]);
		var colour = Pb.read(field(Pb.read(field(Pb.read(field(Pb.read(field(types[0], 3).data), 6).data), 2).data), 4).data);
		equals(field(Pb.read(field(colour, 7).data), 9).value, 0xff112233);
		var style = Pb.read(field(Pb.read(field(Pb.read(field(Pb.read(field(Pb.read(field(types[1], 3).data), 6).data), 2).data), 5).data), 2).data);
		equals(field(Pb.read(field(style, 1).data), 2).value, Apk.THEME);
	});
	test("JAR signing: each entry's SHA-256, long names on continuation lines", () -> {
		var mf = files.get("META-INF/MANIFEST.MF").toString();
		assert(StringTools.startsWith(mf, "Manifest-Version: 1.0\r\n"));
		for (line in mf.split("\r\n")) assert(line.length <= 72, line);
		var unwrapped = mf.split("\r\n ").join("");
		for (n => data in files)
			if (!StringTools.startsWith(n, "META-INF/"))
				assert(unwrapped.indexOf('Name: $n\r\nSHA-256-Digest: ${haxe.crypto.Base64.encode(haxe.crypto.Sha256.make(data))}') >= 0, n);
		var sf = files.get("META-INF/HELDER.SF").toString();
		assert(sf.indexOf("SHA-256-Digest-Manifest: " + haxe.crypto.Base64.encode(haxe.crypto.Sha256.make(files.get("META-INF/MANIFEST.MF")))) >= 0);
		equals(Der.read(files.get("META-INF/HELDER.EC"), 0).tag, 0x30);
	});
}
