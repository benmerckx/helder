package helder.typescript.check;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Syntax;

// The entry file and the files it imports, parsed, bound and checked by tsgo.
// Everything lowering needs is fetched up front: the files' ASTs, the symbols
// of their identifiers and the targets of their module specifiers. A
// compilation server (`helder dev`) keeps its tsgo running between builds;
// a one-shot build stops it before code generation.
class Project {
	public final path:String;
	public var file(default, null):SourceFile;
	// (every program file that is not a declaration file)
	public final files:Array<SourceFile> = [];
	public final isJS:Bool;
	final modules:Map<Node, String> = [];

	static var session:Null<{key:String, tsgo:Tsgo, tables:Tables}> = null;

	public static function check(entry:String, globals:String):Project {
		var found = Tsgo.find(haxe.io.Path.directory(entry));
		var key = found.exe + "\n" + Sys.getCwd();
		if (session != null && session.key != key) {
			session.tsgo.close();
			session = null;
		}
		if (session == null) {
			var tsgo = new Tsgo(found.exe, Sys.getCwd());
			tsgo.call("initialize", null);
			session = {key: key, tsgo: tsgo, tables: Tables.load(found.typescript)};
		}
		var s = session;
		try {
			var project = new Project(entry, globals, s.tsgo, s.tables);
			if (!hxmc.Driver.resident) stop();
			return project;
		} catch (e:Dynamic) {
			// (a broken pipe is not kept for the next build)
			if (!hxmc.Driver.resident || !Std.isOfType(e, String) || StringTools.startsWith(e, "TSHX003")) stop();
			throw e;
		}
	}

	public static function stop() {
		if (session != null) session.tsgo.close();
		session = null;
	}

	function new(entry:String, globals:String, tsgo:Tsgo, tables:Tables) {
		var absolute = haxe.io.Path.normalize(sys.FileSystem.fullPath(entry));
		path = relative(absolute);
		isJS = ~/\.[cm]?jsx?$/.match(absolute);
		if (!sys.FileSystem.exists(absolute)) throw path + ": TSHX002: input file not found";
		var options = {
			target: 99, module: 99, moduleResolution: 100, strict: true, allowJs: true, checkJs: false, noEmit: true,
			skipLibCheck: true, types: [], lib: ["lib.esnext.d.ts"]
		};
		var snapshot:Dynamic = tsgo.call("createSnapshot", {createPrograms: [{rootFiles: [absolute, globals], compilerOptions: options}]});
		var at = {snapshot: snapshot.snapshot, project: snapshot.projects[0].id};
		try load(tsgo, tables, at, absolute, globals) catch (e:Dynamic) {
			tsgo.call("release", {snapshot: at.snapshot});
			throw e;
		}
		tsgo.call("release", {snapshot: at.snapshot});
	}

	function load(tsgo:Tsgo, tables:Tables, at:{snapshot:Dynamic, project:Dynamic}, absolute:String, globals:String) {
		var names:Array<String> = tsgo.call("getSourceFileNames", at);
		var sources = [for (n in names) if (!StringTools.endsWith(n, ".d.ts") && n != globals) n];
		var errors:Array<String> = [];
		function report(list:Array<Dynamic>)
			if (list != null) for (d in list) {
				var where = d.fileName == null ? path : relative(d.fileName) + ":" + (d.startPosition.line + 1);
				if (d.startPosition != null && d.endPosition != null && d.startPosition.line == d.endPosition.line)
					where += ": characters " + d.startPosition.character + "-" + d.endPosition.character;
				errors.push(where + " : TS" + d.code + ": " + message(d));
			}
		report(tsgo.call("getProgramDiagnostics", at));
		report(tsgo.call("getSyntacticDiagnostics", {snapshot: at.snapshot, project: at.project, files: sources}));
		var checked = [for (n in sources) if (!~/\.[cm]?jsx?$/.match(n)) n];
		if (errors.length == 0 && checked.length > 0)
			report(tsgo.call("getSemanticDiagnostics", {snapshot: at.snapshot, project: at.project, files: checked}));
		if (errors.length > 0) throw errors.join("\n");
		for (name in sources) {
			var sf = new SourceFile(name, tsgo.request("getSourceFile", haxe.Json.stringify({snapshot: at.snapshot, project: at.project, file: name})), tables);
			files.push(sf);
			if (name == absolute) file = sf;
			symbols(tsgo, at, sf);
			for (i in 1...sf.count) switch sf.kindAt(i) {
				case KindImportDeclaration | KindExportDeclaration:
					var specifier = sf.node(i).moduleSpecifier();
					if (specifier != null && specifier.kind == KindStringLiteral) {
						var r:Dynamic = tsgo.call("getResolvedModule", {snapshot: at.snapshot, project: at.project, file: name, moduleName: specifier.text, mode: 99});
						if (r != null && r.resolvedFileName != null) modules.set(specifier, r.resolvedFileName);
					}
				case _:
			}
		}
		if (file == null) throw path + ": TSHX002: input file not found";
	}

	static function message(d:Dynamic):String {
		var text:String = d.text;
		var chain:Array<Dynamic> = d.messageChain;
		if (chain != null) for (c in chain) text += " " + message(c);
		return text;
	}

	// Asks the checker which symbol every identifier refers to, in one request.
	function symbols(tsgo:Tsgo, at:{snapshot:Dynamic, project:Dynamic}, sf:SourceFile) {
		var key = sf.string(sf.extendedData(1, 8)), raw = sf.tables.raw(KindIdentifier);
		var ids = [for (i in 1...sf.count) if (sf.kindAt(i) == KindIdentifier) i];
		if (ids.length == 0) return;
		var result:Array<Dynamic> = tsgo.call("getSymbolsAtLocations", {snapshot: at.snapshot, project: at.project, locations: [for (i in ids) i + "." + raw + "." + key]});
		for (j in 0...ids.length) if (result[j] != null) sf.symbols.set(ids[j], Std.string(result[j].id));
	}

	// a path as messages show it: relative to the working directory when under it
	static function relative(file:String):String {
		var cwd = haxe.io.Path.addTrailingSlash(haxe.io.Path.normalize(Sys.getCwd()));
		return StringTools.startsWith(file, cwd) ? file.substr(cwd.length) : file;
	}

	// The file a module specifier resolves to, or null.
	public function resolve(specifier:Node):Null<String>
		return modules.get(specifier);

	public function fail(n:Node, message:String):Dynamic {
		if (n == null) throw path + ":0: TSHX001: " + message;
		throw relative(n.file.path) + ":" + n.file.line(n.file.skipTrivia(n.pos)) + ": TSHX001: " + message;
	}
}
