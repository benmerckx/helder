package helder.cli;

import haxe.io.Bytes;
import haxe.io.Path;
import helder.async.*;
import helder.pack.Jwt;
import helder.pack.apple.Identity.PrivateKey;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `helder publish [entry] --play | --testflight [--track <t>] [--draft] [--dry-run]`:
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
// --dry-run builds and signs, gets the token and reads what is there (the
// track's releases; the app), prints what would change, and uploads or
// commits nothing (a Play edit it opened is deleted). HELDER_PLAY_API and
// HELDER_ASC_API point elsewhere than Google's and Apple's (the tests' stand-in).
class Publish {
	public static inline var PLAY = "https://androidpublisher.googleapis.com";
	public static inline var ASC = "https://api.appstoreconnect.apple.com";

	@:coroutine public static function run(o:Options):Int {
		var play = o.has("play"), testflight = o.has("testflight");
		if (play == testflight) {
			Term.err(Style.usage("helder publish: --play or --testflight (helder publish --help)"));
			return 2;
		}
		var e = try Entry.of(o) catch (err:Dynamic) {
			Term.err(Style.usage('helder publish: $err'));
			return 2;
		}
		var dry = o.has("dry-run");
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
					throw "TestFlight takes an .ipa signed for distribution: HELDER_IOS_CERTIFICATE, HELDER_IOS_KEY and HELDER_IOS_PROFILE";
				if (!Ios.build(e, out, Release).ok) return 1;
				var i = App.ios(e.name, e.config);
				toTestFlight(out, i.id, i.versionName, i.version, dry, key);
			}
		} catch (err:Dynamic) {
			Term.err(Style.status("error", Fail, Std.string(err)));
			return 1;
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
		var r = Devices.output("curl", args.concat([url]));
		if (tmp != null) try FileSystem.deleteFile(tmp) catch (_:Dynamic) {};
		if (r.code != 0) throw '$method $url: curl: exit code ${r.code} ${r.errors.trim()}';
		var at = r.text.lastIndexOf("\n");
		return {code: Std.parseInt(r.text.substr(at + 1)) ?? 0, body: at < 0 ? "" : r.text.substr(0, at)};
	}

	@:coroutine static function json(method:String, url:String, token:String, ?body:Dynamic, ok = 200):Dynamic {
		var r = http(method, url, ["Authorization: Bearer " + token, "Content-Type: application/json"],
			body == null ? null : Bytes.ofString(haxe.Json.stringify(body)));
		if (r.code != ok && !(ok == 200 && r.code == 204)) throw '$method $url: HTTP ${r.code} ${r.body.trim()}';
		return r.body.trim() == "" ? {} : haxe.Json.parse(r.body);
	}

	static function textOrFile(name:String, v:String):String
		return v.trim().startsWith("{") || v.indexOf("-----BEGIN") >= 0 ? v : FileSystem.exists(v) ? File.getContent(v) : throw '$name: $v: no such file';

	// ---- Google Play

	static function serviceAccount(e:Entry):Dynamic {
		var v = Sys.getEnv("HELDER_PLAY_SERVICE_ACCOUNT"), name = "HELDER_PLAY_SERVICE_ACCOUNT";
		if (v == null || v.trim() == "") {
			var m:Dynamic = e.config?.android?.serviceAccount;
			if (m == null) throw 'Google Play takes a service account\'s JSON key: HELDER_PLAY_SERVICE_ACCOUNT (its path or text), or "helder": {"android": {"serviceAccount"}}';
			v = Path.isAbsolute(m) || e.root == "." ? m : '${e.root}/$m';
			name = '"helder": {"android": {"serviceAccount"}}';
		}
		var j:Dynamic = try haxe.Json.parse(textOrFile(name, v)) catch (err:String) throw err catch (err:Dynamic) throw '$name: not JSON ($err)';
		if (j.client_email == null || j.private_key == null) throw '$name: not a service account\'s key (client_email, private_key)';
		return j;
	}

	// the service account's access token (RFC 7523: a JWT bearer grant)
	@:coroutine public static function googleToken(sa:Dynamic):String {
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
		var api = (Sys.getEnv("HELDER_PLAY_API") ?? "").trim();
		if (api == "") api = PLAY;
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
		json("POST", '$base/edits/$edit:commit', token);
		Term.out(Style.status("published", Ok, '$pkg versionCode $code on $track ($status)'));
	}

	// ---- App Store Connect

	static function ascKey():{id:String, issuer:String, key:PrivateKey} {
		var id = Sys.getEnv("HELDER_ASC_KEY_ID"), issuer = Sys.getEnv("HELDER_ASC_ISSUER_ID"), key = Sys.getEnv("HELDER_ASC_KEY");
		var missing = [for (n => v in ["HELDER_ASC_KEY_ID" => id, "HELDER_ASC_ISSUER_ID" => issuer, "HELDER_ASC_KEY" => key]) if (v == null || v.trim() == "") n];
		missing.sort(Reflect.compare);
		if (missing.length > 0) throw 'App Store Connect takes an API key: ${missing.join(", ")} not given (the key\'s id, its issuer id, the .p8)';
		var k = try PrivateKey.fromPem(textOrFile("HELDER_ASC_KEY", key)) catch (err:String) throw 'HELDER_ASC_KEY: $err';
		if (k.ec == null) throw "HELDER_ASC_KEY: not an App Store Connect key (a P-256 .p8)";
		return {id: id.trim(), issuer: issuer.trim(), key: k};
	}

	public static function ascToken(k:{id:String, issuer:String, key:PrivateKey}):String {
		var now = Std.int(Date.now().getTime() / 1000);
		return Jwt.sign({alg: "ES256", kid: k.id, typ: "JWT"}, {iss: k.issuer, iat: now, exp: now + 1200, aud: "appstoreconnect-v1"}, k.key);
	}

	@:coroutine public static function toTestFlight(ipa:String, bundleId:String, version:String, build:String, dry:Bool, k:{id:String, issuer:String, key:PrivateKey}) {
		var api = (Sys.getEnv("HELDER_ASC_API") ?? "").trim();
		if (api == "") api = ASC;
		var token = ascToken(k);
		var apps:Array<Dynamic> = json("GET", '$api/v1/apps?filter%5BbundleId%5D=' + StringTools.urlEncode(bundleId), token).data;
		if (apps == null || apps.length == 0) throw 'App Store Connect has no app $bundleId (make its record first: My Apps, +, New App)';
		var app:String = apps[0].id;
		var size = FileSystem.stat(ipa).size;
		if (dry) {
			Term.out(Style.status("dry run", Info, '$bundleId is app $app on App Store Connect'));
			Term.out(Style.status("would", Info, 'upload ${Path.withoutDirectory(ipa)} ($version ($build), ${Math.round(size / 1024)} KB) for TestFlight'));
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
	}
}
