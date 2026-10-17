import hxmc.web.Island;
import hxmc.web.Static;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The site's generator (`make site`): every page rendered from components
// with @hxmc/web's static renderer, the examples' WebAssembly builds and the
// API reference made with the compiler, the packages' browser modules
// copied, into one directory. Run from the repository root, on Eval or
// natively:
//   bin/hxmc/hxmc -cp packages/view/src -cp packages/web/src -cp packages/web/examples -cp site/src \
//     -D hxmc.view.renderer.html=hxmc.web.StaticRenderer --run Site --out bin/site --tool bin/hxmc/hxmc
// Options: --out <dir>; --tool <hxmc>, which builds the examples and reads
// the packages' types (without: neither, a quick look at the pages);
// --build <dir> for intermediate files (bin/site-build); --version <id>,
// the build in the address of each file a page loads (a cache-busting
// query, as the client's Version.hx); --jobs <n>.
// What the Makefile adds next to the pages: the playground's compiler and
// std, the pages' JavaScript (site/client, by the port), the measured data
// (site/data), lix under tools/.
class Site {
	public static var out = "bin/site";
	public static var build = "bin/site-build";
	public static var tool:Null<String> = null;
	public static var version:Null<String> = null;
	public static var jobs = 4;
	public static final REPO = "https://github.com/benmerckx/hxmc";

	// the page being rendered (its path in the site: "docs/using.html")
	public static var page = "index.html";
	// the pages written: path -> bytes (the report)
	public static final written = new Map<String, Int>();

	static function main() {
		var args = Sys.args();
		var i = 0;
		while (i < args.length) {
			var a = args[i++];
			switch a {
				case "--out": out = args[i++];
				case "--build": build = args[i++];
				case "--tool": tool = args[i++];
				case "--version": version = args[i++];
				case "--jobs": jobs = Std.parseInt(args[i++]);
				case _: throw 'site: unknown argument $a';
			}
		}
		var t0 = haxe.Timer.stamp();
		FileSystem.createDirectory(out);
		FileSystem.createDirectory(build);
		var examples = Examples.collect();
		if (tool != null) Examples.buildAll(examples);
		var api = tool != null ? Api.extract() : new Api([]);
		copyStatic();
		Pages.all(examples, api);
		var total = 0;
		for (p => n in written)
			total += n;
		Sys.println('site: ${Lambda.count(written)} pages (${Math.round(total / 1024)} KB of HTML), ${examples.length} examples, in ${Math.round(haxe.Timer.stamp() - t0)} s');
	}

	// "../" for each folder of the page being rendered
	public static function prefix():String {
		var n = page.split("/").length - 1;
		return [for (_ in 0...n) "../"].join("");
	}

	// a page or file of the site, from the page being rendered
	public static function link(path:String):String {
		if (path.startsWith("http") || path.startsWith("#")) return path;
		var p = prefix() + path;
		return p == "" ? "./" : p;
	}

	// a file a page loads (a script, a module, a stylesheet): with the build
	// in its address
	public static function asset(path:String):String
		return link(path) + (version == null ? "" : "?v=" + version);

	// a page: the layout around content, written to out/path
	public static function write(path:String, html:String) {
		Static.write(out + "/" + path, html);
		written.set(path, html.length);
	}

	public static function renderPage(path:String, render:Void->String) {
		page = path;
		// (islands' files, from this page)
		Island.url = asset;
		Island.runner = "os/browser.mjs";
		write(path, render());
	}

	// a source file on GitHub
	public static function github(path:String):String
		return REPO + (FileSystem.exists(path) && FileSystem.isDirectory(path) ? "/tree/main/" : "/blob/main/") + path;

	// the packages' browser modules, the loader and the stylesheet
	static function copyStatic() {
		Static.copy("site/style.css", out + "/style.css");
		Static.copy("packages/web/loader.js", out + "/loader.js");
		Static.copy("packages/os/browser.mjs", out + "/os/browser.mjs");
		for (p in ["os", "gfx", "text", "ui", "web"])
			Static.copy('packages/$p/imports.mjs', '$out/$p/imports.mjs');
		Static.copy("site/favicon.svg", out + "/favicon.svg");
	}

	// a command in sh (a large stack, as the Makefile's), its output in log;
	// its exit code
	public static function sh(args:Array<String>, log:String, ?env:Map<String, String>):Int {
		var vars = env == null ? "" : [for (k => v in env) k + "=" + quote(v) + " "].join("");
		return Sys.command("sh", ["-c", "ulimit -s unlimited 2>/dev/null; " + vars + args.map(quote).join(" ") + " > " + quote(log) + " 2>&1"]);
	}

	public static function quote(s:String):String
		return "'" + s.replace("'", "'\\''") + "'";

	public static function read(path:String):String
		return File.getContent(path);
}
