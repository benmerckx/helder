package helder.typescript.lower;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;
import helder.typescript.check.Types.TsType;

using Lambda;

// A Haxe type as the manifest gives it (helder.typescript.api.Manifest's format).
enum HType {
	HInt;
	HFloat;
	HBool;
	HString;
	HVoid;
	HDynamic;
	HNull(t:HType);
	HArray(t:HType);
	HFn(args:Array<HArg>, ret:HType);
	HAnon(fields:Array<HArg>);
	HClass(path:String, params:Array<HType>);
	HRead(t:HType);
	// ViewOf<R>: a View of renderer R's markup
	HView(renderer:String);
	HAbstract(path:String, params:Array<HType>, under:HType, values:Null<Array<String>>);
	HEnum(path:String);
	HParam(name:String);
}

typedef HArg = {name:String, opt:Bool, t:HType};

class HTypes {
	public static function of(d:Dynamic):HType {
		if (Std.isOfType(d, String)) return switch (d : String) {
			case "Int": HInt;
			case "Float": HFloat;
			case "Bool": HBool;
			case "String": HString;
			case "Void": HVoid;
			case _: HDynamic;
		}
		if (d == null) return HDynamic;
		if (Reflect.hasField(d, "null")) return HNull(of(Reflect.field(d, "null")));
		if (Reflect.hasField(d, "array")) return HArray(of(d.array));
		if (Reflect.hasField(d, "fn")) return HFn(args(d.fn), of(d.ret));
		if (Reflect.hasField(d, "anon")) return HAnon(args(d.anon));
		if (Reflect.hasField(d, "class")) return HClass(Reflect.field(d, "class"), [for (p in (d.params : Array<Dynamic>)) of(p)]);
		if (Reflect.hasField(d, "read")) return HRead(of(d.read));
		if (Reflect.hasField(d, "view")) return HView(d.view);
		if (Reflect.hasField(d, "abstract")) return HAbstract(Reflect.field(d, "abstract"), [for (p in (d.params : Array<Dynamic>)) of(p)], of(d.under), d.values);
		if (Reflect.hasField(d, "enum")) return HEnum(Reflect.field(d, "enum"));
		if (Reflect.hasField(d, "param")) return HParam(d.param);
		return HDynamic;
	}

	static function args(list:Array<Dynamic>):Array<HArg>
		return [for (a in list) {name: a.name, opt: a.opt == true, t: of(a.t)}];

	// through Null and abstracts (but Read, ViewOf): what values look like
	public static function bare(t:HType):HType
		return switch t {
			case HNull(x): bare(x);
			case HAbstract(_, _, under, null): bare(under);
			case _: t;
		}
}

// A member of a class of the API (Manifest's Member).
class MMember {
	public final name:String;
	public final kind:String;
	public final type:HType;
	public final value:Dynamic;
	public final get:Null<String>;
	public final set:Null<String>;
	public final mount:Bool;
	public final readonly:Bool;

	public function new(name:String, d:Dynamic) {
		this.name = name;
		kind = d.kind;
		type = HTypes.of(d.type);
		value = d.value;
		get = d.get;
		set = d.set;
		mount = d.mount == true;
		readonly = d.readonly == true;
	}
}

// A class of the API (Manifest's Class).
class MClass {
	public final path:String;
	public final ident:String;
	public final type:String;
	public final rendered:Null<String>;
	public final only:Null<Array<String>>;
	public final other:Map<String, String> = [];
	public final isInterface:Bool;
	public final statics:Map<String, MMember> = [];
	public final members:Map<String, MMember> = [];
	public final ctor:Null<HType>;

	public function new(path:String, d:Dynamic) {
		this.path = path;
		ident = d.ident;
		type = d.type;
		rendered = d.rendered;
		isInterface = Reflect.field(d, "interface") == true;
		if (d.limits != null) {
			only = d.limits.only;
			for (r in Reflect.fields(d.limits.other)) other.set(r, Reflect.field(d.limits.other, r));
		} else only = null;
		for (f in Reflect.fields(d.statics)) statics.set(f, new MMember(f, Reflect.field(d.statics, f)));
		for (f in Reflect.fields(d.members)) members.set(f, new MMember(f, Reflect.field(d.members, f)));
		ctor = d.ctor == null ? null : HTypes.of(d.ctor);
	}
}

// A renderer's contract (Manifest's Renderer).
class MRenderer {
	public final path:String;
	public final id:Int;
	public final node:Null<String>;
	public final runtime:String;
	public final runtimeFunctions:Array<String>;
	public final elements:Null<Array<String>>;
	public final events:Null<Map<String, HType>>;
	public final neutral:Bool;
	public final native:Bool;
	public final markEnds:Bool;
	public final functions:Map<String, String> = [];
	public final setters:Null<{names:Map<String, String>, prefixes:Map<String, String>, fallback:Null<String>}>;

	public function new(path:String, d:Dynamic) {
		this.path = path;
		id = d.id;
		node = d.node;
		runtime = d.runtime;
		runtimeFunctions = d.runtimeFunctions;
		elements = d.elements;
		events = d.events == null ? null : [for (f in Reflect.fields(d.events)) f => HTypes.of(Reflect.field(d.events, f))];
		neutral = d.neutral == true;
		native = d.native == true;
		markEnds = d.markEnds == true;
		for (f in Reflect.fields(d.functions)) functions.set(f, Reflect.field(d.functions, f));
		setters = d.setters == null ? null : {
			names: [for (f in Reflect.fields(d.setters.names)) f => Reflect.field(d.setters.names, f)],
			prefixes: [for (f in Reflect.fields(d.setters.prefixes)) f => Reflect.field(d.setters.prefixes, f)],
			fallback: d.setters.fallback
		};
	}

	// the function setting attribute name (setters), or null: setProperty's
	public function setter(name:String):Null<String> {
		if (setters == null) return null;
		var s = setters.names.get(name);
		if (s != null) return s;
		for (p => f in setters.prefixes) if (StringTools.startsWith(name, p)) return f;
		return setters.fallback;
	}
}

// The manifest the build's typing made (helder.typescript.api.Manifest): its
// modules' (each its declaration class's @:helder.manifest), merged.
class Manifest {
	// (the metadata a module's part is on its declaration class)
	public static inline final META = ":helder.manifest";

	public final classes:Map<String, MClass> = [];
	public final byType:Map<String, MClass> = [];
	public final renderers:Map<String, MRenderer> = [];
	public final neutralEvents:Map<String, HType> = [];
	// (the declaration classes, by their idents: their __init__s name the functions it lists, dropped after the lowering)
	public final keep:Array<String> = [];

	public function new(parts:Array<{ident:String, json:String}>) {
		for (part in parts) {
			var d:Dynamic = haxe.Json.parse(part.json);
			if (d.version != 1) throw "TSHX004: the manifest of " + d.module + " is of another version (" + d.version + ")";
			keep.push(part.ident);
			for (p in Reflect.fields(d.classes)) {
				var c = new MClass(p, Reflect.field(d.classes, p));
				classes.set(p, c);
				byType.set(c.type, c);
			}
			for (p in Reflect.fields(d.renderers)) if (!renderers.exists(p)) renderers.set(p, new MRenderer(p, Reflect.field(d.renderers, p)));
			if (d.neutralEvents != null) for (f in Reflect.fields(d.neutralEvents)) neutralEvents.set(f, HTypes.of(Reflect.field(d.neutralEvents, f)));
		}
	}

	public function cls(path:String):Null<MClass> return classes.exists(path) ? classes.get(path) : byType.get(path);
}

// A Haxe class helder's declaration files declare to TypeScript programs:
// its name there, its Haxe type path.
class ForeignClass {
	public final name:String;
	public final path:String;
	public final node:Node;

	public function new(name, path, node) {
		this.name = name;
		this.path = path;
		this.node = node;
	}
}

enum Foreign {
	FClass(c:ForeignClass);
	// one of a class's statics: a function, a component (`const f: typeof Class.f`)
	FStatic(c:ForeignClass, member:String);
}

// helder's API as declaration files declare it to TypeScript programs
// (src/helder/view/index.d.ts, generated by helder.typescript.api.Declarations
// from a module's declaration class, as a program's own are): a declared
// class is the Haxe class `__haxe` names (else the one of its name in the
// file's package, the directories below src/), a declared `const name:
// typeof Class.member` that class's static; `__haxe`'s `__module` names the
// module's declaration class (helder.typescript.api.Modules), which the
// build types: its manifest (Manifest) gives their members and types. What
// the program imports from such files resolves by symbol.
class Api {
	final bySymbol:Map<String, Foreign> = [];
	final classesBySymbol:Map<String, ForeignClass> = [];
	final exports:Map<String, Map<String, Foreign>> = [];
	// (helder/view's types the lowering knows: Signal, Memo, Read, by symbol)
	final known:Map<String, String> = [];
	// what the manifest is made of: the modules' declaration classes (`__module`)
	public final modules:Array<String> = [];
	public var manifest:Null<Manifest> = null;

	public function new(project:Project) {
		for (sf in project.declarations) index(sf);
		// (the program's imports of them)
		for (sf in project.files) for (n in sf.root.statements()) if (n.kind == KindImportDeclaration) {
			var target = project.resolve(n.moduleSpecifier());
			var clause = n.importClause();
			if (target == null || clause == null || clause.namedBindings() == null || clause.namedBindings().kind != KindNamedImports) continue;
			var from = project.declarations.find(d -> d.path == target);
			if (from == null) continue;
			for (spec in clause.namedBindings().elements()) {
				var exported = (spec.propertyName() ?? spec.name()).text;
				var f = exports.exists(from.path) ? exports.get(from.path).get(exported) : null;
				if (f != null && spec.name().symbol != null) bySymbol.set(spec.name().symbol, f);
			}
		}
		linkImports(project);
		// (a signal called with one argument: whether it is a function, an update, by its type)
		for (sf in project.files) for (i in 1...sf.count) if (sf.kindAt(i) == KindCallExpression) {
			var n = sf.node(i);
			var args = n.arguments() ?? [];
			if (args.length == 1 && isSignal(n.expression().tsType)) {
				var a = args[0];
				while (a.kind == KindParenthesizedExpression) a = a.expression();
				project.types.callable(a.tsType);
			}
		}
	}

	// what an identifier names, when it is helder's
	public function of(id:Node):Null<Foreign> return id.kind == KindIdentifier && id.symbol != null ? bySymbol.get(id.symbol) : null;

	// the class a type's values are instances of, when it is helder's
	public function classOf(t:Null<TsType>):Null<ForeignClass> return t == null || t.symbol == null ? null : classesBySymbol.get(t.symbol);

	// whether a type is helder/view's Signal (a value called to read, write and update it)
	public function isSignal(t:Null<TsType>):Bool return t != null && t.symbol != null && known.get(t.symbol) == "Signal";

	public function isMemo(t:Null<TsType>):Bool return t != null && t.symbol != null && known.get(t.symbol) == "Memo";

	// whether a type node names helder/view's Read (a component's prop that reads)
	public function namesRead(typeNode:Null<Node>):Bool {
		if (typeNode == null || typeNode.kind != KindTypeReference) return false;
		var name = typeNode.typeName();
		return name != null && name.kind == KindIdentifier && name.symbol != null && (known.get(name.symbol) == "Read" || isImportOf(name, "Read"));
	}

	final importedKnown:Map<String, String> = [];

	function isImportOf(id:Node, what:String):Bool return importedKnown.get(id.symbol) == what;

	function index(sf:SourceFile) {
		var named = new Map<String, String>(), classes = new Map<String, ForeignClass>(), out = new Map<String, Foreign>();
		exports.set(sf.path, out);
		var module:Null<String> = null;
		for (n in sf.root.statements()) if (n.kind == KindVariableStatement) for (d in n.declarationList().declarations())
			if (d.name().kind == KindIdentifier && d.name().text == "__haxe" && d.type() != null && d.type().kind == KindTypeLiteral)
				for (m in d.type().members()) if (m.kind == KindPropertySignature && m.type() != null && m.type().kind == KindLiteralType) {
					if (m.name().text == "__module") module = m.type().literal().text;
					else named.set(m.name().text, m.type().literal().text);
				}
		var pack = packageOf(sf.path);
		for (n in sf.root.statements()) if (n.kind == KindClassDeclaration && n.name() != null) {
			var name = n.name().text;
			var path = named.get(name) ?? (pack == "" ? name : pack + "." + name);
			var c = new ForeignClass(name, path, n);
			classes.set(name, c);
			if (n.name().symbol != null) {
				classesBySymbol.set(n.name().symbol, c);
				bySymbol.set(n.name().symbol, FClass(c));
			}
			out.set(name, FClass(c));
		}
		if (module != null && modules.indexOf(module) < 0) modules.push(module);
		// (helder/view's types: Signal and Memo interfaces, Read an alias)
		if (module == "helder.view.TypeScript")
			for (n in sf.root.statements()) if ((n.kind == KindInterfaceDeclaration || n.kind == KindTypeAliasDeclaration) && n.name() != null && n.name().symbol != null)
				known.set(n.name().symbol, n.name().text);
		for (n in sf.root.statements()) if (n.kind == KindVariableStatement) for (d in n.declarationList().declarations()) {
			var t = d.type();
			if (d.name().kind != KindIdentifier || t == null || t.kind != KindTypeQuery) continue;
			var q = t.exprName();
			if (q.kind != KindQualifiedName || q.left().kind != KindIdentifier || !classes.exists(q.left().text)) continue;
			var f = FStatic(classes.get(q.left().text), q.right().text);
			out.set(d.name().text, f);
			if (d.name().symbol != null) bySymbol.set(d.name().symbol, f);
		}
	}

	// (the program's imports of helder/view's types: their local symbols)
	function linkImports(project:Project) {
		for (sf in project.files) for (n in sf.root.statements()) if (n.kind == KindImportDeclaration) {
			var clause = n.importClause();
			if (clause == null || clause.namedBindings() == null || clause.namedBindings().kind != KindNamedImports) continue;
			for (spec in clause.namedBindings().elements()) {
				var exported = (spec.propertyName() ?? spec.name()).text;
				if (spec.name().symbol != null && (exported == "Read" || exported == "Signal" || exported == "Memo")) {
					var target = project.resolve(n.moduleSpecifier());
					var from = project.declarations.find(d -> d.path == target);
					if (from != null) importedKnown.set(spec.name().symbol, exported);
				}
			}
		}
	}

	// a declaration file's Haxe package: its directories below the last src/
	static function packageOf(path:String):String {
		var parts = haxe.io.Path.directory(path).split("/");
		var at = parts.lastIndexOf("src");
		return at < 0 ? "" : parts.slice(at + 1).join(".");
	}
}
