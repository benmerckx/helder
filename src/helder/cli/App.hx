package helder.cli;

import helder.pack.android.Apk;
import helder.pack.ios.Bundle;

using StringTools;

// An app's identity on Android and iOS, from package.json's "helder" key
// (Entry.config), every field optional:
//
//   "helder": {
//     "id": "org.example.game",       the application id and bundle id (org.helder.<name>)
//     "label": "Game",                the launcher's and the home screen's (the name)
//     "version": 3,                   versionCode, CFBundleVersion (1)
//     "versionName": "1.2",           versionName, CFBundleShortVersionString (1.0)
//     "android": {"permissions": ["INTERNET"], "minSdk": 29, "targetSdk": 35, "key": "<file>"},
//     "ios": {"minVersion": "15.0", "entitlements": "<file>"}
//   }
//
// (permissions: android.permission.<name> unless it has a dot; minSdk 29 is
// the floor, Bionic's ELF TLS; key: the debug key's file, DebugKey;
// minVersion: 15.0 the floor, hxmc's; entitlements: an XML plist signed
// with the executable.) Pure: an error is a thrown message.
class App {
	// the Android manifest's options; dev: helder dev's host, which asks for
	// INTERNET (its socket to the dev server, through adb reverse)
	public static function android(name:String, config:Dynamic, dev = false):ApkOptions {
		var a:Dynamic = config?.android;
		var id = field(config, "id") ?? "org.helder." + androidName(name);
		if (!Apk.validId(id)) throw 'package.json\'s "helder": {"id": "$id"} is not an application id (a.b.c: letters, digits, _; each part starting with a letter)';
		var permissions:Array<String> = a?.permissions == null ? [] : [for (p in (a.permissions : Array<Dynamic>)) Std.string(p).trim()];
		if (dev && !permissions.contains("INTERNET") && !permissions.contains("android.permission.INTERNET")) permissions.push("INTERNET");
		var minSdk = int(a?.minSdk, 29, "android.minSdk"), targetSdk = int(a?.targetSdk, 35, "android.targetSdk");
		if (minSdk < 29) throw 'package.json\'s "helder": {"android": {"minSdk": $minSdk}}: 29 is the lowest (Android 10: Bionic\'s ELF TLS)';
		return {
			id: id,
			label: field(config, "label") ?? name,
			versionCode: int(config?.version, 1, "version"),
			versionName: field(config, "versionName") ?? "1.0",
			minSdk: minSdk,
			targetSdk: targetSdk,
			permissions: permissions,
		};
	}

	// the iOS bundle's: its id, label, versions, minimum version, entitlements' file (null: none)
	public static function ios(name:String, config:Dynamic):IosOptions {
		var i:Dynamic = config?.ios;
		var id = field(config, "id") ?? "org.helder." + ~/[^a-zA-Z0-9-]/g.replace(name, "-");
		if (!Bundle.validId(id)) throw 'package.json\'s "helder": {"id": "$id"} is not a bundle id (a.b.c: letters, digits, -)';
		var min = i?.minVersion == null ? "15.0" : Std.string(i.minVersion);
		if (!~/^[0-9]+\.[0-9]+$/.match(min)) throw 'package.json\'s "helder": {"ios": {"minVersion": "$min"}}: a version, major.minor (15.0)';
		return {
			id: id,
			label: field(config, "label") ?? name,
			version: Std.string(int(config?.version, 1, "version")),
			versionName: field(config, "versionName") ?? "1.0",
			minVersion: min,
			entitlements: i?.entitlements == null ? null : Std.string(i.entitlements),
		};
	}

	// the debug key's file: HELDER_ANDROID_KEY, else package.json's
	// "android": {"key"} (from the project's directory), else in helder's cache
	public static function androidKey(config:Dynamic, root:String, cache:String, env:Null<String>):String {
		if (env != null && env != "") return env;
		var k:Dynamic = config?.android?.key;
		if (k != null) return haxe.io.Path.isAbsolute(Std.string(k)) || root == "." ? Std.string(k) : '$root/$k';
		return '$cache/android/debug-key';
	}

	// a name as an id's last part: lower case, letters, digits and _, starting with a letter
	static function androidName(name:String):String {
		var n = ~/[^a-z0-9_]/g.replace(name.toLowerCase(), "_");
		return ~/^[a-z]/.match(n) ? n : "app_" + n;
	}

	static function field(config:Dynamic, key:String):Null<String> {
		var v:Dynamic = config == null ? null : Reflect.field(config, key);
		return v == null ? null : Std.string(v);
	}

	static function int(v:Dynamic, def:Int, what:String):Int {
		if (v == null) return def;
		var n = Std.parseInt(Std.string(v));
		if (n == null || n < 1) throw 'package.json\'s "helder": $what: a whole number from 1, not $v';
		return n;
	}
}

typedef IosOptions = {
	id:String,
	label:String,
	version:String,
	versionName:String,
	minVersion:String,
	entitlements:Null<String>,
}
