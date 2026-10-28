package helder.pack.ios;

import haxe.io.Bytes;
import helder.pack.Zip;
import helder.pack.ios.Plist;
import helder.test.Test;

// The iOS bundle's files (Bundle, Plist): Info.plist read back, its keys as
// CoreFoundation sorts them, CodeResources' hashes, the .ipa's layout and modes
function tests() {
	final info = Bundle.infoPlist("Hello", "org.example.hello", "Hello & Co", "3", "1.2", "15.0", true);
	final dict = (v:PValue) -> switch v {
		case PDict(d): d;
		case _: throw "not a dictionary";
	};

	test("Info.plist: an XML property list, read back", () -> {
		var d = dict(Plist.parse(info.toString()));
		equals(d.get("CFBundleExecutable"), PString("Hello"));
		equals(d.get("CFBundleIdentifier"), PString("org.example.hello"));
		equals(d.get("CFBundleDisplayName"), PString("Hello & Co"));
		equals(d.get("CFBundleVersion"), PString("3"));
		equals(d.get("CFBundleShortVersionString"), PString("1.2"));
		equals(d.get("CFBundlePackageType"), PString("APPL"));
		equals(d.get("MinimumOSVersion"), PString("15.0"));
		equals(d.get("UILaunchScreen"), PDict(new Map()));
		equals(d.get("LSRequiresIPhoneOS"), PBool(true));
		equals(d.get("UIDeviceFamily"), PArray([PInt(1), PInt(2)]));
		// (the simulator's platform; a device's iPhoneOS)
		equals(d.get("CFBundleSupportedPlatforms"), PArray([PString("iPhoneSimulator")]));
		equals(d.get("DTPlatformName"), PString("iphonesimulator"));
		var device = dict(Plist.parse(Bundle.infoPlist("Hello", "org.example.hello", "Hello", "1", "1.0", "16.0", false).toString()));
		equals(device.get("DTPlatformName"), PString("iphoneos"));
		equals(device.get("CFBundleSupportedPlatforms"), PArray([PString("iPhoneOS")]));
	});
	test("keys sorted, text escaped: the same values, the same bytes", () -> {
		var s = info.toString();
		assert(s.indexOf("<key>CFBundleDevelopmentRegion</key>") < s.indexOf("<key>CFBundleDisplayName</key>"));
		assert(s.indexOf("<key>UISupportedInterfaceOrientations</key>") < s.indexOf("<key>UISupportedInterfaceOrientations~ipad</key>"));
		assert(s.indexOf("<string>Hello &amp; Co</string>") > 0);
		equals(Bundle.infoPlist("Hello", "org.example.hello", "Hello & Co", "3", "1.2", "15.0", true).compare(info), 0);
		assert(s.indexOf('<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"') > 0);
	});
	test("a property list's values round trip", () -> {
		var v = PDict(["a" => PArray([]), "b" => PData(Bytes.ofHex("00ff10")), "c" => PBool(false), "d" => PInt(-3), "e" => PDict(new Map())]);
		equals(Plist.parse(Plist.xml(v).toString()), v);
	});
	test("CodeResources: Info.plist's SHA-1 in files, codesign's rules", () -> {
		var d = dict(Plist.parse(Bundle.codeResources(["Info.plist" => info]).toString()));
		equals(dict(d.get("files")).get("Info.plist"), PData(haxe.crypto.Sha1.make(info)));
		// (files2 leaves Info.plist out: the signature binds it)
		equals([for (k in dict(d.get("files2")).keys()) k], []);
		equals(dict(d.get("rules2")).get("^Info\\.plist$"), PDict(["omit" => PBool(true), "weight" => PInt(20)]));
		var more = dict(Plist.parse(Bundle.codeResources(["Info.plist" => info, "assets/a.png" => Bytes.ofString("png")]).toString()));
		equals(dict(more.get("files2")).get("assets/a.png"),
			PDict(["hash" => PData(haxe.crypto.Sha1.make(Bytes.ofString("png"))), "hash2" => PData(haxe.crypto.Sha256.make(Bytes.ofString("png")))]));
	});
	test("the .ipa: Payload/<name>.app/, stored, the executable 0755", () -> {
		var res = Bundle.codeResources(["Info.plist" => info]);
		var es = Zip.read(Bundle.ipa("Hello", Bytes.ofString("exe"), info, res));
		equals([for (e in es) e.name], ["Payload/Hello.app/Hello", "Payload/Hello.app/Info.plist", "Payload/Hello.app/_CodeSignature/CodeResources"]);
		equals([for (e in es) e.mode], [0x1ed, 0x1a4, 0x1a4]);
		equals(es[1].data.compare(info), 0);
	});
	test("a bundle id: reverse DNS", () -> {
		assert(Bundle.validId("org.example.hello-world"));
		assert(!Bundle.validId("hello"));
		assert(!Bundle.validId("org.example.hello_world"));
	});
}
