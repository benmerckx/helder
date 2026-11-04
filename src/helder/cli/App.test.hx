package helder.cli;

import haxe.io.Bytes;
import helder.image.PngDecoder;
import helder.image.PngEncoder;
import helder.pack.android.Arsc;
import helder.pack.ios.Plist;
import helder.test.Test;

// An app's identity from package.json's "helder" key (App): the defaults,
// the overrides, the mistakes; the debug key's file. The manifest
// (Manifest: helder.webmanifest) parsed into the same, its mistakes; the
// icons made from its sources (Icons, PngEncoder) and Android's resource
// table of them (Arsc)
function tests() {
	test("Android: the defaults from the name", () -> {
		equals(App.android("Hello", null), {
			id: "org.helder.hello",
			label: "Hello",
			versionCode: 1,
			versionName: "1.0",
			minSdk: 29,
			targetSdk: 35,
			permissions: [],
			orientation: "any"
		});
		equals(App.android("my-game", null).id, "org.helder.my_game");
		equals(App.android("3d", null).id, "org.helder.app_3d");
		// (helder dev's host: its socket)
		equals(App.android("Hello", null, true).permissions, ["INTERNET"]);
		equals(App.android("Hello", {android: {permissions: ["INTERNET"]}}, true).permissions, ["INTERNET"]);
	});
	test("Android: package.json's", () -> {
		var o = App.android("Hello", {
			id: "org.example.game",
			label: "Game",
			version: 7,
			versionName: "2.1",
			android: {permissions: ["VIBRATE", "com.example.X"], minSdk: 31, targetSdk: 34}
		});
		equals(o, {
			id: "org.example.game",
			label: "Game",
			versionCode: 7,
			versionName: "2.1",
			minSdk: 31,
			targetSdk: 34,
			permissions: ["VIBRATE", "com.example.X"],
			orientation: "any"
		});
	});
	test("Android: mistakes", () -> {
		equals(Std.string(throws(() -> App.android("x", {id: "game"}))),
			"package.json's \"helder\": {\"id\": \"game\"} is not an application id (a.b.c: letters, digits, _; each part starting with a letter)");
		equals(Std.string(throws(() -> App.android("x", {android: {minSdk: 26}}))),
			"package.json's \"helder\": {\"android\": {\"minSdk\": 26}}: 29 is the lowest (Android 10: Bionic's ELF TLS)");
		equals(Std.string(throws(() -> App.android("x", {version: "two"}))), "package.json's \"helder\": version: a whole number from 1, not two");
	});
	test("iOS: the defaults and package.json's", () -> {
		equals(App.ios("Hello", null), {
			id: "org.helder.Hello",
			label: "Hello",
			version: "1",
			versionName: "1.0",
			minVersion: "15.0",
			entitlements: null,
			signing: null,
			sdk: null,
			nonExemptEncryption: null,
			privacy: null,
			orientation: "any",
			fullscreen: false
		});
		equals(App.ios("my_game", null).id, "org.helder.my-game");
		var o = App.ios("Hello", {id: "org.example.game", version: 4, ios: {minVersion: "16.4", entitlements: "app.entitlements"}});
		equals([o.id, o.version, o.minVersion, o.entitlements], ["org.example.game", "4", "16.4", "app.entitlements"]);
		equals(Std.string(throws(() -> App.ios("x", {ios: {minVersion: "16"}}))), "package.json's \"helder\": {\"ios\": {\"minVersion\": \"16\"}}: a version, major.minor (15.0)");
		equals(Std.string(throws(() -> App.ios("x", {id: "org.example.a_b"}))), "package.json's \"helder\": {\"id\": \"org.example.a_b\"} is not a bundle id (a.b.c: letters, digits, -)");
	});
	test("the orientation and fullscreen: both platforms', the build's define", () -> {
		equals(App.android("x", {orientation: "portrait"}).orientation, "portrait");
		var o = App.ios("x", {orientation: "landscape", fullscreen: true});
		equals([o.orientation, Std.string(o.fullscreen)], ["landscape", "true"]);
		equals(App.defines({fullscreen: true}), ["-D", "helder.fullscreen"]);
		equals(App.defines({fullscreen: false}), []);
		equals(App.defines(null), []);
		equals(Std.string(throws(() -> App.android("x", {orientation: "sideways"}))),
			"package.json's \"helder\": {\"orientation\": \"sideways\"}: portrait, landscape or any");
		equals(Std.string(throws(() -> App.ios("x", {fullscreen: "yes"}))), "package.json's \"helder\": {\"fullscreen\": yes}: true or false");
	});
	test("the debug key's file: HELDER_ANDROID_KEY, package.json's, the cache", () -> {
		equals(App.androidKey(null, "app", "/c/helder", null), "/c/helder/android/debug-key");
		equals(App.androidKey({android: {key: "keys/debug"}}, "app", "/c/helder", null), "app/keys/debug");
		equals(App.androidKey({android: {key: "keys/debug"}}, ".", "/c/helder", null), "keys/debug");
		equals(App.androidKey({android: {key: "/k"}}, "app", "/c/helder", null), "/k");
		equals(App.androidKey({android: {key: "keys/debug"}}, "app", "/c/helder", "/env/key"), "/env/key");
	});
	test("the manifest: the web's members and helder's", () -> {
		var m = Manifest.parse(haxe.Json.stringify({
			name: "Expansion Game",
			short_name: "Expansion",
			display: "fullscreen",
			orientation: "landscape-primary",
			theme_color: "#3ED6C3",
			background_color: "#060912",
			icons: ([
				{src: "icon.svg", sizes: "any", type: "image/svg+xml"},
				{src: "maskable.png", sizes: "512x512 1024x1024", purpose: "maskable monochrome"}
			] : Array<Dynamic>),
			helder: {
				version: "1.2",
				build: 7,
				id: "org.example.game",
				android: {minSdk: 31, permissions: ["VIBRATE"]},
				ios: {bundleId: "org.example.game-ios", minVersion: "16.0"},
				splash: {image: "splash.png", dark: {background_color: "black"}}
			}
		}));
		var a = App.android("x", m), i = App.ios("x", m);
		equals(a, {
			id: "org.example.game",
			label: "Expansion",
			versionCode: 7,
			versionName: "1.2",
			minSdk: 31,
			targetSdk: 35,
			permissions: ["VIBRATE"],
			orientation: "landscape"
		});
		equals([i.id, i.label, i.version, i.versionName, i.minVersion, i.orientation, Std.string(i.fullscreen)],
			["org.example.game-ios", "Expansion", "7", "1.2", "16.0", "landscape", "true"]);
		var signed = App.ios("x", Manifest.parse(haxe.Json.stringify({
			helder: {
				ios: {
					signing: {certificate: "dist.pem", key: "dist.key", profile: "app.mobileprovision"},
					sdk: {version: "26.1", xcode: "2610"},
					nonExemptEncryption: false,
					privacy: {NSPrivacyAccessedAPICategoryUserDefaults: ["CA92.1"]}
				}
			}
		})));
		equals([signed.signing.certificate, signed.signing.key, signed.signing.profile], ["dist.pem", "dist.key", "app.mobileprovision"]);
		equals([signed.sdk.version, signed.sdk.xcode], ["26.1", "2610"]);
		equals(signed.nonExemptEncryption, false);
		equals(Reflect.field(signed.privacy, "NSPrivacyAccessedAPICategoryUserDefaults"), ["CA92.1"]);
		equals(App.defines(m), ["-D", "helder.fullscreen"]);
		equals([m.theme, m.background, m.splash.background, m.splash.darkBackground], [0xFF3ED6C3, 0xFF060912, 0xFF060912, 0xFF000000]);
		equals(m.icons[1].sizes, [512, 1024]);
		equals(m.icons[1].purpose, ["maskable", "monochrome"]);
		equals(m.icons[0].purpose, ["any"]);
		// (the web's alone: the defaults; natural is any)
		var w = Manifest.parse('{"name": "Hello", "orientation": "natural", "display": "standalone"}');
		equals(App.android("hello", w), {
			id: "org.helder.hello",
			label: "Hello",
			versionCode: 1,
			versionName: "1.0",
			minSdk: 29,
			targetSdk: 35,
			permissions: [],
			orientation: "any"
		});
		equals(App.defines(w), []);
		equals(Manifest.files(haxe.Json.stringify({icons: [{src: "a.png"}, {src: "https://x/b.png"}, {src: "../c.png"}], helder: {splash: {image: "s.png"}}})),
			["a.png", "s.png"]);
	});
	test("the manifest: mistakes", () -> {
		function error(json:Dynamic):String
			return Std.string(throws(() -> Manifest.parse(Std.isOfType(json, String) ? json : haxe.Json.stringify(json))));
		equals(error("{"), "helder.webmanifest: not JSON (" + Std.string(throws(() -> haxe.Json.parse("{"))) + ")");
		equals(error("[]"), "helder.webmanifest: not a JSON object");
		equals(error({display: "kiosk"}), "helder.webmanifest: display: \"kiosk\": fullscreen, standalone, minimal-ui, browser");
		equals(error({orientation: "up"}).split(":")[1], " orientation");
		equals(error({theme_color: "teal-ish"}), "helder.webmanifest: theme_color: \"teal-ish\" is not a CSS colour (#rrggbb, rgb(), a name)");
		equals(error({name: 3}), "helder.webmanifest: name: a string, not 3");
		equals(error({icons: [{sizes: "48x48"}]}), "helder.webmanifest: icons[0]: an object with a src");
		equals(error({icons: [{src: "a.png", sizes: "48"}]}), "helder.webmanifest: icons[0].sizes: \"48\" is not a size (512x512, or any)");
		equals(error({icons: [{src: "a.png", sizes: "48x32"}]}), "helder.webmanifest: icons[0].sizes: 48x32: an icon is square");
		equals(error({icons: [{src: "a.png", purpose: "round"}]}), "helder.webmanifest: icons[0].purpose: \"round\": any, maskable or monochrome");
		equals(error({helder: {versoin: "1"}}), "helder.webmanifest: \"helder\": no member \"versoin\" (version, build, id, android, ios, splash)");
		equals(error({helder: {build: "two"}}), "helder.webmanifest: \"helder\": {\"build\"}: a whole number from 1, not \"two\"");
		equals(error('{"helder": {"android": {"package": "game"}}}'),
			"helder.webmanifest: \"helder\": {\"android\": {\"package\": \"game\"}} is not an application id (a.b.c: letters, digits, _; each part starting with a letter)");
		equals(error({helder: {android: {minSdk: 26}}}), "helder.webmanifest: \"helder\": {\"android\": {\"minSdk\": 26}}: 29 is the lowest (Android 10: Bionic's ELF TLS)");
		equals(error({helder: {ios: {bundleId: "a_b.c"}}}), "helder.webmanifest: \"helder\": {\"ios\": {\"bundleId\": \"a_b.c\"}} is not a bundle id (a.b.c: letters, digits, -)");
		equals(error({helder: {splash: {dark: {image: 1}}}}), "helder.webmanifest: \"helder\": {\"splash\": {\"dark\": {\"image\"}}}: a string, not 1");
		equals(error({helder: {ios: {signing: {cert: "a.pem"}}}}), "helder.webmanifest: \"helder\": {\"ios\": {\"signing\"}}: no member \"cert\" (certificate, key, profile)");
		equals(error({helder: {ios: {sdk: {version: "26"}}}}), "helder.webmanifest: \"helder\": {\"ios\": {\"sdk\": {\"version\": \"26\"}}}: a version (26.0)");
		equals(error({helder: {ios: {nonExemptEncryption: "no"}}}), "helder.webmanifest: \"helder\": {\"ios\": {\"nonExemptEncryption\"}}: true or false");
		equals(error({helder: {ios: {privacy: {NSPrivacyAccessedAPICategoryUserDefaults: "CA92.1"}}}}),
			"helder.webmanifest: \"helder\": {\"ios\": {\"privacy\": {\"NSPrivacyAccessedAPICategoryUserDefaults\"}}}: an array of reasons (strings: \"CA92.1\")");
	});
	test("iOS distribution: PrivacyInfo's API reasons, the signing settings' mistakes", () -> {
		var exe = haxe.io.Bytes.ofString("\x00_write\x00_stat\x00_mach_absolute_time\x00_stat_not\x00");
		var p = Std.string(helder.pack.ios.Plist.parse(Ios.privacyInfo({NSPrivacyAccessedAPICategoryUserDefaults: ["CA92.1"]}, exe).toString()));
		for (c in ["FileTimestamp", "SystemBootTime", "UserDefaults"]) assert(p.indexOf("NSPrivacyAccessedAPICategory" + c) >= 0, c);
		assert(p.indexOf("DiskSpace") < 0 && p.indexOf("C617.1") >= 0 && p.indexOf("35F9.1") >= 0);
		var o = App.ios("x", null);
		equals(Ios.signing(o, ".", _ -> null), null);
		var env = ["HELDER_IOS_KEY" => "key.pem"];
		equals(Std.string(throws(() -> Ios.signing(o, ".", k -> env.get(k)))),
			'signing for the App Store takes a certificate, its key and a provisioning profile: HELDER_IOS_CERTIFICATE (or "helder": {"ios": {"signing": {"certificate"}}}), HELDER_IOS_PROFILE (or "helder": {"ios": {"signing": {"profile"}}}) not given');
		var all = ["HELDER_IOS_CERTIFICATE" => "missing.pem", "HELDER_IOS_KEY" => "missing.key", "HELDER_IOS_PROFILE" => "missing.mobileprovision"];
		equals(Std.string(throws(() -> Ios.signing(o, ".", k -> all.get(k)))), "HELDER_IOS_CERTIFICATE: missing.pem: no such file (nor PEM text)");
		equals(Ios.dtKeys(App.ios("x", {ios: {sdk: {version: "26.1"}}})).get("DTSDKName"), PString("iphoneos26.1"));
	});
	test("package.json's \"helder\" key: the fallback, deprecated when it holds the identity", () -> {
		equals(Manifest.legacy({id: "org.example.game"}), true);
		equals(Manifest.legacy({android: {}}), true);
		equals(Manifest.legacy({main: "app.Main", defines: {}}), false);
		equals(Manifest.legacy(null), false);
	});
	test("icons: picked by purpose and size, scaled, their mistakes", () -> {
		var red = solid(64, 0xFFFF0000), blue = solid(256, 0xFF0000FF);
		var files = ["red.png" => PngEncoder.encode(red, 64, 64), "blue.png" => PngEncoder.encode(blue, 256, 256),
			"wide.png" => PngEncoder.encode(Bytes.alloc(8 * 4 * 4), 8, 4),
			"dot.svg" => Bytes.ofString('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10" fill="#00ff00"/></svg>')];
		var read = (p:String) -> files.exists(p) ? files.get(p) : throw "no";
		var m = Manifest.parse(haxe.Json.stringify({
			icons: ([
				{src: "red.png", sizes: "64x64"},
				{src: "blue.png", sizes: "256x256"},
				{src: "dot.svg", sizes: "any", purpose: "maskable"}
			] : Array<Dynamic>)
		}));
		var icons = new Icons(m, ".", read);
		equals(icons.pick(["any"], 48).src, "red.png");
		equals(icons.pick(["any"], 100).src, "blue.png");
		equals(icons.pick(["any"], 1024).src, "blue.png");
		equals(icons.pick(["maskable", "any"], 16).src, "dot.svg");
		equals(icons.pick(["monochrome"], 16), null);
		// (the PNG files read back: the sizes asked, the colours kept)
		var png = PngDecoder.decode(icons.png(["any"], 180, 1, null, "x"));
		equals([png.width, png.height, png.rgba.get(0), png.rgba.get(2), png.rgba.get(3)], [180, 180, 0, 255, 255]);
		var small = PngDecoder.decode(icons.png(["any"], 32, 0.5, 0xFFFFFFFF, "x"));
		equals([small.rgba.get(0), small.rgba.get(1), small.rgba.get(4 * (16 * 32 + 16)), small.rgba.get(4 * (16 * 32 + 16) + 1)], [255, 255, 255, 0]);
		var svg = PngDecoder.decode(icons.png(["maskable"], 432, 1, null, "x"));
		equals([svg.width, svg.rgba.get(4 * (216 * 432 + 216)), svg.rgba.get(4 * (216 * 432 + 216) + 1)], [432, 0, 255]);
		// (iOS's: opaque, the 120 px of a 60 pt icon at @2x)
		var ios = PngDecoder.decode(icons.ios(120));
		equals([ios.width, ios.rgba.get(3)], [120, 255]);
		function error(icon:Dynamic, px:Int):String
			return Std.string(throws(() -> new Icons(Manifest.parse(haxe.Json.stringify({icons: [icon]})), ".", read).png(["any"], px, 1, null, "the test")));
		equals(error({src: "red.png", sizes: "48x48"}, 48), "helder.webmanifest: icons[0] (red.png): 64x64, but its sizes say 48x48");
		equals(error({src: "red.png"}, 432), "helder.webmanifest: icons[0] (red.png): 64x64 is too small for the test (432x432): give one of 432x432 or more, or an SVG");
		equals(error({src: "wide.png"}, 8), "helder.webmanifest: icons[0] (wide.png): 8x4: an icon is square");
		equals(error({src: "gone.png"}, 8), "helder.webmanifest: icons[0] (gone.png): no such file");
		// (scaled: an area's average down, its edges up)
		var half = Icons.scale(checker(4), 4, 2);
		equals([half.get(0), half.get(3)], [128, 255]);
		equals(Icons.scale(red, 64, 64) == red, true);
	});
	test("PngEncoder: what it writes, PngDecoder reads; a flat colour small", () -> {
		var c = checker(37);
		var d = PngDecoder.decode(PngEncoder.encode(c, 37, 37));
		equals([d.width, d.height], [37, 37]);
		equals(d.rgba.compare(c), 0);
		var flat = PngEncoder.encode(solid(1024, 0xFF060912), 1024, 1024);
		equals(flat.length < 40000, true); // (of 4 MB: under 1%)
		equals(PngDecoder.decode(flat).rgba.compare(solid(1024, 0xFF060912)), 0);
	});
	test("Arsc: Android's resource table, its ids and configurations", () -> {
		var t = new Arsc("org.example.game");
		var bg = t.add("color", "ic_launcher_background", Argb(0xFF060912));
		var night = t.add("color", "ic_launcher_background", Argb(0xFF000000), {night: true});
		var fg = t.add("mipmap", "ic_launcher_foreground", FilePath("res/mipmap-xxxhdpi-v4/ic_launcher_foreground.png"), {density: Arsc.XXXHDPI});
		var icon = t.add("mipmap", "ic_launcher", FilePath("res/mipmap-anydpi-v26/ic_launcher.xml"));
		var theme = t.add("style", "Theme.Helder", Style(0x01030007, [{attr: 0x0101062c, value: Ref(bg)}, {attr: 0x01010054, value: Ref(bg)}]));
		equals([bg, night, fg, icon, theme], [0x7f010000, 0x7f010000, 0x7f020000, 0x7f020001, 0x7f030000]);
		equals(t.idOf("mipmap", "ic_launcher"), icon);
		equals(t.idOf("raw", "x"), -1);
		equals(Arsc.dump(t.encode()).split("\n"), [
			"0x7f010000 color/ic_launcher_background (default) #ff060912",
			"0x7f010000 color/ic_launcher_background (night) #ff000000",
			"0x7f020000 mipmap/ic_launcher_foreground (640dpi) \"res/mipmap-xxxhdpi-v4/ic_launcher_foreground.png\"",
			"0x7f020001 mipmap/ic_launcher (default) \"res/mipmap-anydpi-v26/ic_launcher.xml\"",
			"0x7f030000 style/Theme.Helder (default) parent=@0x01030007 0x01010054=@0x7f010000 0x0101062c=@0x7f010000"
		]);
	});
}

// a square of a colour (0xAARRGGBB), RGBA
function solid(n:Int, c:Int):Bytes {
	var b = Bytes.alloc(n * n * 4);
	for (k in 0...n * n) {
		b.set(4 * k, c >> 16);
		b.set(4 * k + 1, c >> 8);
		b.set(4 * k + 2, c);
		b.set(4 * k + 3, c >>> 24);
	}
	return b;
}

// black and white squares of a pixel, opaque
function checker(n:Int):Bytes {
	var b = Bytes.alloc(n * n * 4);
	for (y in 0...n)
		for (x in 0...n) {
			var v = (x + y) % 2 == 0 ? 255 : 0, p = 4 * (y * n + x);
			b.set(p, v);
			b.set(p + 1, v);
			b.set(p + 2, v);
			b.set(p + 3, 255);
		}
	return b;
}
