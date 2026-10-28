package helder.pack.ios;

import haxe.io.Bytes;
import helder.pack.ios.Plist;

// An iOS app without Xcode or the SDK, around the program's Mach-O
// executable (hxmc's output for ios-arm64 or ios-sim-arm64): the bundle
// <name>.app holds the program (named <name>), its Info.plist (XML: the
// bundle id, the executable, UILaunchScreen as an empty dictionary, so the
// app gets the screen's own size without a storyboard; the platform, the
// minimum version) and _CodeSignature/CodeResources (the hashes of the
// bundle's other files, with codesign's default rules). The two files are
// written first; then hxmc links the executable into the bundle and signs
// it ad hoc as `codesign -s -` signs one (-D hxmc.codesign-id: the bundle
// id; -D hxmc.codesign-info-plist and -D hxmc.codesign-resources: those
// files, bound by their hashes; -D hxmc.codesign-entitlements: an XML
// plist of entitlements), enough for the simulator. A .ipa is that bundle
// under Payload/ in a zip (the executable with its Unix mode), for devices
// later: their signature needs a certificate and a provisioning profile.
// Pure: the bytes (helder.cli.Ios writes the files and links). Ported from
// hxmc (hxmc.ios.Bundle), MIT.
class Bundle {
	// whether id is a bundle id (reverse DNS: letters, digits, '-')
	public static function validId(id:String):Bool
		return ~/^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$/.match(id);

	// the bundle's files (paths in it): the executable, Info.plist, CodeResources
	public static function files(name:String, exe:Bytes, info:Bytes, resources:Bytes):Array<{path:String, data:Bytes, exec:Bool}>
		return [
			{path: name, data: exe, exec: true},
			{path: "Info.plist", data: info, exec: false},
			{path: "_CodeSignature/CodeResources", data: resources, exec: false}
		];

	// the .ipa: Payload/<name>.app/ in a stored zip, the executable 0755
	public static function ipa(name:String, exe:Bytes, info:Bytes, resources:Bytes):Bytes {
		var entries:Array<helder.pack.Zip.ZipEntry> = [];
		for (f in files(name, exe, info, resources))
			entries.push({name: "Payload/" + name + ".app/" + f.path, data: f.data, align: 1, mode: f.exec ? 0x1ed : 0x1a4});
		return helder.pack.Zip.stored(entries);
	}

	// (exe: CFBundleExecutable, the bundle's name; label: the home screen's)
	public static function infoPlist(exe:String, id:String, label:String, version:String, versionName:String, min:String, simulator:Bool):Bytes {
		var all = PArray([
			PString("UIInterfaceOrientationPortrait"),
			PString("UIInterfaceOrientationPortraitUpsideDown"),
			PString("UIInterfaceOrientationLandscapeLeft"),
			PString("UIInterfaceOrientationLandscapeRight")
		]);
		return Plist.xml(PDict([
			"CFBundleDevelopmentRegion" => PString("en"),
			"CFBundleDisplayName" => PString(label),
			"CFBundleExecutable" => PString(exe),
			"CFBundleIdentifier" => PString(id),
			"CFBundleInfoDictionaryVersion" => PString("6.0"),
			"CFBundleName" => PString(label),
			"CFBundlePackageType" => PString("APPL"),
			"CFBundleShortVersionString" => PString(versionName),
			"CFBundleSupportedPlatforms" => PArray([PString(simulator ? "iPhoneSimulator" : "iPhoneOS")]),
			"CFBundleVersion" => PString(version),
			"DTPlatformName" => PString(simulator ? "iphonesimulator" : "iphoneos"),
			"LSRequiresIPhoneOS" => PBool(true),
			"MinimumOSVersion" => PString(min),
			"UIApplicationSupportsIndirectInputEvents" => PBool(true),
			"UIDeviceFamily" => PArray([PInt(1), PInt(2)]),
			"UILaunchScreen" => PDict([]),
			"UIRequiredDeviceCapabilities" => PArray([PString("arm64")]),
			"UISupportedInterfaceOrientations" => all,
			"UISupportedInterfaceOrientations~ipad" => all
		]));
	}

	// _CodeSignature/CodeResources: each file's SHA-1 (files: the first
	// version's rules) and SHA-1 and SHA-256 (files2), the rules codesign
	// writes for an iOS bundle (Info.plist is in files only: files2's rules
	// omit it, the code signature binds it)
	public static function codeResources(files:Map<String, Bytes>):Bytes {
		function rule(?optional:Bool, ?omit:Bool, weight:Int):PValue {
			var d = ["weight" => PInt(weight)];
			if (optional == true) d.set("optional", PBool(true));
			if (omit == true) d.set("omit", PBool(true));
			return PDict(d);
		}
		var v1 = new Map<String, PValue>(), v2 = new Map<String, PValue>();
		for (path => data in files) {
			v1.set(path, PData(haxe.crypto.Sha1.make(data)));
			if (path != "Info.plist" && path != "PkgInfo")
				v2.set(path, PDict(["hash" => PData(haxe.crypto.Sha1.make(data)), "hash2" => PData(haxe.crypto.Sha256.make(data))]));
		}
		return Plist.xml(PDict([
			"files" => PDict(v1),
			"files2" => PDict(v2),
			"rules" => PDict([
				"^.*" => PBool(true),
				"^.*\\.lproj/" => rule(true, 1000),
				"^.*\\.lproj/locversion.plist$" => rule(false, true, 1100),
				"^Base\\.lproj/" => rule(1010),
				"^version.plist$" => PBool(true)
			]),
			"rules2" => PDict([
				".*\\.dSYM($|/)" => rule(11),
				"^(.*/)?\\.DS_Store$" => rule(false, true, 2000),
				"^.*" => PBool(true),
				"^.*\\.lproj/" => rule(true, 1000),
				"^.*\\.lproj/locversion.plist$" => rule(false, true, 1100),
				"^Base\\.lproj/" => rule(1010),
				"^Info\\.plist$" => rule(false, true, 20),
				"^PkgInfo$" => rule(false, true, 20),
				"^embedded\\.provisionprofile$" => rule(20),
				"^version\\.plist$" => rule(20)
			])
		]));
	}
}
