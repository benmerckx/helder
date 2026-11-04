import haxe.io.Bytes;
import helder.pack.Zip;
import helder.pack.android.*;
import helder.pack.ios.Plist;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

using StringTools;

// The apps `helder build` packages (helder.pack; the pack lane), checked
// without a device, on Eval:
//   haxe -cp src -cp tests/pack --run PackCheck <apk, app or ipa>...
// An APK:
// - the zip: AndroidManifest.xml, lib/<abi>/libmain.so (and classes.dex)
//   stored, the library's data at a multiple of 16 KB, the rest of 4 bytes
//   (zipalign -c -P 16 too, when there);
// - the manifest read back (Axml.dump; aapt dump badging when there):
//   the activity, its library, hasCode, extractNativeLibs, the launcher;
//   screenOrientation, the app's orientation's (none for any);
// - classes.dex when there: Dex.check's structure, Glue's methods;
// - the library (readelf, when there): a shared object of the ABI, 16 KB
//   segments, its soname libmain.so, the export ANativeActivity_onCreate,
//   the import ANativeActivity_finish (libandroid.so's), DT_NEEDED only the
//   system's, no text relocations;
// - the v2 signature: the block, the digest of the contents recomputed and
//   equal to the signed one, verified by apksigner when there, else by
//   openssl (the signer's key and signature over the signed data).
// An .app or an .ipa:
// - the bundle: the executable, Info.plist and _CodeSignature/CodeResources,
//   nothing else (an .ipa: under Payload/<name>.app/, stored, the
//   executable 0755);
// - Info.plist parsed: the executable, the id, UILaunchScreen, the platform
//   and the minimum version; UISupportedInterfaceOrientations (and
//   ~ipad, UIRequiresFullScreen) the app's orientation's, UIStatusBarHidden
//   when fullscreen; CodeResources: Info.plist's SHA-1;
// - the executable: a 64-bit arm64 MH_EXECUTE, PIE, LC_MAIN, the build
//   version's platform and minimum (the plist's), the signature ending the
//   file: a CodeDirectory, ad hoc, identified by the bundle id, its page
//   hashes recomputed, its special slots the hashes of Info.plist (1), the
//   requirements (2), CodeResources (3) and the entitlements (5) when signed;
// - an iPhone's (an .ipa): Xcode's DT* keys, PrivacyInfo.xcprivacy;
// - @signed (a distribution signature, tests/pack/signing's identity): the
//   CodeDirectory not ad hoc, its team, the build version's SDK, the DER
//   entitlements (the XML's), the profile's application-identifier and
//   get-task-allow, embedded.mobileprovision, the designated requirement,
//   the CMS verified by openssl cms -verify over the CodeDirectory against
//   the test CA, Apple's attributes in it; CodeResources sealing
//   Assets.car, the profile and PrivacyInfo.xcprivacy; @encryption:
//   ITSAppUsesNonExemptEncryption false;
// - the assets (both; @assets=<dir>:<key>,<key>... names them, else none):
//   exactly those under assets/ (an APK's stored and 4-byte aligned), each
//   the bytes of <dir>/<key>; a bundle's CodeResources has their SHA-1
//   (files) and SHA-1 and SHA-256 (files2);
// - on a Mac, codesign --verify and plutil -lint;
// - fullscreen (both): the program built with -D helder.fullscreen (the
//   project's line saying so in the library or the executable).
// - @icons (both): the manifest's (helder.webmanifest): an APK's
//   resources.arsc (Arsc.dump) and res/ files, the application's icon the
//   adaptive icon (its 432 px foreground, its background), the activity's
//   theme Theme.Helder (the splash's colour, windowBackground and
//   windowSplashScreenBackground; theme_color statusBarColor and
//   navigationBarColor); a bundle's Assets.car (AssetCatalog.read: the
//   icon's five renditions, opaque, the deployment target; its structure
//   against Apple actool's, tests/pack/reference/Assets.car; xcrun
//   assetutil --info on a Mac) and loose AppIcon PNGs, CFBundleIcons'
//   CFBundleIconName, the launch image (UILaunchScreen's UIImageName), all
//   in CodeResources.
// Exits non-zero on a failure; a missing tool is a line saying so.
class PackCheck {
	static var failures = 0;
	static var want:{id:Null<String>, entitlements:Bool, signed:Bool, encryption:Bool, views:Null<Bool>, orientation:String, fullscreen:Bool, icons:Bool, assets:{dir:String, keys:Array<String>}} = {
		icons: false,
		signed: false,
		encryption: false,
		id: null,
		entitlements: false,
		views: null,
		orientation: "any",
		fullscreen: false,
		assets: {dir: "", keys: []}
	};
	static final dir = "bin/pack/check";

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println(what.rpad(" ", 60) + " " + (ok ? "ok" : "FAIL") + (detail != "" ? "  " + detail : ""));
		if (!ok) failures++;
	}

	static function skip(what:String)
		Sys.println(what.rpad(" ", 60) + " skipped");

	static function has(tool:String):Bool
		return Sys.systemName() != "Windows" && Sys.command("sh", ["-c", 'command -v $tool > /dev/null']) == 0;

	static function exec(cmd:String, args:Array<String>):{code:Int, out:String} {
		var p = new Process(cmd, args);
		var out = p.stdout.readAll().toString() + p.stderr.readAll().toString();
		var code = p.exitCode();
		p.close();
		return {code: code, out: out};
	}

	static function main() {
		FileSystem.createDirectory(dir);
		for (a in Sys.args()) {
			Sys.println("PackCheck: " + a);
			// (<file>@<id>: the app's id checked too; @entitlements: signed
			// with them; @views, @surface: org.hxmc.Activity or NativeActivity;
			// @portrait, @landscape: the orientation (else any); @fullscreen)
			var parts = a.split("@");
			var listed = Lambda.find(parts, p -> p.startsWith("assets="));
			var assets = listed == null ? {dir: "", keys: []} : {
				dir: listed.substring(7, listed.indexOf(":")),
				keys: listed.substr(listed.indexOf(":") + 1).split(",")
			};
			assets.keys.sort(Reflect.compare);
			want = {
				assets: assets,
				id: parts[1] == "" ? null : parts[1],
				entitlements: parts.contains("entitlements"),
				signed: parts.contains("signed"),
				encryption: parts.contains("encryption"),
				views: parts.contains("views") ? true : parts.contains("surface") ? false : null,
				orientation: parts.contains("portrait") ? "portrait" : parts.contains("landscape") ? "landscape" : "any",
				fullscreen: parts.contains("fullscreen"),
				icons: parts.contains("icons")
			};
			if (parts[0].endsWith(".apk")) apk(parts[0]) else bundle(parts[0]);
		}
		if (failures > 0) {
			Sys.println('PackCheck: $failures failed');
			Sys.exit(1);
		}
		Sys.println("PackCheck: all passed");
	}

	// --- Android

	static function apk(path:String) {
		var b = File.getBytes(path);
		var entries = try Zip.read(b) catch (e:Dynamic) {
			check("zip: read back", false, Std.string(e));
			return;
		}
		for (e in entries) {
			check('zip: ${e.name} stored', e.method == 0);
			var align = e.name.endsWith(".so") ? 16384 : 4;
			check('zip: ${e.name} aligned to $align', e.dataAt % align == 0, "at " + e.dataAt);
		}
		if (has("zipalign")) check("zipalign -c -P 16 4", exec("zipalign", ["-c", "-P", "16", "4", path]).code == 0) else skip("zipalign (not found)");
		var all = [for (e in entries) e.name];
		var names = [for (n in all) if (!n.startsWith("assets/") && !n.startsWith("res/") && n != "resources.arsc") n];
		var res = [for (n in all) if (n.startsWith("res/") || n == "resources.arsc") n];
		check("zip: resources.arsc and res/ " + (want.icons ? "(the manifest's icon)" : "none"), want.icons == res.contains("resources.arsc")
			&& (want.icons || res.length == 0), res.join(" "));
		assets([for (e in entries) if (e.name.startsWith("assets/")) e.name.substr(7) => e.data]);
		var lib = [for (n in names) if (n.startsWith("lib/")) n];
		var code = names.contains("classes.dex");
		check("zip: AndroidManifest.xml and one library" + (code ? ", classes.dex" : ""),
			names.contains("AndroidManifest.xml") && lib.length == 1 && names.length == (code ? 3 : 2), names.join(" "));
		if (lib.length != 1 || !names.contains("AndroidManifest.xml")) return;
		var abi = lib[0].split("/")[1];
		check("zip: the library is lib/<abi>/libmain.so", lib[0] == 'lib/$abi/libmain.so' && (abi == "arm64-v8a" || abi == "x86_64"), lib[0]);
		var data = (n:String) -> Lambda.find(entries, e -> e.name == n).data;
		var xml = Axml.dump(data("AndroidManifest.xml"));
		File.saveContent('$dir/${haxe.io.Path.withoutDirectory(path)}.manifest.txt', xml);
		var views = xml.indexOf('"' + Glue.ACTIVITY + '"') >= 0, activity = views ? Glue.ACTIVITY : "android.app.NativeActivity";
		if (want.views != null) check("manifest: the activity the program needs: " + (want.views ? Glue.ACTIVITY : "NativeActivity"), views == want.views);
		check("manifest: " + activity + (views && !code ? ", but no classes.dex" : ""),
			xml.indexOf('android:name(0x01010003)="$activity"') >= 0 && (code || !views));
		if (want.id != null) check('manifest: package ${want.id}', xml.indexOf('package="${want.id}"') >= 0);
		check("manifest: android.app.lib_name main", xml.indexOf('"android.app.lib_name"') >= 0 && xml.indexOf('android:value(0x01010024)="main"') >= 0);
		check("manifest: hasCode " + code + ", extractNativeLibs false, debuggable",
			xml.indexOf("android:hasCode(0x0101000c)=" + code) >= 0 && xml.indexOf("android:extractNativeLibs(0x010104ea)=false") >= 0
			&& xml.indexOf("android:debuggable(0x0101000f)=true") >= 0);
		check("manifest: the launcher's intent filter", xml.indexOf('"android.intent.action.MAIN"') >= 0 && xml.indexOf('"android.intent.category.LAUNCHER"') >= 0);
		var so = ~/android:screenOrientation\(0x0101001e\)=(\d+)/;
		var orientation = so.match(xml) ? so.matched(1) : "none";
		check('manifest: screenOrientation for ${want.orientation}', orientation == (switch want.orientation {
			case "portrait": "1";
			case "landscape": "6";
			case _: "none";
		}), orientation);
		if (want.icons && res.contains("resources.arsc")) icons(xml, data, res);
		if (has("aapt")) {
			var r = exec("aapt", ["dump", "badging", path]);
			check("aapt dump badging", r.code == 0 && r.out.indexOf("launchable-activity: name='" + activity + "'") >= 0, r.out.split("\n")[0]);
		} else skip("aapt dump badging (not found)");
		if (code) {
			var methods = [];
			var errors = Dex.check(data("classes.dex"), methods);
			check("classes.dex: its structure (Dex.check)", errors.length == 0, errors.slice(0, 3).join("; "));
			check("classes.dex: Glue's listener", methods.contains("Lorg/hxmc/Glue; event(IILjava/lang/Object;II)I"));
		}
		var so = '$dir/libmain-$abi.so';
		File.saveBytes(so, data(lib[0]));
		if (want.fullscreen) built(data(lib[0]));
		if (has("readelf")) elf(so, abi) else skip("readelf (not found)");
		signature(path, b);
	}

	// the resources of the manifest's icon and splash
	static function icons(xml:String, data:String->Bytes, res:Array<String>) {
		var table = Arsc.dump(data("resources.arsc"));
		File.saveContent('$dir/resources.txt', table);
		var line = (name:String) -> Lambda.find(table.split("\n"), l -> l.indexOf(" " + name + " ") > 0);
		var icon = line("mipmap/ic_launcher"), theme = line("style/Theme.Helder");
		check("resources: mipmap/ic_launcher, the application's icon and round icon", icon != null
			&& xml.indexOf("android:icon(0x01010002)=@" + icon.split(" ")[0]) >= 0 && xml.indexOf("android:roundIcon(0x0101052c)=@" + icon.split(" ")[0]) >= 0,
			icon);
		var files = [for (l in table.split("\n")) if (l.indexOf('"res/') > 0) l.substring(l.indexOf('"') + 1, l.lastIndexOf('"'))];
		files.sort(Reflect.compare);
		var listed = [for (r in res) if (r != "resources.arsc") r];
		listed.sort(Reflect.compare);
		check("resources: their files, each in res/", files.join(",") == listed.join(","), files.join(" "));
		if (icon != null) {
			var adaptive = Axml.dump(data(icon.substring(icon.indexOf('"') + 1, icon.lastIndexOf('"'))));
			check("resources: an adaptive icon, a background and a foreground", adaptive.startsWith("<adaptive-icon>") && adaptive.indexOf("<background android:drawable") > 0
				&& adaptive.indexOf("<foreground android:drawable") > 0);
		}
		var fg = res.indexOf("res/mipmap-xxxhdpi-v4/ic_launcher_foreground.png") >= 0 ? helder.image.PngDecoder.decode(data("res/mipmap-xxxhdpi-v4/ic_launcher_foreground.png")) : null;
		check("resources: the foreground 432 px (108 dp at xxxhdpi)", fg != null && fg.width == 432 && fg.height == 432);
		check("resources: Theme.Helder, the activity's: the splash's background, the window's", theme != null
			&& xml.indexOf("android:theme(0x01010000)=@" + theme.split(" ")[0]) >= 0 && theme.indexOf("0x0101062c=@") > 0 && theme.indexOf("0x01010054=@") > 0, theme);
		// (theme_color, #3ED6C3: the status and navigation bars', statusBarColor and navigationBarColor)
		var bars = line("color/theme_color");
		check("resources: theme_color the system bars' (statusBarColor, navigationBarColor)", bars != null && bars.toLowerCase().indexOf("ff3ed6c3") > 0 && theme != null
			&& theme.indexOf("0x01010451=@" + bars.split(" ")[0]) > 0 && theme.indexOf("0x01010452=@" + bars.split(" ")[0]) > 0, '$bars / $theme');
	}

	static function elf(so:String, abi:String) {
		var readelf = (a:Array<String>) -> exec("readelf", ["-W"].concat(a).concat([so])).out;
		var h = readelf(["-h"]);
		check("library: a shared object of the ABI", h.indexOf("DYN (Shared object file)") >= 0 && h.indexOf(abi == "x86_64" ? "X86-64" : "AArch64") >= 0);
		var load = ~/^\s*LOAD\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)\s+0x[0-9a-f]+\s+0x[0-9a-f]+\s+0x[0-9a-f]+\s+.{3}\s+0x([0-9a-f]+)/;
		var segs = 0, aligned = true;
		for (line in readelf(["-l"]).split("\n"))
			if (load.match(line)) {
				segs++;
				var off = Std.parseInt("0x" + load.matched(1)), va = Std.parseInt("0x" + load.matched(2)), al = Std.parseInt("0x" + load.matched(3));
				if (al != 0x4000 || off % 0x4000 != va % 0x4000) aligned = false;
			}
		check("library: 16 KB segments", segs >= 2 && aligned, segs + " loadable");
		var d = readelf(["-d"]);
		check("library: SONAME libmain.so", d.indexOf("Library soname: [libmain.so]") >= 0);
		check("library: no text relocations", d.indexOf("TEXTREL") < 0);
		var allowed = ["libc.so", "libm.so", "libdl.so", "liblog.so", "libandroid.so", "libEGL.so", "libGLESv3.so", "libGLESv2.so", "libvulkan.so"];
		var needed = ~/\(NEEDED\)\s+Shared library: \[([^\]]+)\]/, s = d, libs = [];
		while (needed.match(s)) {
			libs.push(needed.matched(1));
			s = needed.matchedRight();
		}
		check("library: DT_NEEDED the system's libraries only", libs.contains("libc.so") && Lambda.foreach(libs, x -> allowed.contains(x)), libs.join(" "));
		var syms = readelf(["--dyn-syms"]);
		check("library: exports ANativeActivity_onCreate", ~/FUNC\s+GLOBAL\s+DEFAULT\s+\d+\s+ANativeActivity_onCreate/.match(syms));
		// (Android's own calls behind their constant tests: there, still linked; elsewhere
		// none, src/helder/os/AppLink.test.hx)
		check("library: imports ANativeActivity_finish (libandroid.so)", ~/FUNC\s+GLOBAL\s+DEFAULT\s+UND\s+ANativeActivity_finish/.match(syms)
			&& libs.contains("libandroid.so"));
	}

	// the APK Signing Block before the central directory, its v2 signer
	static function signature(path:String, b:Bytes) {
		var eocdAt = b.length - 22;
		var cdAt = b.getInt32(eocdAt + 16);
		var magic = b.getString(cdAt - 16, 16);
		check("signature: the APK Signing Block", magic == "APK Sig Block 42");
		if (magic != "APK Sig Block 42") return;
		var size = b.getInt32(cdAt - 24), blockAt = cdAt - size - 8;
		check("signature: the block's sizes agree", b.getInt32(blockAt) == size);
		var at = blockAt + 8, v2 = null;
		while (at < cdAt - 24) {
			var len = b.getInt32(at), id = b.getInt32(at + 8);
			if (id == 0x7109871a) v2 = b.sub(at + 12, len - 4);
			at += 8 + len;
		}
		check("signature: a v2 block", v2 != null);
		if (v2 == null) return;
		var signer = v2.sub(8, v2.getInt32(4));
		var sd = signer.sub(4, signer.getInt32(0));
		var digests = sd.sub(4, sd.getInt32(0));
		var digest = digests.sub(4, digests.getInt32(0));
		check("signature: ECDSA with SHA-256", digest.getInt32(0) == 0x0201);
		var eocd = b.sub(eocdAt, b.length - eocdAt);
		eocd.setInt32(16, blockAt);
		var computed = Apk.contentDigest([b.sub(0, blockAt), b.sub(cdAt, eocdAt - cdAt), eocd]);
		check("signature: the contents' digest recomputed", computed.toHex() == digest.sub(8, digest.getInt32(4)).toHex());
		var rest = signer.sub(4 + sd.length, signer.length - 4 - sd.length);
		var sigs = rest.sub(4, rest.getInt32(0));
		var sig1 = sigs.sub(4, sigs.getInt32(0));
		var sig = sig1.sub(8, sig1.getInt32(4));
		var keyAt = 4 + rest.getInt32(0);
		var spki = rest.sub(keyAt + 4, rest.getInt32(keyAt));
		if (has("apksigner")) {
			var r = exec("apksigner", ["verify", "--verbose", path]);
			check("apksigner verify (v2)", r.code == 0 && r.out.indexOf("Verified using v2 scheme (APK Signature Scheme v2): true") >= 0,
				r.code == 0 ? "" : r.out.trim().split("\n").pop());
		} else skip("apksigner verify (not found)");
		if (has("openssl")) {
			var base = '$dir/${haxe.io.Path.withoutDirectory(path)}';
			File.saveBytes('$base.signed-data', sd);
			File.saveBytes('$base.sig', sig);
			File.saveBytes('$base.key.der', spki);
			var k =exec("openssl", ["pkey", "-pubin", "-inform", "DER", "-in", '$base.key.der', "-out", '$base.key.pem']);
			var r = exec("openssl", ["dgst", "-sha256", "-verify", '$base.key.pem', "-signature", '$base.sig', '$base.signed-data']);
			check("signature: openssl verifies the signer's", k.code == 0 && r.code == 0, r.out.trim());
			// (the certificate in the signed data: the signer's key)
			var certs = sd.sub(4 + digests.length, sd.length - 4 - digests.length);
			File.saveBytes('$base.cert.der', certs.sub(8, certs.getInt32(4)));
			var c = exec("openssl", ["x509", "-inform", "DER", "-in", '$base.cert.der', "-noout", "-subject", "-pubkey"]);
			check("signature: openssl reads the certificate (CN=Android Debug)", c.code == 0 && c.out.indexOf("Android Debug") >= 0,
				c.out.trim().split("\n")[0]);
		} else skip("openssl (not found)");
	}

	// the bundle's assets/ against what the program names (want.assets)
	static function assets(got:Map<String, Bytes>) {
		var keys = [for (k in got.keys()) k];
		keys.sort(Reflect.compare);
		check("assets: " + (want.assets.keys.length == 0 ? "none" : want.assets.keys.join(", ")), keys.join(",") == want.assets.keys.join(","), keys.join(" "));
		for (k in want.assets.keys)
			if (got.exists(k)) check('assets: $k the file\'s bytes', got.get(k).compare(File.getBytes('${want.assets.dir}/$k')) == 0);
	}

	// --- iOS

	static function bundle(path:String) {
		var files = new Map<String, Bytes>(), modes = new Map<String, Null<Int>>();
		var ipa = path.endsWith(".ipa");
		if (ipa) {
			var re = ~/^Payload\/([^\/]+\.app)\/(.+)$/;
			for (e in Zip.read(File.getBytes(path))) {
				check('ipa: ${e.name} stored, under Payload/<name>.app/', e.method == 0 && re.match(e.name));
				if (!re.match(e.name)) continue;
				files.set(re.matched(2), e.data);
				modes.set(re.matched(2), e.mode);
			}
		} else
			for (rel in walk(path, ""))
				files.set(rel, File.getBytes('$path/$rel'));
		var info = files.get("Info.plist");
		check("bundle: Info.plist", info != null);
		if (info == null) return;
		var d = switch (try Plist.parse(info.toString()) catch (_:Dynamic) null) {
			case PDict(d): d;
			case _: null;
		}
		check("Info.plist: an XML property list, a dictionary", d != null);
		if (d == null) return;
		var str = (k:String) -> switch d.get(k) {
			case PString(s): s;
			case _: null;
		};
		var exe = str("CFBundleExecutable"), id = str("CFBundleIdentifier"), min = str("MinimumOSVersion");
		check("Info.plist: CFBundleExecutable, CFBundleIdentifier, MinimumOSVersion", exe != null && id != null && min != null, '$exe $id $min');
		if (want.id != null) check('Info.plist: CFBundleIdentifier ${want.id}', id == want.id, id);
		check("Info.plist: CFBundlePackageType APPL, UILaunchScreen", str("CFBundlePackageType") == "APPL" && d.get("UILaunchScreen") != null);
		var sim = switch d.get("CFBundleSupportedPlatforms") {
			case PArray([PString(p)]): p == "iPhoneSimulator";
			case _: false;
		}
		check("Info.plist: DTPlatformName the platform's", str("DTPlatformName") == (sim ? "iphonesimulator" : "iphoneos"));
		var orientations = (k:String) -> switch d.get(k) {
			case PArray(a): [for (v in a) switch v {
					case PString(s): StringTools.replace(s, "UIInterfaceOrientation", "");
					case _: "?";
				}].join(",");
			case _: "";
		};
		var all = "Portrait,PortraitUpsideDown,LandscapeLeft,LandscapeRight";
		var phone = want.orientation == "portrait" ? "Portrait" : want.orientation == "landscape" ? "LandscapeLeft,LandscapeRight" : all;
		var pad = want.orientation == "portrait" ? "Portrait,PortraitUpsideDown" : phone;
		check('Info.plist: UISupportedInterfaceOrientations for ${want.orientation}', orientations("UISupportedInterfaceOrientations") == phone,
			orientations("UISupportedInterfaceOrientations"));
		check('Info.plist: UISupportedInterfaceOrientations~ipad for ${want.orientation}', orientations("UISupportedInterfaceOrientations~ipad") == pad);
		check("Info.plist: UIRequiresFullScreen with an orientation", (d.get("UIRequiresFullScreen") != null) == (want.orientation != "any"));
		check("Info.plist: UIStatusBarHidden " + want.fullscreen, (d.get("UIStatusBarHidden") != null) == want.fullscreen);
		var names = [for (k in files.keys()) if (!k.startsWith("assets/")) k];
		names.sort(Reflect.compare);
		assets([for (k => v in files) if (k.startsWith("assets/")) k.substr(7) => v]);
		var expected = ["Info.plist", exe, "_CodeSignature/CodeResources"];
		if (want.icons) {
			for (f in helder.pack.ios.AssetCatalog.LOOSE) {
				var png = files.exists(f.file) ? helder.image.PngDecoder.decode(files.get(f.file)) : null;
				check('bundle: ${f.file}, ${f.px} px, opaque', png != null && png.width == f.px && png.rgba.get(3) == 255);
				expected.push(f.file);
			}
			var primary = (k:String) -> switch d.get(k) {
				case PDict(a): switch a.get("CFBundlePrimaryIcon") {
						case PDict(p): Type.enumEq(p.get("CFBundleIconName"), PString("AppIcon")) && p.exists("CFBundleIconFiles");
						case _: false;
					}
				case _: false;
			}
			check("Info.plist: CFBundleIcons, ~ipad's: CFBundleIconName AppIcon", primary("CFBundleIcons") && primary("CFBundleIcons~ipad"));
			expected.push("Assets.car");
			if (files.exists("Assets.car")) car(files.get("Assets.car"), min);
			else check("bundle: Assets.car", false);
			var launch = switch d.get("UILaunchScreen") {
				case PDict(l): l.get("UIImageName");
				case _: null;
			}
			check("Info.plist: UILaunchScreen's UIImageName LaunchImage", launch != null && Type.enumEq(launch, PString("LaunchImage")));
			for (f in ["LaunchImage@3x~iphone.png", "LaunchImage@2x~ipad.png"]) {
				check('bundle: $f', files.exists(f));
				expected.push(f);
			}
		}
		if (!sim) {
			expected.push("PrivacyInfo.xcprivacy");
			var p = files.get("PrivacyInfo.xcprivacy");
			var priv = p == null ? null : switch (try Plist.parse(p.toString()) catch (_:Dynamic) null) {
				case PDict(x): x;
				case _: null;
			}
			check("PrivacyInfo.xcprivacy: no tracking, the API types listed", priv != null && Type.enumEq(priv.get("NSPrivacyTracking"), PBool(false))
				&& priv.exists("NSPrivacyAccessedAPITypes"));
			for (k in ["DTPlatformVersion", "DTSDKName", "DTXcode", "DTXcodeBuild", "BuildMachineOSBuild", "DTPlatformBuild"])
				check('Info.plist: $k', str(k) != null, str(k));
		}
		if (want.signed) {
			expected.push("embedded.mobileprovision");
			check("bundle: embedded.mobileprovision, the profile", files.exists("embedded.mobileprovision")
				&& files.get("embedded.mobileprovision").compare(File.getBytes("tests/pack/signing/test.mobileprovision")) == 0);
		}
		if (want.encryption) check("Info.plist: ITSAppUsesNonExemptEncryption false", Type.enumEq(d.get("ITSAppUsesNonExemptEncryption"), PBool(false)));
		expected.sort(Reflect.compare);
		check("bundle: the executable, Info.plist, _CodeSignature/CodeResources", names.join(",") == expected.join(","), names.join(" "));
		if (ipa) check("ipa: the executable 0755, the rest 0644", modes.get(exe) == 0x1ed && modes.get("Info.plist") == 0x1a4);
		var bin = files.get(exe), res = files.get("_CodeSignature/CodeResources");
		if (bin == null || res == null) return;
		var hashed = switch (try Plist.parse(res.toString()) catch (_:Dynamic) null) {
			case PDict(c): switch c.get("files") {
					case PDict(f): switch f.get("Info.plist") {
						case PData(h): h.toHex() == haxe.crypto.Sha1.make(info).toHex();
						case _: false;
					}
					case _: false;
				}
			case _: false;
		}
		check("CodeResources: Info.plist's SHA-1", hashed);
		var sealed = switch (try Plist.parse(res.toString()) catch (_:Dynamic) null) {
			case PDict(c): {files: c.get("files"), files2: c.get("files2")};
			case _: null;
		}
		for (k in want.assets.keys) {
			var data = files.get('assets/$k');
			if (data == null || sealed == null) continue;
			var one = switch sealed.files {
				case PDict(f): switch f.get('assets/$k') {
						case PData(h): h.toHex() == haxe.crypto.Sha1.make(data).toHex();
						case _: false;
					}
				case _: false;
			}
			var two = switch sealed.files2 {
				case PDict(f): switch f.get('assets/$k') {
						case PDict(e): switch e.get("hash2") {
								case PData(h): h.toHex() == haxe.crypto.Sha256.make(data).toHex();
								case _: false;
							}
						case _: false;
					}
				case _: false;
			}
			check('CodeResources: assets/$k\'s SHA-1 and SHA-256', one && two);
		}
		if (want.fullscreen) built(bin);
		macho(bin, id, sim, min, info, res);
		if (sealed != null)
			for (f in ["Assets.car", "embedded.mobileprovision", "PrivacyInfo.xcprivacy"])
				if (files.exists(f)) check('CodeResources: $f\'s SHA-256', switch sealed.files2 {
					case PDict(x): switch x.get(f) {
							case PDict(e): switch e.get("hash2") {
									case PData(h): h.toHex() == haxe.crypto.Sha256.make(files.get(f)).toHex();
									case _: false;
								}
							case _: false;
						}
					case _: false;
				});
		if (!ipa && Sys.systemName() == "Mac") {
			var r = exec("codesign", ["--verify", "--strict", "--verbose=2", path]);
			check("codesign --verify --strict", r.code == 0, r.out.trim().split("\n").join("; "));
			var r = exec("plutil", ["-lint", '$path/Info.plist']);
			check("plutil -lint Info.plist", r.code == 0, r.out.trim());
		} else if (!ipa) skip("codesign --verify, plutil -lint (macOS)");
	}

	// (fullscreen: the project's line of a build with -D helder.fullscreen)
	static function built(b:Bytes) {
		// (as bytes, or as UTF-16 units: how hxmc keeps a literal)
		var text = "packed project (fullscreen)", wide = Bytes.alloc(2 * text.length);
		for (k in 0...text.length)
			wide.setUInt16(2 * k, text.charCodeAt(k));
		var found = false;
		for (s in [Bytes.ofString(text), wide]) {
			var i = 0;
			while (!found && i <= b.length - s.length) {
				if (b.get(i) == s.get(0) && b.sub(i, s.length).compare(s) == 0) found = true;
				i++;
			}
		}
		check("the program built with -D helder.fullscreen", found);
	}

	static function walk(root:String, rel:String):Array<String> {
		var out = [];
		for (n in FileSystem.readDirectory(rel == "" ? root : '$root/$rel')) {
			var r = rel == "" ? n : '$rel/$n';
			if (FileSystem.isDirectory('$root/$r')) out = out.concat(walk(root, r)) else out.push(r);
		}
		return out;
	}

	static function be32(b:Bytes, at:Int):Int
		return (b.get(at) << 24) | (b.get(at + 1) << 16) | (b.get(at + 2) << 8) | b.get(at + 3);

	static function cstr(b:Bytes, at:Int, max:Int):String {
		var e = at;
		while (e < at + max && b.get(e) != 0)
			e++;
		return b.getString(at, e - at);
	}

	static function macho(b:Bytes, id:String, sim:Bool, min:String, info:Bytes, res:Bytes) {
		check("Mach-O: 64-bit, arm64, MH_EXECUTE", b.getInt32(0) == 0xfeedfacf && b.getInt32(4) == 0x0100000c && b.getInt32(12) == 2);
		check("Mach-O: PIE", b.getInt32(24) & 0x200000 != 0);
		var ncmds = b.getInt32(16), at = 32;
		var platform = -1, minos = -1, main = false, sigOff = -1, sigSize = 0;
		for (_ in 0...ncmds) {
			var cmd = b.getInt32(at), size = b.getInt32(at + 4);
			switch cmd {
				case 0x32:
					platform = b.getInt32(at + 8);
					minos = b.getInt32(at + 12);
				case 0x80000028: main = true;
				case 0x1d:
					sigOff = b.getInt32(at + 8);
					sigSize = b.getInt32(at + 12);
				case _:
			}
			at += size;
		}
		var p = min.split(".");
		check("Mach-O: the build version's platform: " + (sim ? "iOS simulator (7)" : "iOS (2)"), platform == (sim ? 7 : 2), "" + platform);
		check("Mach-O: the build version's minimum is MinimumOSVersion", minos == (Std.parseInt(p[0]) << 16) | (Std.parseInt(p[1]) << 8), StringTools.hex(minos));
		check("Mach-O: LC_MAIN", main);
		check("Mach-O: the code signature ends the file", sigOff > 0 && sigOff + sigSize == b.length);
		if (sigOff <= 0) return;
		check("signature: a SuperBlob", be32(b, sigOff) == 0xfade0cc0);
		var blobs = new Map<Int, Int>();
		for (k in 0...be32(b, sigOff + 8))
			blobs.set(be32(b, sigOff + 12 + 8 * k), sigOff + be32(b, sigOff + 16 + 8 * k));
		var cd = blobs.get(0), req = blobs.get(2);
		check("signature: a CodeDirectory and requirements", cd != null && req != null && be32(b, cd) == 0xfade0c02 && be32(b, req) == 0xfade0c01);
		if (cd == null || req == null) return;
		var flags = be32(b, cd + 12), hashOff = be32(b, cd + 16), identOff = be32(b, cd + 20), nSpecial = be32(b, cd + 24), nCode = be32(b, cd + 28),
			codeLimit = be32(b, cd + 32);
		if (want.signed) check("CodeDirectory: not ad hoc (a certificate's)", flags == 0, StringTools.hex(flags));
		else check("CodeDirectory: ad hoc, not linker-signed", flags & 0x2 != 0 && flags & 0x20000 == 0, StringTools.hex(flags));
		check("CodeDirectory: identified by the bundle id", cstr(b, cd + identOff, 256) == id, cstr(b, cd + identOff, 256));
		check("CodeDirectory: SHA-256 of 4 KB pages up to the signature", b.get(cd + 36) == 32 && b.get(cd + 37) == 2 && b.get(cd + 39) == 12
			&& codeLimit == sigOff && nCode == (codeLimit + 4095) >> 12);
		var bad = 0;
		for (k in 0...nCode) {
			var off = k << 12, n = codeLimit - off < 4096 ? codeLimit - off : 4096;
			if (haxe.crypto.Sha256.make(b.sub(off, n)).toHex() != b.sub(cd + hashOff + 32 * k, 32).toHex()) bad++;
		}
		check("CodeDirectory: the page hashes recomputed", bad == 0, bad + " of " + nCode + " differ");
		var slot = (k:Int) -> k > nSpecial ? "" : b.sub(cd + hashOff - 32 * k, 32).toHex();
		check("CodeDirectory: slot 1, Info.plist's hash", slot(1) == haxe.crypto.Sha256.make(info).toHex());
		check("CodeDirectory: slot 2, the requirements' hash", slot(2) == haxe.crypto.Sha256.make(b.sub(req, be32(b, req + 4))).toHex());
		check("CodeDirectory: slot 3, CodeResources' hash", slot(3) == haxe.crypto.Sha256.make(res).toHex());
		var ent = blobs.get(5);
		if (want.entitlements) check("signature: the entitlements (slot 5)", ent != null && be32(b, ent) == 0xfade7171);
		if (ent != null) check("CodeDirectory: slot 5, the entitlements' hash", slot(5) == haxe.crypto.Sha256.make(b.sub(ent, be32(b, ent + 4))).toHex());
		if (want.signed) signed(b, cd, blobs, slot, sigOff + sigSize);
	}

	// a distribution signature: the build version's SDK, the team, the DER
	// entitlements, the designated requirement, the CMS verified by openssl
	// over the CodeDirectory (tests/pack/signing's CA)
	static function signed(b:Bytes, cd:Int, blobs:Map<Int, Int>, slot:Int->String, end:Int) {
		var at = 32, sdk = -1;
		for (_ in 0...b.getInt32(16)) {
			if (b.getInt32(at) == 0x32) sdk = b.getInt32(at + 16);
			at += b.getInt32(at + 4);
		}
		check("Mach-O: the build version's SDK 26.0", sdk == 0x1a0000, StringTools.hex(sdk));
		check("CodeDirectory: the team HLDRTEST01", cstr(b, cd + be32(b, cd + 48), 32) == "HLDRTEST01");
		var der = blobs.get(7), xml = blobs.get(5), cms = blobs.get(0x10000);
		check("signature: DER entitlements (slot 7), their hash", der != null && be32(b, der) == 0xfade7172
			&& slot(7) == haxe.crypto.Sha256.make(b.sub(der, be32(b, der + 4))).toHex());
		if (xml != null && der != null) {
			var e = switch Plist.parse(b.sub(xml + 8, be32(b, xml + 4) - 8).toString()) {
				case PDict(e): e;
				case _: new Map();
			}
			check("entitlements: the profile's for the bundle, get-task-allow false", Type.enumEq(e.get("get-task-allow"), PBool(false))
				&& Type.enumEq(e.get("application-identifier"), PString("HLDRTEST01." + want.id)));
			check("entitlements: the DER of the XML's", b.sub(der + 8, be32(b, der + 4) - 8).compare(helder.pack.apple.CodeSign.entitlementsDer(e)) == 0);
		}
		var req = blobs.get(2);
		check("requirements: a designated requirement (an expression)", be32(b, req + 8) == 1 && be32(b, req + 12) == 3 && be32(b, req + 20) == 0xfade0c00);
		check("signature: a CMS blob (slot 0x10000)", cms != null && be32(b, cms) == 0xfade0b01);
		if (cms == null) return;
		var cdBytes = b.sub(cd, be32(b, cd + 4));
		File.saveBytes('$dir/cd.bin', cdBytes);
		File.saveBytes('$dir/cms.der', b.sub(cms + 8, be32(b, cms + 4) - 8));
		if (has("openssl")) {
			var r = exec("openssl", ["cms", "-verify", "-binary", "-inform", "DER", "-in", '$dir/cms.der', "-content", '$dir/cd.bin', "-CAfile",
				"tests/pack/signing/ca.pem", "-purpose", "any", "-out", '$dir/cms.out']);
			check("CMS: openssl cms -verify over the CodeDirectory (the CA's chain)", r.code == 0, r.out.trim().split("\n").join("; "));
			var p = exec("openssl", ["cms", "-cmsout", "-print", "-inform", "DER", "-in", '$dir/cms.der']);
			check("CMS: Apple's attributes (1.2.840.113635.100.9.1, .2)", p.out.indexOf("1.2.840.113635.100.9.1") >= 0 && p.out.indexOf("1.2.840.113635.100.9.2") >= 0);
		} else skip("openssl cms -verify (not found)");
	}

	// Assets.car: the app icon's renditions (AssetCatalog.read), and the
	// structure of Apple actool's (tests/pack/reference/Assets.car, from
	// viraptor/actool's samples): the same blocks, header, key format
	// attributes and rendition layouts, TLVs, facet and bitmap keys' shapes
	static function car(bytes:Bytes, min:String) {
		var c = try helder.pack.ios.AssetCatalog.read(bytes) catch (e:Dynamic) {
			check("Assets.car: read back", false, Std.string(e));
			return;
		}
		var images = [for (r in c.renditions) if (r.layout == 12) '${r.key.get(15)}:${r.width}'];
		images.sort(Reflect.compare);
		check("Assets.car: 120, 180 (iPhone), 152, 167 (iPad), 1024 (marketing)", images.join(" ") == "1:120 1:180 2:152 2:167 6:1024", images.join(" "));
		check("Assets.car: opaque", Lambda.foreach(c.renditions, r -> r.pixels == null || r.pixels.get(3) == 255));
		check("Assets.car: iOS, the deployment target", c.platform == "ios" && c.deployment == min, c.platform + " " + c.deployment);
		var ref = helder.pack.ios.AssetCatalog.read(File.getBytes("tests/pack/reference/Assets.car"));
		check("Assets.car: actool's blocks (and iOS's APPEARANCEKEYS)", [for (n in ref.blocks) if (!c.blocks.contains(n)) n].length == 0
			&& [for (n in c.blocks) if (!ref.blocks.contains(n)) n].join(",") == "APPEARANCEKEYS", c.blocks.join(" "));
		check("Assets.car: the key format's attributes, actool's", [for (a in c.keyformat) if (!ref.keyformat.contains(a) && a != 15 && a != 16) a].length == 0);
		check("Assets.car: the renditions' key size, two bytes an attribute", c.renditionKeySize == 2 * c.keyformat.length && ref.renditionKeySize == 2 * ref.keyformat.length);
		var refIcon = Lambda.find(ref.renditions, r -> r.layout == 12 && r.key.get(2) == 220);
		var icon = Lambda.find(c.renditions, r -> r.layout == 12);
		var tags = (r:helder.pack.ios.AssetCatalog.Rendition) -> {
			var t = [for (k in r.tlvs.keys()) k];
			t.sort(Reflect.compare);
			t.join(",");
		}
		check("Assets.car: an icon's rendition: actool's TLVs, element, part, format", refIcon != null && tags(icon) == tags(refIcon)
			&& icon.key.get(1) == refIcon.key.get(1) && icon.key.get(2) == refIcon.key.get(2) && icon.format == refIcon.format, tags(icon) + " / " + tags(refIcon));
		var refMulti = Lambda.find(ref.renditions, r -> r.layout == 1010), multi = Lambda.find(c.renditions, r -> r.layout == 1010);
		check("Assets.car: a MultiSized rendition: actool's TLVs and SISM", multi != null && refMulti != null && tags(multi) == tags(refMulti)
			&& multi.data.getString(0, 4) == refMulti.data.getString(0, 4) && multi.key.get(2) == refMulti.key.get(2));
		check("Assets.car: the facet's value, actool's shape", c.facets.get("AppIcon").length == ref.facets.get("AppIcon").length
			&& c.facets.get("AppIcon").sub(0, 6).compare(ref.facets.get("AppIcon").sub(0, 6)) == 0);
		var bk = c.bitmapKeys.get(6849), refBk = ref.bitmapKeys.get(6849);
		check("Assets.car: the bitmap keys' shape, actool's", bk != null && refBk != null && bk.getInt32(12) == c.keyformat.length
			&& refBk.getInt32(12) == ref.keyformat.length && bk.sub(0, 8).compare(refBk.sub(0, 8)) == 0);
		if (Sys.systemName() == "Mac" && has("xcrun")) {
			File.saveBytes('$dir/Assets.car', bytes);
			var r = exec("xcrun", ["assetutil", "--info", '$dir/Assets.car']);
			check("xcrun assetutil --info Assets.car", r.code == 0 && r.out.indexOf("AppIcon") >= 0, r.out.trim().split("\n").slice(0, 3).join("; "));
		} else skip("xcrun assetutil --info (macOS)");
	}
}
