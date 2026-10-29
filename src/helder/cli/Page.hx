package helder.cli;

import haxe.io.Bytes;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The page a wasm32-wasi build runs in (page.html): helder.os's browser.mjs
// and the browser modules (src/helder/<package>/imports.mjs) of the
// packages the module imports (an imports.mjs naming one of its import
// modules: hxmc_gfx, helder_async, ...), DejaVu Sans when it uses
// helder.text. `helder dev` serves it with the dev client; `helder build
// web` writes it beside the module, with the modules and fonts it names
// (the program's assets are beside it already: helder.asset's Bundle).
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

	// the page: base is where browser.mjs (base/os/browser.mjs) and the imports are, fonts their URLs
	// (assets: the URL of the module's assets.json, the files read before
	// main, which browser.mjs fetches; null: none)
	public static function html(title:String, wasm:String, base:String, packages:Array<String>, fonts:Array<String>, dev:Bool, ?assets:String):String {
		var imports = [for (p in packages) '$base$p/imports.mjs'];
		var browser = '${base}os/browser.mjs';
		return template()
			.replace("{{title}}", StringTools.htmlEscape(title))
			.replace("{{preload}}", [for (u in imports.concat([browser])) '<link rel="modulepreload" href="$u">'].join("\n"))
			.replace("{{wasm}}", wasm)
			.replace("{{browser}}", browser)
			.replace("{{fonts}}", haxe.Json.stringify(fonts))
			.replace("{{imports}}", haxe.Json.stringify(imports))
			.replace("{{dev}}", dev ? "true" : "false")
			.replace("{{assets}}", haxe.Json.stringify(assets));
	}

	static macro function template():haxe.macro.Expr
		return macro $v{sys.io.File.getContent(haxe.macro.Context.resolvePath("helder/cli/page.html"))};

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

	// `helder build --target web`: the page (<name>.html), browser.mjs, the imports and the fonts beside the module
	public static function write(helder:String, wasm:String, title:String):Array<String> {
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
		// (the program's assets: helder.asset's Bundle put them in assets/ beside the module)
		var listed = FileSystem.exists('$wasm.assets.json');
		// (./: the page's module script imports browser.mjs from there, where helder/... is a bare specifier)
		File.saveContent('$dir/$name.html', html(title, '$name.wasm', "./helder/", pkgs, urls, false, listed ? '$name.wasm.assets.json' : null));
		return files;
	}
}
