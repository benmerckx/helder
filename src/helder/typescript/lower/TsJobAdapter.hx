package helder.typescript.lower;

import helder.definition.Kernel;
import helder.jobs.JobDefinition;
import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;
import helder.typescript.lower.Definitions;

// job(f)'s TypeScript adapter (JobDefinition's, Haxe's Sendable): f a
// module-level function of the program, named; its input's and result's
// types its annotations (described to the check as SendTypes: number,
// boolean, string, Uint8Array, T | null, arrays, object types of these);
// the module-level constants it reads, and those the functions it calls
// read, found in its body (a worker's instance has its module of its own:
// they are sent with the input), each typed by its annotation or its
// literal. What else it reads is refused: a class, helder's API (the main
// thread's), a variable of another module.
class TsJobAdapter extends TsAdapter implements JobAdapter {
	static inline var NAMED = "a job is a static or module-level function, named (Class.field, field)";

	final project:Project;
	// (the job's function's file: the constants it reads are its module's)
	var home:Null<SourceFile> = null;

	public function new(src:Project, defines:String->Null<String>) {
		super(src, defines, "job");
		project = src;
	}

	public function signature(k:KNode):JobSignature {
		var id:Node = k.pos;
		var d = switch k.value {
			case KRef(_): function_(id);
			case _: null;
		}
		if (d == null) return error(NAMED, k.pos);
		var name = d.name().text;
		home = d.file;
		var inputs = [
			for (p in d.parameters()) {
				if (p.type() == null) error('$name: the parameter ${p.name().text} needs its type (a job\'s input is sent)', p);
				sendType(p.type());
			}
		];
		var result = d.type() == null ? null : d.type().kind == KindVoidKeyword ? null : sendType(d.type());
		if (d.type() == null) error('$name: its result needs its type (a job\'s result is sent)', d);
		var captures = [];
		visit(d, d, [d => true], captures);
		return {
			name: name,
			inputs: inputs,
			result: result,
			captures: captures,
			gcFree: false,
			source: d
		};
	}

	// the module-level function declaration an identifier names (here or imported), or null
	function function_(id:Node):Null<Node> {
		var d = Scope.declared(id.file, id.text, KindFunctionDeclaration);
		if (d != null) return d;
		var from = Scope.imported(id.file, id.text);
		return from == null ? null : declarationOf(from.specifier, from.name, KindFunctionDeclaration);
	}

	function declarationOf(specifier:Node, name:String, kind:Kind):Null<Node> {
		var path = project.resolve(specifier);
		if (path == null) return null;
		for (f in project.files)
			if (f.path == path) return Scope.declared(f, name, kind);
		return null;
	}

	// ---- what a function reads

	function visit(n:Node, fn:Node, seen:Map<Node, Bool>, out:Array<{name:String, type:SendType, pos:KPos}>) {
		if (n.kind == KindIdentifier && reference(n) && !declaredIn(n.text, n, fn)) outer(n, fn, seen, out);
		for (c in n.children())
			visit(c, fn, seen, out);
	}

	// (an identifier that names a binding: not a member's name, a key, a type)
	static function reference(n:Node):Bool {
		var p = n.parent;
		if (p == null) return false;
		return switch p.kind {
			case KindPropertyAccessExpression: p.name() != n;
			case KindPropertyAssignment | KindMethodDeclaration | KindPropertySignature | KindPropertyDeclaration: p.name() != n;
			case KindTypeReference | KindQualifiedName | KindTypeAliasDeclaration | KindInterfaceDeclaration | KindTypeParameter: false;
			case KindVariableDeclaration | KindParameter | KindFunctionDeclaration | KindBindingElement | KindImportSpecifier: p.name() != n;
			case KindLabeledStatement | KindBreakStatement | KindContinueStatement: false;
			case _: !inType(n);
		}
	}

	static function inType(n:Node):Bool {
		var p = n.parent;
		while (p != null) {
			switch p.kind {
				case KindTypeReference | KindTypeLiteral | KindUnionType | KindArrayType | KindFunctionType | KindTypeQuery: return true;
				case KindBlock | KindSourceFile: return false;
				case _:
			}
			p = p.parent;
		}
		return false;
	}

	// whether name is declared inside fn (its parameters, locals, nested functions), where n is
	static function declaredIn(name:String, n:Node, fn:Node):Bool {
		var found = false;
		function walk(x:Node) {
			if (found) return;
			switch x.kind {
				case KindVariableDeclaration | KindParameter | KindFunctionDeclaration | KindBindingElement | KindClassDeclaration
					| KindFunctionExpression:
					if (x != fn && x.name() != null && x.name().kind == KindIdentifier && x.name().text == name) found = true;
				case _:
			}
			for (c in x.children())
				walk(c);
		}
		for (p in fn.parameters())
			walk(p);
		if (fn.body() != null) walk(fn.body());
		return found;
	}

	// a name the function reads from outside it
	function outer(n:Node, fn:Node, seen:Map<Node, Bool>, out:Array<{name:String, type:SendType, pos:KPos}>) {
		var name = n.text;
		var f = function_(n);
		if (f != null) {
			if (!seen.exists(f)) {
				seen.set(f, true);
				if (f.body() != null) visit(f.body(), f, seen, out);
				for (p in f.parameters())
					if (p.initializer() != null) visit(p.initializer(), f, seen, out);
			}
			return;
		}
		var v = Scope.declared(n.file, name, KindVariableDeclaration);
		if (v != null) {
			if (n.file != home) error('a job cannot read `$name`: a variable of another module than its function', n);
			if (Lambda.exists(out, c -> c.name == name)) return;
			var list = v.parent;
			if (list != null && list.flags & NodeFlags.Const == 0) error('a job cannot read `$name`: a let or var (a job reads module-level constants, sent with its input)', n);
			out.push({name: name, type: constType(v), pos: (n : KPos)});
			return;
		}
		if (Scope.declared(n.file, name, KindClassDeclaration) != null) error('a job cannot read `$name`: a class (shared mutable state)', n);
		var from = Scope.imported(n.file, name);
		if (from != null) {
			var path = project.resolve(from.specifier);
			var api = path == null || Lambda.exists(project.declarations, d -> d.path == path);
			error('a job cannot read `$name`: ' + (api ? "helder's API (it is the main thread's)" : "an import that is not a function"), n);
		}
		// (else a global of JavaScript's: Math, JSON, Number...)
	}

	// a constant's type: its annotation, else its literal's
	function constType(v:Node):SendType {
		if (v.type() != null) return sendType(v.type());
		var i = v.initializer();
		var t:Null<SendKind> = i == null ? null : switch i.kind {
			case KindNumericLiteral: SFloat;
			case KindPrefixUnaryExpression if (i.operand().kind == KindNumericLiteral): SFloat;
			case KindStringLiteral | KindNoSubstitutionTemplateLiteral: SString;
			case KindTrueKeyword | KindFalseKeyword: SBool;
			case _: null;
		}
		if (t == null) error('a job cannot read `${v.name().text}`: give it a type (a constant read by a job is sent with its input)', v);
		var k = t;
		return new SendType(k == SFloat ? "number" : k == SString ? "string" : "boolean", () -> k);
	}

	// ---- types, by their annotations

	function sendType(t:Node):SendType {
		var text = t.file.slice(t.file.skipTrivia(t.pos), t.end);
		return new SendType(text, () -> sendKind(t, text));
	}

	function sendKind(t:Node, text:String):SendKind {
		return switch t.kind {
			case KindNumberKeyword: SFloat;
			case KindBooleanKeyword: SBool;
			case KindStringKeyword: SString;
			case KindParenthesizedType: sendKind(t.type(), text);
			case KindAnyKeyword | KindUnknownKeyword | KindObjectKeyword: SBad("dynamic");
			case KindVoidKeyword | KindUndefinedKeyword | KindNullKeyword: SBad("Void");
			case KindLiteralType if (t.literal().kind == KindNullKeyword): SBad("Void");
			case KindLiteralType: switch t.literal().kind {
					case KindNumericLiteral: SFloat;
					case KindStringLiteral: SString;
					case _: SBool;
				}
			case KindFunctionType: SBad("a function");
			case KindArrayType: SList(sendType(t.elementType()));
			case KindTypeOperator: sendKind(t.type(), text);
			case KindUnionType:
				var rest = [for (m in t.types()) if (!nullish(m)) m];
				if (rest.length == 1 && rest.length < t.types().length) SNull(sendType(rest[0])) else if (rest.length == 1) sendKind(rest[0], text) else
					SBad("a union (not yet)");
			case KindTypeLiteral: fields(t.members(), text);
			case KindTypeReference if (t.typeName().kind == KindIdentifier): reference_(t, t.typeName().text, text);
			case _: SBad("not a type a job knows");
		}
	}

	static function nullish(m:Node):Bool
		return m.kind == KindUndefinedKeyword || m.kind == KindNullKeyword || (m.kind == KindLiteralType && m.literal().kind == KindNullKeyword);

	function reference_(t:Node, n:String, text:String):SendKind {
		var args = t.typeArguments() ?? [];
		switch n {
			case "Array" | "ReadonlyArray" if (args.length == 1): return SList(sendType(args[0]));
			case "Uint8Array": return SBytes;
			case _:
		}
		var file = t.file;
		var from = Scope.imported(file, n);
		function find(kind:Kind):Null<Node>
			return from != null ? declarationOf(from.specifier, from.name, kind) : Scope.declared(file, n, kind);
		var alias = find(KindTypeAliasDeclaration);
		if (alias != null) return alias.typeParameters() != null && alias.typeParameters().length > 0 ? SBad("generic (its values' types must be known)") : sendKind(alias.type(), text);
		var face = find(KindInterfaceDeclaration);
		if (face != null) return fields(face.members(), text);
		if (find(KindClassDeclaration) != null || from != null || ["Map", "Set", "Date", "WeakMap", "RegExp", "Promise", "Error"].contains(n))
			return SBad("a class (shared mutable state)");
		return SBad("a type parameter (not known to be sendable)");
	}

	function fields(members:Array<Node>, text:String):SendKind {
		var fs = [];
		for (m in members) {
			if (m.kind != KindPropertySignature) return SBad("an object with methods");
			if (m.type() == null) return SBad("dynamic");
			var t = sendType(m.type());
			fs.push({name: m.name().text, type: m.questionToken() != null ? new SendType(t.text, () -> SNull(t)) : t});
		}
		fs.sort((x, y) -> x.name < y.name ? -1 : 1);
		return SFields(fs);
	}
}
