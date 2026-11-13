package helder.cli;

import haxe.io.Bytes;
import haxe.io.Path;
import helder.async.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// helder.run from the command line: `helder publish --run` (a named
// project, <run.name>.helder.run, its owner's: helder login's token, or in
// GitHub Actions the workflow's OIDC token), `helder share` (anonymous:
// unlisted, for a week, a random address), `helder login` and `logout`
// (GitHub's device flow through helder.build: the token helder.build makes,
// kept in helder's config directory), `helder migrate` (helder.webmanifest
// to helder.json).
//
// A release is the web build (bin/run/<name>: helder build --target web's
// files, the page left out: helder.run renders its own from the page's
// values, Page.written), the icon at 512 px and the screenshots under
// _helder/. Uploaded as helder.build's API takes it: POST /api/publish
// (what the release is, each file's path, SHA-256 and size) answers the
// blobs it does not have yet; each is PUT to /api/blob/<sha256>; POST
// /api/publish/<release>/commit makes it current. helder.build checks the
// module's imports and that every script is helder's runtime (a runtime
// changed here is refused). HELDER_API: another helder.build (a local one).
class Run {
	public static inline var API = "https://helder.build";
	// (as helder.build refuses: a file, a release)
	static inline var MAX_FILE = 25 * 1024 * 1024;
	static inline var MAX_RELEASE = 100 * 1024 * 1024;

	static function api():String {
		var a = Sys.getEnv("HELDER_API");
		return a != null && a.trim() != "" ? ~/\/+$/.replace(a.trim(), "") : API;
	}

	// ---- publish and share

	@:coroutine public static function publish(o:Options):Int
		return release(o, false);

	@:coroutine public static function share(o:Options):Int
		return release(o, true);

	@:coroutine static function release(o:Options, anonymous:Bool):Int {
		var command = anonymous ? "share" : "publish";
		var e = try Entry.resolve(o.entry, "web") catch (err:Dynamic) {
			Term.err(Style.usage('helder $command: $err'));
			return 2;
		}
		var cfg:Manifest.AppConfig = e.config ?? {};
		var run = cfg.run;
		if (!anonymous && run == null) {
			Term.err(Style.usage('helder publish --run: helder.json has no run block (its address: {"run": {"name": "my-app"}}; helder share needs none)'));
			return 2;
		}
		var name = anonymous ? null : run.name ?? HelderJson.slug(cfg.name ?? e.name);
		if (name != null) {
			var why = HelderJson.nameProblem(name);
			if (why != null) {
				Term.err(Style.usage('helder publish --run: the address "$name" $why (helder.json: run.name)'));
				return 2;
			}
		}
		var dry = o.has("dry-run");
		var auth:Null<String> = null;
		if (!anonymous && !dry) {
			auth = try token() catch (err:Dynamic) {
				Term.err(Style.status("error", Fail, Std.string(err)));
				return 1;
			}
			if (auth == null) {
				Term.err(Style.usage("helder publish --run: not signed in: helder login (in GitHub Actions: permissions: id-token: write); helder share needs no account"));
				return 2;
			}
		}
		if (e.typescript != null) try Compiler.typescript(e.helder) catch (err:Dynamic) {
			Term.err(Style.status("error", Fail, Std.string(err)));
			return 1;
		}
		Term.out(Style.header(command, ["helder.run", anonymous ? "anonymous" : '$name.helder.run', e.label()]));
		var dir = Entry.clean('${e.root}/bin/run/${e.name}');
		try {
			if (FileSystem.exists(dir)) remove(dir);
			TestCommand.mkdirs(dir);
			var wasm = '$dir/${e.name}.wasm';
			if (!BuildCommand.build(e, wasm, Release).ok) return 1;
			Page.write(e.helder, wasm, e.name, e.manifest == null ? null : {file: e.manifest, cfg: e.config, root: e.root});
			var page = Page.written;
			// (what helder.run makes itself, or refuses: the page, the web manifest)
			for (f in FileSystem.readDirectory(dir)) if (f.endsWith(".html") || f == Manifest.FILE) FileSystem.deleteFile('$dir/$f');
			TestCommand.mkdirs('$dir/_helder');
			var icon = new Icons(cfg, e.root).png(["any", "maskable"], 512, 1, null, "helder.run's icon");
			if (icon != null) File.saveBytes('$dir/_helder/icon.png', icon);
			var shots = screenshots(o, e, run, dir);
			var files = list(dir, "");
			var total = 0;
			for (f in files) {
				if (f.size > MAX_FILE) throw '${f.path}: ${mb(f.size)}: helder.run takes files of 25 MB at most';
				total += f.size;
			}
			if (total > (anonymous ? MAX_FILE : MAX_RELEASE)) throw 'the release is ${mb(total)}: helder.run takes ${anonymous ? "25 MB for a share" : "100 MB"} at most';
			var meta = {
				name: name,
				title: cfg.name ?? e.name,
				label: cfg.label,
				description: cfg.description,
				version: cfg.versionName,
				kind: run?.kind,
				tags: run?.tags ?? [],
				listed: run?.listed == true,
				source: run?.source,
				theme: cfg.theme == null ? null : Page.css(cfg.theme),
				background: cfg.background == null ? null : Page.css(cfg.background),
				orientation: cfg.orientation,
				fullscreen: cfg.fullscreen == true,
				icon: icon == null ? null : "_helder/icon.png",
				screenshots: shots,
				stores: cfg.stores ?? {},
				page: page,
				helder: helderVersion(e)
			};
			Term.out(Style.status("release", Info, '${files.length} files, ${mb(total)}' + Style.dim(Style.sep() + dir)));
			if (dry) {
				Term.out(haxe.Json.stringify(meta, null, "  "));
				for (f in files) Term.out('  ${f.path} ${mb(f.size)}');
				Term.out(Style.status("dry run", Info, "nothing uploaded"));
				return 0;
			}
			var start = call("POST", "/api/publish", auth, {anonymous: anonymous, meta: meta, files: [for (f in files) {path: f.path, sha256: f.sha256, size: f.size}]});
			var missing:Array<String> = start.missing ?? [];
			var upload:String = start.uploadToken;
			var sent = 0;
			for (f in files) if (missing.contains(f.sha256)) {
				missing.remove(f.sha256);
				Term.spin('uploading ${f.path}');
				var r = Publish.http("PUT", api() + '/api/blob/${f.sha256}', ["Authorization: Bearer " + upload, "Content-Type: application/octet-stream"], null,
					{path: '$dir/${f.path}', offset: 0, length: f.size});
				Term.done();
				if (r.code != 200 && r.code != 201) throw 'PUT /api/blob/${f.sha256} (${f.path}): HTTP ${r.code} ${message(r.body)}';
				sent += f.size;
			}
			var done = call("POST", '/api/publish/${start.release}/commit', upload, {});
			Term.out(Style.status("uploaded", Info, mb(sent) + Style.dim(Style.sep() + 'the rest helder.run had')));
			Term.out(Style.status(anonymous ? "shared" : "published", Ok, '${done.url}' + (done.version != null ? Style.dim(Style.sep() + 'v${done.version}') : "")));
			// (the page about it: helder.build/<name>)
			if (done.page != null) Term.out(Style.status("page", Info, '${done.page}'));
			if (done.expires != null) Term.out(Style.status("expires", Info, '${done.expires}' + Style.dim(Style.sep() + "a share lasts a week")));
			if (done.listed == false && !anonymous && run?.listed == true) Term.out(Style.status("listing", Info, Std.string(done.listing ?? "not listed yet")));
			return 0;
		} catch (err:Dynamic) {
			Term.err(Style.status("error", Fail, Std.string(err)));
			return 1;
		}
	}

	// the release's screenshots under _helder/: helder.json's run.screenshots,
	// else one of the program taken headless (a phone's size when it is a
	// portrait one), else none
	@:coroutine static function screenshots(o:Options, e:Entry, run:Null<HelderJson.RunConfig>, dir:String):Array<String> {
		var named = run?.screenshots;
		if (named != null) return [
			for (k => s in named) {
				var from = e.root == "." ? s : '${e.root}/$s';
				if (!FileSystem.exists(from)) throw 'helder.json: run.screenshots[$k]: $s: no such file';
				var to = '_helder/shot-${k + 1}.${Path.extension(s).toLowerCase()}';
				File.copy(from, '$dir/$to');
				to;
			}
		];
		if (o.has("no-screenshot")) return [];
		var portrait = (e.config?.orientation : Null<String>) == "portrait";
		var file = '$dir/_helder/shot-1.png';
		try {
			var h = Options.parse("run", [o.entry ?? ".", "--headless", "--snap", file, "--at", "2", "--size", portrait ? "390x844" : "1280x800"].concat(portrait ? ["--scale", "2"] : []));
			// (as the web page has it: no window buttons drawn)
			Sys.putEnv("HELDER_CONTROLS", "none");
			if (HeadlessCommand.run(h, Entry.of(h)) == 0 && FileSystem.exists(file)) return ["_helder/shot-1.png"];
		} catch (err:Dynamic) {}
		Term.err(Style.status("warning", Warn, "no screenshot of the program (its page shows its icon): name some in helder.json's run.screenshots"));
		return [];
	}

	// the files under dir, sorted, with their SHA-256
	static function list(dir:String, at:String):Array<{path:String, sha256:String, size:Int}> {
		var out = [];
		var names = FileSystem.readDirectory(at == "" ? dir : '$dir/$at');
		names.sort(Reflect.compare);
		for (n in names) {
			var rel = at == "" ? n : '$at/$n', full = '$dir/$rel';
			if (FileSystem.isDirectory(full)) out = out.concat(list(dir, rel));
			else {
				var b = File.getBytes(full);
				out.push({path: rel, sha256: haxe.crypto.Sha256.make(b).toHex(), size: b.length});
			}
		}
		return out;
	}

	// helder's version the build used (its package.json's), its runtime's
	static function helderVersion(e:Entry):Null<String> {
		var pj = Path.directory(e.helder) + "/package.json";
		var j:Dynamic = try haxe.Json.parse(File.getContent(pj)) catch (_:Dynamic) null;
		return j?.version;
	}

	// ---- helder.build's API

	@:coroutine static function call(method:String, path:String, bearer:Null<String>, body:Dynamic):Dynamic {
		var headers = ["Content-Type: application/json", "Accept: application/json"];
		if (bearer != null) headers.push("Authorization: Bearer " + bearer);
		var r = Publish.http(method, api() + path, headers, Bytes.ofString(haxe.Json.stringify(body)));
		if (r.code < 200 || r.code >= 300) throw '$method $path: HTTP ${r.code} ${message(r.body)}';
		return r.body.trim() == "" ? {} : haxe.Json.parse(r.body);
	}

	// an API error's message (its JSON's "error"), else the body
	static function message(body:String):String {
		var j:Dynamic = try haxe.Json.parse(body) catch (_:Dynamic) null;
		return j?.error != null ? Std.string(j.error) : body.trim().substr(0, 400);
	}

	// the credential to publish with: HELDER_TOKEN, else in GitHub Actions
	// the workflow's OIDC token for helder.build, else helder login's; null: none
	@:coroutine static function token():Null<String> {
		var env = Sys.getEnv("HELDER_TOKEN");
		if (env != null && env.trim() != "") return env.trim();
		var url = Sys.getEnv("ACTIONS_ID_TOKEN_REQUEST_URL"), req = Sys.getEnv("ACTIONS_ID_TOKEN_REQUEST_TOKEN");
		if (url != null && url != "" && req != null && req != "") {
			var r = Publish.http("GET", url + (url.contains("?") ? "&" : "?") + "audience=helder.build", ["Authorization: bearer " + req]);
			if (r.code != 200) throw 'GitHub Actions\' OIDC token: HTTP ${r.code} ${r.body.trim()}';
			return haxe.Json.parse(r.body).value;
		}
		var c = credentials();
		return c?.token;
	}

	// ---- login

	// where helder keeps its credentials: %APPDATA%\helder, else $XDG_CONFIG_HOME/helder, ~/.config/helder
	static function configDir():String {
		var appdata = Sys.getEnv("APPDATA");
		if (Sys.systemName() == "Windows" && appdata != null) return appdata.split("\\").join("/") + "/helder";
		var xdg = Sys.getEnv("XDG_CONFIG_HOME");
		return (xdg != null && xdg != "" ? xdg : (Sys.getEnv("HOME") ?? ".") + "/.config") + "/helder";
	}

	static function credentialsFile():String
		return configDir() + "/credentials.json";

	static function credentials():Null<{token:String, login:String, api:String}> {
		var j:Dynamic = try haxe.Json.parse(File.getContent(credentialsFile())) catch (_:Dynamic) null;
		var c:Dynamic = j == null ? null : Reflect.field(j, api());
		return c == null || c.token == null ? null : {token: c.token, login: c.login, api: api()};
	}

	// GitHub's device flow, through helder.build: the code shown, the page
	// opened, polled until signed in; helder.build's token kept
	@:coroutine public static function login():Int {
		try {
			var d = call("POST", "/api/login/device", null, {});
			Term.out(Style.status("sign in", Info, 'open ${d.verificationUri} and enter ${d.userCode}'));
			open(d.verificationUri);
			var interval:Float = d.interval ?? 5, until = haxe.Timer.stamp() + (d.expiresIn ?? 900);
			Term.spin("waiting for GitHub");
			while (haxe.Timer.stamp() < until) {
				Async.delay(interval);
				var r = call("POST", '/api/login/device/${d.id}', null, {});
				if (r.slowDown == true) interval += 5;
				if (r.token == null) continue;
				Term.done();
				var file = credentialsFile();
				var all:Dynamic = try haxe.Json.parse(File.getContent(file)) catch (_:Dynamic) {};
				Reflect.setField(all, api(), {token: r.token, login: r.login});
				TestCommand.mkdirs(configDir());
				File.saveContent(file, haxe.Json.stringify(all, null, "  "));
				if (Sys.systemName() != "Windows") Devices.output("chmod", ["600", file]);
				Term.out(Style.status("signed in", Ok, '${r.login}' + Style.dim(Style.sep() + file)));
				return 0;
			}
			Term.done();
			throw "the code expired: helder login again";
		} catch (err:Dynamic) {
			Term.err(Style.status("error", Fail, Std.string(err)));
			return 1;
		}
	}

	public static function logout():Int {
		var file = credentialsFile();
		var all:Dynamic = try haxe.Json.parse(File.getContent(file)) catch (_:Dynamic) null;
		if (all == null || Reflect.field(all, api()) == null) {
			Term.out(Style.status("signed out", Info, "no token kept for " + api()));
			return 0;
		}
		Reflect.deleteField(all, api());
		File.saveContent(file, haxe.Json.stringify(all, null, "  "));
		Term.out(Style.status("signed out", Ok, 'the token for ${api()} forgotten (helder.build\'s settings revoke it)'));
		return 0;
	}

	@:coroutine static function open(url:String) {
		try switch Sys.systemName() {
			case "Windows": Devices.output("cmd", ["/c", "start", "", url]);
			case "Mac": Devices.output("open", [url]);
			case _: Devices.output("xdg-open", [url]);
		} catch (_:Dynamic) {}
	}

	// ---- migrate

	public static function migrate(dir:String):Int {
		var from = dir == "." ? Manifest.FILE : '$dir/${Manifest.FILE}', to = dir == "." ? HelderJson.FILE : '$dir/${HelderJson.FILE}';
		if (FileSystem.exists(to)) {
			Term.err(Style.usage('helder migrate: $to is there already'));
			return 2;
		}
		if (!FileSystem.exists(from)) {
			Term.err(Style.usage('helder migrate: no $from to migrate'));
			return 2;
		}
		try {
			var text = HelderJson.fromManifest(File.getContent(from));
			HelderJson.parse(text);
			File.saveContent(to, text);
			FileSystem.deleteFile(from);
			Term.out(Style.status("migrated", Ok, '$from → $to'));
			return 0;
		} catch (err:Dynamic) {
			Term.err(Style.status("error", Fail, Std.string(err)));
			return 1;
		}
	}

	// ---- helpers

	static function remove(dir:String) {
		for (f in FileSystem.readDirectory(dir)) {
			var p = '$dir/$f';
			if (FileSystem.isDirectory(p)) remove(p) else FileSystem.deleteFile(p);
		}
		FileSystem.deleteDirectory(dir);
	}

	static function mb(n:Int):String
		return n < 1024 * 1024 ? '${Math.round(n / 102.4) / 10} KB' : '${Math.round(n / 104857.6) / 10} MB';
}
