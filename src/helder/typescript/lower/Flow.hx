package helder.typescript.lower;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;

using Lambda;

// A class the frontend gives a layout of its own (an hxmc class under the
// runtime's JsObject): its declared fields in slots, numbers in F64 ones.
class TypedClass {
	public final node:Node;
	public final name:String;
	public final index:Int;
	public var parent:Null<TypedClass>;
	// own fields in definition order: declared fields, then parameter properties
	public final own:Array<String> = [];
	// (set by the frontend)
	public var info:Null<hxmc.ir.Ir.ClassInfo> = null;

	public function new(node, name, index) {
		this.node = node;
		this.name = name;
		this.index = index;
	}

	// every field, inherited ones first: their order in the layout
	public function fields():Array<String> return (parent == null ? [] : parent.fields()).concat(own);

	public function declares(f:String):Null<TypedClass> {
		var c = this;
		while (c != null) {
			if (c.own.contains(f)) return c;
			c = c.parent;
		}
		return null;
	}

	public function isA(other:TypedClass):Bool {
		var c = this;
		while (c != null) {
			if (c == other) return true;
			c = c.parent;
		}
		return false;
	}
}

private enum Source {
	E(n:Node); // an expression's value
	F(fact:Int); // a fact
}

// Whole-program proof of what values a place holds: a binding, a direct
// function's result, a typed class's field, the elements of the arrays a
// group of bindings share. A place is a number, nullish, an instance of a
// typed class (or nullish), or unknown. It does not trust declared types
// (`any`, assertions and missing arguments can put anything behind them): it
// follows every value that can flow in, the least fixpoint from no values.
// Places without proof stay dynamic.
class Flow {
	public static inline var BOTTOM = -4;
	public static inline var NULLISH = -3;
	public static inline var NUMBER = -2;
	public static inline var TOP = -1;
	public static inline var ARRAY = -5; // an array (or nullish)

	final src:Project;
	public final classes:Array<TypedClass> = [];
	final classOfSymbol:Map<String, TypedClass> = [];
	final classOfNode:Map<Node, TypedClass> = [];
	final sources:Map<String, Array<Source>> = [];
	final facts:Map<String, Int> = [];
	// direct functions (Frontend.isDirect, at a module's top level), by their name's symbol
	final functions:Map<String, Node> = [];
	// (receiver, field name, value) of every property write
	final writes:Array<{recv:Node, name:String, value:Source}> = [];
	// union-find of bindings that may hold the same array
	final groupParent:Map<String, String> = [];
	final escaped:Map<String, Bool> = [];
	final thisFacts:Map<Node, Int> = [];
	// whether the program writes properties reflectively (Object.defineProperty, freeze, ...)
	public var reflective(default, null) = false;

	public function new(src:Project) {
		this.src = src;
		findClasses();
		for (sf in src.files) for (n in sf.root.statements())
			if (n.kind == KindFunctionDeclaration && n.name() != null && n.body() != null && Frontend.isDirect(n)) functions.set(n.name().symbol, n);
		for (s => f in functions) declareFunction(s, f);
		for (c in classes) declareClass(c);
		for (sf in src.files) collect(sf.root);
		solve();
		if (Sys.getEnv("HELDER_TS_FLOW") == "1") {
			var keys = [for (k in sources.keys()) k];
			keys.sort(Reflect.compare);
			for (k in keys) Sys.stderr().writeString(k + " = " + place(k) + " <- " + [for (x in sources.get(k)) switch x {
				case E(n): n.kind.toString() + "@" + n.pos;
				case F(f): "" + f;
			}].join(", ") + "\n");
		}
	}

	// ---- the questions the frontend asks

	public function binding(declaration:Node):Bool return place("s:" + declaration.name().symbol) == NUMBER;

	public function result(f:Node):Bool return f.name() != null && place("r:" + f.name().symbol) == NUMBER;

	public function typed(classNode:Node):Null<TypedClass> return classOfNode.get(classNode);

	// the typed class an expression's value is an instance of (or nullish), else null
	public function classOf(n:Node):Null<TypedClass> {
		var f = fact(n);
		return f >= 0 ? classes[f] : null;
	}

	// whether a typed class's field always holds a number
	// whether an expression's value is a number
	public function isNumber(n:Node):Bool return fact(n) == NUMBER;

	// whether an expression's value is an array (or nullish)
	public function isArray(n:Node):Bool return fact(n) == ARRAY;

	// whether no code writes a property of this name (but the runtime's own)
	public function untouched(name:String):Bool {
		if (reflective) return false;
		for (w in writes) if (w.name == null || w.name == name) return false;
		return true;
	}

	public function numberField(c:TypedClass, name:String):Bool {
		var d = c.declares(name);
		return d != null && place("f:" + d.index + ":" + name) == NUMBER;
	}

	// ---- classes

	function findClasses() {
		// (a program that writes properties reflectively, deletes them by a
		// computed name or changes prototypes keeps the object model)
		var deleted = new Map<String, Bool>();
		for (sf in src.files) for (i in 1...sf.count) switch sf.kindAt(i) {
			case KindIdentifier:
				var t = sf.node(i).text;
				if (["defineProperty", "defineProperties", "assign", "freeze", "seal", "preventExtensions", "setPrototypeOf", "Reflect", "__proto__", "__defineGetter__", "__defineSetter__"].contains(t)) reflective = true;
			case KindDeleteExpression:
				var target = sf.node(i).expression();
				while (target.kind == KindParenthesizedExpression) target = target.expression();
				if (target.kind == KindPropertyAccessExpression) deleted.set(target.name().text, true);
				else if (target.kind == KindElementAccessExpression && target.argumentExpression().kind == KindStringLiteral) deleted.set(target.argumentExpression().text, true);
				else reflective = true;
			case _:
		}
		if (reflective) return;
		for (sf in src.files) for (n in sf.root.statements()) if (n.kind == KindClassDeclaration && n.name() != null && (n.modifiers() ?? []).length == 0 || n.kind == KindClassDeclaration && n.name() != null && onlyExport(n)) {
			var parent:Null<TypedClass> = null;
			var heritage = n.heritageClauses();
			var ok = true;
			if (heritage != null) for (h in heritage) if (h.token() == KindExtendsKeyword) {
				var e = h.types()[0].expression();
				parent = e.kind == KindIdentifier ? classOfSymbol.get(e.symbol) : null;
				if (parent == null) ok = false;
			}
			if (!ok) continue;
			var c = new TypedClass(n, n.name().text, classes.length);
			c.parent = parent;
			for (m in n.members()) {
				var isStatic = m.modifiers().exists(x -> x.kind == KindStaticKeyword);
				if (m.kind == KindPropertyDeclaration && !isStatic && !m.modifiers().exists(x -> x.kind == KindDeclareKeyword || x.kind == KindAbstractKeyword)) {
					var name = m.name();
					if (name.kind == KindIdentifier || name.kind == KindStringLiteral) c.own.push(name.text);
					else if (name.kind != KindPrivateIdentifier) ok = false;
				}
				if (m.kind == KindIndexSignature) ok = false;
			}
			for (m in n.members()) if (m.kind == KindConstructor) for (p in Frontend.parametersOf(m)) if (isParameterProperty(p) && p.name().kind == KindIdentifier) c.own.push(p.name().text);
			for (f in c.own) if (deleted.exists(f) || c.parent != null && c.parent.declares(f) != null) ok = false;
			if (!ok) continue;
			classes.push(c);
			classOfSymbol.set(n.name().symbol, c);
			classOfNode.set(n, c);
		}
	}

	static function onlyExport(n:Node):Bool {
		var mods = n.modifiers() ?? [];
		return mods.length == 1 && mods[0].kind == KindExportKeyword;
	}

	public static function isParameterProperty(p:Node):Bool
		return p.modifiers().exists(x -> x.kind == KindPublicKeyword || x.kind == KindPrivateKeyword || x.kind == KindProtectedKeyword || x.kind == KindReadonlyKeyword || x.kind == KindOverrideKeyword);

	static function constructorOf(c:TypedClass):Null<Node> {
		for (m in c.node.members()) if (m.kind == KindConstructor && m.body() != null) return m;
		return null;
	}

	// the class whose constructor `new c(...)` runs first (an implicit one passes its arguments up)
	static function constructorClass(c:TypedClass):TypedClass {
		var k = c;
		while (constructorOf(k) == null && k.parent != null) k = k.parent;
		return k;
	}

	function declareClass(c:TypedClass) {
		var ctor = constructorOf(c);
		// (a class used other than by new, extends and instanceof can be constructed with anything)
		var escapes = onlyExport(c.node);
		if (!escapes) for (sf in src.files) for (i in 1...sf.count) if (sf.kindAt(i) == KindIdentifier) {
			var id = sf.node(i);
			if (id.symbol != c.node.name().symbol || id == c.node.name()) continue;
			var parent = id.parent;
			var ok = parent.kind == KindNewExpression && parent.expression() == id
				|| parent.kind == KindExpressionWithTypeArguments
				|| parent.kind == KindTypeReference || parent.kind == KindTypeQuery
				|| parent.kind == KindBinaryExpression && parent.operatorToken().kind == KindInstanceOfKeyword && parent.right() == id;
			if (!ok) escapes = true;
		}
		if (ctor != null) for (p in Frontend.parametersOf(ctor)) {
			var s = p.name().kind == KindIdentifier ? p.name().symbol : null;
			if (s == null) continue;
			var plain = !Frontend.usesArguments(ctor.body()) && p.initializer() == null && p.questionToken() == null && p.dotDotDotToken() == null && !escapes;
			sources.set("s:" + s, plain ? [] : [F(TOP)]);
		}
		for (m in c.node.members()) {
			if (m.kind == KindPropertyDeclaration && (m.name().kind == KindIdentifier || m.name().kind == KindStringLiteral) && c.own.contains(m.name().text))
				addSource("f:" + c.index + ":" + m.name().text, m.initializer() == null ? F(NULLISH) : E(m.initializer()));
		}
		if (ctor != null) for (p in Frontend.parametersOf(ctor)) if (isParameterProperty(p) && p.name().kind == KindIdentifier)
			addSource("f:" + c.index + ":" + p.name().text, E(p.name()));
	}

	// ---- functions

	function declareFunction(s:String, f:Node) {
		var arguments = Frontend.usesArguments(f.body());
		for (a in Frontend.parametersOf(f)) if (a.name().kind == KindIdentifier)
			sources.set("s:" + a.name().symbol, !arguments && a.initializer() == null && a.questionToken() == null && a.dotDotDotToken() == null ? [] : [F(TOP)]);
		var returns:Array<Source> = [];
		var body = f.body().statements();
		if (body == null || body.length == 0 || body[body.length - 1].kind != KindReturnStatement) returns.push(F(NULLISH));
		function visit(n:Node) {
			if (n == null || isFunction(n)) return;
			if (n.kind == KindReturnStatement) returns.push(n.expression() == null ? F(NULLISH) : E(n.expression()));
			for (c in n.children()) visit(c);
		}
		visit(f.body());
		sources.set("r:" + s, returns);
		if (Frontend.isExported(f)) escape(s, f);
	}

	function escape(s:String, f:Node) {
		for (a in Frontend.parametersOf(f)) if (a.name().kind == KindIdentifier) addSource("s:" + a.name().symbol, F(TOP));
		addSource("r:" + s, F(TOP));
	}

	static function isFunction(n:Node):Bool
		return n.kind == KindFunctionDeclaration || n.kind == KindFunctionExpression || n.kind == KindArrowFunction || n.kind == KindClassDeclaration || n.kind == KindClassExpression || n.kind == KindMethodDeclaration || n.kind == KindConstructor || n.kind == KindGetAccessor || n.kind == KindSetAccessor;

	// ---- what flows where

	function addSource(place:String, s:Source) {
		var list = sources.get(place);
		if (list == null) sources.set(place, list = []);
		list.push(s);
	}

	function tracked(s:Null<String>):Bool return s != null && sources.exists("s:" + s);

	function collect(n:Node) {
		if (n == null) return;
		switch n.kind {
			case KindVariableDeclaration:
				var list = n.parent;
				if (n.name().kind == KindIdentifier) {
					var s = n.name().symbol;
					if (!sources.exists("s:" + s)) sources.set("s:" + s, []);
					var loop = list.parent != null && (list.parent.kind == KindForOfStatement || list.parent.kind == KindForInStatement) ? list.parent : null;
					if (loop != null) addSource("s:" + s, loop.kind == KindForOfStatement ? E(loop) : F(TOP));
					else if (n.initializer() != null) addSource("s:" + s, E(n.initializer()));
					else if (list.flags & NodeFlags.BlockScoped == 0) addSource("s:" + s, F(NULLISH));
					if (list.flags & NodeFlags.BlockScoped == 0 && n.initializer() != null) addSource("s:" + s, F(NULLISH));
				}
				else unknownTargets(n.name());
			case KindCatchClause:
				if (n.variableDeclaration() != null) unknownTargets(n.variableDeclaration().name());
			case KindIdentifier if (functions.exists(n.symbol)):
				var f = functions.get(n.symbol);
				var parent = n.parent;
				if (parent.kind == KindCallExpression && parent.expression() == n) {
					var args = parent.arguments() ?? [];
					var spread = args.exists(a -> a.kind == KindSpreadElement);
					var params = Frontend.parametersOf(f);
					for (i in 0...params.length) if (params[i].name().kind == KindIdentifier)
						addSource("s:" + params[i].name().symbol, spread ? F(TOP) : i < args.length ? E(args[i]) : F(NULLISH));
				}
				else if (n != f.name()) escape(n.symbol, f);
			case KindNewExpression if (n.expression().kind == KindIdentifier && classOfSymbol.exists(n.expression().symbol)):
				construct(constructorClass(classOfSymbol.get(n.expression().symbol)), n.arguments() ?? []);
			case KindCallExpression if (n.expression().kind == KindSuperKeyword):
				var c = enclosingClass(n);
				if (c != null && c.parent != null) construct(constructorClass(c.parent), n.arguments() ?? []);
			case KindBinaryExpression:
				var op = n.operatorToken().kind;
				if (op >= KindFirstAssignment && op <= KindLastAssignment) {
					var left = n.left();
					while (left.kind == KindParenthesizedExpression) left = left.expression();
					var value = op == KindEqualsToken ? E(n.right()) : E(n);
					switch left.kind {
						case KindIdentifier if (tracked(left.symbol)): addSource("s:" + left.symbol, value);
						case KindPropertyAccessExpression if (left.name().kind != KindPrivateIdentifier): writes.push({recv: left.expression(), name: left.name().text, value: value});
						case KindElementAccessExpression: element(left, value);
						case KindArrayLiteralExpression | KindObjectLiteralExpression if (op == KindEqualsToken): unknownTargets(left);
						case _:
					}
				}
			case KindPrefixUnaryExpression | KindPostfixUnaryExpression if (n.unaryOperator() == KindPlusPlusToken || n.unaryOperator() == KindMinusMinusToken):
				var target = n.operand();
				while (target.kind == KindParenthesizedExpression) target = target.expression();
				switch target.kind {
					case KindIdentifier if (tracked(target.symbol)): addSource("s:" + target.symbol, F(NUMBER));
					case KindPropertyAccessExpression: writes.push({recv: target.expression(), name: target.name().text, value: F(NUMBER)});
					case KindElementAccessExpression: element(target, F(NUMBER));
					case _:
				}
			case KindForOfStatement | KindForInStatement:
				var init = n.initializer();
				if (init.kind != KindVariableDeclarationList) unknownTargets(init);
			case _:
		}
		// (a binding's every use, for the arrays it may hold)
		if (n.kind == KindIdentifier && tracked(n.symbol) && n.parent != null) arrayUse(n);
		for (c in n.children()) collect(c);
	}

	function construct(c:TypedClass, args:Array<Node>) {
		var ctor = constructorOf(c);
		if (ctor == null) return;
		var spread = args.exists(a -> a.kind == KindSpreadElement);
		var params = Frontend.parametersOf(ctor);
		for (i in 0...params.length) if (params[i].name().kind == KindIdentifier)
			addSource("s:" + params[i].name().symbol, spread ? F(TOP) : i < args.length ? E(args[i]) : F(NULLISH));
	}

	function enclosingClass(n:Node):Null<TypedClass> {
		var p = n.parent;
		while (p != null && p.kind != KindClassDeclaration && p.kind != KindClassExpression) p = p.parent;
		return p == null ? null : classOfNode.get(p);
	}

	// targets of a destructuring or a loop's bare binding: anything
	function unknownTargets(n:Node) {
		if (n == null) return;
		switch n.kind {
			case KindIdentifier if (tracked(n.symbol)): addSource("s:" + n.symbol, F(TOP));
			case KindPropertyAccessExpression if (n.name().kind != KindPrivateIdentifier): writes.push({recv: n.expression(), name: n.name().text, value: F(TOP)});
			case KindElementAccessExpression: element(n, F(TOP));
			case _: for (c in n.children()) unknownTargets(c);
		}
	}

	// a write through `e[k]`: an array's element, a string-named field, else any field
	function element(target:Node, value:Source) {
		var obj = target.expression(), key = target.argumentExpression();
		while (obj.kind == KindParenthesizedExpression) obj = obj.expression();
		if (key.kind == KindStringLiteral) writes.push({recv: obj, name: key.text, value: value});
		else if (obj.kind == KindIdentifier && tracked(obj.symbol)) addSource("a:" + obj.symbol, value);
		else if (key.kind != KindNumericLiteral) writes.push({recv: obj, name: null, value: F(TOP)});
	}

	// how a binding is used: a use the analysis does not follow lets its array escape
	function arrayUse(id:Node) {
		var p = id.parent;
		inline function use() escaped.set(id.symbol, true);
		switch p.kind {
			case KindVariableDeclaration if (p.name() == id):
			case KindParameter if (p.name() == id):
			case KindVariableDeclaration if (p.initializer() == id && p.name().kind == KindIdentifier):
				union(id.symbol, p.name().symbol);
			case KindBinaryExpression:
				var op = p.operatorToken().kind;
				if (op == KindEqualsToken && p.left() == id) {}
				else if (op == KindEqualsToken && p.right() == id && p.left().kind == KindIdentifier && tracked(p.left().symbol)) union(id.symbol, p.left().symbol);
				else if (op == KindEqualsEqualsEqualsToken || op == KindExclamationEqualsEqualsToken || op == KindEqualsEqualsToken || op == KindExclamationEqualsToken || op == KindAmpersandAmpersandToken || op == KindBarBarToken) {}
				else if (op >= KindFirstAssignment && op <= KindLastAssignment && p.left() == id) {}
				else use();
			case KindElementAccessExpression if (p.expression() == id):
			case KindPropertyAccessExpression if (p.expression() == id):
				var name = p.name().text, call = p.parent.kind == KindCallExpression && p.parent.expression() == p;
				if (name == "length") {}
				else if (call && ["push", "unshift", "fill"].contains(name)) for (a in p.parent.arguments() ?? []) addSource("a:" + id.symbol, a.kind == KindSpreadElement ? F(TOP) : E(a));
				else if (call && name == "splice") {
					var args = p.parent.arguments() ?? [];
					for (i in 2...args.length) addSource("a:" + id.symbol, args[i].kind == KindSpreadElement ? F(TOP) : E(args[i]));
				}
				else if (call && ["pop", "shift", "reverse", "at", "indexOf", "lastIndexOf", "includes", "join", "slice", "concat", "keys", "values", "entries", "toString"].contains(name)) {}
				else if (call && ["sort", "forEach", "map", "filter", "reduce", "reduceRight", "some", "every", "find", "findIndex", "findLast", "findLastIndex", "flatMap"].contains(name)) {
					// (a callback given the array itself, its third argument, can change it)
					var f = (p.parent.arguments() ?? [])[0];
					if (f == null || !(f.kind == KindArrowFunction || f.kind == KindFunctionExpression) || Frontend.parametersOf(f).length > 2) use();
				}
				else use();
			case KindForOfStatement if (p.expression() == id):
			case KindSpreadElement:
			case KindCallExpression if (p.expression() != id && p.expression().kind == KindIdentifier && functions.exists(p.expression().symbol)):
				var args = p.arguments() ?? [], params = Frontend.parametersOf(functions.get(p.expression().symbol)), i = args.indexOf(id);
				if (i >= 0 && i < params.length && params[i].name().kind == KindIdentifier) union(id.symbol, params[i].name().symbol); else use();
			case KindPrefixUnaryExpression if (p.unaryOperator() == KindExclamationToken):
			case KindTypeOfExpression | KindIfStatement | KindParenthesizedExpression:
			case KindConditionalExpression if (p.condition() == id):
			case KindPrefixUnaryExpression | KindPostfixUnaryExpression:
			case _: use();
		}
	}

	function group(s:String):String {
		var p = groupParent.get(s);
		if (p == null || p == s) return s;
		var r = group(p);
		groupParent.set(s, r);
		return r;
	}

	function union(a:String, b:String) {
		var x = group(a), y = group(b);
		if (x != y) groupParent.set(x, y);
	}

	// ---- the fixpoint

	function solve() {
		// (array places by group: a member's element sources, and what its own sources say of its elements)
		var groups = new Map<String, Array<Source>>();
		function into(g:String, s:Source) {
			var list = groups.get(g);
			if (list == null) groups.set(g, list = []);
			list.push(s);
		}
		for (key => list in sources) if (StringTools.startsWith(key, "s:")) {
			var s = key.substr(2), g = group(s);
			if (escaped.exists(s)) into(g, F(TOP));
			for (x in list) switch x {
				case E(n):
					var v = n;
					while (v.kind == KindParenthesizedExpression || v.kind == KindAsExpression || v.kind == KindSatisfiesExpression || v.kind == KindNonNullExpression) v = v.expression();
					if (v.kind == KindArrayLiteralExpression) for (e in v.elements()) into(g, e.kind == KindSpreadElement || e.kind == KindOmittedExpression ? F(TOP) : E(e));
					else if (v.kind == KindIdentifier && tracked(v.symbol)) {} // (unioned)
					else if (v.kind == KindNullKeyword || v.kind == KindIdentifier && v.text == "undefined") {}
					else into(g, F(TOP));
				case F(f): if (f == TOP) into(g, F(TOP));
			}
		}
		for (key => list in sources) if (StringTools.startsWith(key, "a:")) for (x in list) into(group(key.substr(2)), x);
		for (g => list in groups) sources.set("g:" + g, list);
		var changed = true;
		while (changed) {
			changed = false;
			for (key => list in sources) {
				var f = BOTTOM;
				for (x in list) f = join(f, switch x {
					case E(n): fact(n);
					case F(v): v;
				});
				if (f != place(key)) {
					facts.set(key, f);
					changed = true;
				}
			}
			// (writes reach the fields of the classes their receiver may be: any with that name when it is not known)
			var fieldFacts = new Map<String, Int>();
			for (w in writes) {
				var rc = fact(w.recv);
				var value = switch w.value {
					case E(n): fact(n);
					case F(v): v;
				};
				for (c in classes) {
					var names = w.name == null ? c.own : c.own.contains(w.name) ? [w.name] : [];
					if (names.length == 0) continue;
					if (rc >= 0 && !(classes[rc].isA(c) || c.isA(classes[rc]))) continue;
					if (rc == NULLISH || rc == NUMBER || rc == ARRAY) continue;
					for (name in names) {
						var key = "f:" + c.index + ":" + name;
						fieldFacts.set(key, join(fieldFacts.get(key) ?? BOTTOM, value));
					}
				}
			}
			for (key => f in fieldFacts) {
				var merged = join(place(key), f);
				if (merged != place(key)) {
					// (kept as a source, so the next round's join includes it)
					addSource(key, F(merged));
					facts.set(key, merged);
					changed = true;
				}
			}
		}
	}

	function place(key:String):Int return facts.get(key) ?? BOTTOM;

	function join(a:Int, b:Int):Int {
		if (a == BOTTOM) return b;
		if (b == BOTTOM || a == b) return a;
		if (a == TOP || b == TOP) return TOP;
		if (a == NULLISH && (b >= 0 || b == ARRAY)) return b;
		if (b == NULLISH && (a >= 0 || a == ARRAY)) return a;
		if (a >= 0 && b >= 0) {
			var c = classes[a];
			while (c != null && !classes[b].isA(c)) c = c.parent;
			return c == null ? TOP : c.index;
		}
		return TOP;
	}

	// what an expression's value is, given the places' facts so far
	function fact(n:Null<Node>):Int {
		if (n == null) return TOP;
		return switch n.kind {
			case KindNumericLiteral: NUMBER;
			case KindArrayLiteralExpression: ARRAY;
			case KindNullKeyword | KindVoidExpression: NULLISH;
			case KindIdentifier:
				if (n.text == "NaN" || n.text == "Infinity") NUMBER;
				else if (n.text == "undefined" && !tracked(n.symbol)) NULLISH;
				else if (tracked(n.symbol)) place("s:" + n.symbol);
				else TOP;
			case KindParenthesizedExpression | KindNonNullExpression | KindAsExpression | KindSatisfiesExpression: fact(n.expression());
			case KindPrefixUnaryExpression: n.unaryOperator() == KindExclamationToken ? TOP : NUMBER;
			case KindPostfixUnaryExpression: NUMBER;
			case KindConditionalExpression: join(fact(n.whenTrue()), fact(n.whenFalse()));
			case KindNewExpression:
				n.expression().kind == KindIdentifier && classOfSymbol.exists(n.expression().symbol) ? classOfSymbol.get(n.expression().symbol).index : TOP;
			case KindThisKeyword: thisFact(n);
			case KindCallExpression:
				var callee = n.expression();
				callee.kind == KindIdentifier && functions.exists(callee.symbol) ? place("r:" + callee.symbol) : TOP;
			case KindElementAccessExpression:
				var obj = n.expression();
				while (obj.kind == KindParenthesizedExpression) obj = obj.expression();
				if (obj.kind == KindIdentifier && tracked(obj.symbol)) {
					var e = place("g:" + group(obj.symbol));
					// (out of range: undefined, which an instance place allows)
					e >= 0 || e == BOTTOM ? e : TOP;
				} else TOP;
			case KindForOfStatement:
				var iterable = n.expression();
				while (iterable.kind == KindParenthesizedExpression) iterable = iterable.expression();
				if (iterable.kind == KindIdentifier && tracked(iterable.symbol)) {
					var e = place("g:" + group(iterable.symbol));
					e >= 0 || e == BOTTOM ? e : TOP;
				} else TOP;
			case KindPropertyAccessExpression:
				var rc = fact(n.expression());
				var name = n.name().text;
				if (rc >= 0) {
					var d = classes[rc].declares(name);
					d == null ? TOP : place("f:" + d.index + ":" + name);
				} else if (rc == ARRAY && name == "length") NUMBER;
				else rc == BOTTOM ? BOTTOM : TOP;
			case KindBinaryExpression:
				switch n.operatorToken().kind {
					case KindMinusToken | KindAsteriskToken | KindSlashToken | KindPercentToken | KindAmpersandToken | KindBarToken | KindCaretToken
						| KindLessThanLessThanToken | KindGreaterThanGreaterThanToken | KindGreaterThanGreaterThanGreaterThanToken
						| KindAsteriskAsteriskToken | KindMinusEqualsToken | KindAsteriskEqualsToken | KindSlashEqualsToken | KindPercentEqualsToken
						| KindAsteriskAsteriskEqualsToken | KindLessThanLessThanEqualsToken | KindGreaterThanGreaterThanEqualsToken
						| KindGreaterThanGreaterThanGreaterThanEqualsToken | KindAmpersandEqualsToken | KindBarEqualsToken | KindCaretEqualsToken: NUMBER;
					case KindPlusToken | KindPlusEqualsToken:
						var l = fact(n.left()), r = fact(n.right());
						// (nothing known yet of a side: nothing known yet of the sum)
						l == BOTTOM || r == BOTTOM ? BOTTOM : l == NUMBER && r == NUMBER ? NUMBER : TOP;
					case KindEqualsToken: fact(n.right());
					case KindBarBarToken | KindAmpersandAmpersandToken | KindQuestionQuestionToken | KindBarBarEqualsToken | KindAmpersandAmpersandEqualsToken | KindQuestionQuestionEqualsToken:
						join(fact(n.left()), fact(n.right()));
					case KindCommaToken: fact(n.right());
					case _: TOP;
				}
			case _: TOP;
		}
	}

	// `this` in a typed class's constructor or field initializer: the instance being made
	function thisFact(n:Node):Int {
		var f = thisFacts.get(n);
		if (f != null) return f;
		var p = n.parent;
		f = TOP;
		while (p != null) {
			if (p.kind == KindArrowFunction) {
				p = p.parent;
				continue;
			}
			if (p.kind == KindConstructor || p.kind == KindPropertyDeclaration && !p.modifiers().exists(x -> x.kind == KindStaticKeyword)) {
				var c = classOfNode.get(p.parent);
				if (c != null) f = c.index;
				break;
			}
			if (isFunction(p) || p.kind == KindClassStaticBlockDeclaration) break;
			p = p.parent;
		}
		thisFacts.set(n, f);
		return f;
	}
}
