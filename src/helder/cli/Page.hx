package helder.cli;

import haxe.io.Bytes;
import helder.asset.AssetPath;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The page a wasm32-wasi build runs in (page.html): helder.os's browser.mjs
// and the browser modules (src/helder/<package>/imports.mjs) of the
// packages the module imports (an imports.mjs naming one of its import
// modules: hxmc_gfx, helder_async, ...), DejaVu Sans when it uses
// helder.text and this machine has it, and the fonts among the program's
// assets (Asset.font's: the page's fonts too, there from the first frame,
// before the program's loads finish). `helder dev` serves it with the dev
// client; `helder build web` writes it beside the module, with the modules
// and fonts it names (the program's assets are beside it already:
// helder.asset's Bundle).
class Page {
	static final FONT_DIRS = ["/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/TTF", "/usr/share/fonts/dejavu", "/Library/Fonts", "C:/Windows/Fonts"];

	// the packages whose imports.mjs the module needs (os, gfx, ...)
	public static function packages(helder:String, wasm:String):Array<String> {
		var names = importModules(File.getBytes(wasm));
		var out = [];
		var dirs = FileSystem.readDirectory('$helder/helder');
		dirs.sort(Reflect.compare);
		for (d in dirs) {
			var f = '$helder/helder/$d/imports.mjs';
			if (!FileSystem.exists(f)) continue;
			var s = File.getContent(f);
			if (Lambda.exists(names, n -> new EReg("\\b" + n + "\\b", "").match(s))) out.push(d);
		}
		return out;
	}

	// the fonts the page gives the program (helder.text has no system fonts in a browser)
	public static function fonts(packages:Array<String>):Array<String> {
		if (!packages.contains("text")) return [];
		var out = [];
		for (f in ["DejaVuSans.ttf", "DejaVuSans-Bold.ttf"])
			for (d in FONT_DIRS) if (FileSystem.exists('$d/$f')) {
				out.push('$d/$f');
				break;
			}
		return out;
	}

	// the keys of the program's assets that are fonts (by their extension)
	public static function assetFonts(wasm:String):Array<String> {
		var out = [for (a in AssetStep.assets(wasm)) if (~/\.(ttf|otf|ttc)$/i.match(a.key)) a.key];
		out.sort(Reflect.compare);
		return out;
	}

	// the page: base is where browser.mjs (base/os/browser.mjs) and the imports are, fonts their URLs
	// (assets: the URL of the module's assets.json, the files read before
	// main, which browser.mjs fetches; null: none)
	// (app: the manifest's tags, style and splash, Page.app's)
	public static function html(title:String, wasm:String, base:String, packages:Array<String>, fonts:Array<String>, dev:Bool, ?assets:String,
			?app:PageApp):String {
		var imports = [for (p in packages) '$base$p/imports.mjs'];
		var browser = '${base}os/browser.mjs';
		return template()
			.replace("{{title}}", StringTools.htmlEscape(title))
			.replace("{{head}}", app?.head ?? "")
			.replace("{{style}}", app?.style ?? "")
			.replace("{{splash}}", app?.splash ?? "")
			.replace("{{preload}}", [for (u in imports.concat([browser])) '<link rel="modulepreload" href="$u">'].join("\n"))
			.replace("{{wasm}}", wasm)
			.replace("{{browser}}", browser)
			.replace("{{fonts}}", haxe.Json.stringify(fonts))
			.replace("{{imports}}", haxe.Json.stringify(imports))
			.replace("{{dev}}", dev ? "true" : "false")
			.replace("{{assets}}", haxe.Json.stringify(assets));
	}

	// the manifest's part of the page (null: no manifest): the manifest
	// linked (base: where it and its files are), theme-color, the
	// description, the icons of any purpose as rel=icon, the
	// apple-touch-icon (touch: its URL, an opaque 180 px one the build
	// makes, null: none); the body's background the splash's (its dark one
	// for a dark scheme), and the splash image (else an icon) in the middle
	// of it until the program runs
	public static function app(cfg:Manifest.AppConfig, base:String, ?touch:String):PageApp {
		inline function attr(s:String)
			return StringTools.htmlEscape(s, true);
		var head = ['<link rel="manifest" href="${attr(base + Manifest.FILE)}">'];
		if (cfg.theme != null) head.push('<meta name="theme-color" content="${css(cfg.theme)}">');
		if (cfg.description != null) head.push('<meta name="description" content="${attr(cfg.description)}">');
		for (i in cfg.icons ?? []) if (i.purpose.contains("any")) {
			var src = Manifest.local(i.src) ? base + i.src : i.src;
			head.push('<link rel="icon" href="${attr(src)}"' + (i.sizes != null ? ' sizes="${[for (s in i.sizes) '${s}x$s'].join(" ")}"' : i.type == "image/svg+xml" ? ' sizes="any"' : "")
				+ (i.type != null ? ' type="${attr(i.type)}"' : "") + ">");
		}
		if (touch != null) head.push('<link rel="apple-touch-icon" href="${attr(touch)}">');
		var s = cfg.splash, style = [];
		if (s?.background != null) style.push('body { background: ${css(s.background)}; }');
		if (s?.darkBackground != null) style.push('@media (prefers-color-scheme: dark) { body { background: ${css(s.darkBackground)}; } }');
		var image = s?.image, dark = s?.darkImage;
		if (image == null) {
			var i = new Icons(cfg, ".", _ -> null).pick(["any", "maskable"], 160);
			if (i != null) image = i.src;
		}
		var splash = "";
		if (image != null) {
			style.push('#helder-splash { position: fixed; inset: 0; margin: auto; width: 160px; height: 160px; object-fit: contain; pointer-events: none; }');
			var src = Manifest.local(image) ? base + image : image;
			splash = dark == null ? '<img id="helder-splash" alt="" src="${attr(src)}">' : '<picture id="helder-splash-picture"><source media="(prefers-color-scheme: dark)" srcset="${attr(Manifest.local(dark) ? base + dark : dark)}"><img id="helder-splash" alt="" src="${attr(src)}"></picture>';
		}
		return {head: head.join("\n"), style: style.join("\n"), splash: splash};
	}

	// a colour as CSS's #rrggbb (#rrggbbaa when not opaque)
	public static function css(c:Int):String {
		var rgb = "#" + StringTools.hex(c & 0xFFFFFF, 6).toLowerCase();
		return (c >>> 24) == 0xFF ? rgb : rgb + StringTools.hex(c >>> 24, 2).toLowerCase();
	}

	static inline function template():String
		return PageTemplate.text();

	// the module names of a wasm module's imports
	public static function importModules(b:Bytes):Array<String> {
		var at = 8, out = [];
		function leb():Int {
			var r = 0, shift = 0;
			while (true) {
				var x = b.get(at++);
				r |= (x & 0x7f) << shift;
				shift += 7;
				if (x < 0x80) return r;
			}
		}
		function name():String {
			var n = leb();
			var s = b.getString(at, n);
			at += n;
			return s;
		}
		function limits() {
			var flags = leb();
			leb();
			if (flags & 1 != 0) leb();
		}
		while (at < b.length) {
			var id = b.get(at++), size = leb(), end = at + size;
			if (id == 2) {
				for (_ in 0...leb()) {
					var m = name();
					name();
					switch b.get(at++) {
						case 0: leb();
						case 1:
							at++;
							limits();
						case 2: limits();
						case 3: at += 2;
						case _:
							at++;
							leb();
					}
					if (!out.contains(m)) out.push(m);
				}
				return out;
			}
			at = end;
		}
		return out;
	}

	// `helder build --target web`: the page (<name>.html), browser.mjs, the
	// imports and the fonts beside the module; with the app's manifest
	// (app: its file, its config) it too as it is (helder.webmanifest), the
	// files it names at their paths, and apple-touch-icon.png (Icons.ios: 180 px)
	public static function write(helder:String, wasm:String, title:String, ?app:{file:String, cfg:Manifest.AppConfig, root:String}):Array<String> {
		var dir = haxe.io.Path.directory(wasm), name = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(wasm));
		if (dir == "") dir = ".";
		var pkgs = packages(helder, wasm), fs = fonts(pkgs);
		var files = ['$dir/$name.html'];
		for (p in pkgs.concat(["os"])) {
			TestCommand.mkdirs('$dir/helder/$p');
			for (f in (p == "os" ? ["browser.mjs", "imports.mjs"] : p == "jobs" ? ["imports.mjs", "worker.mjs"] : ["imports.mjs"])) {
				File.copy('$helder/helder/$p/$f', '$dir/helder/$p/$f');
				files.push('$dir/helder/$p/$f');
			}
		}
		var urls = [];
		if (fs.length > 0) TestCommand.mkdirs('$dir/fonts');
		for (f in fs) {
			var n = haxe.io.Path.withoutDirectory(f);
			File.copy(f, '$dir/fonts/$n');
			urls.push('fonts/$n');
		}
		for (k in assetFonts(wasm))
			urls.push(AssetPath.url(AssetPath.bundled(k)));
		if (pkgs.contains("text") && urls.length == 0)
			Term.err(Style.status("warning", Warn, 'the page has no font: DejaVu Sans is not on this machine (${FONT_DIRS.join(", ")}), and the program loads none with Asset.font'));
		// (the program's assets: helder.asset's Bundle put them in assets/ beside the module)
		var listed = FileSystem.exists('$wasm.assets.json');
		// (./: the page's module script imports browser.mjs from there, where helder/... is a bare specifier)
		var page:Null<PageApp> = null;
		if (app != null) {
			var text = File.getContent(app.file);
			File.saveContent('$dir/${Manifest.FILE}', text);
			files.push('$dir/${Manifest.FILE}');
			for (f in Manifest.files(text)) {
				var from = app.root == "." ? f : '${app.root}/$f';
				if (!FileSystem.exists(from)) throw '${Manifest.FILE}: $f: no such file';
				TestCommand.mkdirs(haxe.io.Path.directory('$dir/$f') == "" ? "." : haxe.io.Path.directory('$dir/$f'));
				File.copy(from, '$dir/$f');
				files.push('$dir/$f');
			}
			var icons = new Icons(app.cfg, app.root), touch = null;
			if (icons.has("any") || icons.has("maskable")) {
				File.saveBytes('$dir/apple-touch-icon.png', icons.ios(180));
				files.push('$dir/apple-touch-icon.png');
				touch = "apple-touch-icon.png";
			}
			page = Page.app(app.cfg, "", touch);
			if (app.cfg.name != null) title = app.cfg.name;
		}
		File.saveContent('$dir/$name.html', html(title, '$name.wasm', "./helder/", pkgs, urls, false, listed ? '$name.wasm.assets.json' : null, page));
		return files;
	}
}

typedef PageApp = {head:String, style:String, splash:String};
