package helder.asset;

#if macro
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Type;
import sys.FileSystem;
import sys.io.File;

using StringTools;
#end

// The files a build takes with it: those its code names (Asset's macros,
// Model.of) and still uses after dead code elimination. Once the program is
// typed (Context.onGenerate, which runs before Haxe's own elimination), the
// typed code is walked from what runs (the main call, @:keep, each class's
// __init__) along what it reaches (static fields, constructors, instance
// fields by name: an override or an interface's implementation is one the
// call may reach), as the elimination itself does, and each call of a
// loader (a static function marked @:helder.asset.load, or
// @:helder.asset.sync for a read before main: Model.of) with its key as a
// constant is a file of the bundle. A file named only in code that nothing
// reaches is left out. With -dce no, and in dev builds (-D hxmc.dev, where
// the files are read from disk and watched), every one named counts.
//
// Then, by target (hxmc.target), what the build itself can do:
// - desktop (linux-*, macos-*, windows-*): each file a resource of the
//   executable (Context.addResource: hxmc puts it in the read-only data,
//   once, read through Files without a file system); not in dev builds;
// - the web (wasm32-wasi): each file copied beside the module as
//   assets/<key>, and <module>.assets.json listing those read before main
//   (@:helder.asset.sync), which os's browser.mjs fetches (its assets
//   option) while the module loads;
// - iOS (-D helder.asset.app=<the .app>, helder.cli.Ios's): each file
//   copied into the bundle as assets/<key> and the bundle's
//   _CodeSignature/CodeResources written again with their hashes, before
//   hxmc links and signs the executable binding it;
// - Android: nothing here: helder.cli.Android puts the manifest's files in
//   the APK's assets/, stored.
// Every build gets the list of the keys as a resource (Assets.bundled), and
// `--macro helder.asset.Bundle.use("<file>")` (helder's CLI) writes the
// manifest there: {target, dev, assets: [{key, file, sync, bytes}]}, the
// files' full paths (helder build's packaging, helder dev's watcher).
// Hooks for later: a file's settings beside it (sword.png.meta) and a
// format per target (compressed textures) would be read and applied here.
class Bundle {
	// the list's resource, and each file's (desktop)
	public static inline var LIST = "helder.asset:";
	public static inline var PREFIX = "helder.asset/";

	#if macro
	static var registered = false;
	static var manifest:Null<String> = null;

	// helder's CLI, each build: the manifest's file
	public static function use(?file:String) {
		registered = false;
		manifest = file;
		ensure();
	}

	// (the first asset named in a compilation, without use: its hooks)
	public static function ensure() {
		if (registered) return;
		registered = true;
		Context.onGenerate(generate);
		Context.onAfterGenerate(() -> registered = false);
	}

	static function output():Null<String> {
		var o = haxe.macro.Compiler.getOutput();
		// (the repository tool's `hxmc <output> <args>` hides it)
		for (d in ["helder.asset.out", "helder.scene.out"])
			if ((o == null || o == "") && Context.defined(d)) o = Context.definedValue(d);
		return o == null || o == "" ? null : o;
	}

	static function generate(types:Array<Type>) {
		var refs = references(types);
		var target = Context.definedValue("hxmc.target") ?? "";
		// (hxmc without a target named: this machine's)
		if (target == "" && Context.definedValue("target.name") == "hxmc") target = switch Sys.systemName() {
			case "Windows": "windows-";
			case "Mac": "macos-";
			case _: "linux-";
		}
		var dev = Context.defined("hxmc.dev");
		var keys = [for (k in refs.keys()) k];
		keys.sort(Reflect.compare);
		var entries = [];
		for (k in keys) {
			var f = AssetMacro.locate(k);
			if (f == null) continue;
			entries.push({key: k, file: FileSystem.fullPath(f).split("\\").join("/"), sync: refs.get(k), bytes: FileSystem.stat(f).size});
		}
		if (manifest != null) {
			var d = Path.directory(manifest);
			if (d != "" && !FileSystem.exists(d)) FileSystem.createDirectory(d);
			File.saveContent(manifest, haxe.Json.stringify({target: target, dev: dev, assets: entries}, "\t"));
		}
		if (entries.length == 0 && manifest == null) return;
		if (target != "") Context.addResource(LIST, haxe.io.Bytes.ofString([for (e in entries) e.key].join("\n")));
		var desktop = target.startsWith("linux-") || target.startsWith("macos-") || target.startsWith("windows-");
		if (desktop && !dev)
			for (e in entries)
				Context.addResource(PREFIX + e.key, File.getBytes(e.file));
		var out = output();
		if (target == "wasm32-wasi" && out != null) {
			var dir = Path.directory(out);
			if (dir == "") dir = ".";
			if (!dev)
				for (e in entries) {
					var dest = '$dir/${AssetPath.bundled(e.key)}';
					mkdirs(Path.directory(dest));
					File.copy(e.file, dest);
				}
			File.saveContent(out + ".assets.json", haxe.Json.stringify([for (e in entries) if (e.sync) AssetPath.bundled(e.key)]));
		}
		var app = Context.definedValue("helder.asset.app");
		if (app != null && app != "" && !dev) intoApp(app, entries);
	}

	// iOS: the files in the bundle, CodeResources with their hashes
	static function intoApp(app:String, entries:Array<{key:String, file:String, sync:Bool, bytes:Int}>) {
		var files = new Map<String, haxe.io.Bytes>();
		files.set("Info.plist", File.getBytes('$app/Info.plist'));
		for (e in entries) {
			var rel = AssetPath.bundled(e.key), b = File.getBytes(e.file);
			mkdirs(Path.directory('$app/$rel'));
			File.saveBytes('$app/$rel', b);
			files.set(rel, b);
		}
		File.saveBytes('$app/_CodeSignature/CodeResources', helder.pack.ios.Bundle.codeResources(files));
	}

	static function mkdirs(d:String)
		if (d != "" && !FileSystem.exists(d)) {
			mkdirs(Path.directory(d));
			FileSystem.createDirectory(d);
		}

	// the keys the program's loaders are called with (true: read before
	// main, @:helder.asset.sync), from what runs
	static function references(types:Array<Type>):Map<String, Bool> {
		var found = new Map<String, Bool>();
		var classes:Array<ClassType> = [];
		for (t in types)
			switch t {
				case TInst(c, _): classes.push(c.get());
				case _:
			}
		// (no asset's module: nothing to look for)
		if (!Lambda.exists(classes, c -> c.pack.join(".") == "helder.asset" && c.name == "Files")) return found;
		var all = Context.defined("hxmc.dev") || Context.definedValue("dce") == "no";
		var queue:Array<TypedExpr> = [];
		var marked = new Map<String, Bool>();
		var byName = new Map<String, Array<ClassField>>();
		for (c in classes)
			for (f in c.fields.get()) {
				var l = byName.get(f.name);
				if (l == null) byName.set(f.name, l = []);
				l.push(f);
			}
		function push(e:Null<TypedExpr>)
			if (e != null) queue.push(e);
		function id(c:ClassType):String
			return c.pack.concat([c.module, c.name]).join(".");
		function markClass(c:ClassType)
			if (!marked.exists("K " + id(c))) {
				marked.set("K " + id(c), true);
				push(c.init);
				if (c.superClass != null) markClass(c.superClass.t.get());
			}
		function markStatic(c:ClassType, f:ClassField) {
			var k = "S " + id(c) + "." + f.name;
			if (marked.exists(k)) return;
			marked.set(k, true);
			markClass(c);
			push(f.expr());
		}
		function markName(n:String)
			if (!marked.exists("I " + n)) {
				marked.set("I " + n, true);
				var l = byName.get(n);
				if (l != null) for (f in l) push(f.expr());
			}
		function markNew(c:ClassType)
			if (!marked.exists("C " + id(c))) {
				marked.set("C " + id(c), true);
				markClass(c);
				if (c.constructor != null) push(c.constructor.get().expr());
				if (c.superClass != null) markNew(c.superClass.t.get());
			}
		function markAll(c:ClassType) {
			for (f in c.statics.get())
				markStatic(c, f);
			markNew(c);
			for (f in c.fields.get())
				markName(f.name);
		}
		function loader(f:ClassField, args:Array<TypedExpr>) {
			var sync = f.meta.has(":helder.asset.sync");
			if (!sync && !f.meta.has(":helder.asset.load") || args.length == 0) return;
			switch args[0].expr {
				case TConst(TString(k)): found.set(k, sync || found.get(k) == true);
				case _:
			}
		}
		function visit(e:TypedExpr) {
			switch e.expr {
				case TCall({expr: TField(_, FStatic(c, f))}, args):
					loader(f.get(), args);
					markStatic(c.get(), f.get());
					for (a in args)
						visit(a);
					return;
				case TField(_, FStatic(c, f)):
					// (the class as a type there is no use of its constructor)
					markStatic(c.get(), f.get());
					return;
				case TField(_, FInstance(_, _, f) | FClosure(_, f)):
					markName(f.get().name);
				case TField(_, FAnon(f)):
					markName(f.get().name);
				case TField(_, FDynamic(n)):
					markName(n);
				case TNew(c, _, _):
					markNew(c.get());
				case TTypeExpr(TClassDecl(c)):
					markNew(c.get());
				case _:
			}
			haxe.macro.TypedExprTools.iter(e, visit);
		}
		if (all) {
			for (c in classes) {
				for (f in c.statics.get().concat(c.fields.get()))
					push(f.expr());
				if (c.constructor != null) push(c.constructor.get().expr());
				push(c.init);
			}
		} else {
			push(Context.getMainExpr());
			// (what the runtime calls by name: Std.string's toString)
			markName("toString");
			for (c in classes) {
				var keep = c.meta.has(":keep");
				var s = c.superClass;
				while (!keep && s != null) {
					keep = s.t.get().meta.has(":keepSub");
					s = s.t.get().superClass;
				}
				if (keep || c.meta.has(":keepSub")) markAll(c);
				markClass(c);
				for (f in c.statics.get())
					if (f.meta.has(":keep")) markStatic(c, f);
				for (f in c.fields.get())
					if (f.meta.has(":keep")) markName(f.name);
				if (c.constructor != null && c.constructor.get().meta.has(":keep")) markNew(c);
			}
		}
		while (queue.length > 0)
			visit(queue.pop());
		return found;
	}
	#end
}
