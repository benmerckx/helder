package helder.typescript.glue;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;
import helder.typescript.glue.Declarations;

using Lambda;
using StringTools;

// A glue function: its name, and the TypeScript expressions whose values it
// takes, in the order the program evaluates them.
class GlueCall {
	public final name:String;
	public final args:Array<Node>;

	public function new(name, args) {
		this.name = name;
		this.args = args;
	}
}

// The glue between a TypeScript program and helder's Haxe API: a Haxe module
// written before Haxe types the program (helder.typescript.Compiler's
// beforeTypingHook), with a function for each call into the API, each
// member of one of its values read or written, each TSX literal (helder.view's
// markup, compiled by its macro), and one per TypeScript component a literal
// names. Haxe's typer converts the values (helder.typescript.js.Interop) by
// the API's own types; the frontend calls the functions (Dynamic values in
// and out).
class Glue {
	public static inline var PACK = "helder_program";
	public static inline var CLASS = "Program";

	// by the node each lowers: a call, a new, a member read, a TSX literal
	public final calls:Map<Node, GlueCall> = [];
	// member writes: the receiver (an instance's), then the value
	public final sets:Map<Node, GlueCall> = [];
	// the TypeScript components TSX names: given to the glue when the program starts
	public final components:Array<{declaration:Node, setter:String}> = [];

	final project:Project;
	final declarations:Declarations;
	final functions:Array<String> = [];
	final keeps:Array<String> = [];
	final imports:Map<String, String> = [];
	final componentOf:Map<Node, String> = [];
	var markup = false;

	public function new(project:Project) {
		this.project = project;
		declarations = new Declarations(project);
		for (sf in project.files) visit(sf.root);
	}

	// the module's path, and its IR functions' prefix (hxmc's names for statics)
	public static function module():String return PACK + "." + CLASS;

	public static function irName(name:String):String return PACK + "_" + CLASS + "_" + name;

	public function source(entry:String):String {
		var out = ['package $PACK;', '', 'import helder.typescript.js.Interop;'];
		for (alias => path in imports) out.push('import $path as $alias;');
		out.push('');
		out.push('// helder.typescript.glue: $entry\'s calls into helder\'s Haxe API, its members and TSX, typed by Haxe');
		out.push('class $CLASS' + (markup ? ' implements helder.view.Markup' : '') + ' {');
		out.push('\tstatic function main() {');
		out.push('\t\thelder.typescript.js.Seed.main();');
		for (k in keeps) out.push('\t\t$k;');
		out.push('\t}');
		for (f in functions) out.push('\n\t' + f);
		out.push('}');
		return out.join("\n") + "\n";
	}

	function fail(n:Node, message:String):Dynamic return project.fail(n, message);

	function where(n:Node):String return Project.relative(n.file.path) + ":" + n.file.line(n.file.skipTrivia(n.pos));

	static function quote(s:String):String return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t") + '"';

	// ---- the program, node by node

	function visit(n:Node) {
		if (n == null) return;
		switch n.kind {
			case KindImportDeclaration | KindTypeReference | KindTypeQuery | KindExpressionWithTypeArguments | KindInterfaceDeclaration | KindTypeAliasDeclaration:
				return;
			case KindCallExpression if (call(n)):
				return;
			case KindNewExpression if (construct(n)):
				return;
			case KindPropertyAccessExpression if (member(n)):
				return;
			case KindJsxElement | KindJsxSelfClosingElement | KindJsxFragment:
				literal(n);
				return;
			case KindIdentifier if (declarations.of(n) != null && !typePosition(n)):
				fail(n, "helder's " + n.text + " is used as a value: call it, construct it or read its members");
			case _:
		}
		for (c in n.children()) visit(c);
	}

	static function typePosition(id:Node):Bool {
		var p = id.parent;
		return p != null && (p.kind == KindTypeReference || p.kind == KindQualifiedName || p.kind == KindTypeQuery || p.kind == KindImportSpecifier
			|| p.kind == KindExpressionWithTypeArguments || p.kind == KindExportSpecifier);
	}

	// a function's parameters: the values of the nodes passed, in order;
	// its code at the node's place in the program (Haxe's errors there)
	function glue(node:Node, plan:Array<Node>, body:String, returns:Bool):String {
		var name = "g" + functions.length;
		var params = [for (i in 0...plan.length) 'p$i:Dynamic'].join(", ");
		var at = place(node);
		functions.push(returns ? 'public static function $name($params):Dynamic return Interop.result($body, $at);' : 'public static function $name($params):Void Interop.at($body, $at);');
		keeps.push('$name(' + [for (_ in plan) "null"].join(", ") + ')');
		return name;
	}

	// (a node's file and byte range: Interop.at's)
	static function place(n:Node):String
		return quote(sys.FileSystem.fullPath(n.file.path)) + ", " + n.file.offset(n.file.skipTrivia(n.pos)) + ", " + n.file.offset(n.end);

	static function param(plan:Array<Node>, n:Node):String {
		plan.push(n);
		return "p" + (plan.length - 1);
	}

	static function strip(n:Node):Node {
		while (n.kind == KindParenthesizedExpression) n = n.expression();
		return n;
	}

	// an argument: inline markup, an instance of one of helder's classes (cast, so a macro sees its class), else converted
	function argument(plan:Array<Node>, a:Node):String {
		var e = strip(a);
		if (e.kind == KindJsxElement || e.kind == KindJsxSelfClosingElement || e.kind == KindJsxFragment) return markupOf(plan, e);
		if (a.kind == KindSpreadElement) return fail(a, "a spread among the arguments of a call into helder's API");
		var c = declarations.classOf(a.tsType);
		var p = param(plan, a);
		visit(a);
		return c != null ? '(cast Interop.instance($p, ${c.path}, ${quote(where(a))}) : ${c.haxeType()})' : 'Interop.fromJs($p, ${quote(where(a))})';
	}

	// a call of helder's: a class's static, or an instance's method
	function call(n:Node):Bool {
		var callee = strip(n.expression());
		var plan:Array<Node> = [];
		var target:String = null;
		switch callee.kind {
			case KindIdentifier:
				switch declarations.of(callee) {
					case FStatic(c, m): target = '${c.path}.$m';
					case FClass(c): return fail(n, '${c.name} is a class: construct it with new');
					case null: return false;
				}
			case KindPropertyAccessExpression if (callee.questionDotToken() == null && n.questionDotToken() == null):
				var receiver = strip(callee.expression());
				switch declarations.of(receiver) {
					case FClass(c): target = '${c.path}.${callee.name().text}';
					case _:
						var c = declarations.classOf(receiver.tsType);
						if (c == null) return false;
						target = '(cast Interop.instance(${param(plan, receiver)}, ${c.path}, ${quote(where(receiver))}) : ${c.haxeType()}).${callee.name().text}';
						visit(receiver);
				}
			case _:
				return false;
		}
		var args = [for (a in n.arguments() ?? []) argument(plan, a)];
		calls.set(n, new GlueCall(glue(n, plan, '$target(${args.join(", ")})', true), plan));
		return true;
	}

	// new of one of helder's classes
	function construct(n:Node):Bool {
		var callee = strip(n.expression());
		var c = switch declarations.of(callee) {
			case FClass(c): c;
			case _: return false;
		}
		var plan:Array<Node> = [];
		var args = [for (a in n.arguments() ?? []) argument(plan, a)];
		calls.set(n, new GlueCall(glue(n, plan, 'new ${c.path}(${args.join(", ")})', true), plan));
		return true;
	}

	// a member of a class of helder's (a static) or of one of its instances, read (and written where it is a target)
	function member(n:Node):Bool {
		if (n.questionDotToken() != null || n.name().kind == KindPrivateIdentifier) return false;
		var receiver = strip(n.expression());
		var name = n.name().text;
		var plan:Array<Node> = [];
		var target:String;
		var instance = false;
		switch declarations.of(receiver) {
			case FClass(c): target = '${c.path}.$name';
			case _:
				var c = declarations.classOf(receiver.tsType);
				if (c == null) return false;
				target = '(cast Interop.instance(${param(plan, receiver)}, ${c.path}, ${quote(where(receiver))}) : ${c.haxeType()}).$name';
				instance = true;
				visit(receiver);
		}
		calls.set(n, new GlueCall(glue(n, plan, target, true), plan));
		if (written(n)) {
			// (the value: a parameter after the receiver's)
			var value = 'p${plan.length}';
			sets.set(n, new GlueCall(glue(n, plan.concat([n]), '$target = Interop.fromJs($value, ${quote(where(n))})', false), plan));
		}
		return true;
	}

	// whether a member is assigned or updated
	static function written(n:Node):Bool {
		var p = n.parent;
		while (p.kind == KindParenthesizedExpression) {
			n = p;
			p = p.parent;
		}
		return switch p.kind {
			case KindBinaryExpression:
				p.left() == n && p.operatorToken().kind >= KindFirstAssignment && p.operatorToken().kind <= KindLastAssignment;
			case KindPrefixUnaryExpression | KindPostfixUnaryExpression:
				p.unaryOperator() == KindPlusPlusToken || p.unaryOperator() == KindMinusMinusToken;
			case _: false;
		}
	}

	// ---- TSX: helder.view's markup
	// a literal where the program has it: a function making its View from its holes
	function literal(n:Node) {
		var plan:Array<Node> = [];
		var text = markupOf(plan, n);
		calls.set(n, new GlueCall(glue(n, plan, text, true), plan));
	}

	function markupOf(plan:Array<Node>, n:Node):String {
		markup = true;
		return switch n.kind {
			case KindJsxElement:
				var open = n.openingElement();
				var tag = tagOf(open.tagName());
				'<$tag' + attributes(plan, open.attributes()) + '>' + [for (c in n.jsxChildren()) child(plan, c)].join("") + '</$tag>';
			case KindJsxSelfClosingElement:
				'<' + tagOf(n.tagName()) + attributes(plan, n.attributes()) + '/>';
			case KindJsxFragment:
				'<>' + [for (c in n.jsxChildren()) child(plan, c)].join("") + '</>';
			case _: fail(n, "unsupported TSX");
		}
	}

	// an element's name: the renderer's (lower case, or namespaced), a component of helder's or of the program's
	function tagOf(t:Node):String {
		switch t.kind {
			case KindJsxNamespacedName: return t.namespace().text + ":" + t.name().text;
			case KindIdentifier if (~/^[a-z]/.match(t.text) && declarations.of(t) == null): return t.text;
			case KindIdentifier:
				switch declarations.of(t) {
					case FStatic(c, m): return importOf(c.path + "." + m);
					case FClass(c): return fail(t, '${c.name} is a class, not a component');
					case null:
						var f = componentDeclaration(t);
						if (f == null) return fail(t, t.text + " is not a component this compiler knows: a top-level function of the program's, or one of helder's");
						return componentOf.exists(f) ? componentOf.get(f) : component(f);
				}
			case KindPropertyAccessExpression:
				switch declarations.of(strip(t.expression())) {
					case FClass(c): return importOf(c.path + "." + t.name().text);
					case _:
				}
			case _:
		}
		return fail(t, "unsupported element name");
	}

	// (helder's component by an alias the module imports)
	function importOf(path:String):String {
		for (alias => p in imports) if (p == path) return alias;
		var alias = "Component" + Lambda.count(imports) + "_" + path.split(".").pop();
		imports.set(alias, path);
		return alias;
	}

	// the program's top-level function an element names (in its module, or imported from another)
	function componentDeclaration(t:Node):Null<Node> {
		for (sf in project.files) for (n in sf.root.statements())
			if (n.kind == KindFunctionDeclaration && n.name() != null && n.name().symbol == t.symbol) return n;
		// (imported: the function its module exports by that name)
		for (n in t.file.root.statements()) if (n.kind == KindImportDeclaration && n.importClause() != null && n.importClause().namedBindings() != null
			&& n.importClause().namedBindings().kind == KindNamedImports)
			for (spec in n.importClause().namedBindings().elements()) if (spec.name().text == t.text) {
				var target = project.resolve(n.moduleSpecifier());
				var exported = (spec.propertyName() ?? spec.name()).text;
				for (sf in project.files) if (sf.path == target) for (m in sf.root.statements())
					if (m.kind == KindFunctionDeclaration && m.name() != null && m.name().text == exported) return m;
			}
		return null;
	}

	// a TypeScript component: a Haxe one calling its function (given when the program starts)
	function component(f:Node):String {
		var i = components.length;
		var name = 'Component$i' + "_" + f.name().text;
		functions.push('public static var component$i:Dynamic = null;');
		functions.push('public static function setComponent$i(f:Dynamic):Void component$i = f;');
		functions.push('static function $name(props:Dynamic):Any return Interop.component(component$i, props);');
		keeps.push('setComponent$i(null)');
		components.push({declaration: f, setter: 'setComponent$i'});
		componentOf.set(f, name);
		return name;
	}

	function attributes(plan:Array<Node>, attrs:Node):String {
		var out = "";
		for (a in attrs.properties()) switch a.kind {
			case KindJsxAttribute:
				var name = a.name().kind == KindJsxNamespacedName ? a.name().namespace().text + ":" + a.name().name().text : a.name().text;
				var init = a.initializer();
				if (init == null) out += ' $name';
				else if (init.kind == KindStringLiteral) out += ' $name={${quote(init.text)}}';
				else if (init.kind == KindJsxExpression && init.expression() == null) continue;
				else if (init.kind == KindJsxExpression) out += ' $name={${hole(plan, init.expression(), true)}}';
				else out += ' $name={${markupOf(plan, init)}}';
			case KindJsxSpreadAttribute:
				out += ' {...Interop.toHaxe(${param(plan, a.expression())})}';
				visit(a.expression());
			case _:
		}
		return out;
	}

	function child(plan:Array<Node>, c:Node):String {
		return switch c.kind {
			case KindJsxText | KindJsxTextAllWhiteSpaces: c.text;
			case KindJsxExpression if (c.expression() == null): "";
			case KindJsxExpression if (c.dotDotDotToken() != null): fail(c, "a spread among TSX children");
			// (a function alone: For's row, typed as its children's function)
			case KindJsxExpression if (c.parent.kind == KindJsxElement && isFunction(c.expression()) && c.parent.jsxChildren().filter(k -> k.kind != KindJsxTextAllWhiteSpaces).length == 1):
				var p = param(plan, c.expression());
				visit(c.expression());
				'{(Interop.fromJs($p, ${quote(where(c.expression()))}) : helder.view.graph.Read<Dynamic> -> Any)}';
			case KindJsxExpression: '{' + hole(plan, c.expression(), false) + '}';
			case KindJsxElement | KindJsxSelfClosingElement | KindJsxFragment: markupOf(plan, c);
			case _: fail(c, "unsupported TSX child");
		}
	}

	static function isFunction(e:Node):Bool {
		var s = strip(e);
		return s.kind == KindArrowFunction || s.kind == KindFunctionExpression;
	}

	// a hole: a literal as it is (a static value), nested markup inline, else the value
	function hole(plan:Array<Node>, e:Node, attribute:Bool):String {
		var s = strip(e);
		switch s.kind {
			case KindNumericLiteral: return s.text;
			case KindTrueKeyword: return "true";
			case KindFalseKeyword: return "false";
			case KindStringLiteral | KindNoSubstitutionTemplateLiteral: return quote(s.text);
			case KindJsxElement | KindJsxSelfClosingElement | KindJsxFragment: return markupOf(plan, s);
			case _:
		}
		var p = param(plan, e);
		visit(e);
		return attribute ? 'Interop.fromJs($p, ${quote(where(e))})' : 'Interop.toHaxe($p)';
	}
}
