package helder.pack.apple;

import haxe.io.Bytes;
import helder.pack.ios.Plist;

// A macOS app bundle's seal and signature (helder.cli.Mac): Contents/
// _CodeSignature/CodeResources over the bundle's files with the rules
// codesign writes for a macOS bundle (paths from Contents/: Resources/ in
// files and files2, Info.plist omitted, MacOS/ nested code: the main
// executable is bound by its own signature, not listed), and the universal
// executable signed slice by slice (CodeSign: ad hoc without an identity,
// else Developer ID's with the hardened runtime and a timestamp, what
// notarisation asks for), each slice binding the same Info.plist and
// CodeResources.
class MacBundle {
	// files: their paths from Contents/ (Resources/AppIcon.icns...), not the executable's
	public static function codeResources(files:Map<String, Bytes>):Bytes {
		function rule(?optional:Bool, ?omit:Bool, ?nested:Bool, weight:Int):PValue {
			var d = ["weight" => PInt(weight)];
			if (optional == true) d.set("optional", PBool(true));
			if (omit == true) d.set("omit", PBool(true));
			if (nested == true) d.set("nested", PBool(true));
			return PDict(d);
		}
		var v1 = new Map<String, PValue>(), v2 = new Map<String, PValue>();
		for (path => data in files) {
			if (path == "Info.plist" || path == "PkgInfo" || StringTools.startsWith(path, "MacOS/")) continue;
			if (StringTools.startsWith(path, "Resources/")) v1.set(path, PData(haxe.crypto.Sha1.make(data)));
			v2.set(path, PDict(["hash" => PData(haxe.crypto.Sha1.make(data)), "hash2" => PData(haxe.crypto.Sha256.make(data))]));
		}
		return Plist.xml(PDict([
			"files" => PDict(v1),
			"files2" => PDict(v2),
			"rules" => PDict([
				"^Resources/" => PBool(true),
				"^Resources/.*\\.lproj/" => rule(true, 1000),
				"^Resources/.*\\.lproj/locversion.plist$" => rule(false, true, 1100),
				"^Resources/Base\\.lproj/" => rule(1010),
				"^version.plist$" => PBool(true)
			]),
			"rules2" => PDict([
				".*\\.dSYM($|/)" => rule(11),
				"^(.*/)?\\.DS_Store$" => rule(false, true, 2000),
				"^(Frameworks|SharedFrameworks|PlugIns|Plug-ins|XPCServices|Helpers|MacOS|Library/(Automator|Spotlight|LoginItems))/" => rule(false, false,
					true, 10),
				"^.*" => PBool(true),
				"^Info\\.plist$" => rule(false, true, 20),
				"^PkgInfo$" => rule(false, true, 20),
				"^Resources/" => rule(20),
				"^Resources/.*\\.lproj/" => rule(true, 1000),
				"^Resources/.*\\.lproj/locversion.plist$" => rule(false, true, 1100),
				"^Resources/Base\\.lproj/" => rule(1010),
				"^[^/]+$" => rule(false, false, true, 10),
				"^embedded\\.provisionprofile$" => rule(20),
				"^version\\.plist$" => rule(20)
			])
		]));
	}

	// the universal executable's slices (thin Mach-Os) each signed, joined
	// again (Fat); identity null: ad hoc; runtime: the hardened runtime's
	// version (0xMMmmpp), Developer ID's
	public static function sign(slices:Array<Bytes>, o:{
		identifier:String,
		identity:Null<Identity>,
		infoPlist:Bytes,
		resources:Bytes,
		?runtime:Int,
		?timestamp:Bytes->Bytes,
		?time:Date
	}):Bytes
		return Fat.make([
			for (s in slices)
				CodeSign.sign(s, {
					identifier: o.identifier,
					identity: o.identity,
					infoPlist: o.infoPlist,
					resources: o.resources,
					runtime: o.runtime,
					timestamp: o.timestamp,
					time: o.time
				})
		]);
}
