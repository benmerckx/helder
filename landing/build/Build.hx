import haxe.io.Bytes;
import haxe.io.BytesOutput;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

using StringTools;

// make landing: bin/landing, the landing page (landing/README.md), run by
// the repository's tool from the repository's root:
//
//   bin/hxmc/hxmc -cp landing/build --run Build --tool bin/hxmc/hxmc --hxmc hxmc --out bin/landing
//
// Nothing is compiled ahead but the page itself: the compiler
// (compiler/Reactor.hx, built here by the tool from hxmc's sources), the
// std, the packages' sources and each target's runtime objects (from the
// nightly npm packages of the hxmc commit the Makefile pins: HXMC_REV;
// HXMC_NPM_VERSION=<version> picks another) go to the page, which compiles
// the examples. The page's code (landing/src) is compiled to JavaScript by
// @hxmc/wasm's compiler under node; the editor (CodeMirror, landing/editor's
// pinned packages) bundled by esbuild.
class Build {
	// the targets a download can be for: [id, its runtime objects' directory]
	// (Linux: the glibc mode, which loads the GPU's drivers)
	static final TARGETS = [
		["linux-x86_64", "linux-x86_64-glibc"],
		["linux-arm64", "linux-arm64-glibc"],
		["macos-arm64", "macos-arm64"],
		["macos-x86_64", "macos-x86_64"],
		["windows-x86_64", "windows-x86_64"],
		["windows-arm64", "windows-arm64"],
	];

	// the examples' packages: their class paths (dependencies first),
	// defines and browser modules (site/src/Examples.hx has the same)
	static final PACKAGES:Map<String, {cp:Array<String>, ?defines:Array<String>, imports:Array<String>, ?fonts:Bool}> = [
		"os" => {cp: ["os"], imports: ["os"]},
		"gfx" => {cp: ["os", "gfx"], imports: ["os", "gfx"]},
		"3d" => {cp: ["os", "gfx", "text", "ui", "3d"], imports: ["os", "gfx"]},
		"physics" => {cp: ["os", "gfx", "3d", "physics"], imports: ["os", "gfx"]},
		"text" => {cp: ["os", "gfx", "text"], imports: ["os", "gfx", "text"], fonts: true},
		"ui" => {
			cp: ["os", "gfx", "text", "view", "ui", "theme"],
			defines: ["hxmc.view.renderer.ui=hxmc.ui.view.NodeRenderer"],
			imports: ["os", "gfx", "text", "ui"],
			fonts: true,
		},
		"theme" => {
			cp: ["os", "gfx", "text", "view", "ui", "theme"],
			defines: ["hxmc.view.renderer.ui=hxmc.ui.view.NodeRenderer"],
			imports: ["os", "gfx", "text", "ui"],
			fonts: true,
		},
	];
	// the gallery's order
	static final ORDER = ["gfx", "physics", "3d", "ui", "theme", "os"];
	static final FONT_DIRS = ["/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/TTF", "/usr/share/fonts/dejavu", "/Library/Fonts"];
	// upstream std's directories no hxmc build reads (the other targets')
	static final STD_SKIP = ["cpp", "cs", "flash", "hl", "java", "js", "jvm", "lua", "neko", "php", "python"];
	// what editor.js exports (the global CM): what landing/src/Editor.hx uses
	static final EDITOR = [
		"@codemirror/view" => "EditorView, keymap, hoverTooltip, tooltips, lineNumbers, highlightActiveLine, highlightActiveLineGutter, highlightSpecialChars, drawSelection, dropCursor",
		"@codemirror/state" => "EditorState",
		"@codemirror/commands" => "history, historyKeymap, defaultKeymap, indentWithTab, undo",
		"@codemirror/language" => "StreamLanguage, syntaxHighlighting, HighlightStyle, indentOnInput, bracketMatching, indentUnit",
		"@codemirror/autocomplete" => "autocompletion, closeBrackets, closeBracketsKeymap, completionKeymap, startCompletion",
		"@codemirror/lint" => "setDiagnostics, lintGutter",
		"@codemirror/search" => "searchKeymap, highlightSelectionMatches",
		"@lezer/highlight" => "tags",
		"@codemirror/legacy-modes/mode/haxe" => "haxe",
	];

	static var out = "bin/landing";
	static var tool = "bin/hxmc/hxmc";
	static var hxmc = "hxmc";
	static final sizes = new haxe.DynamicAccess<Int>();

	static function main() {
		var args = Sys.args();
		var i = 0;
		while (i < args.length) {
			switch args[i] {
				case "--out": out = args[++i];
				case "--tool": tool = args[++i];
				case "--hxmc": hxmc = args[++i];
				case a: fail('unknown argument $a');
			}
			i++;
		}
		var npm = npmPackages();
		rm(out);
		FileSystem.createDirectory(out);
		for (f in ["index.html", "style.css", "favicon.svg"]) File.copy('landing/$f', '$out/$f');
		File.saveContent('$out/.nojekyll', "");

		reactor();
		packs(npm.cli);
		for (p in ["os", "gfx", "text", "ui"]) copy('packages/$p/imports.mjs', '$out/$p/imports.mjs');
		copy("packages/os/browser.mjs", '$out/os/browser.mjs');
		for (f in ["DejaVuSans.ttf", "DejaVuSans-Bold.ttf"]) {
			var d = Lambda.find(FONT_DIRS, d -> FileSystem.exists('$d/$f'));
			if (d == null) fail('$f not found (install fonts-dejavu-core) in ${FONT_DIRS.join(", ")}');
			copy('$d/$f', '$out/fonts/$f');
		}
		editor();
		for (js in [["Main", "main.js"], ["CompilerWorker", "worker.js"], ["Check", "check.js"]]) haxeJs(npm, js[0], js[1]);

		var list = examples();
		var commit = try {
			var p = new Process("git", ["rev-parse", "HEAD"]);
			var c = p.stdout.readAll().toString().trim();
			p.close();
			c;
		} catch (_:Dynamic) "unknown";
		sizes["reactor.wasm"] = FileSystem.stat('$out/reactor.wasm').size;
		var manifest = {
			hxmc: {version: npm.version, rev: npm.rev},
			commit: commit,
			targets: [for (t in TARGETS) t[0]],
			sizes: sizes,
			examples: list,
		};
		File.saveContent('$out/manifest.json', haxe.Json.stringify(manifest, null, "\t"));
		for (f => n in sizes) Sys.println('${f.rpad(" ", 24)} ${Std.string(Math.round(n / 10485.76) / 100).lpad(" ", 7)} MB');
		Sys.println('landing: ${list.length} examples, hxmc ${npm.version}, into $out');
	}

	static function fail(message:String) {
		Sys.stderr().writeString('landing: $message\n');
		Sys.exit(1);
	}

	static function run(cmd:String, args:Array<String>, ?cwd:String):String {
		var old = Sys.getCwd();
		if (cwd != null) Sys.setCwd(cwd);
		var p = new Process(cmd, args);
		var o = p.stdout.readAll().toString(), e = p.stderr.readAll().toString();
		var code = p.exitCode();
		p.close();
		if (cwd != null) Sys.setCwd(old);
		if (code != 0) fail('$cmd ${args.join(" ")}: exit $code\n$o$e');
		return o;
	}

	static function rm(path:String) {
		if (!FileSystem.exists(path)) return;
		if (FileSystem.isDirectory(path)) {
			for (f in FileSystem.readDirectory(path)) rm('$path/$f');
			FileSystem.deleteDirectory(path);
		} else FileSystem.deleteFile(path);
	}

	static function copy(from:String, to:String) {
		FileSystem.createDirectory(haxe.io.Path.directory(to));
		File.copy(from, to);
	}

	static function write(rel:String, b:Bytes) {
		FileSystem.createDirectory(haxe.io.Path.directory('$out/$rel'));
		File.saveBytes('$out/$rel', b);
		sizes[rel] = b.length;
	}

	// the files under dir, relative to it, sorted; keep(rel, isDir)
	static function walk(dir:String, ?keep:(String, Bool) -> Bool, rel = ""):Array<String> {
		var names = FileSystem.readDirectory(rel == "" ? dir : '$dir/$rel');
		names.sort(Reflect.compare);
		var files = [];
		for (n in names) {
			var r = rel == "" ? n : '$rel/$n';
			var isDir = FileSystem.isDirectory('$dir/$r');
			if (keep != null && !keep(r, isDir)) continue;
			if (isDir) files = files.concat(walk(dir, keep, r)) else files.push(r);
		}
		return files;
	}

	// a pack (landing/src/Pack.hx): a little-endian u32 n, n bytes of JSON
	// [[path, size], ...], then the files' bytes in that order
	static function pack(entries:Array<{path:String, data:Bytes}>):Bytes {
		var index = Bytes.ofString(haxe.Json.stringify([for (e in entries) [e.path, e.data.length]]));
		var o = new BytesOutput();
		o.writeInt32(index.length);
		o.write(index);
		for (e in entries) o.write(e.data);
		return o.getBytes();
	}

	// ---- the npm packages ----

	static function npmPackages():{version:String, rev:String, cli:String, wasm:String} {
		var rev = ~/^HXMC_REV \?= (\w+)/m;
		if (!rev.match(File.getContent("Makefile"))) fail("no HXMC_REV in the Makefile");
		var r = rev.matched(1);
		var version = Sys.getEnv("HXMC_NPM_VERSION");
		if (version == null || version == "") {
			var all:Array<String> = haxe.Json.parse(run("npm", ["view", "@hxmc/wasm", "versions", "--json"]));
			version = Lambda.fold(all, (v, found) -> v.endsWith("." + r.substr(0, 7)) ? v : found, null);
			if (version == null) fail('no nightly of @hxmc/wasm for hxmc ${r.substr(0, 7)} (HXMC_NPM_VERSION=<version> picks one)');
		}
		var dir = 'bin/landing-npm/$version';
		for (name in ["cli", "wasm"]) {
			var to = '$dir/$name';
			if (FileSystem.exists('$to/package/package.json')) continue;
			FileSystem.createDirectory(to);
			var lines = run("npm", ["pack", '@hxmc/$name@$version', "--silent"], to).trim().split("\n");
			var tgz = lines[lines.length - 1];
			run("tar", ["xzf", tgz], to);
			FileSystem.deleteFile('$to/$tgz');
		}
		return {version: version, rev: r, cli: '$dir/cli/package', wasm: '$dir/wasm/package'};
	}

	// ---- the compiler ----

	// compiler/Reactor.hx: hxmc's `haxe` as a resident server, built by the tool from hxmc's sources
	static function reactor() {
		var log = '$out/../landing-reactor.log';
		var args = [
			'$out/reactor.wasm',
			"-cp", '$hxmc/haxe/src', "-cp", '$hxmc/hxmc/src', "-cp", "packages/web/src", "-cp", "landing/compiler", "-main", "Reactor",
			"-D", "disable-parallelism", "-D", "hxmc.gc-prefault", "-cp", "bin/hxmc/std", "--custom-target", "hxmc", "-D", "hxmc.target=wasm32-wasi",
		];
		var code = Sys.command("sh", ["-c", "ulimit -s unlimited 2>/dev/null; " + [tool].concat(args).map(quote).join(" ") + " > " + quote(log) + " 2>&1"]);
		if (code != 0 || !FileSystem.exists('$out/reactor.wasm')) fail('the compiler did not build:\n${File.getContent(log)}');
	}

	static function quote(s:String):String
		return "'" + s.replace("'", "'\\''") + "'";

	// ---- the packs ----

	static function packs(cli:String) {
		// the std: upstream's (without the other targets') and hxmc's merged one
		var std = '$cli/haxe/upstream/std', hxmcStd = '$cli/hxmc/bootstrap/hxmc-std';
		var entries = [
			for (r in walk(std, (r, isDir) -> !(isDir && r.indexOf("/") < 0 && STD_SKIP.contains(r)))) {path: 'std/$r', data: File.getBytes('$std/$r')}
		];
		for (r in walk(hxmcStd)) entries.push({path: 'hxmc-std/$r', data: File.getBytes('$hxmcStd/$r')});
		write("std.pack", pack(entries));

		// the packages' sources and examples (what the page compiles, with the
		// files macros read: theme's sheets, 3d's models); the examples' other
		// files also served, for the programs that load them (Model.of)
		var src = [];
		var pkgs = FileSystem.readDirectory("packages");
		pkgs.sort(Reflect.compare);
		for (p in pkgs) for (sub in ["src", "examples"]) {
			var d = 'packages/$p/$sub';
			if (!FileSystem.exists(d)) continue;
			for (r in walk(d)) {
				var rel = 'packages/$p/$sub/$r';
				src.push({path: rel, data: File.getBytes('$d/$r')});
				if (sub == "examples" && !r.endsWith(".hx")) copy('$d/$r', '$out/$rel');
			}
		}
		write("src.pack", pack(src));

		// each target's runtime objects (fetched when a download asks for that target)
		var rt = '$cli/hxmc/bootstrap/rt';
		for (t in TARGETS) {
			var files = [for (r in walk('$rt/${t[1]}')) {path: '${t[1]}/$r', data: File.getBytes('$rt/${t[1]}/$r')}];
			files.push({path: "HASH", data: File.getBytes('$rt/HASH')});
			write('rt/${t[0]}.pack', pack(files));
		}
	}

	// ---- the page's code ----

	static function editor() {
		var dir = "landing/editor";
		if (!FileSystem.exists('$dir/node_modules/esbuild')) run("npm", ["ci", "--no-audit", "--no-fund"], dir);
		var entry = [for (m => names in EDITOR) 'export {$names} from "$m";'].join("\n");
		// (from the editor's directory: esbuild resolves stdin's imports against it)
		var target = FileSystem.fullPath(out) + "/editor.js", old = Sys.getCwd();
		Sys.setCwd(dir);
		var p = new Process("node_modules/.bin/esbuild", ["--bundle", "--format=iife", "--global-name=CM", "--minify", "--sourcefile=entry.js", '--outfile=$target']);
		p.stdin.writeString(entry);
		p.stdin.close();
		var e = p.stderr.readAll().toString();
		var code = p.exitCode();
		p.close();
		Sys.setCwd(old);
		if (code != 0) fail('esbuild: $e');
		sizes["editor.js"] = FileSystem.stat('$out/editor.js').size;
	}

	// a program of landing/src compiled to JavaScript, by @hxmc/wasm's compiler under node
	static function haxeJs(npm:{cli:String, wasm:String}, main:String, file:String) {
		var log = '$out/../landing-$file.log';
		var cmd = ["node", "--stack-size=65500", '${npm.wasm}/wasi.mjs', '${npm.wasm}/haxe.wasm', "-cp", "landing/src", "-main", main, "-js", '$out/$file', "-D", "js-es=6", "-dce", "full"];
		var code = Sys.command("sh", ["-c", 'ulimit -s unlimited 2>/dev/null; HAXE_STD_PATH=${quote(npm.cli + "/haxe/upstream/std")} ' + cmd.map(quote).join(" ") + " > " + quote(log) + " 2>&1"]);
		if (code != 0 || !FileSystem.exists('$out/$file')) fail('$main did not compile:\n${File.getContent(log)}');
		sizes[file] = FileSystem.stat('$out/$file').size;
	}

	// ---- the examples ----

	static final HEADER = ~/^\/\/ *(title|summary|tags|demo): *(.*)$/;

	// the examples with a demo the page can show (a canvas, a sound), as
	// site/src/Examples.hx reads them
	static function examples():Array<Dynamic> {
		var list = [];
		for (pkg in ORDER) {
			var dir = 'packages/$pkg/examples';
			var names = FileSystem.readDirectory(dir).filter(n -> n.endsWith(".hx"));
			names.sort(Reflect.compare);
			for (n in names) {
				var head = new Map<String, String>();
				for (line in File.getContent('$dir/$n').split("\n")) {
					if (!line.startsWith("//")) break;
					if (HEADER.match(line.trim())) head[HEADER.matched(1)] = HEADER.matched(2).trim();
				}
				if (!head.exists("title") || !head.exists("demo")) continue;
				var canvas = ~/^canvas +(\d+)x(\d+)$/;
				var isCanvas = canvas.match(head["demo"]);
				if (!isCanvas && head["demo"] != "sound") continue;
				var main = n.substr(0, n.length - 3);
				var p = PACKAGES[pkg];
				var args = [];
				for (c in p.cp) args = args.concat(["-cp", '/lib/src/packages/$c/src']);
				if (p.defines != null) for (d in p.defines) args = args.concat(["-D", d]);
				args = args.concat(["-cp", '/lib/src/packages/$pkg/examples', "-main", main]);
				list.push({
					id: '$pkg-${main.toLowerCase()}',
					pkg: pkg,
					main: main,
					title: head["title"],
					summary: head.exists("summary") ? head["summary"] : "",
					tags: [for (t in (head.exists("tags") ? head["tags"] : pkg).split(",")) t.trim()],
					demo: isCanvas ? ({canvas: [Std.parseInt(canvas.matched(1)), Std.parseInt(canvas.matched(2))]} : Dynamic) : ({sound: true} : Dynamic),
					source: 'packages/$pkg/examples/$n',
					sources: [for (m in used(dir, n, names)) 'packages/$pkg/examples/$m'],
					args: args,
					imports: [for (i in p.imports) '$i/imports.mjs'],
					fonts: p.fonts == true,
				});
			}
		}
		return list;
	}

	// the files of the folder an example uses in its code (CubeShader for
	// Cube), and theirs; what its comments name does not count
	static function used(dir:String, file:String, names:Array<String>):Array<String> {
		var found = [];
		var todo = [file];
		while (todo.length > 0) {
			var src = ~/\/\/[^\n]*|\/\*[\s\S]*?\*\//g.replace(File.getContent('$dir/${todo.shift()}'), "");
			for (n in names) {
				if (n == file || found.contains(n)) continue;
				if (new EReg("\\b" + n.substr(0, n.length - 3) + "\\b", "").match(src)) {
					found.push(n);
					todo.push(n);
				}
			}
		}
		return found;
	}
}
