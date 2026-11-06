package helder.typescript.lower;

import helder.definition.Kernel;
import helder.ui.actions.ActionsDefinition;
import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;
import helder.typescript.lower.Definitions;

// actions(namespace, {...})'s TypeScript adapter (ActionsDefinition's,
// Haxe's an enum's: ActionsMacro): the object literal's methods (or arrow
// functions) are the actions, their parameters' annotations the arguments'
// types (number, string, boolean, T | null, arrays, object types of these),
// described to the handler as ArgTypes. A method with arguments returns
// them as an object, `{percent}` (what TypeScript types the action as),
// and one without is empty: the bodies are never run.
class TsActionsAdapter extends TsAdapter implements ActionsAdapter {
	public function new(src:Project, defines:String->Null<String>) {
		super(src, defines, "actions");
	}

	public function declared(k:KNode):Array<{name:String, type:String, params:Array<{name:String, type:ArgType, pos:KPos}>, pos:KPos}> {
		var fields = switch k.value {
			case KObject(fs): fs;
			case _: error('the actions are an object literal of methods, not ${k.describe()}', k.pos);
		}
		return [
			for (f in fields) {
				var fn = switch f.node.value {
					case KFunction(fn): fn;
					case _: error('${f.name} is a method (its parameters the action\'s arguments), not ${f.node.describe()}', f.node.pos);
				}
				var d:Node = fn.source;
				var params = [
					for (p in d.parameters()) {
						if (p.name().kind != KindIdentifier) error('${f.name}: an argument is a plain parameter, named', p);
						if (p.dotDotDotToken() != null) error('${f.name}: an action takes a fixed number of arguments', p);
						if (p.type() == null) error('${f.name}: the parameter ${p.name().text} needs its type (an argument is read from a JSON keymap)', p);
						var t = argType(p.type());
						{name: p.name().text, type: p.questionToken() != null || p.initializer() != null ? new ArgType(t.text, () -> ANull(t)) : t, pos: (p : KPos)};
					}
				];
				actionBody(f.name, d, [for (p in params) p.name]);
				{name: f.name, type: f.name, params: params, pos: (d : KPos)};
			}
		];
	}

	// (its body: empty, or `return {a, b}` of its parameters in order)
	function actionBody(name:String, d:Node, params:Array<String>) {
		var b = d.body();
		var want = params.length == 0 ? "empty ({})" : "`return { " + params.join(", ") + " };` (its arguments as an object, what TypeScript types the action as)";
		function fail():Dynamic
			return error('$name\'s body is $want', b ?? d);
		if (b == null) fail();
		var result:Null<Node> = null;
		if (b.kind == KindBlock) {
			var ss = b.statements();
			if (ss.length == 0 && params.length == 0) return;
			if (ss.length != 1 || ss[0].kind != KindReturnStatement || ss[0].expression() == null) fail();
			result = ss[0].expression();
		} else result = b;
		while (result.kind == KindParenthesizedExpression)
			result = result.expression();
		if (result.kind != KindObjectLiteralExpression) fail();
		var props = result.properties();
		if (props.length != params.length) fail();
		for (i in 0...props.length)
			if (props[i].kind != KindShorthandPropertyAssignment || props[i].name().text != params[i]) fail();
	}

	// ---- types, by their annotations

	function argType(t:Node):ArgType {
		var text = t.file.slice(t.file.skipTrivia(t.pos), t.end);
		return new ArgType(text, () -> argKind(t));
	}

	function argKind(t:Node):ArgKind {
		return switch t.kind {
			case KindNumberKeyword: ANumber;
			case KindBooleanKeyword: ABool;
			case KindStringKeyword: AString;
			case KindParenthesizedType: argKind(t.type());
			case KindAnyKeyword | KindUnknownKeyword | KindObjectKeyword: ABad("dynamic");
			case KindVoidKeyword | KindUndefinedKeyword | KindNullKeyword: ABad("Void");
			case KindLiteralType if (t.literal().kind == KindNullKeyword): ABad("Void");
			case KindLiteralType: switch t.literal().kind {
					case KindNumericLiteral: ANumber;
					case KindStringLiteral: AString;
					case _: ABool;
				}
			case KindFunctionType: ABad("a function");
			case KindArrayType: AList(argType(t.elementType()));
			case KindTypeOperator: argKind(t.type());
			case KindUnionType:
				var rest = [for (m in t.types()) if (!argNullish(m)) m];
				if (rest.length == 1 && rest.length < t.types().length) ANull(argType(rest[0])) else if (rest.length == 1) argKind(rest[0]) else
					ABad("a union");
			case KindTypeLiteral: argFields(t.members());
			case KindTypeReference if (t.typeName().kind == KindIdentifier): argReference(t, t.typeName().text);
			case _: ABad("not a type JSON gives");
		}
	}

	static function argNullish(m:Node):Bool
		return m.kind == KindUndefinedKeyword || m.kind == KindNullKeyword || (m.kind == KindLiteralType && m.literal().kind == KindNullKeyword);

	function argReference(t:Node, n:String):ArgKind {
		var args = t.typeArguments() ?? [];
		switch n {
			case "Array" | "ReadonlyArray" if (args.length == 1): return AList(argType(args[0]));
			case _:
		}
		var file = t.file;
		var from = Scope.imported(file, n);
		function find(kind:Kind):Null<Node>
			return from != null ? declaration(from.specifier, from.name, kind) : Scope.declared(file, n, kind);
		var alias = find(KindTypeAliasDeclaration);
		if (alias != null) return alias.typeParameters() != null && alias.typeParameters().length > 0 ? ABad("a type parameter") : argKind(alias.type());
		var face = find(KindInterfaceDeclaration);
		if (face != null) return argFields(face.members());
		if (find(KindClassDeclaration) != null || from != null || ["Map", "Set", "Date", "WeakMap", "RegExp", "Promise", "Error"].contains(n))
			return ABad("a class");
		return ABad("a type parameter");
	}

	function argFields(members:Array<Node>):ArgKind {
		var fs = [];
		for (m in members) {
			if (m.kind != KindPropertySignature) return ABad("an object with methods");
			if (m.type() == null) return ABad("dynamic");
			fs.push({name: m.name().text, type: argType(m.type()), optional: m.questionToken() != null});
		}
		return AFields(fs);
	}
}
