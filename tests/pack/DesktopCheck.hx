import haxe.io.Bytes;
import helder.pack.Zip;
import helder.pack.ios.Plist;
import helder.pack.windows.Authenticode;
import helder.pack.windows.Pe;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The desktop releases `helder build --package` makes (helder.cli.Desktop;
// the viewer-package lane), checked on Eval without the platforms' tools:
//   haxe -cp src -cp tests/pack --run DesktopCheck <dir> <id> <package>...
// - a .tar.gz (Linux): gunzipped, its ustar entries read: the program
//   (0755) at the top of <name>-<version>/, install.sh, the .desktop file
//   (Exec, Icon, MimeType, StartupWMClass), the hicolor icons 16 to 512
//   (PNGs of their size), the AppStream metainfo; beside it the Flatpak
//   manifest naming the tarball by its SHA-256;
// - a Windows zip: the .exe (0755), a PE32+ of the GUI subsystem, its
//   resources (icons, the group, the version), its checksum; signed: the
//   WIN_CERTIFICATE's SpcIndirectDataContent's digest the image's hash
//   recomputed (osslsigncode verify, the lane's, checks the rest);
// - a macOS zip: <Label>.app's Info.plist, the universal executable
//   (0755: both slices), AppIcon.icns, _CodeSignature/CodeResources (the
//   icon's hashes in files and files2), each slice's signature binding
//   Info.plist and CodeResources and its pages' hashes.
// The files the lane's tools check next (the .exe, the .desktop file, the
// metainfo) are written to <dir>/check/.
class DesktopCheck {
	static var failures = 0;

	static function check(ok:Bool, what:String) {
		if (!ok) {
			Sys.println("  FAIL " + what);
			failures++;
		}
	}

	static function main() {
		var args = Sys.args();
		var dir = args[0], id = args[1];
		FileSystem.createDirectory('$dir/check');
		for (f in args.slice(2)) {
			Sys.println("desktop: " + f);
			var b = File.getBytes(f);
			if (f.endsWith(".tar.gz")) linux(dir, id, f, b) else if (f.indexOf("windows") >= 0) windows(dir, b) else mac(b);
		}
		if (failures > 0) {
			Sys.println('desktop: $failures failed');
			Sys.exit(1);
		}
		Sys.println("desktop: the packages are as they should be");
	}

	// ---- Linux

	static function linux(dir:String, id:String, file:String, gz:Bytes) {
		check(gz.get(0) == 0x1f && gz.get(1) == 0x8b, "gzip's magic");
		var size = gz.getInt32(gz.length - 4);
		var tar = Bytes.alloc(size);
		var n = new haxe.zip.InflateImpl(new haxe.io.BytesInput(gz.sub(10, gz.length - 18)), false, false).readBytes(tar, 0, size);
		check(n == size && haxe.crypto.Crc32.make(tar) == gz.getInt32(gz.length - 8), "gunzipped whole, its CRC");
		var entries = new Map<String, {mode:Int, kind:Int, data:Bytes}>();
		var at = 0;
		while (at + 512 <= tar.length && tar.get(at) != 0) {
			var name = cstr(tar, at, 100), prefix = cstr(tar, at + 345, 155);
			if (prefix != "") name = prefix + "/" + name;
			var len = octal(tar, at + 124, 12), mode = octal(tar, at + 100, 8), kind = tar.get(at + 156);
			var sum = 0;
			for (i in 0...512)
				sum += i >= 148 && i < 156 ? 32 : tar.get(at + i);
			check(octal(tar, at + 148, 8) == sum, '$name: its header checksum');
			check(cstr(tar, at + 257, 6) == "ustar", '$name: ustar');
			entries.set(name, {mode: mode, kind: kind, data: tar.sub(at + 512, len)});
			at += 512 + ((len + 511) & ~511);
		}
		var top = [for (k in entries.keys()) if (k.endsWith("/") && k.split("/").length == 2) k][0];
		check(top != null, "one top directory");
		var name = top.substr(0, top.indexOf("-"));
		var exe = entries.get(top + name);
		check(exe != null && exe.mode == 0x1ed && exe.data.getInt32(0) == 0x464c457f, 'the program $name: an ELF, 0755');
		check(entries.get(top + "install.sh")?.mode == 0x1ed, "install.sh, 0755");
		var desktop = entries.get(top + 'share/applications/$id.desktop');
		check(desktop != null, '$id.desktop');
		if (desktop != null) {
			var t = desktop.data.toString();
			File.saveBytes('$dir/check/$id.desktop', desktop.data);
			for (want in ["[Desktop Entry]", 'Exec=$name %F', 'Icon=$id', 'StartupWMClass=$name', "MimeType=image/jpeg;", "application/pdf;", "Type=Application"])
				check(t.indexOf(want) >= 0, '$id.desktop: $want');
		}
		for (px in [16, 24, 32, 48, 64, 128, 256, 512]) {
			var icon = entries.get(top + 'share/icons/hicolor/${px}x$px/apps/$id.png');
			check(icon != null && icon.data.getInt32(16) == be(px) && icon.data.getInt32(20) == be(px), 'the icon at ${px}x$px');
		}
		var meta = entries.get(top + 'share/metainfo/$id.metainfo.xml');
		check(meta != null && meta.data.toString().indexOf('<id>$id</id>') > 0 && meta.data.toString().indexOf('<launchable type="desktop-id">$id.desktop</launchable>') > 0, "the metainfo");
		if (meta != null) File.saveBytes('$dir/check/$id.metainfo.xml', meta.data);
		var manifest = haxe.io.Path.directory(file) + '/$id.flatpak.json';
		check(FileSystem.exists(manifest), "the Flatpak manifest beside it");
		if (FileSystem.exists(manifest)) {
			var j:Dynamic = haxe.Json.parse(File.getContent(manifest));
			check(j.id == id && j.command == name, "the manifest's id and command");
			var src:Dynamic = j.modules[0].sources[0];
			check(src.path == haxe.io.Path.withoutDirectory(file) && src.sha256 == haxe.crypto.Sha256.make(gz).toHex(), "the manifest's source: the tarball by its SHA-256");
			check((Reflect.field(j, "finish-args") : Array<String>).contains("--socket=wayland"), "Wayland");
		}
	}

	// ---- Windows

	static function windows(dir:String, zip:Bytes) {
		var es = Zip.read(zip);
		var exe = [for (e in es) if (e.name.endsWith(".exe")) e][0];
		check(exe != null && exe.mode == 0x1ed, "the .exe, 0755");
		if (exe == null) return;
		File.saveBytes('$dir/check/' + haxe.io.Path.withoutDirectory(exe.name), exe.data);
		var p = new Pe(exe.data);
		check(p.subsystem == 2, "the GUI subsystem");
		var rsrc = [for (i in 0...p.count) p.section(i)].filter(s -> s.name == ".rsrc")[0];
		check(rsrc != null && exe.data.getInt32(p.directoryAt(2)) == rsrc.va, "a resource section, the directory at it");
		if (rsrc != null) {
			var r = exe.data.sub(rsrc.rawAt, rsrc.vsize);
			var ids = [for (k in 0...r.getUInt16(14)) r.getInt32(16 + 8 * k)];
			check(ids.join(",") == "3,14,16", 'icons, their group, the version: ${ids.join(",")}');
		}
		var copy = exe.data.sub(0, exe.data.length);
		var sum = copy.getInt32(p.checksumAt);
		check(Pe.withChecksum(copy).getInt32(p.checksumAt) == sum, "its checksum");
		var c = p.certificates();
		if (c.size == 0) {
			Sys.println("  unsigned");
			return;
		}
		check(c.at + c.size == exe.data.length && exe.data.getUInt16(c.at + 4) == 0x200 && exe.data.getUInt16(c.at + 6) == 2, "a WIN_CERTIFICATE ending the file");
		var hash = Authenticode.hash(exe.data, p);
		var cms = exe.data.sub(c.at + 8, exe.data.getInt32(c.at) - 8);
		check(cms.toHex().indexOf(Authenticode.indirectData(hash).toHex()) > 0, "the signed digest: the image's hash");
	}

	// ---- macOS

	static function mac(zip:Bytes) {
		var es = Zip.read(zip);
		var by = [for (e in es) e.name => e];
		var app = es[0].name.substr(0, es[0].name.indexOf(".app/") + 5);
		var info = by.get(app + "Contents/Info.plist"), seal = by.get(app + "Contents/_CodeSignature/CodeResources");
		var icns = by.get(app + "Contents/Resources/AppIcon.icns");
		check(info != null && seal != null && icns != null, "Info.plist, CodeResources, AppIcon.icns");
		if (info == null || seal == null) return;
		var plist = Plist.parse(info.data.toString());
		var exeName = switch plist {
			case PDict(d): switch d.get("CFBundleExecutable") {
					case PString(s): s;
					case _: "";
				}
			case _: "";
		}
		var exe = by.get(app + "Contents/MacOS/" + exeName);
		check(exe != null && exe.mode == 0x1ed, "the executable, 0755");
		check(icns.data.getString(0, 4) == "icns", "an .icns");
		var res = Plist.parse(seal.data.toString());
		switch res {
			case PDict(d):
				var v1 = switch d.get("files") {
					case PDict(f): f.get("Resources/AppIcon.icns");
					case _: null;
				}
				var v2 = switch d.get("files2") {
					case PDict(f): f.get("Resources/AppIcon.icns");
					case _: null;
				}
				check(v1 != null && v1.match(PData(_)) && data(v1).compare(haxe.crypto.Sha1.make(icns.data)) == 0, "the icon sealed in files: its SHA-1");
				var h2 = switch v2 {
					case PDict(x): x.get("hash2");
					case _: null;
				}
				check(h2 != null && h2.match(PData(_)) && data(h2).compare(haxe.crypto.Sha256.make(icns.data)) == 0, "the icon sealed in files2: its SHA-256");
			case _: check(false, "CodeResources: a dictionary");
		}
		if (exe == null) return;
		var b = exe.data;
		check(b.get(0) == 0xca && b.get(1) == 0xfe && b.get(2) == 0xba && b.get(3) == 0xbe, "a universal executable");
		var n = bin(b, 4);
		check(n == 2, "two slices");
		for (i in 0...n) {
			var off = bin(b, 8 + 20 * i + 8), size = bin(b, 8 + 20 * i + 12);
			var s = b.sub(off, size);
			var ncmds = s.getInt32(16), at = 32, sig = -1;
			for (_ in 0...ncmds) {
				if (s.getInt32(at) == 0x1d) sig = s.getInt32(at + 8);
				at += s.getInt32(at + 4);
			}
			check(sig > 0 && bin(s, sig) == 0xfade0cc0, 'slice $i: a SuperBlob');
			if (sig < 0) continue;
			var cd = -1;
			for (k in 0...bin(s, sig + 8))
				if (bin(s, sig + 12 + 8 * k) == 0) cd = sig + bin(s, sig + 16 + 8 * k);
			var hashOff = bin(s, cd + 16), pages = bin(s, cd + 28), limit = bin(s, cd + 32);
			check(limit == sig, 'slice $i: the code limit at the signature');
			check(s.sub(cd + hashOff - 32, 32).compare(haxe.crypto.Sha256.make(info.data)) == 0, 'slice $i: Info.plist bound');
			check(s.sub(cd + hashOff - 96, 32).compare(haxe.crypto.Sha256.make(seal.data)) == 0, 'slice $i: CodeResources bound');
			var ok = true;
			for (p in 0...pages) {
				var o = p << 12;
				if (s.sub(cd + hashOff + 32 * p, 32).compare(haxe.crypto.Sha256.make(s.sub(o, limit - o < 4096 ? limit - o : 4096))) != 0) ok = false;
			}
			check(ok, 'slice $i: its pages\' hashes');
			Sys.println('  slice $i: ' + ((bin(s, cd + 12) & 2) != 0 ? "ad hoc" : "signed") + ((bin(s, cd + 12) & 0x10000) != 0 ? ", hardened runtime" : ""));
		}
	}

	static function data(v:PValue):Bytes
		return switch v {
			case PData(b): b;
			case _: Bytes.alloc(0);
		}

	static function cstr(b:Bytes, at:Int, max:Int):String {
		var n = 0;
		while (n < max && b.get(at + n) != 0)
			n++;
		return b.getString(at, n);
	}

	static function octal(b:Bytes, at:Int, max:Int):Int {
		var v = 0;
		for (i in 0...max) {
			var c = b.get(at + i);
			if (c == 32 && v == 0) continue;
			if (c < 48 || c > 55) break;
			v = v * 8 + c - 48;
		}
		return v;
	}

	static inline function be(v:Int):Int
		return ((v & 0xff) << 24) | ((v >> 8 & 0xff) << 16) | ((v >> 16 & 0xff) << 8) | (v >>> 24);

	static function bin(b:Bytes, at:Int):Int
		return (b.get(at) << 24) | (b.get(at + 1) << 16) | (b.get(at + 2) << 8) | b.get(at + 3);
}
