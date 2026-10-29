package helder.typescript.glue;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;
import helder.typescript.check.Types.TsType;

using Lambda;

// A Haxe class helder declares to TypeScript programs: its path, its type
// parameters (as many as its declaration's).
class ForeignClass {
	public final name:String;
	public final path:String;
	public final params:Int;
	public final node:Node;

	public function new(name, path, params, node) {
		this.name = name;
		this.path = path;
		this.params = params;
		this.node = node;
	}

	// the Haxe type of its instances (its type parameters Dynamic)
	public function haxeType():String return params == 0 ? path : path + "<" + [for (_ in 0...params) "Dynamic"].join(", ") + ">";
}

enum Foreign {
	FClass(c:ForeignClass);
	// one of a class's statics: a function, a component (`const f: typeof Class.f`)
	FStatic(c:ForeignClass, member:String);
}

// helder's API as declaration files declare it to TypeScript programs
// (src/helder/view/index.d.ts, ...): a declared class is the Haxe class of
// its name in the file's package (the directories below src/; another one
// named in the file's `declare const __haxe: {Name: "pack.Class"}`), a
// declared `const name: typeof Class.member` that class's static. What the
// program imports from such files resolves by symbol: the classes, and the
// program's names for them.
class Declarations {
	final bySymbol:Map<String, Foreign> = [];
	final classesBySymbol:Map<String, ForeignClass> = [];

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
				var f = exportOf(from, exported);
				if (f != null && spec.name().symbol != null) bySymbol.set(spec.name().symbol, f);
			}
		}
	}

	// what an identifier names, when it is helder's
	public function of(id:Node):Null<Foreign> return id.kind == KindIdentifier && id.symbol != null ? bySymbol.get(id.symbol) : null;

	// the class a type's values are instances of, when it is helder's
	public function classOf(t:Null<TsType>):Null<ForeignClass> return t == null || t.symbol == null ? null : classesBySymbol.get(t.symbol);

	final exports:Map<String, Map<String, Foreign>> = [];

	function exportOf(sf:SourceFile, name:String):Null<Foreign> return exports.exists(sf.path) ? exports.get(sf.path).get(name) : null;

	function index(sf:SourceFile) {
		var named = new Map<String, String>(), classes = new Map<String, ForeignClass>(), out = new Map<String, Foreign>();
		exports.set(sf.path, out);
		for (n in sf.root.statements()) if (n.kind == KindVariableStatement) for (d in n.declarationList().declarations())
			if (d.name().kind == KindIdentifier && d.name().text == "__haxe" && d.type() != null && d.type().kind == KindTypeLiteral)
				for (m in d.type().members()) if (m.kind == KindPropertySignature && m.type() != null && m.type().kind == KindLiteralType)
					named.set(m.name().text, m.type().literal().text);
		var pack = packageOf(sf.path);
		for (n in sf.root.statements()) if (n.kind == KindClassDeclaration && n.name() != null) {
			var name = n.name().text;
			var path = named.get(name) ?? (pack == "" ? name : pack + "." + name);
			var c = new ForeignClass(name, path, (n.typeParameters() ?? []).length, n);
			classes.set(name, c);
			if (n.name().symbol != null) classesBySymbol.set(n.name().symbol, c);
			out.set(name, FClass(c));
			if (n.name().symbol != null) bySymbol.set(n.name().symbol, FClass(c));
		}
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

	// a declaration file's Haxe package: its directories below the last src/
	static function packageOf(path:String):String {
		var parts = haxe.io.Path.directory(path).split("/");
		var at = parts.lastIndexOf("src");
		return at < 0 ? "" : parts.slice(at + 1).join(".");
	}
}
