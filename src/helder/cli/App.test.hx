package helder.cli;

import helder.test.Test;

// An app's identity from package.json's "helder" key (App): the defaults,
// the overrides, the mistakes; the debug key's file
function tests() {
	test("Android: the defaults from the name", () -> {
		equals(App.android("Hello", null), {
			id: "org.helder.hello",
			label: "Hello",
			versionCode: 1,
			versionName: "1.0",
			minSdk: 29,
			targetSdk: 35,
			permissions: []
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
			permissions: ["VIBRATE", "com.example.X"]
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
			entitlements: null
		});
		equals(App.ios("my_game", null).id, "org.helder.my-game");
		var o = App.ios("Hello", {id: "org.example.game", version: 4, ios: {minVersion: "16.4", entitlements: "app.entitlements"}});
		equals([o.id, o.version, o.minVersion, o.entitlements], ["org.example.game", "4", "16.4", "app.entitlements"]);
		equals(Std.string(throws(() -> App.ios("x", {ios: {minVersion: "16"}}))), "package.json's \"helder\": {\"ios\": {\"minVersion\": \"16\"}}: a version, major.minor (15.0)");
		equals(Std.string(throws(() -> App.ios("x", {id: "org.example.a_b"}))), "package.json's \"helder\": {\"id\": \"org.example.a_b\"} is not a bundle id (a.b.c: letters, digits, -)");
	});
	test("the debug key's file: HELDER_ANDROID_KEY, package.json's, the cache", () -> {
		equals(App.androidKey(null, "app", "/c/helder", null), "/c/helder/android/debug-key");
		equals(App.androidKey({android: {key: "keys/debug"}}, "app", "/c/helder", null), "app/keys/debug");
		equals(App.androidKey({android: {key: "keys/debug"}}, ".", "/c/helder", null), "keys/debug");
		equals(App.androidKey({android: {key: "/k"}}, "app", "/c/helder", null), "/k");
		equals(App.androidKey({android: {key: "keys/debug"}}, "app", "/c/helder", "/env/key"), "/env/key");
	});
}
