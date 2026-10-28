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
// - classes.dex when there: Dex.check's structure, Glue's methods;
// - the library (readelf, when there): a shared object of the ABI, 16 KB
//   segments, its soname libmain.so, the export ANativeActivity_onCreate,
//   DT_NEEDED only the system's, no text relocations;
// - the v2 signature: the block, the digest of the contents recomputed and
//   equal to the signed one, verified by apksigner when there, else by
//   openssl (the signer's key and signature over the signed data).
// An .app or an .ipa:
// - the bundle: the executable, Info.plist and _CodeSignature/CodeResources,
//   nothing else (an .ipa: under Payload/<name>.app/, stored, the
//   executable 0755);
// - Info.plist parsed: the executable, the id, UILaunchScreen, the platform
//   and the minimum version; CodeResources: Info.plist's SHA-1;
// - the executable: a 64-bit arm64 MH_EXECUTE, PIE, LC_MAIN, the build
//   version's platform and minimum (the plist's), the signature ending the
//   file: a CodeDirectory, ad hoc, identified by the bundle id, its page
//   hashes recomputed, its special slots the hashes of Info.plist (1), the
//   requirements (2), CodeResources (3) and the entitlements (5) when signed;
// - on a Mac, codesign --verify and plutil -lint.
// Exits non-zero on a failure; a missing tool is a line saying so.
class PackCheck {
	static var failures = 0;
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
			if (a.endsWith(".apk")) apk(a) else bundle(a);
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
		var names = [for (e in entries) e.name];
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
		check("manifest: " + activity + (views && !code ? ", but no classes.dex" : ""),
			xml.indexOf('android:name(0x01010003)="$activity"') >= 0 && (code || !views));
		check("manifest: android.app.lib_name main", xml.indexOf('"android.app.lib_name"') >= 0 && xml.indexOf('android:value(0x01010024)="main"') >= 0);
		check("manifest: hasCode " + code + ", extractNativeLibs false, debuggable",
			xml.indexOf("android:hasCode(0x0101000c)=" + code) >= 0 && xml.indexOf("android:extractNativeLibs(0x010104ea)=false") >= 0
			&& xml.indexOf("android:debuggable(0x0101000f)=true") >= 0);
		check("manifest: the launcher's intent filter", xml.indexOf('"android.intent.action.MAIN"') >= 0 && xml.indexOf('"android.intent.category.LAUNCHER"') >= 0);
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
		if (has("readelf")) elf(so, abi) else skip("readelf (not found)");
		signature(path, b);
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
		check("library: exports ANativeActivity_onCreate", ~/FUNC\s+GLOBAL\s+DEFAULT\s+\d+\s+ANativeActivity_onCreate/.match(readelf(["--dyn-syms"])));
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
		check("Info.plist: CFBundlePackageType APPL, UILaunchScreen", str("CFBundlePackageType") == "APPL" && d.get("UILaunchScreen") != null);
		var sim = switch d.get("CFBundleSupportedPlatforms") {
			case PArray([PString(p)]): p == "iPhoneSimulator";
			case _: false;
		}
		check("Info.plist: DTPlatformName the platform's", str("DTPlatformName") == (sim ? "iphonesimulator" : "iphoneos"));
		var names = [for (k in files.keys()) k];
		names.sort(Reflect.compare);
		var want = ["Info.plist", exe, "_CodeSignature/CodeResources"];
		want.sort(Reflect.compare);
		check("bundle: the executable, Info.plist, _CodeSignature/CodeResources", names.join(",") == want.join(","), names.join(" "));
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
		macho(bin, id, sim, min, info, res);
		if (!ipa && Sys.systemName() == "Mac") {
			var r = exec("codesign", ["--verify", "--strict", "--verbose=2", path]);
			check("codesign --verify --strict", r.code == 0, r.out.trim().split("\n").join("; "));
			var r = exec("plutil", ["-lint", '$path/Info.plist']);
			check("plutil -lint Info.plist", r.code == 0, r.out.trim());
		} else if (!ipa) skip("codesign --verify, plutil -lint (macOS)");
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
		check("CodeDirectory: ad hoc, not linker-signed", flags & 0x2 != 0 && flags & 0x20000 == 0, StringTools.hex(flags));
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
		if (ent != null) check("CodeDirectory: slot 5, the entitlements' hash", slot(5) == haxe.crypto.Sha256.make(b.sub(ent, be32(b, ent + 4))).toHex());
	}
}
