package helder.cli;

import haxe.io.Path;
import helder.pack.apple.Fat;
import helder.pack.apple.Icns;
import helder.pack.ios.Plist;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `helder build --target macos`: a macOS app bundle, universal
// (bin/macos/<Label>.app: Contents/Info.plist, MacOS/<name> both arm64's and
// x86-64's slices, each signed ad hoc as hxmc signs them; Resources/
// AppIcon.icns from the manifest's icons): its document types
// (CFBundleDocumentTypes) from helder.webmanifest's file_handlers (the W3C
// manifest's: {"accept": {"image/jpeg": [".jpg", ".jpeg"]}}): Finder's
// "Open With", a document's double click, the Dock's icon (helder.os's
// App.onOpen). Launched with `open bin/macos/<Label>.app`.
class Mac {
	// (a MIME type's uniform type identifier, for LSItemContentTypes)
	static final UTIS = [
		"image/jpeg" => "public.jpeg", "image/png" => "public.png", "image/gif" => "com.compuserve.gif", "image/webp" => "org.webmproject.webp",
		"image/tiff" => "public.tiff", "image/heic" => "public.heic", "image/avif" => "public.avif", "image/bmp" => "com.microsoft.bmp"
	];

	public static function out(e:Entry):String {
		var o = App.ios(e.name, e.config);
		return Entry.clean('${e.root}/bin/macos/${o.label}.app');
	}

	// the file handlers' types: each MIME type and its extensions
	public static function fileTypes(config:Dynamic):Array<{mime:String, extensions:Array<String>}> {
		var out = [];
		var handlers:Array<Dynamic> = config?.file_handlers ?? [];
		for (h in handlers) {
			var accept:haxe.DynamicAccess<Array<String>> = h.accept;
			if (accept == null) continue;
			for (mime => exts in accept)
				out.push({mime: mime, extensions: [for (x in exts) x.startsWith(".") ? x.substr(1) : x]});
		}
		return out;
	}

	public static function infoPlist(exe:String, id:String, label:String, version:String, versionName:String, types:Array<{mime:String, extensions:Array<String>}>,
			icon:Bool):haxe.io.Bytes {
		var keys = [
			"CFBundleDevelopmentRegion" => PString("en"),
			"CFBundleDisplayName" => PString(label),
			"CFBundleExecutable" => PString(exe),
			"CFBundleIdentifier" => PString(id),
			"CFBundleInfoDictionaryVersion" => PString("6.0"),
			"CFBundleName" => PString(label),
			"CFBundlePackageType" => PString("APPL"),
			"CFBundleShortVersionString" => PString(versionName),
			"CFBundleVersion" => PString(version),
			"LSMinimumSystemVersion" => PString("11.0"),
			"NSHighResolutionCapable" => PBool(true),
			"NSPrincipalClass" => PString("NSApplication")
		];
		if (icon) keys.set("CFBundleIconFile", PString("AppIcon"));
		if (types.length > 0) keys.set("CFBundleDocumentTypes", PArray([
			PDict([
				"CFBundleTypeName" => PString(label + " document"),
				"CFBundleTypeRole" => PString("Viewer"),
				"LSHandlerRank" => PString("Alternate"),
				"LSItemContentTypes" => PArray([for (t in types) PString(UTIS.exists(t.mime) ? UTIS.get(t.mime) : t.mime)]),
				"CFBundleTypeExtensions" => PArray([for (t in types) for (x in t.extensions) PString(x)])
			])
		]));
		return Plist.xml(PDict(keys));
	}

	// both slices built, joined, the bundle written around them
	@:coroutine public static function build(e:Entry, out:String, mode:BuildCommand.Mode):{ok:Bool, ms:Int, messages:String} {
		if (!out.endsWith(".app")) throw '$out: a macOS app is a .app';
		var o = App.ios(e.name, e.config);
		var t0 = haxe.Timer.stamp(), slices = [], messages = "";
		for (target in ["macos-arm64", "macos-x86_64"]) {
			e.target = target;
			var exe = Entry.clean('${e.root}/bin/$target/${e.name}');
			var r = BuildCommand.build(e, exe, mode);
			messages += r.messages;
			if (!r.ok) return {ok: false, ms: Math.round((haxe.Timer.stamp() - t0) * 1000), messages: messages};
			slices.push(File.getBytes(exe));
		}
		e.target = "macos";
		if (FileSystem.exists(out)) TestCommand.rmrf(out);
		TestCommand.mkdirs('$out/Contents/MacOS');
		TestCommand.mkdirs('$out/Contents/Resources');
		var exe = '$out/Contents/MacOS/${e.name}';
		File.saveBytes(exe, Fat.make(slices));
		if (Sys.systemName() != "Windows") Sys.command("chmod", ["+x", exe]);
		var m:Manifest.AppConfig = e.config, icon = false;
		if (m != null && m.icons != null) {
			var icons = new Icons(m, e.root);
			if (icons.has("any") || icons.has("maskable")) {
				File.saveBytes('$out/Contents/Resources/AppIcon.icns', Icns.write(px -> icons.ios(px)));
				icon = true;
			}
		}
		File.saveBytes('$out/Contents/Info.plist', infoPlist(e.name, o.id, o.label, o.version, o.versionName, fileTypes(e.config), icon));
		var ms = Math.round((haxe.Timer.stamp() - t0) * 1000);
		Term.out(Style.status("bundled", Ok, Style.path(out) + Style.dim(Style.sep() + "arm64, x86_64")));
		return {ok: true, ms: ms, messages: messages};
	}
}
