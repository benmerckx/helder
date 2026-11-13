package helder.cli;

import haxe.io.Bytes;
import haxe.io.Path;
import helder.async.*;
import helder.pack.Jwt;
import helder.pack.apple.Identity.PrivateKey;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `helder publish [entry] --play | --testflight | --notarize [--track <t>] [--draft] [--dry-run]`:
// the release built, signed and uploaded through the store's own API, as
// fastlane, EAS Submit and Codemagic do, without them (HTTP by curl):
//
// - --play (Google Play, the Play Developer Publishing API v3): the App
//   Bundle (Android.bundle: the release key's), a service account's token
//   (an RS256 JWT for the androidpublisher scope, exchanged at its
//   token_uri), then edits.insert, bundles.upload, tracks.update (--track:
//   internal by default; alpha, beta, production; the release completed,
//   or a draft with --draft, which an app never published needs) and
//   edits.commit. The service account's JSON key: HELDER_PLAY_SERVICE_ACCOUNT
//   (its path or its text), else the manifest's "android": {"serviceAccount"}.
// - --testflight (App Store Connect API): the .ipa signed for distribution
//   (Ios.build), an ES256 JWT of the API key (HELDER_ASC_KEY_ID,
//   HELDER_ASC_ISSUER_ID, HELDER_ASC_KEY: the .p8's path or its text),
//   the app found by its bundle id, then Apple's build upload API: a
//   buildUploads record (the versions, iOS), a buildUploadFiles
//   reservation (the .ipa's name, size, com.apple.ipa), its upload
//   operations (each part PUT where they say), the file committed (its
//   MD5), the upload's state read back. TestFlight takes the build once
//   App Store Connect has processed it.
//
// - --notarize (macOS, on a Mac: Apple's notary service through
//   notarytool, the same API key): the release's zip (Desktop.pack, a
//   Developer ID identity's: HELDER_MACOS_*) submitted and waited for, its
//   log printed when refused, the ticket stapled to the .app and the zip
//   made again (Desktop.notarize).
//
// --dry-run builds and signs, gets the token and reads what is there (the
// track's releases; the app), prints what would change, and uploads or
// commits nothing (a Play edit it opened is deleted). HELDER_PLAY_API and
// HELDER_ASC_API point elsewhere than Google's and Apple's (the tests' stand-in).
class Publish {
	public static inline var PLAY = "https://androidpublisher.googleapis.com";
	public static inline var ASC = "https://api.appstoreconnect.apple.com";

	@:coroutine public static function run(o:Options):Int {
		if (o.has("run")) {
			if (o.has("play") || o.has("testflight") || o.has("notarize") || o.has("screenshots") || o.has("listing")) {
				Term.err(Style.usage("helder publish: --run alone (each destination is its own publish)"));
				return 2;
			}
			return Run.publish(o);
		}
		if (!Lambda.exists(["play", "testflight", "notarize", "screenshots", "listing"], k -> o.has(k))) return every(o);
		var play = o.has("play"), testflight = o.has("testflight"), shots = o.has("screenshots"), listing = o.has("listing"), notarize = o.has("notarize");
		if (!shots && !listing && !notarize && play == testflight || notarize && (play || testflight || shots || listing)) {
			Term.err(Style.usage("helder publish: --play or --testflight, --notarize, or --screenshots, --listing (helder publish --help)"));
			return 2;
		}
		var e = try Entry.of(o) catch (err:Dynamic) {
			Term.err(Style.usage('helder publish: $err'));
			return 2;
		}
		var dry = o.has("dry-run");
		if (notarize) return try {
			Term.out(Style.header("publish", ["notarisation", e.main]));
			Desktop.notarize(e, o.out, dry);
		} catch (err:Dynamic) {
			Term.err(Style.status("error", Fail, Std.string(err)));
			1;
		}
		if (shots || listing) return try {
			Term.out(Style.header("publish", [listing ? "store listings" : "store screenshots", e.main]));
			var dir = "bin/store";
			// (--listing --no-screenshot: the text alone, the stores' screenshots left as they are)
			var list = listing && o.has("no-screenshot") ? [] : screenshots(e, dir, App.android(e.name, e.config).orientation == "landscape");
			var changes = [];
			if (listing) {
				var both = !play && !testflight;
				if (play || both) changes = changes.concat(playListing(e, dir, list, App.android(e.name, e.config).id, o.value("locale") ?? "en-US", dry, serviceAccount(e)));
				if (testflight || both) changes = changes.concat(ascListing(e, dir, list, App.ios(e.name, e.config), o.value("locale") ?? "en-US", dry, ascKey()));
			}
			review(dir, list, listing ? changes : null, dry);
			0;
		} catch (err:Dynamic) {
			Term.err(Style.status("error", Fail, Std.string(err)));
			1;
		}
		try {
			if (play) {
				e.target = "android-arm64";
				Term.out(Style.header("publish", ["Google Play", e.main]));
				var sa = serviceAccount(e);
				var out = o.out ?? Android.out(e, true);
				if (!Android.bundle(e, out).ok) return 1;
				var id = App.android(e.name, e.config).id;
				toPlay(out, id, App.android(e.name, e.config).versionCode, o.value("track") ?? "internal", o.has("draft"), dry, sa);
			} else {
				e.target = "ios-arm64";
				Term.out(Style.header("publish", ["TestFlight", e.main]));
				var key = ascKey();
				var out = o.out ?? Ios.out(e);
				if (Ios.signing(App.ios(e.name, e.config), e.root) == null)
					throw "TestFlight takes an .ipa signed for distribution: HELDER_IOS_IDENTITY (or HELDER_IOS_CERTIFICATE and HELDER_IOS_KEY)";
				if (!Ios.build(e, out, Release).ok) return 1;
				var i = App.ios(e.name, e.config);
				toTestFlight(out, i.id, i.versionName, i.version, dry, key, o.has("submit"));
			}
		} catch (err:Dynamic) {
			Term.err(Style.status("error", Fail, Std.string(err)));
			return 1;
		}
		return 0;
	}

	// `helder publish` with no destination: each one helder.json names
	// (helder.run's first), as `helder publish --<destination>` does it
	@:coroutine static function every(o:Options):Int {
		var e = try Entry.of(o) catch (err:Dynamic) {
			Term.err(Style.usage('helder publish: $err'));
			return 2;
		}
		var cfg:Manifest.AppConfig = e.config;
		var runs = [];
		if (cfg?.run != null) runs.push(["--run"]);
		for (d in cfg?.destinations ?? []) runs.push(["--" + d.to].concat(d.track != null ? ["--track", d.track] : []).concat(d.draft ? ["--draft"] : []));
		if (runs.length == 0) {
			Term.err(Style.usage("helder publish: where to: --run, --play, --testflight or --notarize, or name them in helder.json (a run block, targets.<t>.publish)"));
			return 2;
		}
		for (r in runs) {
			var args = (o.entry == null ? [] : [o.entry]).concat(r).concat(o.has("dry-run") ? ["--dry-run"] : []).concat(o.has("no-screenshot") ? ["--no-screenshot"] : []);
			var code = run(Options.parse("publish", args));
			if (code != 0) return code;
		}
		return 0;
	}

	// ---- HTTP (curl): the status and the body

	@:coroutine public static function http(method:String, url:String, headers:Array<String>, ?body:Bytes, ?file:{path:String, offset:Int, length:Int}):{
		code:Int,
		body:String
	} {
		var args = ["-sS", "-X", method, "-w", "\n%{http_code}"];
		for (h in headers)
			args = args.concat(["-H", h]);
		var tmp:Null<String> = null;
		if (file != null && (file.offset != 0 || file.length != FileSystem.stat(file.path).size)) {
			// (a part of the file: its bytes on their own)
			var all = File.getBytes(file.path);
			body = all.sub(file.offset, file.length);
			file = null;
		}
		if (body != null) {
			tmp = DevCommand.cache() + "/publish-" + Std.random(1 << 30) + ".body";
			TestCommand.mkdirs(Path.directory(tmp));
			File.saveBytes(tmp, body);
			args = args.concat(["--data-binary", "@" + tmp]);
		} else if (file != null) args = args.concat(["--data-binary", "@" + file.path]);
		else if (method != "GET" && method != "DELETE" && method != "HEAD") args = args.concat(["-H", "Content-Length: 0"]);
		// (a POST with no body: Google's front end refuses one without its length, which curl on Windows leaves out)
		var r = Devices.output("curl", args.concat([url]));
		if (tmp != null) try FileSystem.deleteFile(tmp) catch (_:Dynamic) {};
		if (r.code != 0) throw '$method $url: curl: exit code ${r.code} ${r.errors.trim()}';
		var at = r.text.lastIndexOf("\n");
		return {code: Std.parseInt(r.text.substr(at + 1)) ?? 0, body: at < 0 ? "" : r.text.substr(0, at)};
	}

	@:coroutine public static function json(method:String, url:String, token:String, ?body:Dynamic, ok = 200):Dynamic {
		var r = http(method, url, ["Authorization: Bearer " + token, "Content-Type: application/json"],
			body == null ? null : Bytes.ofString(haxe.Json.stringify(body)));
		if (r.code != ok && !(ok == 200 && r.code == 204)) throw '$method $url: HTTP ${r.code} ${r.body.trim()}';
		return r.body.trim() == "" ? {} : haxe.Json.parse(r.body);
	}

	// (a secret's text, or the file it names: JSON, PEM, or a bare base64 key, its armour lost)
	static function textOrFile(name:String, v:String):String {
		var t = v.trim();
		if (t.startsWith("{") || v.indexOf("-----BEGIN") >= 0 || (t.length >= 64 && ~/^[A-Za-z0-9+\/=\s]+$/.match(t))) return v;
		return FileSystem.exists(t) ? File.getContent(t) : throw '$name: $v: no such file';
	}

	// ---- Google Play

	// Google's credentials, the first there is: an access token
	// (HELDER_PLAY_ACCESS_TOKEN, or GOOGLE_OAUTH_ACCESS_TOKEN: what
	// google-github-actions/auth gives with token_format: access_token, a
	// short-lived one through Workload Identity Federation), else a service
	// account's JSON key (HELDER_PLAY_SERVICE_ACCOUNT: its path or text; the
	// manifest's "android": {"serviceAccount"}; GOOGLE_APPLICATION_CREDENTIALS
	// when it is one), signed for a token
	public static function serviceAccount(e:Entry):Dynamic {
		for (n in ["HELDER_PLAY_ACCESS_TOKEN", "GOOGLE_OAUTH_ACCESS_TOKEN"]) {
			var t = Sys.getEnv(n);
			if (t != null && t.trim() != "") return {token: t.trim()};
		}
		var v = Sys.getEnv("HELDER_PLAY_SERVICE_ACCOUNT"), name = "HELDER_PLAY_SERVICE_ACCOUNT";
		if (v == null || v.trim() == "") {
			var m:Dynamic = e.config?.android?.serviceAccount, adc = Sys.getEnv("GOOGLE_APPLICATION_CREDENTIALS");
			if (m != null) {
				v = Path.isAbsolute(m) || e.root == "." ? m : '${e.root}/$m';
				name = '"helder": {"android": {"serviceAccount"}}';
			} else if (adc != null && adc.trim() != "") {
				v = adc;
				name = "GOOGLE_APPLICATION_CREDENTIALS";
			} else
				throw 'Google Play takes an access token (GOOGLE_OAUTH_ACCESS_TOKEN: Workload Identity Federation\'s, or HELDER_PLAY_ACCESS_TOKEN) or a service account\'s JSON key (HELDER_PLAY_SERVICE_ACCOUNT, its path or text; "helder": {"android": {"serviceAccount"}})';
		}
		var j:Dynamic = try haxe.Json.parse(textOrFile(name, v)) catch (err:String) throw err catch (err:Dynamic) throw '$name: not JSON ($err)';
		if (j.type == "external_account")
			throw '$name: Workload Identity Federation\'s credentials file: give its access token instead (google-github-actions/auth with token_format: access_token, access_token_scopes: https://www.googleapis.com/auth/androidpublisher; GOOGLE_OAUTH_ACCESS_TOKEN)';
		if (j.client_email == null || j.private_key == null) throw '$name: not a service account\'s key (client_email, private_key)';
		return j;
	}

	// the service account's access token (RFC 7523: a JWT bearer grant)
	@:coroutine public static function googleToken(sa:Dynamic):String {
		if (sa.token != null) return sa.token;
		var now = Std.int(Date.now().getTime() / 1000);
		var uri:String = sa.token_uri ?? "https://oauth2.googleapis.com/token";
		var jwt = Jwt.sign({alg: "RS256", typ: "JWT"}, {
			iss: sa.client_email,
			scope: "https://www.googleapis.com/auth/androidpublisher",
			aud: uri,
			iat: now,
			exp: now + 3600
		}, PrivateKey.fromPem(sa.private_key));
		var r = http("POST", uri, ["Content-Type: application/x-www-form-urlencoded"],
			Bytes.ofString("grant_type=" + StringTools.urlEncode("urn:ietf:params:oauth:grant-type:jwt-bearer") + "&assertion=" + jwt));
		if (r.code != 200) throw 'the service account\'s token: HTTP ${r.code} ${r.body.trim()}';
		return haxe.Json.parse(r.body).access_token;
	}

	@:coroutine public static function toPlay(aab:String, pkg:String, versionCode:Int, track:String, draft:Bool, dry:Bool, sa:Dynamic) {
		if (!["internal", "alpha", "beta", "production"].contains(track)) throw '--track $track: internal, alpha, beta or production';
		var api = playApi();
		var base = '$api/androidpublisher/v3/applications/$pkg';
		var token = googleToken(sa);
		var edit:String = json("POST", '$base/edits', token, {}).id;
		var status = draft ? "draft" : "completed";
		if (dry) {
			var t:Dynamic = try json("GET", '$base/edits/$edit/tracks/$track', token) catch (_:Dynamic) {releases: []};
			var now = [for (r in (t.releases ?? [] : Array<Dynamic>)) '${r.status} ${(r.versionCodes ?? [] : Array<Dynamic>).join(",")}'];
			Term.out(Style.status("dry run", Info, '$pkg: $track has ${now.length == 0 ? "no release" : now.join("; ")}'));
			Term.out(Style.status("would", Info, 'upload ${Path.withoutDirectory(aab)} (versionCode $versionCode, ${Math.round(FileSystem.stat(aab).size / 1024)} KB) and release it on $track ($status)'));
			json("DELETE", '$base/edits/$edit', token);
			return;
		}
		Term.spin("uploading " + Path.withoutDirectory(aab));
		var r = http("POST", '$api/upload/androidpublisher/v3/applications/$pkg/edits/$edit/bundles?uploadType=media',
			["Authorization: Bearer " + token, "Content-Type: application/octet-stream"], null, {path: aab, offset: 0, length: FileSystem.stat(aab).size});
		Term.done();
		if (r.code != 200) throw 'bundles.upload: HTTP ${r.code} ${r.body.trim()}';
		var code:Int = haxe.Json.parse(r.body).versionCode;
		json("PUT", '$base/edits/$edit/tracks/$track', token, {track: track, releases: [{versionCodes: [Std.string(code)], status: status}]});
		try json("POST", '$base/edits/$edit:commit', token) catch (err:String) {
			// (an app never published takes drafts alone: its first release
			// sent for review in Play Console, the ones after it directly)
			if (status == "draft" || err.indexOf("status draft") < 0) throw err;
			status = "draft";
			json("PUT", '$base/edits/$edit/tracks/$track', token, {track: track, releases: [{versionCodes: [Std.string(code)], status: status}]});
			json("POST", '$base/edits/$edit:commit', token);
			Term.out(Style.status("draft", Warn, '$pkg has never been published: its first release is a draft; send it for review in Play Console (Publishing overview), the ones after it go out directly'));
		}
		Term.out(Style.status("published", Ok, '$pkg versionCode $code on $track ($status)'));
	}

	// ---- App Store Connect

	// the APIs' bases (HELDER_ASC_API, HELDER_PLAY_API: the tests' stand-in)
	public static function ascApi():String {
		var api = (Sys.getEnv("HELDER_ASC_API") ?? "").trim();
		return api == "" ? ASC : api;
	}

	public static function playApi():String {
		var api = (Sys.getEnv("HELDER_PLAY_API") ?? "").trim();
		return api == "" ? PLAY : api;
	}

	// the App Store Connect API key: HELDER_ASC_API_KEY (one secret: JSON
	// {"key_id", "issuer_id", "private_key"}, its path or text), else
	// HELDER_ASC_KEY_ID, HELDER_ASC_ISSUER_ID and HELDER_ASC_KEY (the .p8)
	public static function ascKey():{id:String, issuer:String, key:PrivateKey} {
		var k = ascKeyText();
		var key = try PrivateKey.fromPem(k.pem) catch (err:String) throw 'HELDER_ASC_KEY: $err';
		if (key.ec == null) throw "HELDER_ASC_KEY: not an App Store Connect key (a P-256 .p8)";
		return {id: k.id, issuer: k.issuer, key: key};
	}

	// the API key's id, issuer id and the .p8's text (notarytool's --key is a file)
	public static function ascKeyText():{id:String, issuer:String, pem:String} {
		var id = Sys.getEnv("HELDER_ASC_KEY_ID"), issuer = Sys.getEnv("HELDER_ASC_ISSUER_ID"), key = Sys.getEnv("HELDER_ASC_KEY");
		var bundle = Sys.getEnv("HELDER_ASC_API_KEY");
		if (bundle != null && bundle.trim() != "") {
			var j:Dynamic = try haxe.Json.parse(textOrFile("HELDER_ASC_API_KEY", bundle)) catch (err:String) throw err catch (err:Dynamic) throw 'HELDER_ASC_API_KEY: not JSON ($err)';
			id = j.key_id ?? j.keyId;
			issuer = j.issuer_id ?? j.issuerId;
			key = j.private_key ?? j.privateKey ?? j.key;
			if (id == null || issuer == null || key == null) throw 'HELDER_ASC_API_KEY: JSON of "key_id", "issuer_id" and "private_key" (the .p8\'s text)';
		}
		var missing = [for (n => v in ["HELDER_ASC_KEY_ID" => id, "HELDER_ASC_ISSUER_ID" => issuer, "HELDER_ASC_KEY" => key]) if (v == null || v.trim() == "") n];
		missing.sort(Reflect.compare);
		if (missing.length > 0) throw 'App Store Connect takes an API key: HELDER_ASC_API_KEY, or ${missing.join(", ")} not given (the key\'s id, its issuer id, the .p8)';
		return {id: id.trim(), issuer: issuer.trim(), pem: textOrFile("HELDER_ASC_KEY", key)};
	}

	public static function ascToken(k:{id:String, issuer:String, key:PrivateKey}):String {
		var now = Std.int(Date.now().getTime() / 1000);
		return Jwt.sign({alg: "ES256", kid: k.id, typ: "JWT"}, {iss: k.issuer, iat: now, exp: now + 1200, aud: "appstoreconnect-v1"}, k.key);
	}

	@:coroutine public static function toTestFlight(ipa:String, bundleId:String, version:String, build:String, dry:Bool, k:{id:String, issuer:String, key:PrivateKey}, submit = false) {
		var api = ascApi();
		var token = ascToken(k);
		var apps:Array<Dynamic> = json("GET", '$api/v1/apps?filter%5BbundleId%5D=' + StringTools.urlEncode(bundleId), token).data;
		if (apps == null || apps.length == 0) throw 'App Store Connect has no app $bundleId (make its record first: Apps, +, New App)';
		var app:String = apps[0].id;
		var size = FileSystem.stat(ipa).size;
		if (dry) {
			Term.out(Style.status("dry run", Info, '$bundleId is app $app on App Store Connect'));
			Term.out(Style.status("would", Info, 'upload ${Path.withoutDirectory(ipa)} ($version ($build), ${Math.round(size / 1024)} KB) for TestFlight'));
			if (submit) Listing.submit(api, () -> ascToken(k), app, version, build, true);
			return;
		}
		var upload:Dynamic = json("POST", '$api/v1/buildUploads', token, {
			data: {
				type: "buildUploads",
				attributes: {cfBundleShortVersionString: version, cfBundleVersion: build, platform: "IOS"},
				relationships: {app: {data: {type: "apps", id: app}}}
			}
		}, 201).data;
		var file:Dynamic = json("POST", '$api/v1/buildUploadFiles', token, {
			data: {
				type: "buildUploadFiles",
				attributes: {assetType: "ASSET", fileName: Path.withoutDirectory(ipa), fileSize: size, uti: "com.apple.ipa"},
				relationships: {buildUpload: {data: {type: "buildUploads", id: upload.id}}}
			}
		}, 201).data;
		var ops:Array<Dynamic> = file.attributes.uploadOperations ?? [];
		Term.spin('uploading ${Path.withoutDirectory(ipa)} (${ops.length} parts)');
		for (op in ops) {
			var headers = [for (h in (op.requestHeaders ?? [] : Array<Dynamic>)) '${h.name}: ${h.value}'];
			var r = http(op.method ?? "PUT", op.url, headers, null, {path: ipa, offset: op.offset ?? 0, length: op.length ?? size});
			if (r.code < 200 || r.code >= 300) throw 'the upload\'s part at ${op.offset}: HTTP ${r.code} ${r.body.trim()}';
		}
		Term.done();
		json("PATCH", '$api/v1/buildUploadFiles/${file.id}', token, {
			data: {
				type: "buildUploadFiles",
				id: file.id,
				attributes: {uploaded: true, sourceFileChecksums: {file: {algorithm: "MD5", hash: haxe.crypto.Md5.make(File.getBytes(ipa)).toHex()}}}
			}
		});
		var state:Dynamic = json("GET", '$api/v1/buildUploads/${upload.id}', token).data;
		Term.out(Style.status("uploaded", Ok, '$bundleId $version ($build): App Store Connect\'s build upload ${upload.id}, ${haxe.Json.stringify(state.attributes?.state ?? "")}; TestFlight lists it once processed'));
		if (submit) Listing.submit(api, () -> ascToken(k), app, version, build, false);
	}

	// ---- store screenshots (helder.story.StoreShots, built and run by Shots)

	@:coroutine public static function screenshots(e:Entry, dir:String, landscape:Bool):Array<Dynamic> {
		var list = Shots.store(e, dir, landscape);
		// (Google Play's icon: the app's, 512 pixels, opaque)
		var png = try new Icons(e.config, e.root).ios(512) catch (_:Dynamic) null;
		if (png != null) {
			TestCommand.mkdirs('$dir/android-icon');
			File.saveBytes('$dir/android-icon/icon.png', png);
			list.push({
				file: "android-icon/icon.png", size: "android-icon", store: "android", type: "icon", story: "the app's icon", caption: null, width: 512, height: 512,
				sha256: haxe.crypto.Sha256.make(png).toHex(), md5: haxe.crypto.Md5.make(png).toHex()
			});
			File.saveContent('$dir/shots.json', haxe.Json.stringify(list, null, "  "));
		}
		Term.out(Style.status("rendered", Ok, '${[for (s in list) if (s.type != "icon") s].length} screenshots in $dir'));
		return list;
	}

	// the review sheet: every screenshot by store size, its story, caption,
	// size and hash, and what would change in the stores (changes; null: not compared)
	static function review(dir:String, list:Array<Dynamic>, changes:Null<Array<String>>, dry:Bool) {
		var esc = StringTools.htmlEscape;
		var h = ['<!doctype html><meta charset="utf-8"><title>Store screenshots</title>',
			'<style>body{font:14px system-ui;margin:24px;background:#f4f4f5}figure{display:inline-block;margin:8px;vertical-align:top;background:#fff;padding:8px;border-radius:8px}img{height:360px;display:block}figcaption{font-size:12px;color:#52525b;max-width:260px}code{font-size:11px}</style>',
			'<h1>Store screenshots</h1>'];
		if (changes != null) {
			h.push('<h2>${dry ? "What would change" : "What changed"} in the stores</h2><ul>');
			for (c in changes) h.push('<li>${esc(c)}</li>');
			if (changes.length == 0) h.push("<li>nothing: the stores have these screenshots</li>");
			h.push("</ul>");
		}
		var sizes = [];
		for (s in list) if (!sizes.contains(s.size)) sizes.push(s.size);
		for (size in sizes) {
			h.push('<h2>${esc(size)}</h2>');
			for (s in list) if (s.size == size)
				h.push('<figure><img src="${esc(s.file)}"><figcaption>${esc(s.story)}${s.caption == null ? "" : " &middot; " + esc(s.caption)}<br>${s.width}x${s.height}<br><code>${s.sha256.substr(0, 16)}</code></figcaption></figure>');
		}
		File.saveContent('$dir/review.html', h.join("\n"));
		Term.out(Style.status("review", Info, Style.path('$dir/review.html')));
	}

	// Google Play's listing: each image type's screenshots against ours by
	// SHA-256: the ones not ours deleted, ours not there uploaded, committed
	@:coroutine static function playListing(e:Entry, dir:String, list:Array<Dynamic>, pkg:String, lang:String, dry:Bool, sa:Dynamic):Array<String> {
		var api = playApi();
		var base = '$api/androidpublisher/v3/applications/$pkg';
		var token = googleToken(sa);
		var edit:String = json("POST", '$base/edits', token, {}).id;
		var cfg:Manifest.AppConfig = e.config;
		var changes = cfg?.listing == null ? [] : Listing.play(cfg.listing, cfg.name ?? e.name, e.root, base, edit, token, lang, dry), types = [];
		for (s in list) if (s.store == "android" && !types.contains(s.type)) types.push(s.type);
		for (type in types) {
			var ours:Array<Dynamic> = [for (s in list) if (s.store == "android" && s.type == type) s];
			var theirs:Array<Dynamic> = json("GET", '$base/edits/$edit/listings/$lang/$type', token).images ?? [];
			for (t in theirs)
				if (!Lambda.exists(ours, s -> s.sha256 == t.sha256)) {
					changes.push('Google Play $lang $type: delete ${t.id}');
					if (!dry) json("DELETE", '$base/edits/$edit/listings/$lang/$type/${t.id}', token);
				}
			for (s in ours)
				if (!Lambda.exists(theirs, t -> t.sha256 == s.sha256)) {
					changes.push('Google Play $lang $type: upload ${s.file}');
					if (!dry) {
						var r = http("POST", '$api/upload/androidpublisher/v3/applications/$pkg/edits/$edit/listings/$lang/$type?uploadType=media',
							["Authorization: Bearer " + token, "Content-Type: image/png"], null, {path: '$dir/${s.file}', offset: 0, length: FileSystem.stat('$dir/${s.file}').size});
						if (r.code != 200) throw 'images.upload ${s.file}: HTTP ${r.code} ${r.body.trim()}';
					}
				}
		}
		if (dry || changes.length == 0) json("DELETE", '$base/edits/$edit', token) else json("POST", '$base/edits/$edit:commit', token);
		changes = changes.concat(Listing.dataSafety(cfg?.listing, e.root, base, token, dry));
		for (c in changes) Term.out(Style.status(dry ? "would" : "listing", dry ? Info : Ok, c));
		return changes;
	}

	// App Store Connect's: the editable version's localization, its
	// screenshot sets by display type (made when missing), each set's
	// screenshots against ours by MD5 (sourceFileChecksum): the others
	// deleted, ours missing uploaded (reserved, the parts sent, committed)
	@:coroutine static function ascListing(e:Entry, dir:String, list:Array<Dynamic>, ios:Dynamic, locale:String, dry:Bool, k:{id:String, issuer:String, key:PrivateKey}):Array<String> {
		var bundleId:String = ios.id;
		var api = ascApi();
		var token = ascToken(k);
		var apps:Array<Dynamic> = json("GET", '$api/v1/apps?filter%5BbundleId%5D=' + StringTools.urlEncode(bundleId), token).data;
		if (apps == null || apps.length == 0) throw 'App Store Connect has no app $bundleId';
		var cfg:Manifest.AppConfig = e.config, changes = [];
		var version = Listing.appStore(cfg?.listing, cfg?.name ?? e.name, e.root, api, token, apps[0], ios.versionName, dry, changes);
		if (version == null) {
			for (c in changes) Term.out(Style.status("would", Info, c));
			Term.out(Style.status("would", Info, 'App Store screenshots: compared once version ${ios.versionName} is made'));
			return changes;
		}
		if (!Lambda.exists(list, s -> s.store == "ios")) {
			for (c in changes) Term.out(Style.status(dry ? "would" : "listing", dry ? Info : Ok, c));
			return changes;
		}
		var locs:Array<Dynamic> = json("GET", '$api/v1/appStoreVersions/$version/appStoreVersionLocalizations', token).data;
		var loc:Dynamic = Lambda.find(locs ?? [], l -> l.attributes.locale == locale);
		if (loc == null) {
			if (dry && changes.length > 0) {
				for (c in changes) Term.out(Style.status("would", Info, c));
				return changes;
			}
			throw 'App Store Connect: the version has no $locale localization';
		}
		var sets:Array<Dynamic> = json("GET", '$api/v1/appStoreVersionLocalizations/${loc.id}/appScreenshotSets', token).data ?? [];
		var types = [];
		for (s in list) if (s.store == "ios" && !types.contains(s.type)) types.push(s.type);
		for (type in types) {
			var ours:Array<Dynamic> = [for (s in list) if (s.store == "ios" && s.type == type) s];
			var set:Dynamic = Lambda.find(sets, x -> x.attributes.screenshotDisplayType == type);
			var theirs:Array<Dynamic> = [];
			if (set == null) {
				changes.push('App Store $locale $type: a screenshot set made');
				if (!dry) set = json("POST", '$api/v1/appScreenshotSets', token, {
					data: {
						type: "appScreenshotSets",
						attributes: {screenshotDisplayType: type},
						relationships: {appStoreVersionLocalization: {data: {type: "appStoreVersionLocalizations", id: loc.id}}}
					}
				}, 201).data;
			} else theirs = json("GET", '$api/v1/appScreenshotSets/${set.id}/appScreenshots', token).data ?? [];
			for (t in theirs)
				if (!Lambda.exists(ours, s -> s.md5 == t.attributes.sourceFileChecksum)) {
					changes.push('App Store $locale $type: delete ${t.id}');
					if (!dry) json("DELETE", '$api/v1/appScreenshots/${t.id}', token, null, 204);
				}
			for (s in ours)
				if (!Lambda.exists(theirs, t -> t.attributes.sourceFileChecksum == s.md5)) {
					changes.push('App Store $locale $type: upload ${s.file}');
					if (dry) continue;
					var path = '$dir/${s.file}', size = FileSystem.stat(path).size;
					var shot:Dynamic = json("POST", '$api/v1/appScreenshots', token, {
						data: {
							type: "appScreenshots",
							attributes: {fileName: Path.withoutDirectory(s.file), fileSize: size},
							relationships: {appScreenshotSet: {data: {type: "appScreenshotSets", id: set.id}}}
						}
					}, 201).data;
					for (op in (shot.attributes.uploadOperations ?? [] : Array<Dynamic>)) {
						var headers = [for (h in (op.requestHeaders ?? [] : Array<Dynamic>)) '${h.name}: ${h.value}'];
						var r = http(op.method ?? "PUT", op.url, headers, null, {path: path, offset: op.offset ?? 0, length: op.length ?? size});
						if (r.code < 200 || r.code >= 300) throw 'a screenshot\'s part: HTTP ${r.code} ${r.body.trim()}';
					}
					json("PATCH", '$api/v1/appScreenshots/${shot.id}', token, {
						data: {type: "appScreenshots", id: shot.id, attributes: {uploaded: true, sourceFileChecksum: s.md5}}
					});
				}
		}
		for (c in changes) Term.out(Style.status(dry ? "would" : "listing", dry ? Info : Ok, c));
		return changes;
	}

	// the active App Store profile of a bundle id for the certificate, from
	// App Store Connect (bundleIds by identifier, their profiles)
	// make: the certificate's id on App Store Connect and the name, to make
	// one when there is none (helder setup ios)
	@:coroutine public static function profile(bundleId:String, cert:haxe.io.Bytes, k:{id:String, issuer:String, key:PrivateKey},
			?make:{certificate:String, name:String}):helder.pack.apple.Identity.Profile {
		var api = ascApi();
		var token = ascToken(k);
		var ids:Array<Dynamic> = json("GET", '$api/v1/bundleIds?filter%5Bidentifier%5D=' + StringTools.urlEncode(bundleId), token).data ?? [];
		var id:Dynamic = Lambda.find(ids, b -> b.attributes?.identifier == bundleId);
		if (id == null) throw 'App Store Connect: no App ID $bundleId (Certificates, Identifiers & Profiles: Identifiers, +)';
		var all:Array<Dynamic> = json("GET", '$api/v1/bundleIds/${id.id}/profiles?limit=200', token).data ?? [];
		var found = [];
		for (p in all) {
			var a:Dynamic = p.attributes;
			if (a == null || a.profileType != "IOS_APP_STORE" || a.profileState != "ACTIVE" || a.profileContent == null) continue;
			var parsed = helder.pack.apple.Identity.Profile.parse(haxe.crypto.Base64.decode(a.profileContent));
			if (Lambda.exists(parsed.certificates, c -> c.compare(cert) == 0)) found.push(parsed);
		}
		if (found.length == 0 && make != null) {
			var made:Dynamic = json("POST", '$api/v1/profiles', token, {
				data: {
					type: "profiles",
					attributes: {name: make.name, profileType: "IOS_APP_STORE"},
					relationships: {
						bundleId: {data: {type: "bundleIds", id: id.id}},
						certificates: {data: [{type: "certificates", id: make.certificate}]}
					}
				}
			}, 201).data;
			var p = helder.pack.apple.Identity.Profile.parse(haxe.crypto.Base64.decode(made.attributes.profileContent));
			Term.out(Style.status("profile", Ok, '"${p.name}" made on App Store Connect (App Store, $bundleId)'));
			return p;
		}
		if (found.length == 0)
			throw 'App Store Connect: no active App Store profile for $bundleId with this certificate (Profiles, +, App Store Connect: the App ID, the certificate; or HELDER_IOS_PROFILE)';
		Term.out(Style.status("profile", Info, '"${found[0].name}" from App Store Connect'));
		return found[0];
	}
}
