package helder.typescript.check;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Syntax;

// The entry file and the files it imports, parsed, bound and checked by tsgo.
// Everything lowering needs is fetched up front: the files' ASTs, the symbols
// of their identifiers, their types and the targets of their module specifiers. A
// compilation server (`helder dev`) keeps its tsgo running between builds;
// a one-shot build stops it before code generation.
class Project {
	public final path:String;
	public var file(default, null):SourceFile;
	// (every program file that is not a declaration file)
	public final files:Array<SourceFile> = [];
	// (the declaration files the program and they import: helder's API, lower.Api)
	public final declarations:Array<SourceFile> = [];
	public final isJS:Bool;
	public var types(default, null):Types;
	final modules:Map<Node, String> = [];

	// the program's source files the last check found, also when it failed
	// (what a watcher follows)
	public static var read(default, null):Array<String> = [];

	static var session:Null<{key:String, tsgo:Tsgo, tables:Tables}> = null;

	// (checked: after, given the project while tsgo is up, asks what the lowering needs beyond it)
	public static function check(entry:String, globals:String, ?after:Project->Void):Project {
		read = [haxe.io.Path.normalize(sys.FileSystem.fullPath(entry))];
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
			if (after != null) after(project);
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
		last = null;
	}

	// The last build's snapshot, kept by a compilation server: the next build
	// with the same entry and options updates it with the files that changed
	// since (by size and time), so tsgo reparses and rechecks only what they
	// affect; none changed, it is used as it is.
	static var last:Null<{key:String, snapshot:Int, project:String, stamps:Map<String, String>}> = null;

	static function stamp(file:String):String {
		var s = try sys.FileSystem.stat(file) catch (_:Dynamic) return "";
		return s.size + "@" + s.mtime.getTime();
	}

	static function snapshot(tsgo:Tsgo, key:String, roots:Array<String>, options:Dynamic):{snapshot:Int, project:String} {
		var previous = last;
		last = null;
		if (previous != null && previous.key == key) {
			var changed = [], deleted = [];
			for (f => s in previous.stamps) {
				var now = stamp(f);
				if (now == "") deleted.push(f) else if (now != s) changed.push(f);
			}
			if (changed.length == 0 && deleted.length == 0) return {snapshot: previous.snapshot, project: previous.project};
			var r:Dynamic = tsgo.call("updateSnapshot", {snapshot: previous.snapshot, changes: {fileNotifications: {changed: changed, deleted: deleted}, ensurePrograms: true}});
			// (the same snapshot again: taken once more, given back once)
			tsgo.call("release", {snapshot: r.snapshot == previous.snapshot ? r.snapshot : previous.snapshot});
			return {snapshot: r.snapshot, project: previous.project};
		}
		if (previous != null) tsgo.call("release", {snapshot: previous.snapshot});
		var r:Dynamic = tsgo.call("createSnapshot", {createPrograms: [{rootFiles: roots, compilerOptions: options}]});
		return {snapshot: r.snapshot, project: r.projects[0].id};
	}

	function new(entry:String, globals:String, tsgo:Tsgo, tables:Tables) {
		var absolute = haxe.io.Path.normalize(sys.FileSystem.fullPath(entry));
		path = relative(absolute);
		isJS = ~/\.[cm]?jsx?$/.match(absolute);
		if (!sys.FileSystem.exists(absolute)) throw path + ": TSHX002: input file not found";
		var options = Config.options(tsgo, absolute, relative, f -> config = f);
		var key = absolute + "\n" + haxe.Json.stringify(options);
		var at = snapshot(tsgo, key, [absolute, globals], options);
		// (kept for the next build, a failed one's too: its files are watched)
		function keep() last = {key: key, snapshot: at.snapshot, project: at.project, stamps: [for (f in read) f => stamp(f)]};
		try load(tsgo, tables, at, absolute, globals) catch (e:Dynamic) {
			keep();
			throw e;
		}
		keep();
	}

	var config:Null<String> = null;

	function load(tsgo:Tsgo, tables:Tables, at:{snapshot:Int, project:String}, absolute:String, globals:String) {
		var names:Array<String> = tsgo.call("getSourceFileNames", at);
		var sources = [for (n in names) if (!StringTools.endsWith(n, ".d.ts") && n != globals) n];
		read = sources.copy();
		if (config != null) read.push(config);
		var errors:Array<String> = [];
		function report(list:Array<Dynamic>)
			if (list != null) for (d in list) {
				var where = d.fileName == null ? path : relative(d.fileName) + ":" + (d.startPosition.line + 1);
				if (d.fileName != null && d.startPosition != null && d.endPosition != null && d.startPosition.line == d.endPosition.line)
					where += ": characters " + d.startPosition.character + "-" + d.endPosition.character + " ";
				errors.push(where + ": TS" + d.code + ": " + message(d));
			}
		report(tsgo.call("getProgramDiagnostics", at));
		report(tsgo.call("getSyntacticDiagnostics", {snapshot: at.snapshot, project: at.project, files: sources}));
		var checked = [for (n in sources) if (!~/\.[cm]?jsx?$/.match(n)) n];
		if (errors.length == 0 && checked.length > 0)
			report(tsgo.call("getSemanticDiagnostics", {snapshot: at.snapshot, project: at.project, files: checked}));
		if (errors.length > 0) throw errors.join("\n");
		types = new Types(tsgo, at, tables);
		var pending:Array<String> = [], seen = new Map<String, Bool>();
		function load(name:String, program:Bool) {
			var sf = new SourceFile(name, tsgo.request("getSourceFile", haxe.Json.stringify({snapshot: at.snapshot, project: at.project, file: name})), tables);
			(program ? files : declarations).push(sf);
			if (name == absolute) file = sf;
			symbols(tsgo, at, sf);
			if (program) types.load(sf);
			for (i in 1...sf.count) switch sf.kindAt(i) {
				case KindImportDeclaration | KindExportDeclaration:
					var specifier = sf.node(i).moduleSpecifier();
					if (specifier != null && specifier.kind == KindStringLiteral) {
						var r:Dynamic = tsgo.call("getResolvedModule", {snapshot: at.snapshot, project: at.project, file: name, moduleName: specifier.text, mode: 99});
						if (r != null && r.resolvedFileName != null) {
							var target:String = r.resolvedFileName;
							modules.set(specifier, target);
							if (StringTools.endsWith(target, ".d.ts") && !seen.exists(target)) {
								seen.set(target, true);
								pending.push(target);
							}
						}
					}
				case _:
			}
		}
		for (name in sources) load(name, true);
		while (pending.length > 0) load(pending.shift(), false);
		if (file == null) throw path + ": TSHX002: input file not found";
	}

	static function message(d:Dynamic):String {
		var text:String = d.text;
		var chain:Array<Dynamic> = d.messageChain;
		if (chain != null) for (c in chain) text += " " + message(c);
		return text;
	}

	// Asks the checker which symbol every identifier refers to, in one request.
	function symbols(tsgo:Tsgo, at:{snapshot:Int, project:String}, sf:SourceFile) {
		var key = sf.string(sf.extendedData(1, 8)), raw = sf.tables.raw(KindIdentifier);
		var ids = [for (i in 1...sf.count) if (sf.kindAt(i) == KindIdentifier) i];
		if (ids.length == 0) return;
		var result:Array<Dynamic> = tsgo.call("getSymbolsAtLocations", {snapshot: at.snapshot, project: at.project, locations: [for (i in ids) i + "." + raw + "." + key]});
		for (j in 0...ids.length) if (result[j] != null) sf.symbols.set(ids[j], Std.string(result[j].reference != null ? result[j].reference.id : result[j].id));
	}

	// a path as messages show it: relative to the working directory when under it
	public static function relative(file:String):String {
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
