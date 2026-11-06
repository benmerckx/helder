package helder.cli;

import helder.pack.android.Apk;
import helder.pack.ios.Bundle;

using StringTools;

// The app's manifest: helder.webmanifest at the project's root, a W3C Web
// App Manifest (https://www.w3.org/TR/appmanifest/) that a browser reads as
// it is, with the native apps' settings in its "helder" member (a browser
// ignores members it does not know):
//
//   {
//     "name": "Expansion",                 the app's name; short_name: the launcher's label when given
//     "short_name": "Expansion",
//     "description": "...", "lang": "en", "dir": "ltr", "categories": ["games"],
//     "start_url": ".", "id": ".",          the web's (copied as they are)
//     "display": "fullscreen",             fullscreen: the system's bars hidden (Window.immersive, UIStatusBarHidden); standalone, minimal-ui, browser: not
//     "orientation": "landscape",          any, natural, portrait(-primary, -secondary), landscape(-primary, -secondary)
//     "theme_color": "#060912",            the browser's and the system bars' colour
//     "background_color": "#060912",       the splash screen's and the page's background, an adaptive icon's background
//     "icons": [{"src": "icon.svg", "sizes": "any", "type": "image/svg+xml", "purpose": "any"},
//               {"src": "icon-maskable.png", "sizes": "1024x1024", "purpose": "maskable"}],
//     "screenshots": [...],
//     "helder": {
//       "version": "1.2", "build": 3,      versionName and versionCode, CFBundleShortVersionString and CFBundleVersion (1.0, 1)
//       "id": "org.example.game",          both platforms' id (else org.helder.<name>)
//       "android": {"package": "org.example.game", "minSdk": 29, "targetSdk": 36, "permissions": ["VIBRATE"], "key": "<file>",
//                   "signing": {"certificate": "<pem>", "key": "<pem>"}},
//       "ios": {"bundleId": "org.example.game", "minVersion": "15.0", "entitlements": "<file>",
//               "signing": {"certificate": "<pem>", "key": "<pem>", "profile": "<.mobileprovision>"},
//               "sdk": {"version": "26.0", "build": "23A339", "xcode": "2600", "xcodeBuild": "17A324", "machine": "25A354"},
//               "nonExemptEncryption": false,
//               "privacy": {"NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"]}},
//       "splash": {"background_color": "#060912", "image": "splash.png",
//                  "dark": {"background_color": "#000000", "image": "splash-dark.png"}}
//     }
//   }
//
// Its icons are the sources of every icon a target needs (Icons: PNGs and
// SVGs, scaled at build time). Read into the shape App takes (package.json's
// "helder" key's, the fallback: a project without a manifest; with one, the
// manifest wins), its mistakes thrown as messages naming the member. Pure
// (parse), but load, which reads the file.
class Manifest {
	public static inline var FILE = "helder.webmanifest";

	static final DISPLAY = ["fullscreen", "standalone", "minimal-ui", "browser"];
	static final ORIENTATION = [
		"any", "natural", "portrait", "portrait-primary", "portrait-secondary", "landscape", "landscape-primary", "landscape-secondary"
	];
	static final PURPOSE = ["any", "maskable", "monochrome"];
	static final HELDER = ["version", "build", "id", "android", "ios", "splash"];
	static final ANDROID = ["package", "minSdk", "targetSdk", "permissions", "key", "signing", "serviceAccount"];
	static final IOS = ["bundleId", "minVersion", "entitlements", "signing", "sdk", "nonExemptEncryption", "privacy"];
	static final SIGNING = ["certificate", "key", "profile"];
	public static final SDK = ["version", "build", "xcode", "xcodeBuild", "machine"];
	static final SPLASH = ["background_color", "image", "dark"];
	// package.json's "helder" members that are the app's identity (the others, main, name, defines: the build's)
	public static final LEGACY = ["id", "label", "version", "versionName", "orientation", "fullscreen", "android", "ios"];

	// the manifest's file in a project's directory, null: none
	public static function find(root:String):Null<String> {
		var f = root == "." ? FILE : '$root/$FILE';
		return sys.FileSystem.exists(f) ? f : null;
	}

	// the file read and parsed (its icons' paths from the project's directory)
	public static function load(file:String):AppConfig {
		var text = try sys.io.File.getContent(file) catch (e:Dynamic) throw '$file: $e';
		return parse(text, FILE);
	}

	// whether package.json's "helder" key holds the app's identity (the deprecated place)
	public static function legacy(h:Dynamic):Bool
		return h != null && Lambda.exists(LEGACY, k -> Reflect.hasField(h, k));

	static var warned = false;

	// the deprecation's warning, once a run, for an app of package.json's "helder" key
	public static function warn(e:Entry) {
		if (!e.deprecated || warned) return;
		warned = true;
		Term.err(Style.status("warning", Warn, DEPRECATED));
	}

	public static final DEPRECATED = 'package.json\'s "helder" key for the app\'s identity is deprecated: move it to $FILE (a web app manifest; see helder\'s README)';

	// the manifest's text as App's config (where: its name in the messages)
	public static function parse(text:String, where = FILE):AppConfig {
		var j:Dynamic = try haxe.Json.parse(text) catch (e:Dynamic) throw '$where: not JSON ($e)';
		if (!isObject(j)) throw '$where: not a JSON object';
		function str(o:Dynamic, k:String, path:String):Null<String> {
			var v:Dynamic = Reflect.field(o, k);
			if (v == null) return null;
			if (!Std.isOfType(v, String)) throw '$where: $path: a string, not ${haxe.Json.stringify(v)}';
			return v;
		}
		function color(o:Dynamic, k:String, path:String):Null<Int> {
			var s = str(o, k, path);
			if (s == null) return null;
			var c = helder.canvas.CssColor.parse(s.trim().toLowerCase());
			if (c == null || ((c : Int) >>> 24) == 0 && (c : Int) != 0) throw '$where: $path: "$s" is not a CSS colour (#rrggbb, rgb(), a name)';
			return c;
		}
		function known(o:Dynamic, keys:Array<String>, path:String) {
			if (!isObject(o)) throw '$where: $path: an object';
			for (k in Reflect.fields(o)) if (!keys.contains(k)) throw '$where: $path: no member "$k" (${keys.join(", ")})';
		}
		var display = str(j, "display", "display");
		if (display != null && !DISPLAY.contains(display)) throw '$where: display: "$display": ${DISPLAY.join(", ")}';
		var o = str(j, "orientation", "orientation");
		if (o != null && !ORIENTATION.contains(o)) throw '$where: orientation: "$o": ${ORIENTATION.join(", ")}';
		var icons = images(j.icons, "icons", where);
		if (j.screenshots != null) images(j.screenshots, "screenshots", where);
		var h:Dynamic = j.helder ?? {};
		known(h, HELDER, '"helder"');
		var a:Dynamic = h.android ?? {}, i:Dynamic = h.ios ?? {};
		known(a, ANDROID, '"helder": {"android"}');
		known(i, IOS, '"helder": {"ios"}');
		var id = str(h, "id", '"helder": {"id"}');
		var pkg = str(a, "package", '"helder": {"android": {"package"}}') ?? id;
		if (pkg != null && !Apk.validId(pkg)) throw '$where: "helder": {"android": {"package": "$pkg"}} is not an application id (a.b.c: letters, digits, _; each part starting with a letter)';
		var bundle = str(i, "bundleId", '"helder": {"ios": {"bundleId"}}') ?? id;
		if (bundle != null && !Bundle.validId(bundle)) throw '$where: "helder": {"ios": {"bundleId": "$bundle"}} is not a bundle id (a.b.c: letters, digits, -)';
		var build:Dynamic = h.build;
		if (build != null && !(Std.isOfType(build, Int) && (build : Int) >= 1)) throw '$where: "helder": {"build"}: a whole number from 1, not ${haxe.Json.stringify(build)}';
		var minSdk:Dynamic = a.minSdk, targetSdk:Dynamic = a.targetSdk;
		for (n => v in ["minSdk" => minSdk, "targetSdk" => targetSdk])
			if (v != null && !Std.isOfType(v, Int)) throw '$where: "helder": {"android": {"$n"}}: a whole number, not ${haxe.Json.stringify(v)}';
		if (minSdk != null && (minSdk : Int) < 29) throw '$where: "helder": {"android": {"minSdk": $minSdk}}: 29 is the lowest (Android 10: Bionic\'s ELF TLS)';
		if (a.permissions != null && !(Std.isOfType(a.permissions, Array) && Lambda.foreach((a.permissions : Array<Dynamic>), p -> Std.isOfType(p, String))))
			throw '$where: "helder": {"android": {"permissions"}}: an array of strings';
		var min = str(i, "minVersion", '"helder": {"ios": {"minVersion"}}');
		if (min != null && !~/^[0-9]+\.[0-9]+$/.match(min)) throw '$where: "helder": {"ios": {"minVersion": "$min"}}: a version, major.minor (15.0)';
		var signing:Dynamic = i.signing, sdk:Dynamic = i.sdk, privacy:Dynamic = i.privacy, release:Dynamic = a.signing;
		if (release != null) {
			known(release, ["certificate", "key"], '"helder": {"android": {"signing"}}');
			for (k in ["certificate", "key"]) str(release, k, '"helder": {"android": {"signing": {"$k"}}}');
		}
		for (o in [{v: signing, keys: SIGNING, name: "signing"}, {v: sdk, keys: SDK, name: "sdk"}])
			if (o.v != null) {
				known(o.v, o.keys, '"helder": {"ios": {"${o.name}"}}');
				for (k in o.keys) str(o.v, k, '"helder": {"ios": {"${o.name}": {"$k"}}}');
			}
		if (sdk?.version != null && !~/^[0-9]+\.[0-9]+(\.[0-9]+)?$/.match(sdk.version))
			throw '$where: "helder": {"ios": {"sdk": {"version": "${sdk.version}"}}}: a version (26.0)';
		var encryption:Dynamic = i.nonExemptEncryption;
		if (encryption != null && encryption != true && encryption != false) throw '$where: "helder": {"ios": {"nonExemptEncryption"}}: true or false';
		if (privacy != null) {
			known(privacy, Reflect.fields(privacy), '"helder": {"ios": {"privacy"}}');
			for (k in Reflect.fields(privacy)) {
				var v:Dynamic = Reflect.field(privacy, k);
				if (!(Std.isOfType(v, Array) && Lambda.foreach((v : Array<Dynamic>), r -> Std.isOfType(r, String))))
					throw '$where: "helder": {"ios": {"privacy": {"$k"}}}: an array of reasons (strings: "CA92.1")';
			}
		}
		var s:Dynamic = h.splash ?? {};
		known(s, SPLASH, '"helder": {"splash"}');
		var d:Dynamic = s.dark ?? {};
		known(d, ["background_color", "image"], '"helder": {"splash": {"dark"}}');
		var background = color(j, "background_color", "background_color");
		var splash:Splash = {
			background: color(s, "background_color", '"helder": {"splash": {"background_color"}}') ?? background,
			image: str(s, "image", '"helder": {"splash": {"image"}}'),
			darkBackground: color(d, "background_color", '"helder": {"splash": {"dark": {"background_color"}}}'),
			darkImage: str(d, "image", '"helder": {"splash": {"dark": {"image"}}}'),
		};
		var handlers:Dynamic = j.file_handlers;
		if (handlers != null) {
			if (!Std.isOfType(handlers, Array)) throw '$where: file_handlers: an array';
			for (k in 0...(handlers : Array<Dynamic>).length) {
				var fh:Dynamic = handlers[k];
				known(fh, ["action", "accept", "name", "icons", "launch_type"], 'file_handlers[$k]');
				if (!isObject(fh.accept)) throw '$where: file_handlers[$k]: accept: an object of MIME types and their extensions';
				for (mime in Reflect.fields(fh.accept)) {
					var exts:Dynamic = Reflect.field(fh.accept, mime);
					if (!(Std.isOfType(exts, Array) && Lambda.foreach((exts : Array<Dynamic>), x -> Std.isOfType(x, String) && (x : String).startsWith("."))))
						throw '$where: file_handlers[$k]: accept: "$mime": an array of extensions (".jpg")';
				}
			}
		}
		var name = str(j, "name", "name"), short = str(j, "short_name", "short_name");
		return {
			source: where,
			name: name,
			label: short ?? name,
			description: str(j, "description", "description"),
			version: build,
			versionName: str(h, "version", '"helder": {"version"}'),
			orientation: o == null || o == "natural" ? null : o.startsWith("portrait") ? "portrait" : o.startsWith("landscape") ? "landscape" : "any",
			fullscreen: display == "fullscreen",
			theme: color(j, "theme_color", "theme_color"),
			background: background,
			icons: icons,
			splash: splash,
			file_handlers: handlers,
			android: {
				id: pkg,
				permissions: a.permissions,
				minSdk: minSdk,
				targetSdk: targetSdk,
				key: str(a, "key", '"helder": {"android": {"key"}}'),
				signing: release,
				serviceAccount: str(a, "serviceAccount", '"helder": {"android": {"serviceAccount"}}')
			},
			ios: {
				id: bundle,
				minVersion: min,
				entitlements: str(i, "entitlements", '"helder": {"ios": {"entitlements"}}'),
				signing: signing,
				sdk: sdk,
				nonExemptEncryption: encryption,
				privacy: privacy
			},
		};
	}

	// icons or screenshots: each a src, its sizes ("any" or WxH ...), type, purpose
	static function images(v:Dynamic, what:String, where:String):Array<IconSpec> {
		if (v == null) return [];
		if (!Std.isOfType(v, Array)) throw '$where: $what: an array of images';
		var out:Array<IconSpec> = [];
		for (k => e in (v : Array<Dynamic>)) {
			var at = '$what[$k]';
			if (!isObject(e) || !Std.isOfType(e.src, String) || (e.src : String).trim() == "") throw '$where: $at: an object with a src';
			for (f in ["sizes", "type", "purpose"]) if (Reflect.field(e, f) != null && !Std.isOfType(Reflect.field(e, f), String))
				throw '$where: $at.$f: a string';
			var sizes:Null<Array<Int>> = null;
			if (e.sizes != null) {
				sizes = [];
				for (t in ~/\s+/g.split((e.sizes : String).trim())) {
					if (t.toLowerCase() == "any") continue;
					var m = ~/^([0-9]+)[xX]([0-9]+)$/;
					if (!m.match(t) || Std.parseInt(m.matched(1)) == 0) throw '$where: $at.sizes: "$t" is not a size (512x512, or any)';
					if (what == "icons" && m.matched(1) != m.matched(2)) throw '$where: $at.sizes: $t: an icon is square';
					sizes.push(Std.parseInt(m.matched(1)));
				}
				if (sizes.length == 0) sizes = null;
			}
			var purpose = e.purpose == null ? ["any"] : ~/\s+/g.split((e.purpose : String).trim().toLowerCase());
			for (p in purpose) if (!PURPOSE.contains(p)) throw '$where: $at.purpose: "$p": any, maskable or monochrome';
			out.push({src: e.src, sizes: sizes, type: e.type, purpose: purpose});
		}
		return out;
	}

	static function isObject(v:Dynamic):Bool
		return v != null && Reflect.isObject(v) && !Std.isOfType(v, String) && !Std.isOfType(v, Array);

	// the files the manifest names (its icons', screenshots', the splash's), relative to it
	public static function files(text:String):Array<String> {
		var j:Dynamic = haxe.Json.parse(text), out = [];
		for (list in [j.icons, j.screenshots]) if (list != null) for (e in (list : Array<Dynamic>)) out.push(e.src);
		var s:Dynamic = j.helder?.splash;
		if (s?.image != null) out.push(s.image);
		if (s?.dark?.image != null) out.push(s.dark.image);
		return [for (f in out) if (local(f)) f];
	}

	// a src that is a file beside the manifest (not a URL, not above it)
	public static function local(src:String):Bool
		return !~/^[a-z][a-z0-9+.-]*:/i.match(src) && !src.startsWith("/") && !src.split("/").contains("..");
}

// the app's settings: App's config (package.json's "helder" key's shape, with the manifest's own)
typedef AppConfig = {
	?source:String,
	?name:String,
	?label:String,
	?description:String,
	?id:String,
	?version:Dynamic,
	?versionName:String,
	?orientation:String,
	?fullscreen:Bool,
	// 0xAARRGGBB
	?theme:Null<Int>,
	?background:Null<Int>,
	?icons:Array<IconSpec>,
	?splash:Splash,
	// the W3C manifest's file_handlers: the types the app opens (a macOS
	// bundle's CFBundleDocumentTypes; FileTypes.register's elsewhere)
	?file_handlers:Array<{?action:String, accept:haxe.DynamicAccess<Array<String>>}>,
	?android:Dynamic,
	?ios:Dynamic,
}

typedef IconSpec = {
	src:String,
	// the square sizes it says it has (null: any, a vector)
	sizes:Null<Array<Int>>,
	?type:String,
	purpose:Array<String>,
}

typedef Splash = {
	background:Null<Int>,
	image:Null<String>,
	darkBackground:Null<Int>,
	darkImage:Null<String>,
}
