package helder.cli;

import haxe.io.Bytes;
import haxe.io.Path;
import helder.async.*;
import helder.pack.X509;
import helder.pack.apple.Identity;
import helder.pack.apple.Rsa;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `helder setup ios|android [entry] [-o <dir>] [--github]`: what a store
// needs before helder publish can send it anything, done through its API,
// so that what is left by hand is what the stores have no API for (the
// app's record: App Store Connect's New App, Play Console's Create app;
// the service account's invitation in Play Console). The secrets are
// written under -o (default: ~/.helder/<app>/apple or /android, never the
// project's own directory), never printed, never overwritten: a second
// run keeps them and goes on from them. The `gh secret set` lines that
// put them in the repository's secrets are printed, or run with --github.
//
// - ios (the App Store Connect API key: HELDER_ASC_API_KEY, or
//   HELDER_ASC_KEY_ID, HELDER_ASC_ISSUER_ID, HELDER_ASC_KEY, as Publish
//   reads it): the App ID (bundleIds; made when missing), the app's record
//   (looked up: Apple has no API to make one), an Apple Distribution
//   certificate (an RSA key made here, its request sent to
//   POST /v1/certificates) written as identity.pem with Apple's WWDR
//   intermediate and the key (HELDER_IOS_IDENTITY), its App Store profile
//   (made when none is active for it), the API key as one JSON
//   (asc-api-key.json: HELDER_ASC_API_KEY).
// - android: Play's upload key and its self-signed certificate (RSA 2048,
//   30 years) as upload-identity.pem (HELDER_ANDROID_UPLOAD_IDENTITY), the
//   certificate alone beside it, its SHA-1 and SHA-256 fingerprints; with a
//   service account (HELDER_PLAY_SERVICE_ACCOUNT, as Publish reads it) an
//   edit of the package opened and deleted, and what to fix when Google
//   refuses (Advice).
class Setup {
	@:coroutine public static function run(o:Options):Int {
		var platform = o.positionals[0];
		var e = try Entry.resolve(o.positionals[1]) catch (err:Dynamic) {
			Term.err(Style.usage('helder setup: $err'));
			return 2;
		}
		var name = slug(e.config?.name ?? e.name);
		var dir = o.out ?? '${home()}/.helder/$name/${platform == "ios" ? "apple" : "android"}';
		dir = dir.replace("\\", "/");
		if (inside(dir, e.root)) {
			Term.err(Style.usage('helder setup: $dir is inside the project (${e.root}): its keys go elsewhere (-o, default ~/.helder/$name)'));
			return 2;
		}
		Term.out(Style.header("setup", [platform == "ios" ? "App Store Connect" : "Google Play", e.main]));
		try {
			TestCommand.mkdirs(dir);
			var r = platform == "ios" ? ios(e, dir) : android(e, dir);
			Term.out("");
			Term.out(Style.status("secrets", Info, "in GitHub (values not shown; from the files):"));
			for (s in r.secrets) Term.out('  gh secret set ${s.name} < ${quote(s.file.replace("\\", "/"))}');
			if (o.has("github")) github(r.secrets);
			if (r.todo.length > 0) {
				Term.out("");
				Term.out(Style.status("by hand", Warn, "what the store has no API for:"));
				for (t in r.todo) Term.out('  - $t');
			}
			return r.failed == true ? 1 : 0;
		} catch (err:Dynamic) {
			Term.err(Style.status("error", Fail, Std.string(err)));
			return 1;
		}
	}

	// (whether dir is root or under it: their full paths, Windows' case aside)
	public static function inside(dir:String, root:String):Bool {
		function full(p:String):String {
			p = p.replace("\\", "/");
			if (!Path.isAbsolute(p)) p = Path.removeTrailingSlashes(Sys.getCwd().replace("\\", "/")) + "/" + p;
			p = Path.removeTrailingSlashes(Path.normalize(p));
			return Sys.systemName() == "Windows" ? p.toLowerCase() : p;
		}
		var d = full(dir), r = full(root);
		return d == r || d.startsWith(r + "/");
	}

	static function home():String
		return (Sys.getEnv("HOME") ?? Sys.getEnv("USERPROFILE") ?? ".").replace("\\", "/");

	public static function slug(s:String):String {
		var r = ~/[^a-z0-9]+/g.replace(s.toLowerCase(), "-");
		while (r.startsWith("-")) r = r.substr(1);
		while (r.endsWith("-")) r = r.substr(0, r.length - 1);
		return r == "" ? "app" : r;
	}

	static function quote(p:String):String
		return ~/^[A-Za-z0-9_\/.:~-]+$/.match(p) ? p : '"$p"';

	// (a secret's file, kept to its owner where that means something)
	@:coroutine static function save(path:String, text:String) {
		if (FileSystem.exists(path)) throw '$path exists: not overwritten';
		File.saveContent(path, text);
		if (Sys.systemName() != "Windows") Devices.output("chmod", ["600", path]);
	}

	// ---- iOS

	@:coroutine static function ios(e:Entry, dir:String):{secrets:Array<Secret>, todo:Array<String>, ?failed:Bool} {
		var k = Publish.ascKey(), api = Publish.ascApi();
		var i = App.ios(e.name, e.config);
		var bundleId = i.id, label:String = i.label;
		var todo = [];
		inline function token()
			return Publish.ascToken(k);

		// (the App ID)
		var ids:Array<Dynamic> = Publish.json("GET", '$api/v1/bundleIds?filter%5Bidentifier%5D=' + StringTools.urlEncode(bundleId), token()).data ?? [];
		var bid:Dynamic = Lambda.find(ids, b -> b.attributes?.identifier == bundleId);
		if (bid == null) {
			bid = Publish.json("POST", '$api/v1/bundleIds', token(), {
				data: {type: "bundleIds", attributes: {identifier: bundleId, name: label, platform: "IOS"}}
			}, 201).data;
			Term.out(Style.status("App ID", Ok, '$bundleId made'));
		} else Term.out(Style.status("App ID", Ok, '$bundleId'));

		// (the app's record: only looked up)
		var apps:Array<Dynamic> = Publish.json("GET", '$api/v1/apps?filter%5BbundleId%5D=' + StringTools.urlEncode(bundleId), token()).data ?? [];
		if (apps.length == 0) {
			Term.out(Style.status("app", Warn, 'App Store Connect has no app for $bundleId'));
			todo.push('the app\'s record in App Store Connect (Apple has no API to make one): Apps, +, New App: iOS, the name, bundle id $bundleId, a SKU; then helder setup ios again');
		} else Term.out(Style.status("app", Ok, '${apps[0].attributes?.name ?? label} (${apps[0].id})'));

		// (the distribution certificate: identity.pem's, else made)
		var file = '$dir/identity.pem';
		var certs:Array<Dynamic> = Publish.json("GET", '$api/v1/certificates?filter%5BcertificateType%5D=DISTRIBUTION,IOS_DISTRIBUTION&limit=200', token()).data ?? [];
		var id:Identity, certId:String;
		if (FileSystem.exists(file)) {
			id = try Identity.fromPem(File.getContent(file), File.getContent(file)) catch (err:String) throw '$file: $err';
			var on:Dynamic = Lambda.find(certs, c -> c.attributes?.certificateContent != null
				&& haxe.crypto.Base64.decode(c.attributes.certificateContent).compare(id.leaf.der) == 0);
			if (on == null)
				throw '$file: its certificate (${id.leaf.commonName}) is not among App Store Connect\'s distribution certificates (revoked, or expired): move the file away for a new one';
			certId = on.id;
			Term.out(Style.status("certificate", Ok, '${id.leaf.commonName}: kept ($file)'));
		} else {
			Term.spin("making an RSA key (2048 bits)");
			var key = Rsa.generate(2048);
			Term.done();
			var csr = X509.request(key, X509.name([{type: "CN", value: '$label Distribution'}]));
			var r = Publish.http("POST", '$api/v1/certificates', ["Authorization: Bearer " + token(), "Content-Type: application/json"], Bytes.ofString(haxe.Json.stringify({
				data: {type: "certificates", attributes: {certificateType: "DISTRIBUTION", csrContent: haxe.crypto.Base64.encode(csr)}}
			})));
			if (r.code == 409 || (r.code == 403 && r.body.indexOf("maximum") >= 0))
				throw 'App Store Connect makes no more distribution certificates (${certs.length} already: ${[for (c in certs) c.attributes?.name].join(", ")}): revoke one (Certificates, Identifiers & Profiles), or bring its identity as $file (cert, chain, key: openssl pkcs12 -nodes); HTTP ${r.code} ${r.body.trim()}';
			if (r.code != 201) throw 'POST /v1/certificates: HTTP ${r.code} ${r.body.trim()}';
			var made:Dynamic = haxe.Json.parse(r.body).data;
			certId = made.id;
			var der = haxe.crypto.Base64.decode(made.attributes.certificateContent);
			var keyPem = X509.pem("PRIVATE KEY", X509.privateKey(key));
			id = try Identity.fromPem(X509.pem("CERTIFICATE", der), keyPem) catch (err:String) throw 'App Store Connect\'s certificate: $err';
			save(file, [for (c in id.chain) X509.pem("CERTIFICATE", c.der)].join("") + keyPem);
			var expires:String = made.attributes.expirationDate ?? "";
			Term.out(Style.status("certificate", Ok, '${id.leaf.commonName} made${expires == "" ? "" : ", expires " + expires.substr(0, 10)}: ${Style.path(file)}'));
			if (!id.complete()) Term.out(Style.status("chain", Warn, 'no Apple intermediate known for its issuer: identity.pem has the certificate alone'));
		}

		// (its App Store profile)
		var now = Date.now();
		Publish.profile(bundleId, id.leaf.der, k, {certificate: certId, name: '$label App Store ${DateTools.format(now, "%Y-%m-%d")}'});

		// (the API key, as one JSON: the file it is in already, else written)
		var given = Sys.getEnv("HELDER_ASC_API_KEY");
		var keyFile = given != null && !given.trim().startsWith("{") && FileSystem.exists(given.trim()) ? given.trim() : '$dir/asc-api-key.json';
		if (!FileSystem.exists(keyFile)) {
			var t = Publish.ascKeyText();
			save(keyFile, haxe.Json.stringify({key_id: t.id, issuer_id: t.issuer, private_key: t.pem}, null, "  ") + "\n");
			Term.out(Style.status("API key", Ok, Style.path(keyFile)));
		}
		return {secrets: [{name: "HELDER_IOS_IDENTITY", file: file}, {name: "HELDER_ASC_API_KEY", file: keyFile}], todo: todo};
	}

	// ---- Android

	@:coroutine static function android(e:Entry, dir:String):{secrets:Array<Secret>, todo:Array<String>, ?failed:Bool} {
		var a = App.android(e.name, e.config);
		var label:String = a.label, pkg:String = a.id;
		var todo = [], failed = false;
		var file = '$dir/upload-identity.pem';
		var cert:Certificate;
		if (FileSystem.exists(file)) {
			var id = try Identity.fromPem(File.getContent(file), File.getContent(file)) catch (err:String) throw '$file: $err';
			cert = id.leaf;
			Term.out(Style.status("upload key", Ok, 'kept (${Style.path(file)})'));
		} else {
			Term.spin("making an RSA key (2048 bits)");
			var key = Rsa.generate(2048);
			Term.done();
			var serial = helder.pack.Entropy.bytes(16);
			serial.set(0, serial.get(0) & 0x7f);
			var der = X509.selfSigned(key, X509.name([{type: "CN", value: '$label upload key'}, {type: "O", value: label}]), serial, Date.now(), 30);
			save(file, X509.pem("CERTIFICATE", der) + X509.pem("PRIVATE KEY", X509.privateKey(key)));
			cert = Certificate.parse(der);
			var pub = '$dir/upload-certificate.pem';
			if (!FileSystem.exists(pub)) File.saveContent(pub, X509.pem("CERTIFICATE", der));
			Term.out(Style.status("upload key", Ok, '${cert.commonName}, 30 years: ${Style.path(file)} (the certificate alone: ${Style.path(pub)})'));
		}
		Term.out(Style.status("SHA-1", Info, X509.fingerprint(cert.der, false)));
		Term.out(Style.status("SHA-256", Info, X509.fingerprint(cert.der, true)));
		var secrets = [{name: "HELDER_ANDROID_UPLOAD_IDENTITY", file: file}];

		// (the service account, when one is given: an edit opened and deleted)
		var sa:Dynamic = try Publish.serviceAccount(e) catch (err:Dynamic) null;
		if (sa == null) {
			Term.out(Style.status("service account", Info, 'none given (HELDER_PLAY_SERVICE_ACCOUNT): not checked'));
			todo.push('a service account for helder publish --play: Google Cloud console, IAM, Service accounts, a JSON key; then helder setup android with HELDER_PLAY_SERVICE_ACCOUNT');
		} else {
			var who:String = sa.client_email ?? "the access token";
			var token = try Publish.googleToken(sa) catch (err:Dynamic) throw '$who: $err (${Advice.TOKEN})';
			var base = '${Publish.playApi()}/androidpublisher/v3/applications/$pkg';
			var r = Publish.http("POST", '$base/edits', ["Authorization: Bearer " + token, "Content-Type: application/json"], Bytes.ofString("{}"));
			if (r.code == 200) {
				var edit:String = haxe.Json.parse(r.body).id;
				Publish.json("DELETE", '$base/edits/$edit', token);
				Term.out(Style.status("service account", Ok, '$who opens $pkg\'s edits (one opened and deleted)'));
			} else {
				var fix = Advice.play(r.code, r.body, who, pkg, sa.project_id);
				Term.out(Style.status("service account", Fail, '$pkg: HTTP ${r.code}'));
				todo.push(fix);
				failed = true;
			}
			var v = Sys.getEnv("HELDER_PLAY_SERVICE_ACCOUNT");
			if (v != null && !v.trim().startsWith("{") && FileSystem.exists(v.trim())) secrets.push({name: "HELDER_PLAY_SERVICE_ACCOUNT", file: v.trim()});
		}
		todo.push('Play App Signing: upload the first bundle signed with this key (helder publish --play --draft) to make it the upload key; an app that has one already: Play Console, Test and release, App integrity, request an upload key reset with $dir/upload-certificate.pem');
		return {secrets: secrets, todo: todo, failed: failed};
	}

	// ---- GitHub: gh secret set, each value from its file on standard input

	@:coroutine static function github(secrets:Array<Secret>) {
		if (Devices.output("gh", ["--version"]).code != 0) {
			Term.out(Style.status("github", Warn, "gh is not installed: run the lines above"));
			return;
		}
		var repo = Devices.output("gh", ["repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]);
		if (repo.code != 0) {
			Term.out(Style.status("github", Warn, 'not a GitHub repository here (gh repo view: ${repo.errors.trim()}): run the lines above'));
			return;
		}
		for (s in secrets) {
			var p = new Process("gh", ["secret", "set", s.name]);
			var b = File.getBytes(s.file);
			Async.scope(task -> {
				task.async(_ -> BuildCommand.Lines.collect(p.stdout, []));
				task.async(_ -> BuildCommand.Lines.collect(p.stderr, []));
				p.stdin.write(b, 0, b.length);
				p.closeStdin();
				null;
			});
			var code = p.wait();
			p.close();
			if (code != 0) throw 'gh secret set ${s.name}: exit code $code';
			Term.out(Style.status("github", Ok, '${s.name} set on ${repo.text.trim()}'));
		}
	}
}

typedef Secret = {name:String, file:String};

// what to fix when Google refuses the service account (pure: tested)
class Advice {
	public static inline var TOKEN = "its key revoked, or the service account deleted? Make a new JSON key: Google Cloud console, IAM, Service accounts, Keys";

	public static function play(code:Int, body:String, who:String, pkg:String, ?project:String):String {
		var b = body.toLowerCase();
		if (code == 401) return '$who: the token is refused ($TOKEN)';
		if (code == 403 && (b.indexOf("has not been used") >= 0 || b.indexOf("service_disabled") >= 0 || b.indexOf("is disabled") >= 0))
			return 'enable the Google Play Android Developer API for ${project == null ? "the service account's project" : project}: https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com${project == null ? "" : "?project=" + project}';
		if (code == 403)
			return 'invite $who in Play Console (Users and permissions, Invite new users) with access to $pkg: Release to testing tracks, Release to production, Manage store presence (it can take a few minutes to apply)';
		if (code == 404) return 'Play Console has no app $pkg: make it there (Create app; Google has no API for it), then helder setup android again';
		return '$pkg: Google Play answered HTTP $code ${body.trim()}';
	}
}
