package helder.cli;

import haxe.io.Bytes;
import haxe.io.Path;
import helder.pack.Tar;
import helder.pack.Zip;
import helder.pack.apple.Identity;
import helder.pack.windows.Authenticode;
import helder.pack.windows.Pe;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `helder build --target <desktop> --package`: what a release ships for
// each desktop, in bin/dist (-o another directory), named
// <name>-<version>-<platform> (the manifest's version, "helder": {"version"}):
//
// - macos: the universal .app (Mac: sealed and signed, ad hoc or with a
//   Developer ID identity: macSigning) in a zip (<Label>.app/ at its top,
//   the executable 0755); notarised by `helder publish --notarize`;
// - windows-x86_64, windows-arm64: the .exe made a GUI program (no console
//   window), its icon in every size and its version information as
//   resources (helder.pack.windows.Pe), signed (windowsSigning:
//   Authenticode by a certificate and key, or a command of the signer's,
//   HELDER_WINDOWS_SIGN_COMMAND: a cloud HSM's signtool, jsign...), in a
//   zip (<Label>/<name>.exe); "Open with" by `<name>.exe --register`, the
//   program's own (helder.os.FileTypes: the user's registry);
// - linux-x86_64, linux-arm64: a .tar.gz (<name>-<version>/: the program,
//   share/applications/<id>.desktop with the manifest's file types as
//   MimeType, share/icons/hicolor/<n>x<n>/apps/<id>.png from 16 to 512,
//   share/metainfo/<id>.metainfo.xml (AppStream), install.sh: into
//   ~/.local, or PREFIX), and a Flatpak manifest beside it
//   (<id>.flatpak.json: the tarball as its source by its SHA-256, the
//   freedesktop runtime, Wayland with X11 as the fallback, the GPU, the
//   files read; `flatpak-builder --user --install build <id>.flatpak.json`).
//
// Each ends with the package's path and size. Secrets are read from the
// environment (a file's path or its text) and never printed.
class Desktop {
	public static inline var APPLE_TSA = "http://timestamp.apple.com/ts01";
	public static inline var WINDOWS_TSA = "http://timestamp.digicert.com";

	public static function isDesktop(target:String):Bool
		return target == "macos" || target.startsWith("windows-") || target.startsWith("linux-");

	public static function dist(e:Entry, ?out:String):String
		return Entry.clean(out ?? '${e.root}/bin/dist');

	// the package's file name: <name>-<version>-<platform>.<ext>
	public static function fileName(e:Entry, target:String):String {
		var o = App.ios(e.name, e.config);
		var platform = target == "macos" ? "macos-universal" : target;
		var ext = target.startsWith("linux-") ? "tar.gz" : "zip";
		return '${e.name}-${o.versionName}-$platform.$ext';
	}

	@:coroutine public static function pack(e:Entry, target:String, ?out:String):Int {
		var dir = dist(e, out);
		TestCommand.mkdirs(dir);
		var o = App.ios(e.name, e.config);
		var file = '$dir/${fileName(e, target)}';
		try {
			if (target == "macos") {
				var app = Mac.out(e);
				if (!Mac.build(e, app, Release).ok) return 1;
				File.saveBytes(file, Zip.stored(tree(app, Path.withoutDirectory(app))));
			} else if (target.startsWith("windows-")) {
				e.target = target;
				var exe = e.out(target);
				if (!BuildCommand.build(e, exe, Release).ok) return 1;
				var shipped = '${Path.withoutExtension(exe)}.release.exe';
				File.saveBytes(shipped, windowsExe(e, File.getBytes(exe)));
				var signer = windowsSigning();
				var how = "unsigned";
				if (signer != null) {
					how = signer.describe;
					File.saveBytes(shipped, signer.sign(shipped));
				}
				Term.out(Style.status("made", Ok, Style.path(shipped) + Style.dim(Style.sep() + "a GUI program, its icon and version" + Style.sep() + how)));
				File.saveBytes(file, Zip.stored([
					{name: '${o.label}/${e.name}.exe', data: File.getBytes(shipped), align: 1, mode: 0x1ed, deflate: true}
				]));
			} else if (target.startsWith("linux-")) {
				e.target = target;
				var exe = e.out(target);
				if (!BuildCommand.build(e, exe, Release).ok) return 1;
				var tgz = Tar.gz(linuxTree(e, File.getBytes(exe)));
				File.saveBytes(file, tgz);
				var manifest = '$dir/${o.id}.flatpak.json';
				File.saveContent(manifest, flatpak(e, Path.withoutDirectory(file), haxe.crypto.Sha256.make(tgz).toHex()));
				Term.out(Style.status("written", Ok, Style.path(manifest) + Style.dim(Style.sep() + "Flatpak's manifest: flatpak-builder --user --install build " + Path.withoutDirectory(manifest))));
			} else throw '--package: a desktop target (macos, windows-x86_64, linux-x86_64...), not $target';
		} catch (err:Dynamic) {
			Term.err(Style.status("error", Fail, Std.string(err)));
			return 1;
		}
		Term.out(Style.status("packaged", Ok, Style.path(file) + Style.dim(Style.sep() + BuildCommand.size(file))));
		return 0;
	}

	// a directory's files as zip entries under prefix (executables 0755, the rest 0644; deflated)
	public static function tree(dir:String, prefix:String):Array<ZipEntry> {
		var out:Array<ZipEntry> = [];
		function walk(d:String, p:String) {
			var names = FileSystem.readDirectory(d);
			names.sort(Reflect.compare);
			for (n in names) {
				var f = '$d/$n';
				if (FileSystem.isDirectory(f)) walk(f, '$p/$n') else {
					var exec = p.endsWith("/Contents/MacOS") || p.endsWith("Contents/MacOS");
					out.push({name: '$p/$n', data: File.getBytes(f), align: 1, mode: exec ? 0x1ed : 0x1a4, deflate: true});
				}
			}
		}
		walk(dir, prefix);
		return out;
	}

	// ---- Windows

	// the .exe as it ships: GUI, the icon (16 to 256) and the version as resources, the checksum
	public static function windowsExe(e:Entry, exe:Bytes):Bytes {
		var o = App.ios(e.name, e.config);
		var m:Manifest.AppConfig = e.config;
		var resources = [];
		if (m != null && m.icons != null) {
			var icons = new Icons(m, e.root);
			if (icons.has("any") || icons.has("maskable"))
				resources = resources.concat(Pe.Resources.icon([16, 20, 24, 32, 40, 48, 64, 96, 128, 256],
					px -> icons.canvas(["any", "maskable"], px, 1, null, "Windows' icon"), px -> icons.png(["any", "maskable"], px, 1, null, "Windows' icon")));
		}
		var numbers = [for (p in o.versionName.split(".")) Std.parseInt(p) ?? 0];
		while (numbers.length < 3)
			numbers.push(0);
		numbers = numbers.slice(0, 3).concat([Std.parseInt(o.version) ?? 0]);
		var v = numbers.join(".");
		resources.push(Pe.Resources.version(numbers, [
			{key: "CompanyName", value: author(e) ?? o.label},
			{key: "FileDescription", value: m?.description ?? o.label},
			{key: "FileVersion", value: v},
			{key: "InternalName", value: e.name},
			{key: "OriginalFilename", value: '${e.name}.exe'},
			{key: "ProductName", value: o.label},
			{key: "ProductVersion", value: o.versionName}
		]));
		var made = Pe.withResources(Pe.gui(exe), va -> Pe.Resources.section(resources, va));
		return Pe.withChecksum(made);
	}

	// how the .exe is signed: HELDER_WINDOWS_SIGN_COMMAND (the file's path
	// appended: signtool sign /fd sha256 /tr ... with a cloud HSM's
	// certificate, as today's code signing certificates are), else
	// HELDER_WINDOWS_IDENTITY, or HELDER_WINDOWS_CERTIFICATE and
	// HELDER_WINDOWS_KEY (PEM: a file's path or its text; RSA or P-256),
	// Authenticode here (Authenticode.sign), timestamped by
	// HELDER_WINDOWS_TIMESTAMP_URL (DigiCert's by default; "none": not);
	// null: none set, unsigned
	public static function windowsSigning(?env:String->Null<String>):Null<{describe:String, sign:String->Bytes}> {
		env = env ?? Sys.getEnv;
		var cmd = env("HELDER_WINDOWS_SIGN_COMMAND");
		if (cmd != null && cmd.trim() != "") return {
			describe: "signed by HELDER_WINDOWS_SIGN_COMMAND",
			sign: path -> {
				// (the command's own output may be the signer's: not shown, only its code)
				var p = new sys.io.Process(Sys.systemName() == "Windows" ? "cmd" : "sh", Sys.systemName() == "Windows" ? ["/c", cmd + ' "$path"'] : ["-c", cmd + ' "$path"']);
				var code = p.exitCode();
				p.close();
				if (code != 0) throw 'HELDER_WINDOWS_SIGN_COMMAND: exit code $code';
				File.getBytes(path);
			}
		};
		var id = identity(env, "HELDER_WINDOWS");
		if (id == null) return null;
		var url = env("HELDER_WINDOWS_TIMESTAMP_URL");
		var tsa = url == "none" ? null : url == null || url.trim() == "" ? WINDOWS_TSA : url.trim();
		return {
			describe: "signed: " + id.leaf.commonName + (tsa == null ? "" : ", timestamped"),
			sign: path -> Authenticode.sign(File.getBytes(path), id, tsa == null ? null : sig -> timestamp(tsa, sig))
		};
	}

	// ---- macOS

	// `helder publish --notarize`: the macOS release built and signed by a
	// Developer ID identity, submitted to Apple's notary service by
	// notarytool (xcrun: a Mac's) with the App Store Connect API key
	// (HELDER_ASC_*: its .p8 written for notarytool where it is text, removed
	// after), waited for; refused, its log; accepted, the ticket stapled to
	// the .app (stapler) and the zip made again. --dry-run: built, signed,
	// the key checked (notarytool history), nothing submitted
	@:coroutine public static function notarize(e:Entry, ?out:String, dry:Bool):Int {
		if (macSigning() == null)
			throw "notarisation takes a Developer ID identity: HELDER_MACOS_IDENTITY, or HELDER_MACOS_CERTIFICATE and HELDER_MACOS_KEY (a Developer ID Application certificate and its key)";
		var key = Publish.ascKeyText();
		var xcrun = Sys.getEnv("XCRUN") ?? "xcrun";
		if (Sys.systemName() != "Mac" && Sys.getEnv("XCRUN") == null) throw "notarisation is notarytool's: on a Mac (xcrun)";
		if (pack(e, "macos", out) != 0) return 1;
		var zip = '${dist(e, out)}/${fileName(e, "macos")}', app = Mac.out(e);
		var p8 = DevCommand.cache() + '/notary/AuthKey_${key.id}.p8';
		TestCommand.mkdirs(Path.directory(p8));
		File.saveContent(p8, key.pem);
		if (Sys.systemName() != "Windows") Sys.command("chmod", ["600", p8]);
		var auth = ["--key", p8, "--key-id", key.id, "--issuer", key.issuer];
		try {
			if (dry) {
				Term.spin("checking the API key with the notary service");
				var r = Devices.output(xcrun, ["notarytool", "history"].concat(auth).concat(["--output-format", "json"]));
				Term.done();
				if (r.code != 0) throw 'notarytool history: exit code ${r.code} ${r.errors.trim()}';
				Term.out(Style.status("dry run", Info, 'would submit ${Style.path(zip)} (${BuildCommand.size(zip)}) and staple ${Style.path(app)}; the key works'));
			} else {
				Term.spin("notarising " + Path.withoutDirectory(zip) + " (Apple's notary service: minutes)");
				var r = Devices.output(xcrun, ["notarytool", "submit", zip].concat(auth).concat(["--wait", "--output-format", "json"]));
				Term.done();
				var j:Dynamic = try haxe.Json.parse(r.text) catch (_:Dynamic) null;
				var status:String = j?.status ?? "";
				if (status != "Accepted") {
					if (j?.id != null) {
						var log = Devices.output(xcrun, ["notarytool", "log", j.id].concat(auth));
						Term.err(log.text);
					}
					throw 'notarisation: ${status == "" ? 'notarytool: exit code ${r.code} ${r.errors.trim()}' : status} ${j?.message ?? ""}'.trim();
				}
				Term.out(Style.status("notarised", Ok, 'submission ${j.id}: Accepted'));
				var s = Devices.output(xcrun, ["stapler", "staple", app]);
				if (s.code != 0) throw 'stapler staple: exit code ${s.code} ${s.errors.trim()} ${s.text.trim()}';
				File.saveBytes(zip, Zip.stored(tree(app, Path.withoutDirectory(app))));
				Term.out(Style.status("stapled", Ok, Style.path(zip) + Style.dim(Style.sep() + BuildCommand.size(zip))));
			}
		} catch (err:Dynamic) {
			try FileSystem.deleteFile(p8) catch (_:Dynamic) {};
			throw err;
		}
		try FileSystem.deleteFile(p8) catch (_:Dynamic) {};
		return 0;
	}

	// the Developer ID identity: HELDER_MACOS_IDENTITY, or
	// HELDER_MACOS_CERTIFICATE and HELDER_MACOS_KEY (a "Developer ID
	// Application" certificate with its chain, its key; PEM), timestamped by
	// HELDER_MACOS_TIMESTAMP_URL (Apple's by default; "none": not, which
	// notarisation refuses); null: none set, ad hoc
	public static function macSigning(?env:String->Null<String>):Null<MacSigning> {
		env = env ?? Sys.getEnv;
		var id = identity(env, "HELDER_MACOS");
		if (id == null) return null;
		var url = env("HELDER_MACOS_TIMESTAMP_URL");
		var tsa = url == "none" ? null : url == null || url.trim() == "" ? APPLE_TSA : url.trim();
		return {identity: id, timestamp: tsa == null ? null : sig -> timestamp(tsa, sig)};
	}

	// (<prefix>_IDENTITY, else <prefix>_CERTIFICATE and <prefix>_KEY; each a
	// file's path or PEM text; one without the other an error)
	static function identity(env:String->Null<String>, prefix:String):Null<Identity> {
		function given(n:String):Null<String> {
			var v = env(n);
			return v == null || v.trim() == "" ? null : v;
		}
		function text(n:String, v:String):String {
			if (v.indexOf("-----BEGIN") >= 0) return v;
			if (FileSystem.exists(v) && !FileSystem.isDirectory(v)) return File.getContent(v);
			throw '$n: neither a file nor PEM text';
		}
		var both = given('${prefix}_IDENTITY');
		if (both != null) return named('${prefix}_IDENTITY', () -> Identity.fromPem(text('${prefix}_IDENTITY', both), text('${prefix}_IDENTITY', both)));
		var cert = given('${prefix}_CERTIFICATE'), key = given('${prefix}_KEY');
		if (cert == null && key == null) return null;
		if (cert == null || key == null) throw 'signing takes a certificate and its key (${prefix}_IDENTITY: both in one PEM): ${cert == null ? '${prefix}_CERTIFICATE' : '${prefix}_KEY'} not given';
		return named('${prefix}_CERTIFICATE, ${prefix}_KEY', () -> Identity.fromPem(text('${prefix}_CERTIFICATE', cert), text('${prefix}_KEY', key)));
	}

	static function named(name:String, f:Void->Identity):Identity
		return try f() catch (err:String) throw err.startsWith(name.split(",")[0].split("_")[0]) ? err : '$name: $err';

	// an RFC 3161 token for a signature's bytes, from the authority at url (curl)
	public static function timestamp(url:String, signature:Bytes):Bytes {
		var req = helder.pack.Timestamp.request(signature);
		var base = DevCommand.cache() + "/timestamp-" + Std.random(1 << 30);
		TestCommand.mkdirs(Path.directory(base));
		File.saveBytes('$base.tsq', req);
		var p = new sys.io.Process("curl", [
			"-sS", "-f", "--retry", "3", "-H", "Content-Type: application/timestamp-query", "--data-binary", '@$base.tsq', "-o", '$base.tsr', url
		]);
		var code = p.exitCode();
		var errors = try p.stderr.readAll().toString() catch (_:Dynamic) "";
		p.close();
		var reply = code == 0 && FileSystem.exists('$base.tsr') ? File.getBytes('$base.tsr') : null;
		for (f in ['$base.tsq', '$base.tsr'])
			try FileSystem.deleteFile(f) catch (_:Dynamic) {};
		if (reply == null) throw 'the timestamp from $url: curl: exit code $code ${errors.trim()}';
		return helder.pack.Timestamp.token(reply);
	}

	// ---- Linux

	static final ICON_SIZES = [16, 24, 32, 48, 64, 128, 256, 512];

	// the tarball's entries: <name>-<version>/ with the program, share/ and install.sh
	public static function linuxTree(e:Entry, exe:Bytes):Array<TarEntry> {
		var o = App.ios(e.name, e.config);
		var m:Manifest.AppConfig = e.config;
		var top = '${e.name}-${o.versionName}';
		var out:Array<TarEntry> = [{name: top}, {name: '$top/${e.name}', data: exe, mode: 0x1ed}];
		out.push({name: '$top/share'});
		out.push({name: '$top/share/applications'});
		out.push({name: '$top/share/applications/${o.id}.desktop', data: Bytes.ofString(desktopEntry(e, e.name))});
		if (m != null && m.icons != null) {
			var icons = new Icons(m, e.root);
			if (icons.has("any") || icons.has("maskable")) {
				for (d in ["share/icons", "share/icons/hicolor"])
					out.push({name: '$top/$d'});
				for (px in ICON_SIZES) {
					var d = '$top/share/icons/hicolor/${px}x$px';
					out.push({name: d});
					out.push({name: '$d/apps'});
					out.push({name: '$d/apps/${o.id}.png', data: icons.png(["any", "maskable"], px, 1, null, "the Linux icon")});
				}
			}
		}
		out.push({name: '$top/share/metainfo'});
		out.push({name: '$top/share/metainfo/${o.id}.metainfo.xml', data: Bytes.ofString(metainfo(e))});
		out.push({name: '$top/install.sh', data: Bytes.ofString(installScript(e)), mode: 0x1ed});
		return out;
	}

	// the MIME types of the manifest's file handlers
	public static function mimeTypes(e:Entry):Array<String>
		return [for (t in Mac.fileTypes(e.config)) t.mime];

	// the .desktop file (exec: the command, on the PATH)
	public static function desktopEntry(e:Entry, exec:String):String {
		var o = App.ios(e.name, e.config);
		var m:Manifest.AppConfig = e.config;
		var types = mimeTypes(e);
		var lines = [
			"[Desktop Entry]",
			"Type=Application",
			'Name=${o.label}',
			'Comment=${m?.description ?? o.label}',
			'Exec=$exec' + (types.length > 0 ? " %F" : ""),
			'Icon=${o.id}',
			"Terminal=false",
			// (Wayland's app_id and the window's class: the program's name, helder.os's)
			'StartupWMClass=${e.name}',
			"Categories=" + (Lambda.exists(types, t -> t.startsWith("image/")) ? "Graphics;Viewer;2DGraphics;RasterGraphics;" : "Utility;")
		];
		if (types.length > 0) lines.push("MimeType=" + types.join(";") + ";");
		return lines.join("\n") + "\n";
	}

	public static function metainfo(e:Entry):String {
		var o = App.ios(e.name, e.config);
		var m:Manifest.AppConfig = e.config;
		var d = Date.now();
		var date = '${d.getUTCFullYear()}-${StringTools.lpad(Std.string(d.getUTCMonth() + 1), "0", 2)}-${StringTools.lpad(Std.string(d.getUTCDate()), "0", 2)}';
		var summary = escape(m?.description ?? o.label);
		var pkg = packageJson(e);
		var exts = [for (t in Mac.fileTypes(e.config)) for (x in t.extensions) x.toUpperCase()];
		var opens = exts.length == 0 ? "" : '\n    <p>It opens ${exts.join(", ")} files, a folder\'s in order, and stays out of the way.</p>';
		var homepage:Null<String> = pkg?.homepage ?? (pkg?.repository?.url == null ? null : ~/^git\+|\.git$/g.replace(pkg.repository.url, ""));
		var dev = author(e);
		var extra = (homepage == null ? "" : '\n  <url type="homepage">${escape(homepage)}</url>')
			+ (dev == null ? "" : '\n  <developer id="${o.id.substr(0, o.id.lastIndexOf("."))}">\n    <name>${escape(dev)}</name>\n  </developer>');
		return '<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>${o.id}</id>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>${escape(license(e))}</project_license>
  <name>${escape(o.label)}</name>
  <summary>$summary</summary>
  <description>
    <p>${escape(o.label)} is ${summary}, a native program for Linux, Windows and macOS.</p>$opens
  </description>$extra
  <launchable type="desktop-id">${o.id}.desktop</launchable>
  <provides>
    <binary>${e.name}</binary>
${[for (t in mimeTypes(e)) '    <mediatype>$t</mediatype>'].join("\n")}
  </provides>
  <releases>
    <release version="${o.versionName}" date="$date"/>
  </releases>
  <content_rating type="oars-1.1"/>
</component>
';
	}

	// (package.json's author: a name, or {"name"})
	static function author(e:Entry):Null<String> {
		var by:Dynamic = packageJson(e)?.author;
		return by == null ? null : Std.isOfType(by, String) ? by : by.name;
	}

	// (the project's package.json; its licence, else the nearest one's above it, else MIT)
	static function packageJson(e:Entry):Dynamic
		return try haxe.Json.parse(File.getContent('${e.root}/package.json')) catch (_:Dynamic) null;

	static function license(e:Entry):String {
		var d = FileSystem.fullPath(e.root);
		while (d != null && d != "") {
			var f = '$d/package.json';
			if (FileSystem.exists(f)) {
				var l:Dynamic = try haxe.Json.parse(File.getContent(f)).license catch (_:Dynamic) null;
				if (l != null) return l;
			}
			var up = Path.directory(d);
			if (up == d || up == "") break;
			d = up;
		}
		return "MIT";
	}

	static function escape(s:String):String
		return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");

	// install.sh: the program into PREFIX/bin (~/.local by default), share/ beside it, the caches told
	static function installScript(e:Entry):String {
		var o = App.ios(e.name, e.config);
		return '#!/bin/sh
# ${o.label} ${o.versionName}: installed for this user (PREFIX=/usr/local sh install.sh: for everyone)
set -eu
here=$$(cd "$$(dirname "$$0")" && pwd)
prefix=$${PREFIX:-$$HOME/.local}
mkdir -p "$$prefix/bin" "$$prefix/share"
install -m 755 "$$here/${e.name}" "$$prefix/bin/${e.name}"
cp -R "$$here/share/." "$$prefix/share/"
command -v update-desktop-database > /dev/null && update-desktop-database -q "$$prefix/share/applications" || true
command -v gtk-update-icon-cache > /dev/null && gtk-update-icon-cache -q -t "$$prefix/share/icons/hicolor" || true
echo "${o.label} installed: $$prefix/bin/${e.name}"
';
	}

	// the Flatpak manifest: the tarball (beside it) installed into /app
	public static function flatpak(e:Entry, tarball:String, sha256:String):String {
		var o = App.ios(e.name, e.config);
		var top = '${e.name}-${o.versionName}';
		return haxe.Json.stringify({
			"id": o.id,
			"runtime": "org.freedesktop.Platform",
			"runtime-version": "24.08",
			"sdk": "org.freedesktop.Sdk",
			"command": e.name,
			"finish-args": [
				"--share=ipc",
				"--socket=wayland",
				"--socket=fallback-x11",
				"--device=dri",
				// (a folder's images browsed: read access to the files, not only the one given)
				"--filesystem=host:ro",
				"--talk-name=org.freedesktop.FileManager1"
			],
			"modules": [
				{
					"name": e.name,
					"buildsystem": "simple",
					"build-commands": [
						'install -Dm755 ${e.name} /app/bin/${e.name}',
						"cp -R share /app/",
						'desktop-file-edit --set-key=Exec --set-value="${e.name} %F" /app/share/applications/${o.id}.desktop'
					],
					"sources": [{"type": "archive", "path": tarball, "sha256": sha256, "strip-components": 1}]
				}
			]
		}, null, "  ") + "\n";
	}
}

typedef MacSigning = {identity:Identity, timestamp:Null<Bytes->Bytes>};
