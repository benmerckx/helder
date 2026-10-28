package helder.typescript.lower;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;
import hxmc.ir.Ir;
import haxe.ds.Vector;
import helder.typescript.ir.Builder;
import helder.typescript.check.Types;
import helder.typescript.lower.Classes.ClassLayout;

// A binding's storage: a global (module scope), a box (captured by a
// closure), or a plain local; `outer`: an enclosing function's plain local,
// which no closure can see (Captures)
private typedef Binding = {ty:Ty, ?cell:Ex, ?global:Int, ?local:Local, ?outer:String};

// A source file's top-level scope: its bindings (globals), direct functions
// and exports. Imports alias the exporting module's bindings, so they are live.
private class Module {
	public var file:SourceFile;
	public var env:Map<String, Binding> = [];
	public var functions:Map<String, FuncInfo> = [];
	public var nodes:Map<String, Node> = [];
	public var functionValues:Map<String, Binding> = [];
	public var others:Array<Node> = [];
	public var exports:Map<String, Binding> = [];
	public var namespace:Binding = null;
	public var functionVars:Map<String, Binding> = [];
	public function new(file:SourceFile) this.file = file;
}

class Frontend {
	var src:Project;
	var p:Program;
	var b:Builder;
	var env:Map<String, Binding> = [];
	var functionVars:Map<String, Binding> = [];
	var functions:Map<String, FuncInfo> = [];
	var nodes:Map<String, Node> = [];
	var typed = 0;
	var dynamicSites = 0;
	var expressions = 0;
	var typedOperations = 0;
	var dynamicOperations = 0;
	var serial = 0;
	var capturedCells:Map<Local, Bool> = [];
	var types:Types;
	var classes:Classes;
	var reps:Reps;
	var captures:Captures;
	// (binding a generator's or async function's parameters: its step closure reads them)
	var sharing = false;
	// (the statement being lowered: where a typed slot's check reports)
	var here:Null<Node> = null;
	// (whether Math's functions are the built-ins: the program assigns no Math and reaches no global object)
	var mathFixed = false;
	var restFunctions:Map<FuncInfo, Bool> = [];
	var argumentFunctions:Map<FuncInfo, Bool> = [];
	// (private names visible in the class bodies being compiled: #name -> brand)
	var privateScopes:Array<Map<String, String>> = [];
	var classSerial = 0;
	// (the name an anonymous function or class expression takes from its binding)
	var pendingName:String = null;
	static inline var PLAIN = 0;
	static inline var METHOD = 1;
	public function new(src:Project, p:Program) {
		this.src = src;
		this.p = p;
	}

	public function coverage():Dynamic return {expressions: expressions, typedSites: typed, dynamicSites: dynamicSites, unsupported: 0, typedOperations: typedOperations, dynamicOperations: dynamicOperations};

	function fail(n:Node, s:String):Dynamic return src.fail(n, s);

	function validate(n:Node) {
		if (n == null) return;
		if (n.kind == KindWithStatement) fail(n, "with is excluded; use explicit property accesses");
		if (n.kind == KindIdentifier && ["Proxy", "eval", "Intl", "WeakRef", "FinalizationRegistry"].indexOf(n.text) >= 0 && n.parent != null && n.parent.kind != KindPropertyAccessExpression)
			fail(n, n.text + " is excluded; use explicit code and supported built-ins");
		if (n.kind == KindCallExpression && n.expression().kind == KindImportKeyword)
			fail(n, "dynamic import is excluded; use statically linked functions");
		for (c in n.children()) validate(c);
	}

	function members(n:Node):Array<Node> {
		var list = n.members();
		return list == null ? [] : list;
	}

	function elements(n:Node):Array<Node> {
		var list = n.elements();
		return list == null ? [] : list;
	}

	function typeAt(n:Node):Ty return TRef(RAny);

	// a direct function's result: as its type says
	function ret(n:Node):Ty return n.kind == KindFunctionDeclaration && n.name() != null && n.parent != null && n.parent.kind == KindSourceFile ? reps.rep(n.returnType()) : TRef(RAny);

	// a let or const binding's, or a direct function's parameter's: as its type says
	function bindingType(n:Node):Ty return n.name().kind == KindIdentifier ? reps.rep(n.name().tsType) : TRef(RAny);

	// a parameter's slot: typed unless it takes a default, is optional or a rest
	function parameterType(n:Node):Ty
		return n.initializer() == null && n.questionToken() == null && n.dotDotDotToken() == null ? bindingType(n) : TRef(RAny);

	// (a value into a typed slot, checked: see Reps)
	function store(e:Ex, t:Ty):Ex return reps.store(b, e, t, where());

	function where():String return here == null ? src.path : Project.relative(here.file.path) + ":" + here.file.line(here.file.skipTrivia(here.pos));

	// a declared name's binding: a plain local, or a box when a closure may capture it
	function bind(name:Null<Node>, t:Ty, init:Ex):Binding {
		if (name != null && !captures.shared(name) && !sharing) {
			var l = b.local(name.text, t);
			b.out.push(SSet(l, init));
			return {ty: t, local: l};
		}
		return {ty: t, cell: b.temp(ENewBox(t, init))};
	}

	// (a typed slot's value before its declaration runs)
	function placeholder(t:Ty):Ex return t == TF64 ? EF64(0) : t.match(TRef(RObj(_))) ? ENull(t) : b.runtime("getUndefined", []);

	// (typed: a direct function's typed parameters and result; a closure's
	// arrive and leave dynamic, its parameters checked on entry: see lambda)
	function declareFunction(n:Node, name:String, typed:Bool):FuncInfo {
		var f = Builder.func(p, name, typed ? ret(n) : TRef(RAny));
		var parameters = parametersOf(n);
		if (n.kind != KindArrowFunction && usesArguments(n.body())) {
			// (all arguments arrive as one array; parameterSetup binds the parameters from it)
			f.args.push(new Local(f.args.length, "%arguments", TRef(RAny)));
			restFunctions.set(f, true);
			argumentFunctions.set(f, true);
			return f;
		}
		for (i in 0...parameters.length) {
			var a = parameters[i];
			if (a.dotDotDotToken() != null) {
				if (i != parameters.length - 1) fail(a, "a rest parameter must be last");
				restFunctions.set(f, true);
			}
			// (a destructured parameter arrives in a hidden local; see parameterSetup)
			if (a.name().kind == KindIdentifier) f.args.push(new Local(f.args.length, a.name().text, typed ? parameterType(a) : TRef(RAny)));
			else f.args.push(new Local(f.args.length, "%parameter" + i, TRef(RAny)));
		}
		return f;
	}

	// Top-level function declarations that do not use `this` are direct: typed
	// IR functions called directly, with one function object each for uses as
	// a value. Other functions and all classes are runtime objects.
	function direct(n:Node):Bool return isDirect(n);

	public static function isDirect(n:Node):Bool return n.body() != null && !usesThis(n.body()) && n.asteriskToken() == null && !hasModifier(n, KindAsyncKeyword);

	public static function usesThis(n:Node):Bool {
		if (n == null || n.kind == KindFunctionDeclaration || n.kind == KindFunctionExpression || n.kind == KindClassDeclaration || n.kind == KindClassExpression) return false;
		if (n.kind == KindThisKeyword || n.kind == KindSuperKeyword || n.kind == KindMetaProperty) return true;
		for (c in n.children()) if (usesThis(c)) return true;
		return false;
	}

	public static function isExported(n:Node):Bool return hasModifier(n, KindExportKeyword);

	static function hasModifier(n:Node, kind:Kind):Bool {
		for (m in n.modifiers()) if (m.kind == kind) return true;
		return false;
	}

	function global(name:String):Binding {
		var g = p.globals.length;
		p.globals.push({ty: TRef(RAny), init: null, name: "ts_" + name + "_" + g});
		var v = {ty: TRef(RAny), global: g};
		env.set(name, v);
		return v;
	}
	var functionValues:Map<String, Binding> = [];
	var modules:Array<Module> = [];
	var moduleOf:Map<String, Module> = [];
	function enter(m:Module) {
		env = m.env;
		functions = m.functions;
		nodes = m.nodes;
		functionValues = m.functionValues;
		functionVars = m.functionVars;
	}

	// (a global that no scope names)
	function anonymousGlobal(name:String):Binding {
		var g = p.globals.length;
		p.globals.push({ty: TRef(RAny), init: null, name: "ts_" + name + "_" + g});
		return {ty: TRef(RAny), global: g};
	}

	function statementsOf(file:SourceFile):Array<Node> {
		return file.root.statements();
	}

	function moduleSpecifier(n:Node):Null<Node> return n.kind == KindImportDeclaration ? n.moduleSpecifier() : n.kind == KindExportDeclaration ? n.moduleSpecifier() : null;

	function targetModule(specifier:Node):Module {
		var name = src.resolve(specifier);
		var m = name == null ? null : moduleOf.get(name);
		if (m == null) fail(specifier, "module " + specifier.text + " is not a TypeScript or JavaScript source file of this program");
		return m;
	}

	// ES module evaluation order: imports depth first, in source order, each module once.
	function moduleOrder():Array<Module> {
		for (f in src.files) {
			var m = new Module(f);
			moduleOf.set(f.path, m);
		}
		var order:Array<Module> = [];
		var visiting:Map<Module, Bool> = [];
		function visit(m:Module) {
			if (visiting.exists(m)) return;
			visiting.set(m, true);
			for (s in statementsOf(m.file)) {
				var spec = moduleSpecifier(s);
				if (spec != null) visit(targetModule(spec));
			}
			order.push(m);
		}
		visit(moduleOf.get(src.file.path));
		return order;
	}

	public function lower() {
		var main = Builder.func(p, "main", TVoid);
		b = new Builder(p, main);
		b.runtime("libInit", []);
		var features = Features.of(src);
		for (f in features) b.runtime("libInstall" + f, []);
		var eventLoop = features.contains("Promise") || features.contains("All") || features.contains("FromAsync");
		modules = moduleOrder();
		types = src.types;
		classes = new Classes(src);
		reps = new Reps(p, types, classes);
		captures = new Captures(src);
		mathFixed = !features.contains("All") && !assignsMath();
		for (m in modules) {
			validate(m.file.root);
			enter(m);
			declareModule(m);
		}
		// (imports and re-exports, until export * chains settle)
		var changed = true;
		while (changed) {
			changed = false;
			for (m in modules) {
				enter(m);
				if (linkModule(m)) changed = true;
			}
		}
		// (function objects first: direct functions' values, then the others; then namespace objects)
		for (m in modules) {
			enter(m);
			for (name in functions.keys()) set(functionValues.get(name), functionValue(functions.get(name), name));
			for (n in m.others) set(n.name() != null ? env.get(n.name().text) : m.exports.get("default"), closure(n, n.name() == null ? "default" : null));
		}
		for (m in modules) if (m.namespace != null) {
			enter(m);
			set(m.namespace, namespaceObject(m));
		}
		for (m in modules) {
			enter(m);
			for (name in functions.keys()) compileFunction(nodes.get(name), functions.get(name));
		}
		// (an uncaught exception is reported on stderr with exit status 1, as node does)
		var body = b.block(() -> {
			for (m in modules) {
				enter(m);
				for (n in statementsOf(m.file)) statement(n, true);
			}
			// (timers and promises: only a program that has them runs the loop)
			if (eventLoop) b.runtime("libRunEventLoop", []);
		});
		var caught = b.local("uncaught", TRef(RAny));
		b.f.hasTry = true;
		b.out.push(STry(body, Vector.fromArrayCopy([{test: null, l: caught, body: b.block(() -> b.runtime("uncaught", [ELocal(caught)]))}])));
		b.out.push(SReturn(null));
		b.finish();
		p.main = main;
		var next = 0;
		function visit(c:ClassInfo) {
			c.id = next++;
			for (d in p.classes) if (d.sup == c) visit(d);
			c.lastDescendant = next - 1;
		}
		visit(p.classes[0]);
		p.classes.sort((a, z) -> a.id - z.id);
	}

	// A module's own bindings and the exports among them.
	function declareModule(m:Module) {
		var sourceStatements = statementsOf(m.file);
		for (n in sourceStatements) if (n.kind == KindFunctionDeclaration && n.body() != null && n.name() != null) {
			var name = n.name().text;
			if (direct(n)) {
				functions.set(name, declareFunction(n, name, true));
				nodes.set(name, n);
			}
		}
		for (n in sourceStatements) if (n.kind == KindVariableStatement && !hasModifier(n, KindDeclareKeyword) && n.declarationList().flags & NodeFlags.BlockScoped != 0) {
			for (d in n.declarationList().declarations()) {
				for (name in bindingNames(d.name())) {
					var t = name == d.name() ? bindingType(d) : TRef(RAny);
					var g = p.globals.length;
					p.globals.push({ty: t, init: null, name: "ts_" + name.text + "_" + g});
					env.set(name.text, {ty: t, global: g});
				}
			}
		}
		for (n in sourceStatements) if ((n.kind == KindClassDeclaration || n.kind == KindEnumDeclaration || n.kind == KindModuleDeclaration) && n.name() != null && !hasModifier(n, KindDeclareKeyword) && !env.exists(n.name().text)) global(n.name().text);
		m.others = [for (n in sourceStatements) if (n.kind == KindFunctionDeclaration && n.body() != null && (n.name() == null || !functions.exists(n.name().text))) n];
		for (n in m.others) if (n.name() != null) global(n.name().text);
		var script = true;
		for (n in sourceStatements) if (n.kind == KindImportDeclaration || n.kind == KindExportDeclaration || n.kind == KindExportAssignment || hasModifier(n, KindExportKeyword)) script = false;
		if (script) {
			var self = global("%scriptThis");
			env.set("this", self);
			set(self, b.runtime("libGlobal", [EStr("globalThis")]));
		}
		hoist(m.file.root, true);
		for (name in functions.keys()) functionValues.set(name, global("%function:" + name));
		for (n in sourceStatements) {
			if (n.kind == KindExportAssignment && !n.isExportEquals()) {
				m.exports.set("default", anonymousGlobal("default"));
				continue;
			}
			if (!hasModifier(n, KindExportKeyword) || hasModifier(n, KindDeclareKeyword)) continue;
			var isDefault = hasModifier(n, KindDefaultKeyword);
			switch (n.kind) {
				case KindVariableStatement: for (d in n.declarationList().declarations()) for (id in bindingNames(d.name())) m.exports.set(id.text, env.get(id.text));
				case KindFunctionDeclaration if (n.body() != null):
					var binding = n.name() == null ? anonymousGlobal("default") : functions.exists(n.name().text) ? functionValues.get(n.name().text) : env.get(n.name().text);
					m.exports.set(isDefault ? "default" : n.name().text, binding);
				case KindClassDeclaration | KindEnumDeclaration | KindModuleDeclaration:
					m.exports.set(isDefault ? "default" : n.name().text, n.name() == null ? anonymousGlobal("default") : env.get(n.name().text));
				case _:
			}
		}
	}

	// Binds imports and records re-exports whose targets are known; true when something new was bound.
	function linkModule(m:Module):Bool {
		var changed = false;
		function bind(name:String, binding:Binding) {
			if (binding != null && env.get(name) != binding) {
				env.set(name, binding);
				changed = true;
			}
		}
		function export(name:String, binding:Binding) {
			if (binding != null && !m.exports.exists(name)) {
				m.exports.set(name, binding);
				changed = true;
			}
		}
		for (n in statementsOf(m.file)) switch (n.kind) {
			case KindImportDeclaration:
				var clause = n.importClause();
				if (clause == null) continue;
				if (clause.isTypeOnly()) continue;
				var target = targetModule(n.moduleSpecifier());
				if (clause.name() != null) bind(clause.name().text, target.exports.get("default"));
				var named = clause.namedBindings();
				if (named == null) continue;
				if (named.kind == KindNamespaceImport) bind(named.name().text, namespaceBinding(target));
				else for (e in named.elements()) if (!e.isTypeOnly()) {
					var imported = e.propertyName() != null ? e.propertyName().text : e.name().text;
					bind(e.name().text, target.exports.get(imported));
				}
			case KindExportDeclaration:
				var decl = n;
				if (decl.isTypeOnly()) continue;
				var target = decl.moduleSpecifier() == null ? null : targetModule(decl.moduleSpecifier());
				var clause = decl.exportClause();
				if (clause == null) {
					for (k in target.exports.keys()) if (k != "default") export(k, target.exports.get(k));
					continue;
				}
				if (clause.kind == KindNamespaceExport) {
					export(clause.name().text, namespaceBinding(target));
					continue;
				}
				for (e in clause.elements()) if (!e.isTypeOnly()) {
					var local = e.propertyName() != null ? e.propertyName().text : e.name().text;
					var binding = target != null ? target.exports.get(local) : functions.exists(local) && !env.exists(local) ? functionValues.get(local) : env.get(local);
					export(e.name().text, binding);
				}
			case _:
		}
		return changed;
	}

	function namespaceBinding(m:Module):Binding {
		if (m.namespace == null) m.namespace = anonymousGlobal("namespace");
		return m.namespace;
	}

	// A module namespace object: a getter per export reading its live binding.
	function namespaceObject(m:Module):Ex {
		var o = b.temp(b.runtime("libModuleNamespace", []));
		var names = [for (k in m.exports.keys()) k];
		names.sort(Reflect.compare);
		for (name in names) {
			var binding = m.exports.get(name);
			var getter = lambda(null, [], true, false, f -> b.out.push(SReturn(any(read(binding)))));
			b.runtime("libDefineMethod", [o, EStr(name), b.runtime("libFunction", [getter.clos, EInt(0), bool(false), EInt(METHOD), EStr(name)]), EInt(1), bool(true)]);
		}
		return o;
	}

	function hoist(n:Node, global:Bool):Void {
		if (n == null) return;
		if (n.kind == KindFunctionDeclaration || n.kind == KindFunctionExpression || n.kind == KindArrowFunction || n.kind == KindClassDeclaration || n.kind == KindClassExpression || n.kind == KindModuleDeclaration) return;
		if (n.kind == KindVariableDeclarationList && n.flags & NodeFlags.BlockScoped == 0) {
			for (d in n.declarations()) for (id in bindingNames(d.name())) {
				var name = id.text;
				if (!functionVars.exists(name)) {
					var existing = env.get(name);
					if (existing != null && (existing.local != null && b.f.locals.indexOf(existing.local) >= 0 || existing.cell != null && switch (existing.cell) {
						case ELocal(l): b.f.locals.indexOf(l) >= 0;
						case _: false;})) {
						functionVars.set(name, existing);
						continue;
					}
					var v:Binding;
					if (global) {
						var g = p.globals.length;
						p.globals.push({ty: TRef(RAny), init: null, name: "ts_var_" + name + "_" + g});
						v = {ty: TRef(RAny), global: g};
						b.out.push(SSetGlobal(g, b.runtime("getUndefined", [])));
					}
					else v = bind(id, TRef(RAny), b.runtime("getUndefined", []));
					functionVars.set(name, v);
					env.set(name, v);
				}
			}
		}
		for (child in n.children()) hoist(child, global);
	}

	function compileFunction(n:Node, f:FuncInfo) {
		var old = b;
		var oldEnv = env;
		var oldVars = functionVars;
		functionVars = [];
		b = new Builder(p, f);
		env = oldEnv.copy();
		var names = parameterNames(n);
		for (a in f.args) env.set(a.name, bind(names.get(a.name), a.ty, ELocal(a)));
		hoist(n.body(), false);
		parameterSetup(n);
		statement(n.body());
		if (f.ret == TVoid) b.out.push(SReturn(null)); else b.out.push(SReturn(store(b.runtime("getUndefined", []), f.ret)));
		b.finish();
		b = old;
		env = oldEnv;
		functionVars = oldVars;
	}

	function get(name:String, n:Node):Binding {
		var v = env.get(name);
		if (v == null) return fail(n, "unknown binding " + name);
		return v;
	}

	// (without TypeScript's `this:` pseudo-parameter)
	public static function parametersOf(n:Node):Array<Node> {
		var list = n.parameters();
		if (list == null) return [];
		return [for (p in list) if (p.name() == null || p.name().kind != KindIdentifier || p.name().text != "this") p];
	}

	public static function usesArguments(n:Node):Bool {
		if (n == null || n.kind == KindFunctionDeclaration || n.kind == KindFunctionExpression || n.kind == KindClassDeclaration || n.kind == KindClassExpression || n.kind == KindMethodDeclaration || n.kind == KindConstructor) return false;
		if (n.kind == KindIdentifier && n.text == "arguments") return true;
		for (c in n.children()) if (usesArguments(c)) return true;
		return false;
	}

	// Defaults and destructuring, left to right, after the arguments are boxed.
	function parameterSetup(n:Node):Void {
		var parameters = parametersOf(n);
		if (argumentFunctions.exists(b.f)) {
			var all = get("%arguments", n);
			env.set("arguments", all);
			for (i in 0...parameters.length) {
				var param = parameters[i];
				var value = param.dotDotDotToken() != null ? b.runtime("libCallMethod", [read(all), EStr("slice"), pack([EF64(i)])]) : b.runtime("libGet", [read(all), any(EF64(i))]);
				bindPattern(param.name(), withDefault(value, param.initializer()), declareLocal);
			}
			return;
		}
		for (i in 0...parameters.length) {
			var param = parameters[i];
			if (param.name().kind == KindIdentifier) {
				if (param.initializer() != null) {
					var v = get(param.name().text, param);
					var cond = b.runtime("strictEq", [any(read(v)), b.runtime("getUndefined", [])]);
					var body = b.block(() -> set(v, expr(param.initializer())));
					b.out.push(SIf(cond, body, new Vector(0)));
				}
			}
			else bindPattern(param.name(), withDefault(read(get("%parameter" + i, param)), param.initializer()), declareLocal);
		}
	}

	// The identifiers a binding name or pattern declares.
	function bindingNames(n:Node):Array<Node> {
		if (n.kind == KindIdentifier) return [n];
		var names = [];
		for (e in n.elements()) if (e.kind != KindOmittedExpression && e.name() != null) names = names.concat(bindingNames(e.name()));
		return names;
	}

	function declareLocal(name:Node, value:Ex) env.set(name.text, bind(name, TRef(RAny), any(value)));

	// (a function's plain parameters' names, by name)
	function parameterNames(n:Null<Node>):Map<String, Node> {
		var names:Map<String, Node> = [];
		if (n != null) for (param in parametersOf(n)) if (param.name().kind == KindIdentifier) names.set(param.name().text, param.name());
		return names;
	}

	function withDefault(value:Ex, initializer:Null<Node>):Ex {
		if (initializer == null) return value;
		var l = b.local("withDefault", TRef(RAny));
		b.out.push(SSet(l, any(value)));
		b.out.push(SIf(b.runtime("strictEq", [ELocal(l), b.runtime("getUndefined", [])]), b.block(() -> b.out.push(SSet(l, any(expr(initializer))))), new Vector(0)));
		return ELocal(l);
	}

	function propertyKey(n:Node):Ex return switch (n.kind) {
		case KindComputedPropertyName: any(expr(n.expression()));
		case KindNumericLiteral: b.runtime("text", [any(EF64(Std.parseFloat(n.text)))]);
		case _: EStr(n.text);
	};

	// Binds a declaration pattern to a value: object patterns read properties
	// (null and undefined throw), array patterns step the value's iterator.
	function bindPattern(pattern:Node, value:Ex, declare:(Node, Ex) -> Void) {
		switch (pattern.kind) {
			case KindIdentifier: declare(pattern, value);
			case KindObjectBindingPattern:
				var v = b.temp(any(value));
				b.runtime("libRequireObject", [v]);
				var used:Array<Ex> = [];
				for (e in pattern.elements()) {
					if (e.dotDotDotToken() != null) {
						bindPattern(e.name(), b.runtime("libObjectRest", [v, pack(used)]), declare);
						continue;
					}
					var key = b.temp(any(propertyKey(e.propertyName() == null ? e.name() : e.propertyName())));
					used.push(key);
					bindPattern(e.name(), withDefault(b.runtime("libGet", [v, key]), e.initializer()), declare);
				}
			case KindArrayBindingPattern:
				var it = b.runtime("libIterator", [any(value)]);
				for (e in pattern.elements()) {
					// (a hole: an omitted expression, or an element without a name)
					if (e.kind == KindOmittedExpression || e.name() == null) {
						b.runtime("libStep", [it]);
						continue;
					}
					if (e.dotDotDotToken() != null) {
						bindPattern(e.name(), b.runtime("libRestArray", [it]), declare);
						continue;
					}
					bindPattern(e.name(), withDefault(b.runtime("libStep", [it]), e.initializer()), declare);
				}
			case _: fail(pattern, "unsupported binding pattern");
		}
	}

	// Destructuring assignment: the targets are references (or nested patterns).
	function assignPattern(target:Node, value:Ex) {
		while (target.kind == KindParenthesizedExpression) target = target.expression();
		switch (target.kind) {
			case KindArrayLiteralExpression:
				var it = b.runtime("libIterator", [any(value)]);
				for (e in elements(target)) switch (e.kind) {
					case KindOmittedExpression: b.runtime("libStep", [it]);
					case KindSpreadElement: assignPattern(e.expression(), b.runtime("libRestArray", [it]));
					case KindBinaryExpression if (e.operatorToken().kind == KindEqualsToken):
						var x = e;
						assignTarget(x.left(), () -> withDefault(b.runtime("libStep", [it]), x.right()));
					case _: assignTarget(e, () -> b.runtime("libStep", [it]));
				}
			case KindObjectLiteralExpression:
				var v = b.temp(any(value));
				b.runtime("libRequireObject", [v]);
				var used:Array<Ex> = [];
				for (prop in properties(target)) switch (prop.kind) {
					case KindSpreadAssignment: assignPattern(prop.expression(), b.runtime("libObjectRest", [v, pack(used)]));
					case KindShorthandPropertyAssignment:
						var key = EStr(prop.name().text);
						used.push(key);
						var init = prop.objectAssignmentInitializer();
						assignTarget(prop.name(), () -> withDefault(b.runtime("libGet", [v, key]), init));
					case KindPropertyAssignment:
						var key = b.temp(any(propertyKey(prop.name())));
						used.push(key);
						var t = prop.initializer();
						if (t.kind == KindBinaryExpression && t.operatorToken().kind == KindEqualsToken) {
							var x = t;
							assignTarget(x.left(), () -> withDefault(b.runtime("libGet", [v, key]), x.right()));
						}
						else assignTarget(t, () -> b.runtime("libGet", [v, key]));
					case _: fail(prop, "unsupported assignment pattern member");
				}
			case _: lvalue(target).write(value);
		}
	}

	// (a reference's object and key are evaluated before the value, as in JS)
	function assignTarget(target:Node, value:() -> Ex) {
		while (target.kind == KindParenthesizedExpression) target = target.expression();
		if (target.kind == KindArrayLiteralExpression || target.kind == KindObjectLiteralExpression) assignPattern(target, value());
		else {
			var ref = lvalue(target);
			ref.write(value());
		}
	}

	function properties(n:Node):Array<Node> {
		var list = n.properties();
		return list == null ? [] : list;
	}

	function read(v:Binding):Ex {
		if (v.global != null) return EGlobal(v.global, v.ty);
		// (a plain local's value now: later writes do not change it)
		if (v.local != null) return b.temp(ELocal(v.local));
		if (v.outer != null) throw "TSHX004: a closure uses a binding it does not capture: " + v.outer;
		return EBoxGet(v.ty, v.cell);
	}

	function set(v:Binding, e:Ex) {
		e = store(e, v.ty);
		if (v.outer != null) throw "TSHX004: a closure uses a binding it does not capture: " + v.outer;
		b.out.push(v.global != null ? SSetGlobal(v.global, e) : v.local != null ? SSet(v.local, e) : SBoxSet(v.ty, v.cell, e));
	}

	function statement(n:Node, top = false, ?labels:Array<String>) {
		if (n == null) return;
		if (labels == null) labels = [];
		if (hasModifier(n, KindDeclareKeyword)) return;
		here = n;
		switch (n.kind) {
			case KindImportDeclaration | KindExportDeclaration: // (bindings: see linkModule)
			case KindExportAssignment:
				if (n.isExportEquals()) fail(n, "export = is not supported; use export default");
				var m = moduleOf.get(n.file.path);
				set(m.exports.get("default"), named(n.expression(), "default"));
			case KindImportEqualsDeclaration: fail(n, "import = require() is not supported; use import declarations");
			case KindFunctionDeclaration: // (hoisted: see hoistFunctions)
			case KindClassDeclaration:
				if (n.name() != null) set(get(n.name().text, n), classValue(n));
				else set(moduleOf.get(n.file.path).exports.get("default"), classValue(n, "default"));
			case KindInterfaceDeclaration | KindTypeAliasDeclaration | KindEmptyStatement:
			case KindEnumDeclaration: enumDeclaration(n);
			case KindModuleDeclaration: namespaceDeclaration(n);
			case KindBlock:
				var old = env;
				env = env.copy();
				var statements = n.statements();
				if (statements == null) statements = [];
				hoistFunctions(statements);
				for (s in statements) statement(s);
				env = old;
			case KindVariableStatement: variableList(n.declarationList(), top, !top);
			case KindVariableDeclarationList: variableList(n, top);
			case KindExpressionStatement: expr(n.expression());
			case KindReturnStatement: emitReturn(n.expression() == null ? null : expr(n.expression()));
			case KindIfStatement:
				var i = n;
				var c = truth(expr(i.expression()));
				var a = b.block(() -> statement(i.thenStatement()));
				var z = b.block(() -> statement(i.elseStatement()));
				b.out.push(SIf(c, a, z));
			case KindLabeledStatement:
				var l = n;
				var inner = l.statement();
				switch (inner.kind) {
					case KindForStatement | KindForOfStatement | KindForInStatement | KindWhileStatement | KindDoStatement | KindLabeledStatement: statement(inner, false, labels.concat([l.label().text]));
					case _:
						var t = target(labels.concat([l.label().text]), JLabel);
						var before = b.flagged;
						irLoop(() -> {
							t.breakDepth = b.depth;
							statement(inner);
							b.out.push(SBreak);
						}, t);
						if (b.flagged > before) land(t.breakCode);
				}
			case KindWhileStatement:
				var w = n;
				loop(labels, w.statement(), () -> exitUnless(w.expression()), null, null);
			case KindDoStatement:
				var d = n;
				loop(labels, d.statement(), null, null, () -> exitUnless(d.expression()));
			case KindForStatement:
				var oldEnv = env;
				env = env.copy();
				var f = n;
				if (f.initializer() != null) {
					if (f.initializer().kind == KindVariableDeclarationList) variableList(f.initializer(), false); else expr(f.initializer());
				}
				loop(labels, f.statement(), f.condition() == null ? null : () -> exitUnless(f.condition()), () -> {
					// (a fresh binding per iteration for closures that captured it)
					if (f.initializer() != null && f.initializer().kind == KindVariableDeclarationList)
						for (d in f.initializer().declarations()) {
							var binding = get(d.name().text, d);
							if (binding.local == null) switch (binding.cell) {
								case ELocal(cell): if (capturedCells.exists(cell)) b.out.push(SSet(cell, ENewBox(binding.ty, read(binding))));
								case _: fail(d, "loop binding must be local");
							}
						}
					if (f.incrementor() != null) expr(f.incrementor());
				}, null);
				env = oldEnv;
			case KindForOfStatement | KindForInStatement:
				var loopNode = n;
				var oldEnv = env;
				env = env.copy();
				var input = expr(loopNode.expression());
				if (n.kind == KindForInStatement) input = b.runtime("libForInKeys", [any(input)]);
				var awaiting = n.kind == KindForOfStatement && loopNode.awaitModifier() != null;
				// (an array whose iteration is the built-in one: stepped by index, as its iterator would)
				var indexed = n.kind == KindForOfStatement && !awaiting && types.isArray(loopNode.expression().tsType);
				var fast = null, index = null;
				if (indexed) {
					input = b.temp(input);
					fast = b.local("indexed", TBool);
					b.out.push(SSet(fast, bool(false)));
					b.out.push(SIf(EInstOf(reps.arrayClass, any(input)), b.block(() -> b.out.push(SSet(fast, b.runtime("libArrayIterable", [any(input)])))), new Vector(0)));
					index = b.local("index", TF64);
					b.out.push(SSet(index, EF64(0)));
				}
				var iterator = b.local("iterator", TRef(RAny));
				var open = b.block(() -> b.out.push(SSet(iterator, b.runtime(awaiting ? "libAsyncIterator" : "libIterator", [any(input)]))));
				if (indexed) {
					b.out.push(SSet(iterator, b.runtime("getUndefined", [])));
					b.out.push(SIf(ENot(ELocal(fast)), open, new Vector(0)));
				}
				else for (s in open) b.out.push(s);
				var init = loopNode.initializer();
				loop(labels, loopNode.statement(), () -> {
					var value:Ex;
					if (indexed) {
						var l = b.local("element", TRef(RAny));
						b.out.push(SIf(ELocal(fast), b.block(() -> {
							b.out.push(SIf(EBin(FGe, ELocal(index), reps.arrayLength(b, input)), Vector.fromArrayCopy([SBreak]), new Vector(0)));
							b.out.push(SSet(l, reps.arrayGet(b, input, ELocal(index))));
							b.out.push(SSet(index, EBin(FAdd, ELocal(index), EF64(1))));
						}), b.block(() -> {
							var v = b.runtime("libIterate", [ELocal(iterator)]);
							b.out.push(SIf(b.runtime("libFinished", [v]), Vector.fromArrayCopy([SBreak]), new Vector(0)));
							b.out.push(SSet(l, v));
						})));
						value = ELocal(l);
					}
					else if (awaiting) {
						// (for await: each step awaits next()'s result)
						var result = yieldPoint(b.runtime("libCallMethod", [ELocal(iterator), EStr("next"), pack([])]), true, AWAIT);
						b.out.push(SIf(truth(b.runtime("libGet", [result, EStr("done")])), Vector.fromArrayCopy([SBreak]), new Vector(0)));
						value = b.runtime("libGet", [result, EStr("value")]);
					}
					else {
						value = b.runtime("libIterate", [ELocal(iterator)]);
						b.out.push(SIf(b.runtime("libFinished", [value]), Vector.fromArrayCopy([SBreak]), new Vector(0)));
					}
					if (init.kind != KindVariableDeclarationList) assignTarget(init, () -> value);
					else {
						var declaration = init.declarations()[0];
						if (init.flags & NodeFlags.BlockScoped == 0) bindPattern(declaration.name(), value, (id, v) -> {
							var binding = functionVars.get(id.text);
							set(binding, v);
							env.set(id.text, binding);});
						else bindPattern(declaration.name(), value, declareLocal);
					}
				}, null, null);
				env = oldEnv;
			case KindSwitchStatement: switchStatement(n, labels);
			case KindThrowStatement: b.out.push(SThrow(any(expr(n.expression()))));
			case KindTryStatement: tryStatement(n);
			case KindBreakStatement: jump(n, true);
			case KindContinueStatement: jump(n, false);
			case _: fail(n, "unsupported statement " + n.kind.toString());
		}
	}

	function emitReturn(e:Null<Ex>) {
		var value = e == null ? (b.f.ret == TVoid ? null : store(b.runtime("getUndefined", []), b.f.ret)) : store(e, b.f.ret);
		// (a constructor returns `this` unless it returns an object)
		if (b.constructorThis != null) value = e == null ? read(b.constructorThis) : b.runtime("libConstructResult", [value, read(b.constructorThis)]);
		if (!insideFinally()) b.out.push(SReturn(value));
		else {
			// (through finally blocks: they run first; see tryStatement)
			if (value != null) {
				if (b.result == null) b.result = b.local("result", b.f.ret);
				b.out.push(SSet(b.result, value));
			}
			flag(-1);
		}
	}

	// Function declarations in a statement list are bound before its statements
	// run; boxes first, so they can call each other.
	function hoistFunctions(statements:Array<Node>) {
		// (class declarations get their binding here and their value where they appear)
		var declared:Map<String, Bool> = [];
		// (let and const bindings exist from the start of the block, so earlier functions see them)
		for (s in statements) if (s.kind == KindVariableStatement && !hasModifier(s, KindDeclareKeyword)) {
			var list = s.declarationList();
			if (list.flags & NodeFlags.BlockScoped == 0) continue;
			for (d in list.declarations()) for (id in bindingNames(d.name())) {
				var t = id == d.name() ? bindingType(d) : TRef(RAny);
				env.set(id.text, bind(id, t, placeholder(t)));
			}
		}
		for (s in statements) if ((s.kind == KindClassDeclaration || s.kind == KindEnumDeclaration || s.kind == KindModuleDeclaration) && s.name() != null && !hasModifier(s, KindDeclareKeyword) && !declared.exists(s.name().text)) {
			declared.set(s.name().text, true);
			env.set(s.name().text, bind(s.name(), TRef(RAny), b.runtime("getUndefined", [])));
		}
		var declarations = [for (s in statements) if (s.kind == KindFunctionDeclaration && s.body() != null) s];
		for (d in declarations) env.set(d.name().text, bind(d.name(), TRef(RAny), b.runtime("getUndefined", [])));
		for (d in declarations) set(env.get(d.name().text), closure(d));
	}

	// (enum and namespace declarations merge into an existing object of the same name)
	function mergeTarget(binding:Binding):Ex {
		var current = b.temp(any(read(binding)));
		var target = b.local("declaration", TRef(RAny));
		b.out.push(SIf(b.runtime("libIsObject", [current]), Vector.fromArrayCopy([SSet(target, current)]), b.block(() -> b.out.push(SSet(target, b.runtime("libObject", [pack([]), pack([])]))))));
		set(binding, ELocal(target));
		return ELocal(target);
	}

	// Enums as TypeScript emits them: name -> value, and value -> name for
	// numeric members; members count up from the previous numeric one.
	function enumDeclaration(n:Node) {
		var obj = mergeTarget(get(n.name().text, n));
		var outer = env;
		env = env.copy();
		var previous:Ex = null;
		for (m in members(n)) {
			var name = m.name().text;
			var value = b.temp(m.initializer() != null ? any(expr(m.initializer())) : previous == null ? any(EF64(0)) : b.runtime("add", [previous, any(EF64(1))]));
			b.runtime("libPut", [obj, EStr(name), value]);
			var numeric = b.runtime("strictEq", [b.runtime("typeOf", [value]), EStr("number")]);
			b.out.push(SIf(numeric, b.block(() -> b.runtime("libPut", [obj, value, EStr(name)])), new Vector(0)));
			// (later initializers may name earlier members)
			env.set(name, {ty: TRef(RAny), cell: b.temp(ENewBox(TRef(RAny), value))});
			previous = value;
		}
		env = outer;
	}

	// Namespaces: the body runs once, as a closure, and exported declarations
	// become properties of the namespace object.
	function namespaceDeclaration(n:Node) {
		if (n.body() == null) return;
		namespaceBody(n.body(), mergeTarget(get(n.name().text, n)));
	}

	function namespaceBody(body:Node, obj:Ex) {
		if (body.kind == KindModuleDeclaration) {
			var name = EStr(body.name().text);
			var current = b.runtime("libGet", [obj, name]);
			var child = b.local("namespace", TRef(RAny));
			b.out.push(SIf(b.runtime("libIsObject", [current]), Vector.fromArrayCopy([SSet(child, current)]), b.block(() -> b.out.push(SSet(child, b.runtime("libObject", [pack([]), pack([])]))))));
			b.runtime("libPut", [obj, name, ELocal(child)]);
			namespaceBody(body.body(), ELocal(child));
			return;
		}
		var outer = env;
		env = env.copy();
		env.set("%namespace", {ty: TRef(RAny), cell: b.temp(ENewBox(TRef(RAny), obj))});
		var r = lambda(null, [], true, false, f -> {
			var statements = body.statements();
			if (statements == null) statements = [];
			hoist(body, false);
			hoistFunctions(statements);
			var ns = read(env.get("%namespace"));
			function export(name:String) b.runtime("libPut", [ns, EStr(name), any(read(get(name, body)))]);
			for (s in statements) if (s.kind == KindFunctionDeclaration && s.body() != null && hasModifier(s, KindExportKeyword)) export(s.name().text);
			for (s in statements) {
				statement(s);
				if (!hasModifier(s, KindExportKeyword) || hasModifier(s, KindDeclareKeyword)) continue;
				switch (s.kind) {
					case KindVariableStatement: for (d in s.declarationList().declarations()) for (id in bindingNames(d.name())) export(id.text);
					case KindClassDeclaration | KindEnumDeclaration | KindModuleDeclaration: export(s.name().text);
					case _:
				}
			}
			b.out.push(SReturn(b.runtime("getUndefined", [])));
		});
		env = outer;
		b.runtime("libCall", [b.runtime("libFunction", [r.clos, EInt(0), bool(false), EInt(METHOD), EStr("")]), b.runtime("getUndefined", []), pack([])]);
	}

	// JS jumps. A target is a loop, switch, labeled statement or finally block.
	// A break or continue that lands right after the innermost IR loop is a
	// plain SBreak; any other jump stores a code in the function's jump local
	// and breaks, and the code is dispatched (land) after each IR loop it
	// leaves. -1 is a return passing through finally blocks.
	function target(labels:Array<String>, kind:JumpKind):JumpTarget
		return {labels: labels, kind: kind, breakCode: ++b.codes, continueCode: ++b.codes, breakDepth: -1, continueDepth: -1};

	function jumpCode():Local {
		if (b.jump == null) b.jump = b.local("jump", TI32);
		return b.jump;
	}

	function irLoop(build:() -> Void, ?t:JumpTarget) {
		if (t != null) b.targets.push(t);
		b.depth++;
		var body = b.block(build);
		b.depth--;
		if (t != null) b.targets.pop();
		b.out.push(SLoop(body));
	}

	function flag(code:Int) {
		b.flagged++;
		b.out.push(SSet(jumpCode(), EInt(code)));
		b.out.push(SBreak);
	}

	function insideFinally():Bool {
		for (t in b.targets) if (t.kind == JFinally) return true;
		return false;
	}

	function land(code:Int) {
		var j = ELocal(jumpCode());
		b.out.push(SIf(EBin(Ne, j, EInt(0)), Vector.fromArrayCopy([SIf(EBin(Eq, j, EInt(code)), Vector.fromArrayCopy([SSet(jumpCode(), EInt(0))]), b.block(propagate))]), new Vector(0)));
	}

	// (a pending jump leaves the enclosing IR loop; at the function's top level only a return remains)
	function propagate() {
		if (b.depth > 0) {
			b.out.push(SBreak);
			return;
		}
		b.out.push(SReturn(b.f.ret == TVoid ? null : b.result != null ? ELocal(b.result) : b.coerce(b.runtime("getUndefined", []), b.f.ret)));
	}

	function jump(n:Node, isBreak:Bool) {
		var label = n.label() == null ? null : n.label().text;
		var crossed = false;
		var t:JumpTarget = null;
		var i = b.targets.length - 1;
		while (i >= 0) {
			var c = b.targets[i--];
			if (c.kind == JFinally) {
				crossed = true;
				continue;
			}
			if (label != null ? c.labels.indexOf(label) >= 0 : isBreak ? c.kind != JLabel : c.kind == JLoop) {
				t = c;
				break;
			}
		}
		if (t == null || !isBreak && t.kind != JLoop) fail(n, "jump target not found");
		if (!crossed && (isBreak ? t.breakDepth : t.continueDepth) == b.depth) b.out.push(SBreak);
		else flag(isBreak ? t.breakCode : t.continueCode);
	}

	function exitUnless(cond:Node) b.out.push(SIf(ENot(truth(expr(cond))), Vector.fromArrayCopy([SBreak]), new Vector(0)));

	function containsContinue(n:Node):Bool {
		if (n == null || n.kind == KindFunctionDeclaration || n.kind == KindFunctionExpression || n.kind == KindArrowFunction || n.kind == KindClassDeclaration) return false;
		if (n.kind == KindContinueStatement) return true;
		for (c in n.children()) if (containsContinue(c)) return true;
		return false;
	}

	// A loop: head (at the top of each iteration; may exit), the body, step
	// (where continue lands) and tail (after step; may exit). A body with
	// continue sits in its own IR loop, which continue leaves.
	function loop(labels:Array<String>, body:Node, head:Null<() -> Void>, step:Null<() -> Void>, tail:Null<() -> Void>) {
		var t = target(labels, JLoop);
		var before = b.flagged;
		var inner = containsContinue(body);
		irLoop(() -> {
			t.breakDepth = b.depth;
			if (head != null) head();
			if (inner) {
				var innerBefore = b.flagged;
				irLoop(() -> {
					t.continueDepth = b.depth;
					statement(body);
					b.out.push(SBreak);});
				if (b.flagged > innerBefore) land(t.continueCode);
			}
			else statement(body);
			if (step != null) step();
			if (tail != null) tail();
		}, t);
		if (b.flagged > before) land(t.breakCode);
	}

	// Cases are tested in order until one matches; bodies from the matched one
	// (or default's) on run in one IR loop that break leaves.
	function switchStatement(n:Node, labels:Array<String>) {
		var sw = n;
		var value = b.temp(expr(sw.expression()));
		var clauses = sw.caseBlock().clauses();
		if (clauses == null) clauses = [];
		var start = b.local("case", TI32);
		var fallback = clauses.length;
		for (i in 0...clauses.length) if (clauses[i].kind == KindDefaultClause) fallback = i;
		function test(i:Int) {
			while (i < clauses.length && clauses[i].kind == KindDefaultClause) i++;
			if (i >= clauses.length) {
				b.out.push(SSet(start, EInt(fallback)));
				return;
			}
			var c = strictEquals(value, expr(clauses[i].expression()));
			b.out.push(SIf(c, Vector.fromArrayCopy([SSet(start, EInt(i))]), b.block(() -> test(i + 1))));
		}
		test(0);
		var t = target(labels, JSwitch);
		var before = b.flagged;
		var oldEnv = env;
		env = env.copy();
		// (the case block is one scope)
		var all:Array<Node> = [];
		for (c in clauses) {
			var list = c.statements();
			if (list != null) all = all.concat(list);
		}
		hoistFunctions(all);
		irLoop(() -> {
			t.breakDepth = b.depth;
			for (i in 0...clauses.length) {
				var statements = clauses[i].statements();
				if (statements == null) statements = [];
				b.out.push(SIf(EBin(Le, ELocal(start), EInt(i)), b.block(() -> for (s in statements) statement(s)), new Vector(0)));
			}
			b.out.push(SBreak);
		}, t);
		env = oldEnv;
		if (b.flagged > before) land(t.breakCode);
	}

	function tryStatement(n:Node) {
		var t = n;
		function guarded() {
			var body = b.block(() -> statement(t.tryBlock()));
			var catches:Array<IrCatch> = [];
			if (t.catchClause() != null) {
				var c = t.catchClause();
				var local = b.local("caught", TRef(RAny));
				var oldEnv = env;
				env = env.copy();
				var handler = b.block(() -> {
					if (c.variableDeclaration() != null) bindPattern(c.variableDeclaration().name(), ELocal(local), declareLocal);
					statement(c.block());});
				env = oldEnv;
				catches.push({test: null, l: local, body: handler});
				b.f.hasTry = true;
				b.out.push(STry(body, Vector.fromArrayCopy(catches)));
			}
			else for (s in body) b.out.push(s);
		}
		if (t.finallyBlock() == null) {
			guarded();
			return;
		}
		// try/finally: the guarded part runs in an IR loop that jumps leave, an
		// exception is held while the finally block runs, then rethrown or the
		// pending jump continues.
		var fin = target([], JFinally);
		var before = b.flagged;
		var threw = b.local("threw", TBool), held = b.local("held", TRef(RAny)), caught = b.local("caught", TRef(RAny));
		b.out.push(SSet(threw, ECast(TBool, EInt(0))));
		b.out.push(SSet(held, ENull(TRef(RAny))));
		irLoop(() -> {
			fin.breakDepth = b.depth;
			var body = b.block(guarded);
			b.f.hasTry = true;
			b.out.push(STry(body, Vector.fromArrayCopy([{test: null, l: caught, body: Vector.fromArrayCopy([SSet(threw, ECast(TBool, EInt(1))), SSet(held, ELocal(caught))])}])));
			b.out.push(SBreak);
		}, fin);
		var jumped = b.flagged > before;
		statement(t.finallyBlock());
		b.out.push(SIf(ELocal(threw), Vector.fromArrayCopy([SThrow(ELocal(held))]), new Vector(0)));
		if (jumped) {
			var j = ELocal(jumpCode());
			var returning = insideFinally() ? b.block(propagate) : Vector.fromArrayCopy([SReturn(b.f.ret == TVoid ? null : b.result != null ? ELocal(b.result) : b.coerce(b.runtime("getUndefined", []), b.f.ret))]);
			b.out.push(SIf(EBin(Eq, j, EInt(-1)), returning, Vector.fromArrayCopy([SIf(EBin(Ne, j, EInt(0)), b.block(propagate), new Vector(0))])));
		}
	}

	// (predeclared: block-scoped bindings were created at block entry; see hoistFunctions)
	function variableList(n:Node, top:Bool, predeclared = false) {
		for (d in n.declarations()) {
			var e = d.initializer() == null ? b.runtime("getUndefined", []) : named(d.initializer(), d.name().kind == KindIdentifier ? d.name().text : null);
			if (d.name().kind != KindIdentifier) {
				var scoped = n.flags & NodeFlags.BlockScoped != 0;
				bindPattern(d.name(), e, !scoped ? (id, v) -> set(functionVars.get(id.text), v) : top || predeclared ? (id, v) -> set(get(id.text, id), v) : declareLocal);
				continue;
			}
			var name = d.name().text;
			if (n.flags & NodeFlags.BlockScoped == 0) {
				if (d.initializer() != null) set(functionVars.get(name), e);
				env.set(name, functionVars.get(name));
			}
			else if (top || predeclared) set(get(name, d), e);
			else {
				var t = bindingType(d);
				env.set(name, bind(d.name(), t, store(e, t)));
			}
		}
	}

	function pack(xs:Array<Ex>):Ex return b.temp(ENewArr(TRef(RAny), Vector.fromArrayCopy([for (x in xs) any(x)])));

	function actuals(nodes:Array<Node>):Array<Ex> return [for (n in nodes) expr(n)];

	function apply(fn:Ex, list:Ex):Ex return b.runtime("libCall", [any(fn), b.runtime("getUndefined", []), list]);

	// (an anonymous function or class expression takes its name from where it is bound)
	function named(n:Node, name:Null<String>):Ex {
		var inner = n;
		while (inner.kind == KindParenthesizedExpression) inner = inner.expression();
		if (name != null && (inner.kind == KindArrowFunction || inner.kind == KindFunctionExpression || inner.kind == KindClassExpression) && inner.name() == null) pendingName = name;
		var e = expr(n);
		pendingName = null;
		return e;
	}

	function takeName():String {
		var name = pendingName;
		pendingName = null;
		return name == null ? "" : name;
	}

	function any(e:Ex):Ex return b.coerce(e, TRef(RAny));

	// (ToNumber)
	function number(e:Ex):Ex return Ir.typeOf(e) == TF64 ? e : b.coerce(any(e), TF64);

	function truth(e:Ex):Ex {
		if (Ir.typeOf(e) == TBool) {
			typedOperations++;
			return e;
		}
		dynamicOperations++;
		return b.runtime("truth", [any(e)]);
	}

	function text(e:Ex):Ex return switch (Ir.typeOf(e)) {
		case TRef(RStr): e;
		case TF64: b.runtime("numberText", [e]);
		case _: b.runtime("text", [any(e)]);
	};

	function expr(n:Node):Ex {
		expressions++;
		var result:Ex = switch (n.kind) {
			case KindPropertyAccessExpression | KindElementAccessExpression | KindCallExpression if (chainTop(n)): optionalChain(n);
			case KindNumericLiteral: EF64(Std.parseFloat(n.text));
			case KindStringLiteral | KindNoSubstitutionTemplateLiteral: EStr(n.text);
			case KindTrueKeyword: ECast(TBool, EInt(1));
			case KindFalseKeyword: ECast(TBool, EInt(0));
			case KindNullKeyword: ENull(TRef(RAny));
			case KindThisKeyword: env.exists("this") ? read(env.get("this")) : b.runtime("getUndefined", []);
			case KindArrowFunction | KindFunctionExpression: closure(n, takeName());
			case KindClassExpression: classValue(n, takeName());
			case KindMetaProperty: env.exists("%newTarget") ? read(env.get("%newTarget")) : b.runtime("getUndefined", []);
			case KindNewExpression: construct(n);
			case KindIdentifier:
				var name = n.text;
				if (name == "undefined") b.runtime("getUndefined", []);
				else if (name == "NaN") EF64(Math.NaN);
				else if (name == "Infinity") EF64(Math.POSITIVE_INFINITY);
				else if (!env.exists(name) && functions.exists(name)) read(functionValues.get(name));
				// (in a namespace, a member exported by another declaration of it)
				else if (!env.exists(name) && env.exists("%namespace")) b.runtime("libNamespaceGet", [read(env.get("%namespace")), EStr(name)]);
				else if (!env.exists(name)) b.runtime("libGlobal", [EStr(name)]);
				else read(get(name, n));
			case KindParenthesizedExpression | KindAsExpression | KindTypeAssertionExpression | KindNonNullExpression | KindSatisfiesExpression: expr(n.expression());
			case KindBinaryExpression: binary(n);
			case KindPrefixUnaryExpression:
				var u = n;
				var x:Ex;
				if (u.unaryOperator() == KindPlusPlusToken || u.unaryOperator() == KindMinusMinusToken) {
					var target = lvalue(u.operand());
					x = b.temp(EBin(u.unaryOperator() == KindPlusPlusToken ? FAdd : FSub, b.coerce(target.read(), TF64), EF64(1)));
					target.write(x);
				}
				else x = expr(u.operand());
				switch (u.unaryOperator()) {
					case KindMinusToken: EConv(FNeg, b.coerce(x, TF64));
					case KindPlusToken: b.coerce(x, TF64);
					case KindExclamationToken: ENot(truth(x));
					case KindPlusPlusToken | KindMinusMinusToken: x;
					case KindTildeToken: EConv(I2F, EBin(Xor, b.runtime("libInt", [any(x)]), EInt(-1)));
					case _: fail(n, "unsupported unary operator");
				}
			case KindPostfixUnaryExpression:
				var u = n;
				var target = lvalue(u.operand());
				var previous = b.temp(b.coerce(target.read(), TF64));
				target.write(EBin(u.unaryOperator() == KindPlusPlusToken ? FAdd : FSub, previous, EF64(1)));
				previous;
			case KindVoidExpression:
				expr(n.expression());
				b.runtime("getUndefined", []);
			case KindTaggedTemplateExpression:
				var t = n;
				var template = t.template();
				var parts = template.kind == KindNoSubstitutionTemplateLiteral ? [template] : [template.head()].concat([for (span in template.templateSpans()) span.literal()]);
				var values = template.kind == KindNoSubstitutionTemplateLiteral ? [] : [for (span in template.templateSpans()) span.expression()];
				// (one frozen strings array per call site, created on first use)
				var site = global("%template" + serial++);
				b.out.push(SIf(ENot(b.runtime("libIsObject", [read(site)])), b.block(() -> set(site, b.runtime("libTemplateObject", [pack([for (x in parts) EStr(x.text)]), pack([for (x in parts) EStr(x.kind == KindNoSubstitutionTemplateLiteral ? x.rawText() : x.rawText())])]))), new Vector(0)));
				var tag = t.tag();
				while (tag.kind == KindParenthesizedExpression) tag = tag.expression();
				if ((tag.kind == KindPropertyAccessExpression || tag.kind == KindElementAccessExpression) && tag.expression().kind != KindSuperKeyword) {
					var obj = b.temp(any(expr(tag.expression())));
					var key = tag.kind == KindPropertyAccessExpression ? EStr(tag.name().text) : any(expr(tag.argumentExpression()));
					b.runtime("libCallMethod", [obj, key, pack([read(site)].concat(actuals(values)))]);
				}
				else {
					var fn = any(expr(t.tag()));
					b.runtime("libCall", [fn, b.runtime("getUndefined", []), pack([read(site)].concat(actuals(values)))]);
				}
			case KindRegularExpressionLiteral:
				var text = n.text;
				var slash = text.lastIndexOf("/");
				b.runtime("libRegExp", [EStr(text.substring(1, slash)), EStr(text.substr(slash + 1))]);
			case KindYieldExpression:
				if (b.resumable == null || !b.resumable.generator) fail(n, "yield outside a generator");
				if (n.asteriskToken() != null) {
					if (b.resumable.async) fail(n, "yield* in async generators is not implemented yet");
					delegate(any(expr(n.expression())));
				}
				else {
					var v = n.expression() == null ? b.runtime("getUndefined", []) : any(expr(n.expression()));
					// (an async generator awaits what it yields)
					if (b.resumable.async) v = yieldPoint(v, true, AWAIT);
					yieldPoint(v, true);
				}
			case KindAwaitExpression:
				if (b.resumable == null || !b.resumable.async) fail(n, "await outside an async function");
				yieldPoint(any(expr(n.expression())), true, AWAIT);
			case KindTemplateExpression:
				var t = n;
				var result:Ex = EStr(t.head().text);
				for (span in t.templateSpans()) {
					var piece = span;
					result = b.runtime("concat", [result, b.runtime("text", [any(expr(piece.expression()))])]);
					result = b.runtime("concat", [result, EStr(piece.literal().text)]);
				}
				result;
			case KindTypeOfExpression:
				var value = n.expression();
				while (value.kind == KindParenthesizedExpression) value = value.expression();
				if (value.kind == KindIdentifier && !env.exists(value.text) && !functions.exists(value.text)) {
					env.exists("%namespace") ? b.runtime("libTypeofNamespace", [read(env.get("%namespace")), EStr(value.text)]) : b.runtime("libTypeofGlobal", [EStr(value.text)]);
				}
				else b.runtime("typeOf", [any(expr(value))]);
			case KindCallExpression: call(n);
			case KindArrayLiteralExpression:
				if (hasSpread(elements(n))) b.runtime("libArray", [spreadList(elements(n))]);
				else b.runtime("libArray", [pack([for (e in elements(n)) e.kind == KindOmittedExpression ? b.runtime("libHole", []) : expr(e)])]);
			case KindElementAccessExpression if (n.expression().kind == KindSuperKeyword):
				b.runtime("libSuperGet", [read(get("%home", n)), thisValue(), any(expr(n.argumentExpression()))]);
			case KindElementAccessExpression if (arrayElement(n)):
				var obj = b.temp(expr(n.expression()));
				typedOperations++;
				reps.arrayGet(b, obj, b.temp(number(expr(n.argumentExpression()))));
			case KindElementAccessExpression:
				var obj = expr(n.expression());
				chainCheck(n, obj);
				var key = expr(n.argumentExpression());
				dynamicOperations++;
				b.runtime("libGet", [any(obj), any(key)]);
			case KindObjectLiteralExpression: objectLiteral(n);
			case KindPropertyAccessExpression if (n.expression().kind == KindSuperKeyword):
				b.runtime("libSuperGet", [read(get("%home", n)), thisValue(), EStr(n.name().text)]);
			case KindPropertyAccessExpression if (n.name().kind == KindPrivateIdentifier):
				var a = expr(n.expression());
				chainCheck(n, a);
				b.runtime("libPrivateGet", [any(a), EStr(brand(n.name()))]);
			case KindPropertyAccessExpression if (n.name().text == "length" && plainAccess(n) && types.isArray(n.expression().tsType)):
				typedOperations++;
				reps.arrayLength(b, b.temp(expr(n.expression())));
			case KindPropertyAccessExpression if (layoutField(n) != null):
				typedOperations++;
				reps.fieldGet(b, layoutField(n), b.temp(expr(n.expression())), n.name().text, where());
			case KindPropertyAccessExpression:
				var a = expr(n.expression());
				var name = n.name().text;
				chainCheck(n, a);
				dynamicOperations++;
				b.runtime("libGet", [any(a), EStr(name)]);
			case KindDeleteExpression:
				var target = n.expression();
				if (target.kind == KindPropertyAccessExpression) b.runtime("libDelete", [any(expr(target.expression())), EStr(target.name().text)]);
				else if (target.kind == KindElementAccessExpression) {
					var obj = expr(target.expression());
					b.runtime("libDelete", [any(obj), any(expr(target.argumentExpression()))]);
				}
				else fail(n, "delete requires a property");
			case KindConditionalExpression:
				var c = n;
				var cond = truth(expr(c.condition()));
				var l = b.local("conditional", typeAt(n));
				var yes = b.block(() -> b.out.push(SSet(l, b.coerce(expr(c.whenTrue()), l.ty))));
				var no = b.block(() -> b.out.push(SSet(l, b.coerce(expr(c.whenFalse()), l.ty))));
				b.out.push(SIf(cond, yes, no));
				ELocal(l);
			case _: fail(n, "unsupported expression " + n.kind.toString());
		};
		if (Ir.typeOf(result).match(TRef(RAny))) dynamicSites++; else typed++;
		return switch (result) {
			case EInt(_) | EF64(_) | EStr(_) | ENull(_) | ELocal(_): result;
			case _: b.temp(result);
		};
	}

	function lvalue(n:Node):{read:() -> Ex, write:Ex->Void} {
		while (n.kind == KindParenthesizedExpression || n.kind == KindNonNullExpression || n.kind == KindAsExpression || n.kind == KindSatisfiesExpression || n.kind == KindTypeAssertionExpression) n = n.expression();
		if (n.kind == KindIdentifier) {
			var v = get(n.text, n);
			return {read: () -> b.temp(read(v)), write: (e) -> set(v, e)};
		}
		if ((n.kind == KindPropertyAccessExpression || n.kind == KindElementAccessExpression) && n.expression().kind == KindSuperKeyword) {
			var key = n.kind == KindPropertyAccessExpression ? EStr(n.name().text) : b.temp(any(expr(n.argumentExpression())));
			var home = read(get("%home", n));
			return {
				read: () -> b.runtime("libSuperGet", [home, thisValue(), key]),
				write: (e) -> {
					b.runtime("libSuperSet", [home, thisValue(), key, any(e)]);
				}
			};
		}
		if (n.kind == KindPropertyAccessExpression && n.name().kind == KindPrivateIdentifier) {
			var obj = b.temp(any(expr(n.expression())));
			var key = EStr(brand(n.name()));
			return {
				read: () -> b.runtime("libPrivateGet", [obj, key]),
				write: (e) -> {
					b.runtime("libPrivateSet", [obj, key, any(e)]);
				}
			};
		}
		if (arrayElement(n)) {
			var obj = b.temp(expr(n.expression()));
			var key = b.temp(number(expr(n.argumentExpression())));
			return {
				read: () -> reps.arrayGet(b, obj, key),
				write: (e) -> reps.arraySet(b, obj, key, e)
			};
		}
		var field = layoutField(n);
		if (field != null) {
			var obj = b.temp(expr(n.expression()));
			var name = n.name().text;
			return {
				read: () -> reps.fieldGet(b, field, obj, name, where()),
				write: (e) -> reps.fieldSet(b, field, obj, name, e, where())
			};
		}
		if (n.kind == KindPropertyAccessExpression || n.kind == KindElementAccessExpression) {
			var obj = expr(n.expression());
			var key = n.kind == KindPropertyAccessExpression ? EStr(n.name().text) : expr(n.argumentExpression());
			return {
				read: () -> b.runtime("libGet", [any(obj), any(key)]),
				write: (e) -> {
					b.runtime("libPut", [any(obj), any(key), any(e)]);
				}
			};
		}
		return fail(n, "unsupported assignment target");
	}

	function thisValue():Ex return env.exists("this") ? read(env.get("this")) : b.runtime("getUndefined", []);

	function strictEquals(a:Ex, z:Ex):Ex return equals(a, z, true);

	function equals(a:Ex, z:Ex, strict:Bool):Ex {
		var direct:Ex = null;
		if (Ir.typeOf(a) == TF64 && Ir.typeOf(z) == TF64) direct = EBin(FEq, a, z);
		if (Ir.typeOf(a) == TBool && Ir.typeOf(z) == TBool) direct = EBin(Eq, a, z);
		if (Ir.typeOf(a).match(TRef(RStr)) && Ir.typeOf(z).match(TRef(RStr))) direct = b.runtime("stringEq", [a, z]);
		if (direct != null) {
			typedOperations++;
			return direct;
		}
		dynamicOperations++;
		return b.runtime(strict ? "strictEq" : "looseEq", [any(a), any(z)]);
	}

	function binary(n:Node):Ex {
		var x = n;
		var op = x.operatorToken().kind;
		if (op == KindCommaToken) {
			expr(x.left());
			return expr(x.right());
		}
		if (op >= KindFirstAssignment && op <= KindLastAssignment) return assign(n);
		if (op == KindInKeyword && x.left().kind == KindPrivateIdentifier) return b.runtime("libPrivateHas", [any(expr(x.right())), EStr(brand(x.left()))]);
		var a = expr(x.left());
		if (op == KindAmpersandAmpersandToken || op == KindBarBarToken || op == KindQuestionQuestionToken) {
			var l = b.local("shortCircuit", TRef(RAny));
			b.out.push(SSet(l, b.coerce(a, l.ty)));
			var cond = truth(a);
			if (op == KindBarBarToken) cond = ENot(cond);
			if (op == KindQuestionQuestionToken) cond = b.runtime("looseEq", [any(a), ENull(TRef(RAny))]);
			var rhs = b.block(() -> b.out.push(SSet(l, b.coerce(expr(x.right()), l.ty))));
			b.out.push(SIf(cond, rhs, new Vector(0)));
			return ELocal(l);
		}
		if (op == KindInstanceOfKeyword) return b.runtime("libInstanceOf", [any(a), any(expr(x.right()))]);
		return operate(op, a, expr(x.right()), n);
	}
	static var compound:Map<Kind, Kind> = [KindPlusEqualsToken => KindPlusToken, KindMinusEqualsToken => KindMinusToken, KindAsteriskEqualsToken => KindAsteriskToken,
		KindAsteriskAsteriskEqualsToken => KindAsteriskAsteriskToken, KindSlashEqualsToken => KindSlashToken, KindPercentEqualsToken => KindPercentToken,
		KindLessThanLessThanEqualsToken => KindLessThanLessThanToken, KindGreaterThanGreaterThanEqualsToken => KindGreaterThanGreaterThanToken,
		KindGreaterThanGreaterThanGreaterThanEqualsToken => KindGreaterThanGreaterThanGreaterThanToken, KindAmpersandEqualsToken => KindAmpersandToken,
		KindBarEqualsToken => KindBarToken, KindCaretEqualsToken => KindCaretToken];
	function assign(n:Node):Ex {
		var x = n;
		var op = x.operatorToken().kind;
		var left = x.left();
		while (left.kind == KindParenthesizedExpression) left = left.expression();
		if (op == KindEqualsToken && (left.kind == KindArrayLiteralExpression || left.kind == KindObjectLiteralExpression)) {
			var e = b.temp(any(expr(x.right())));
			assignPattern(left, e);
			return e;
		}
		var target = lvalue(x.left());
		if (op == KindEqualsToken) {
			var e = named(x.right(), left.kind == KindIdentifier ? left.text : null);
			target.write(e);
			return e;
		}
		if (op == KindBarBarEqualsToken || op == KindAmpersandAmpersandEqualsToken || op == KindQuestionQuestionEqualsToken) {
			// (the right side is evaluated and stored only when it is needed)
			var previous = target.read();
			var l = b.local("logical", TRef(RAny));
			b.out.push(SSet(l, any(previous)));
			var cond = op == KindQuestionQuestionEqualsToken ? b.runtime("looseEq", [any(previous), ENull(TRef(RAny))]) : op == KindBarBarEqualsToken ? ENot(truth(previous)) : truth(previous);
			b.out.push(SIf(cond, b.block(() -> {
				var e = expr(x.right());
				target.write(e);
				b.out.push(SSet(l, any(e)));}), new Vector(0)));
			return ELocal(l);
		}
		var previous = target.read();
		var e = operate(compound.get(op), previous, expr(x.right()), n);
		target.write(e);
		return e;
	}

	function operate(op:Kind, a:Ex, z:Ex, n:Node):Ex {
		if (op == KindInKeyword) return b.runtime("libHas", [any(z), any(a)]);
		if (op == KindEqualsEqualsEqualsToken || op == KindExclamationEqualsEqualsToken || op == KindEqualsEqualsToken || op == KindExclamationEqualsToken) {
			var e = equals(a, z, op == KindEqualsEqualsEqualsToken || op == KindExclamationEqualsEqualsToken);
			return op == KindExclamationEqualsEqualsToken || op == KindExclamationEqualsToken ? ENot(e) : e;
		}
		if (op == KindPlusToken && (Ir.typeOf(a).match(TRef(RStr)) || Ir.typeOf(z).match(TRef(RStr)))) return b.runtime("concat", [text(a), text(z)]);
		if (op == KindPlusToken && (Ir.typeOf(a).match(TRef(RAny)) || Ir.typeOf(z).match(TRef(RAny)))) return b.runtime("add", [any(a), any(z)]);
		var relation = op == KindLessThanToken || op == KindLessThanEqualsToken || op == KindGreaterThanToken || op == KindGreaterThanEqualsToken;
		if (relation && !(Ir.typeOf(a) == TF64 && Ir.typeOf(z) == TF64)) {
			dynamicOperations++;
			return b.runtime("libRelation", [any(a), any(z), EStr(op == KindLessThanToken ? "<" : op == KindLessThanEqualsToken ? "<=" : op == KindGreaterThanToken ? ">" : ">=")]);
		}
		if (op == KindAmpersandToken || op == KindBarToken || op == KindCaretToken || op == KindLessThanLessThanToken || op == KindGreaterThanGreaterThanToken || op == KindGreaterThanGreaterThanGreaterThanToken) {
			var left = b.runtime("libInt", [any(a)]), right = b.runtime("libInt", [any(z)]);
			var value = EBin(op == KindAmpersandToken ? And : op == KindBarToken ? Or : op == KindCaretToken ? Xor : op == KindLessThanLessThanToken ? Shl : op == KindGreaterThanGreaterThanToken ? Shr : UShr, left, right);
			return op == KindGreaterThanGreaterThanGreaterThanToken ? b.runtime("libUnsigned", [b.temp(value)]) : EConv(I2F, value);
		}
		typedOperations++;
		if (op == KindPercentToken) return remainder(a, z);
		if (op == KindAsteriskAsteriskToken) return b.runtime("power", [b.coerce(a, TF64), b.coerce(z, TF64)]);
		var bin:BinOp = switch (op) {
			case KindPlusToken: FAdd;
			case KindMinusToken: FSub;
			case KindAsteriskToken: FMul;
			case KindSlashToken: FDiv;
			case KindPercentToken: FMod;
			case KindLessThanToken: FLt;
			case KindLessThanEqualsToken: FLe;
			case KindGreaterThanToken: FGt;
			case KindGreaterThanEqualsToken: FGe;
			case _: return fail(n, "unsupported binary operator " + op.toString());
		};
		return EBin(bin, b.coerce(a, TF64), b.coerce(z, TF64));
	}

	// `x % c` for a literal integer divisor. Integral dividends below 2^31 in
	// magnitude take a multiply-and-shift quotient (Granlund-Montgomery, as
	// optimizing JS engines do; exact over that range) instead of a hardware
	// division; others take exact binary long division. Both are inline: a call
	// in a loop makes hxmc keep the loop's variables in memory. Variable
	// divisors go through the runtime's JS-exact helper.
	function remainder(a:Ex, z:Ex):Ex {
		var x = b.temp(b.coerce(a, TF64));
		var c = switch (z) {
			case EF64(v) if (v >= 1 && v <= 2147483647 && Math.ffloor(v) == v): Std.int(v);
			case _: return b.runtime("modulo", [x, b.coerce(z, TF64)]);
		};
		var shift = 31;
		while (Math.pow(2, shift - 31) < c) shift++;
		var m = Math.ffloor(Math.pow(2, shift) / c) + 1;
		function long(v:Float):Ex {
			var high = Std.int(Math.ffloor(v / 4294967296.0)), low = Std.int(v - high * 4294967296.0);
			return EBin(LOr, EBin(LShl, EConv(I2L, EInt(high)), EInt(32)), EBin(LAnd, EConv(I2L, EInt(low)), EBin(LUShr, EConv(I2L, EInt(-1)), EInt(32))));
		}
		function set(l:Local, e:Ex) b.out.push(SSet(l, e));
		function when(cond:Ex, then:() -> Void, ?otherwise:() -> Void) b.out.push(SIf(cond, b.block(then), otherwise == null ? new Vector(0) : b.block(otherwise)));
		function loopWhile(cond:() -> Ex, body:() -> Void) b.out.push(SLoop(b.block(() -> {
			when(ENot(cond()), () -> b.out.push(SBreak));
			body();})));
		var l = b.local("remainder", TF64), magnitude = b.local("magnitude", TF64), r = b.local("rest", TF64), done = b.local("integral", TBool);
		set(done, ECast(TBool, EInt(0)));
		when(EBin(FLt, x, EF64(0)), () -> set(magnitude, EConv(FNeg, x)), () -> set(magnitude, x));
		when(EBin(FLt, ELocal(magnitude), EF64(2147483648.0)), () -> {
			var xi = b.temp(EConv(F2L, ELocal(magnitude)));
			when(EBin(FEq, EConv(L2F, xi), ELocal(magnitude)), () -> {
				var q = b.temp(EBin(LShr, EBin(LMul, xi, long(m)), EInt(shift)));
				set(r, EConv(L2F, EBin(LSub, xi, EBin(LMul, q, EConv(I2L, EInt(c))))));
				set(done, ECast(TBool, EInt(1)));
			});
		});
		when(ENot(ELocal(done)), () -> {
			// (x-x is 0 exactly when x is finite)
			when(ENot(EBin(FEq, EBin(FSub, x, x), EF64(0))), () -> set(r, EF64(Math.NaN)), () -> {
				set(r, ELocal(magnitude));
				var t = b.local("step", TF64);
				set(t, EF64(c));
				loopWhile(() -> EBin(FLe, ELocal(t), EBin(FMul, ELocal(r), EF64(0.5))), () -> set(t, EBin(FMul, ELocal(t), EF64(2))));
				loopWhile(() -> EBin(FGe, ELocal(t), EF64(c)), () -> {
					when(EBin(FGe, ELocal(r), ELocal(t)), () -> set(r, EBin(FSub, ELocal(r), ELocal(t))));
					set(t, EBin(FMul, ELocal(t), EF64(0.5)));
				});
			});
		});
		// (the sign of the dividend, -0 included)
		when(EBin(FEq, ELocal(r), EF64(0)), () -> set(l, EBin(FMul, EF64(0), x)), () -> when(EBin(FLt, x, EF64(0)), () -> set(l, EConv(FNeg, ELocal(r))), () -> set(l, ELocal(r))));
		return ELocal(l);
	}

	// A direct function as a function object: (this, args...) ignoring `this`.
	function functionValue(target:FuncInfo, name:String):Ex {
		var saved = here;
		here = nodes.get(name);
		var arity = target.args.length;
		// (called dynamically: the arguments into the target's typed parameters, checked)
		var sig = p.sig([TRef(RAny)].concat([for (a in target.args) TRef(RAny)]), TRef(RAny));
		var f = Builder.func(p, "functionValue" + serial++, TRef(RAny));
		f.args = [new Local(0, "closure", TRef(RAny)), new Local(1, "this", TRef(RAny))];
		for (i in 0...target.args.length) f.args.push(new Local(i + 2, target.args[i].name, TRef(RAny)));
		var li = new LambdaInfo(p.lambdas.length, sig, new Vector(0), f);
		p.lambdas.push(li);
		f.lambda = li;
		var old = b;
		b = new Builder(p, f);
		var call = ECall(target, Vector.fromArrayCopy([for (i in 0...target.args.length) store(ELocal(f.args[i + 2]), target.args[i].ty)]));
		if (target.ret == TVoid) {
			b.out.push(SExpr(call));
			b.out.push(SReturn(b.runtime("getUndefined", [])));
		}
		else b.out.push(SReturn(any(b.temp(call))));
		b.finish();
		b = old;
		here = saved;
		return b.runtime("libFunction", [any(b.temp(ENewClos(li, new Vector(0)))), EInt(arity), bool(restFunctions.exists(target)), EInt(PLAIN), EStr(name)]);
	}

	function bool(v:Bool):Ex return ECast(TBool, EInt(v ? 1 : 0));

	// A compiled closure: (closure, this, hidden..., parameters...). Every
	// binding with a cell in the enclosing scope is captured; `this` is bound
	// from the argument unless it is lexical (arrows). build compiles the body.
	function lambda(n:Null<Node>, hidden:Array<String>, lexicalThis:Bool, restArguments:Bool, build:FuncInfo->Void):{clos:Ex, arity:Int, rest:Bool} {
		var old = b;
		var outer = env;
		var oldVars = functionVars;
		functionVars = [];
		var f = n != null ? declareFunction(n, "lambda" + serial++, false) : Builder.func(p, "lambda" + serial++, TRef(RAny));
		if (restArguments) {
			f.args.push(new Local(f.args.length, "%arguments", TRef(RAny)));
			restFunctions.set(f, true);
		}
		var arity = f.args.length;
		var rest = restFunctions.exists(f);
		var front = [new Local(0, "closure", TRef(RAny)), new Local(1, "this", TRef(RAny))];
		for (i in 0...hidden.length) front.push(new Local(2 + i, hidden[i], TRef(RAny)));
		for (a in f.args) a.id += front.length;
		f.args = front.concat(f.args);
		var sig = p.sig([for (a in f.args.slice(1)) a.ty], f.ret);
		var names = [for (name in outer.keys()) if (outer.get(name).cell != null) name];
		names.sort(Reflect.compare);
		var captures = [for (name in names) switch (outer.get(name).cell) {
			case ELocal(l): l;
			case _: throw "capture must be a local";
		}];
		for (cell in captures) capturedCells.set(cell, true);
		var li = new LambdaInfo(p.lambdas.length, sig, Vector.fromArrayCopy(captures), f);
		p.lambdas.push(li);
		f.lambda = li;
		b = new Builder(p, f);
		env = [];
		for (name in outer.keys()) if (outer.get(name).global != null) env.set(name, outer.get(name));
		for (name in outer.keys()) if (outer.get(name).local != null || outer.get(name).outer != null) env.set(name, {ty: outer.get(name).ty, outer: name});
		for (i in 0...names.length) {
			var v = b.temp(ECapture(li, i, ELocal(f.args[0])));
			env.set(names[i], {ty: outer.get(names[i]).ty, cell: v});
		}
		// (parameters into their typed slots, checked at the function)
		var saved = here;
		if (n != null) here = n;
		var params = argumentFunctions.exists(f) ? new Map<String, Node>() : parameterNames(n);
		for (a in f.args.slice(1)) {
			if (a.name == "this" && lexicalThis) continue;
			var name = params.get(a.name);
			var t = name == null ? a.ty : parameterType(name.parent);
			env.set(a.name, bind(name, t, store(ELocal(a), t)));
		}
		build(f);
		b.finish();
		b = old;
		here = saved;
		env = outer;
		functionVars = oldVars;
		return {clos: any(b.temp(ENewClos(li, Vector.fromArrayCopy([for (c in captures) ELocal(c)])))), arity: arity, rest: rest};
	}

	// A function, arrow, method or accessor as a function object.
	function closure(n:Node, ?name:String):Ex {
		var arrow = n.kind == KindArrowFunction;
		var plain = n.kind == KindFunctionExpression || n.kind == KindFunctionDeclaration;
		if (n.asteriskToken() != null || hasModifier(n, KindAsyncKeyword)) return resumableClosure(n, name);
		var own = plain && n.name() != null ? n.name().text : null;
		// (a named function expression sees itself under its name)
		var self:Binding = null;
		var outer = env;
		if (own != null && n.kind == KindFunctionExpression) {
			env = env.copy();
			var cell = b.temp(ENewBox(TRef(RAny), b.runtime("getUndefined", [])));
			self = {ty: TRef(RAny), cell: cell};
			env.set(own, self);
		}
		var r = lambda(n, [], arrow, false, f -> {
			hoist(n.body(), false);
			parameterSetup(n);
			if (n.body().kind == KindBlock) statement(n.body()); else b.out.push(SReturn(b.coerce(expr(n.body()), f.ret)));
			if (f.ret == TVoid) b.out.push(SReturn(null)); else b.out.push(SReturn(b.coerce(b.runtime("getUndefined", []), f.ret)));
		});
		env = outer;
		var value = b.runtime("libFunction", [r.clos, EInt(r.arity), bool(r.rest), EInt(plain ? PLAIN : METHOD), EStr(own != null ? own : name == null ? "" : name)]);
		if (self != null) set(self, value);
		return value;
	}

	// Generators and async functions. The function, when called, binds its
	// parameters and returns a generator (or, async, a promise driving one)
	// whose step closure runs the body. A suspension saves every IR local of
	// the step function in the generator's frame and returns; the next step
	// restores them, and resume guards (see resumeGuards) skip the code before
	// the suspension point.
	function resumableClosure(n:Node, ?name:String):Ex {
		var async = hasModifier(n, KindAsyncKeyword);
		var generator = n.asteriskToken() != null;
		var arrow = n.kind == KindArrowFunction;
		var own = (n.kind == KindFunctionExpression || n.kind == KindFunctionDeclaration) && n.name() != null ? n.name().text : null;
		var self:Binding = null;
		var outer = env;
		if (own != null && n.kind == KindFunctionExpression) {
			env = env.copy();
			var cell = b.temp(ENewBox(TRef(RAny), b.runtime("getUndefined", [])));
			self = {ty: TRef(RAny), cell: cell};
			env.set(own, self);
		}
		sharing = true;
		var r = lambda(n, [], arrow, false, f -> {
			parameterSetup(n);
			sharing = false;
			var step = lambda(null, ["%generator", "%sent", "%mode"], true, false, g -> {
				b.resumable = {count: 0, value: b.local("yielded", TRef(RAny)), gen: g.args[2], sent: g.args[3], mode: g.args[4], async: async, generator: generator, kinds: []};
				var start = b.out.length;
				hoist(n.body(), false);
				if (n.body().kind == KindBlock) statement(n.body()); else emitReturn(expr(n.body()));
				b.out.push(SReturn(b.runtime("getUndefined", [])));
				var body = b.out.slice(start);
				b.out = b.out.slice(0, start);
				resumeGuards(body);
			});
			var stepFn = b.runtime("libFunction", [step.clos, EInt(3), bool(false), EInt(METHOD), EStr("")]);
			b.out.push(SReturn(b.runtime(async && generator ? "libAsyncGenerator" : async ? "libAsync" : "libGenerator", [stepFn])));
		});
		env = outer;
		var value = b.runtime("libFunction", [r.clos, EInt(r.arity), bool(r.rest), EInt(METHOD), EStr(own != null ? own : name == null ? "" : name)]);
		if (self != null) set(self, value);
		return value;
	}
	// A suspension point handing out value; returns the value sent back in.
	// With modes, a throw() or return() resumption throws or returns here.
	static inline var YIELD = 0;
	static inline var AWAIT = 1;
	function yieldPoint(value:Ex, modes:Bool, kind = YIELD):Ex {
		var r = b.resumable;
		var id = ++r.count;
		r.kinds.set(id, kind);
		b.out.push(SSet(r.value, any(value)));
		b.out.push(SPos("%yield", id));
		if (modes) {
			var mode = b.coerce(ELocal(r.mode), TF64);
			b.out.push(SIf(EBin(FEq, mode, EF64(1)), Vector.fromArrayCopy([SThrow(ELocal(r.sent))]), new Vector(0)));
			b.out.push(SIf(EBin(FEq, mode, EF64(2)), b.block(() -> emitReturn(ELocal(r.sent))), new Vector(0)));
		}
		return b.temp(ELocal(r.sent));
	}

	// yield*: next/throw/return pass through to the inner iterator.
	function delegate(iterable:Ex):Ex {
		var r = b.resumable;
		var it = b.temp(b.runtime("libIterator", [iterable]));
		var received = b.local("received", TRef(RAny)), mode = b.local("delegateMode", TRef(RAny)), result = b.local("delegated", TRef(RAny));
		b.out.push(SSet(received, b.runtime("getUndefined", [])));
		b.out.push(SSet(mode, any(EF64(0))));
		irLoop(() -> {
			var res = b.runtime("libDelegate", [it, ELocal(received), ELocal(mode)]);
			var done = truth(b.runtime("libGet", [res, EStr("done")]));
			b.out.push(SIf(done, b.block(() -> {
				var v = b.runtime("libGet", [res, EStr("value")]);
				b.out.push(SIf(EBin(FEq, b.coerce(ELocal(mode), TF64), EF64(2)), b.block(() -> emitReturn(v)), new Vector(0)));
				b.out.push(SSet(result, v));
				b.out.push(SBreak);
			}), new Vector(0)));
			var sent = yieldPoint(b.runtime("libGet", [res, EStr("value")]), false);
			b.out.push(SSet(received, sent));
			b.out.push(SSet(mode, ELocal(r.mode)));
		});
		return ELocal(result);
	}

	// Resume guards: with `resume` nonzero (the suspension point to return
	// to), statements are skipped unless they contain that point; branches,
	// catch handlers and loops are re-entered towards it, and the point itself
	// clears `resume`. With `resume` zero everything runs normally.
	function resumeGuards(body:Array<Stmt>) {
		var r = b.resumable;
		var resume = b.local("resume", TI32), go = b.local("go", TBool);
		function range(s:Stmt):Null<{lo:Int, hi:Int}> {
			var lo = 0x7fffffff, hi = -1;
			function visit(s:Stmt) switch (s) {
				case SPos("%yield", id):
					if (id < lo) lo = id;
					if (id > hi) hi = id;
				case SIf(_, a, z):
					for (x in a) visit(x);
					for (x in z) visit(x);
				case SLoop(a): for (x in a) visit(x);
				case STry(a, cs):
					for (x in a) visit(x);
					for (c in cs) for (x in c.body) visit(x);
				case _:
			}
			visit(s);
			return hi < 0 ? null : {lo: lo, hi: hi};
		}
		var resumeIs0 = EBin(Eq, ELocal(resume), EInt(0));
		function within(r:{lo:Int, hi:Int}):Array<Stmt> return [
			SSet(go, ECast(TBool, EInt(0))),
			SIf(EBin(Le, EInt(r.lo), ELocal(resume)), Vector.fromArrayCopy([SIf(EBin(Le, ELocal(resume), EInt(r.hi)), Vector.fromArrayCopy([SSet(go, ECast(TBool, EInt(1)))]), new Vector(0))]), new Vector(0))
		];
		var locals:Array<Local> = [];
		var save:Array<Stmt> = null;
		function process(list:Array<Stmt>):Array<Stmt> {
			var out:Array<Stmt> = [];
			var plain:Array<Stmt> = [];
			function flush() {
				if (plain.length > 0) {
					out.push(SIf(resumeIs0, Vector.fromArrayCopy(plain), new Vector(0)));
					plain = [];
				}
			}
			for (s in list) {
				var rg = range(s);
				if (rg == null) {
					plain.push(s);
					continue;
				}
				flush();
				switch (s) {
					case SPos(_, id):
						out.push(SIf(resumeIs0, Vector.fromArrayCopy(save.concat([SExpr(b.runtimeCall("libSuspend", [ELocal(r.gen), EInt(id), EInt(r.kinds.get(id))])), SReturn(ELocal(r.value))])),
							Vector.fromArrayCopy([SIf(EBin(Eq, ELocal(resume), EInt(id)), Vector.fromArrayCopy([SSet(resume, EInt(0))]), new Vector(0))])));
					case SIf(c, a, z):
						var ra = range(SIf(c, a, new Vector(0)));
						// (re-entering: the branch holding the suspension point, without the condition)
						out.push(SIf(resumeIs0, Vector.fromArrayCopy([SSet(go, c)]), Vector.fromArrayCopy(ra == null ? [SSet(go, ECast(TBool, EInt(0)))] : within(ra))));
						out.push(SIf(ELocal(go), Vector.fromArrayCopy(process(a.toArray())), Vector.fromArrayCopy(process(z.toArray()))));
					case SLoop(a):
						for (x in within(rg)) out.push(x);
						out.push(SIf(resumeIs0, Vector.fromArrayCopy([SSet(go, ECast(TBool, EInt(1)))]), new Vector(0)));
						out.push(SIf(ELocal(go), Vector.fromArrayCopy([SLoop(Vector.fromArrayCopy(process(a.toArray())))]), new Vector(0)));
					case STry(a, cs):
						var tryBody = STry(Vector.fromArrayCopy(process(a.toArray())), Vector.fromArrayCopy([for (c in cs) {test: c.test, l: c.l, body: Vector.fromArrayCopy(process(c.body.toArray()))}]));
						var handler:Stmt = tryBody;
						// (resuming inside a catch handler re-enters it without an exception)
						for (c in cs) {
							var rc = range(SLoop(c.body));
							if (rc != null) {
								var enter = within(rc);
								handler = SIf(ECast(TBool, EInt(1)), Vector.fromArrayCopy(enter.concat([SIf(ELocal(go), Vector.fromArrayCopy(process(c.body.toArray())), Vector.fromArrayCopy([handler]))])), new Vector(0));
							}
						}
						out.push(handler);
					case _: throw "unexpected suspension point";
				}
			}
			flush();
			return out;
		}
		// (every local but the guard's own is saved and restored)
		for (l in b.f.locals) if (l != resume && l != go) locals.push(l);
		save = b.block(() -> b.runtime("libSave", [ELocal(r.gen), pack([for (l in locals) ELocal(l)])])).toArray();
		var processed = process(body);
		b.out.push(SSet(resume, b.runtime("libResumePoint", [ELocal(r.gen)])));
		var restore = b.block(() -> for (i in 0...locals.length) b.out.push(SSet(locals[i], b.coerce(b.runtime("libRestore", [ELocal(r.gen), EInt(i)]), locals[i].ty))));
		b.out.push(SIf(EBin(Ne, ELocal(resume), EInt(0)), restore, new Vector(0)));
		for (s in processed) b.out.push(s);
		b.out.push(SReturn(b.runtime("getUndefined", [])));
	}

	function brand(name:Node):String {
		var i = privateScopes.length - 1;
		while (i >= 0) {
			var scope = privateScopes[i--];
			if (scope.exists(name.text)) return scope.get(name.text);
		}
		return fail(name, "unknown private name " + name.text);
	}

	// A property key as an expression: names and literals are strings, computed keys are evaluated.
	function memberKey(name:Node):Ex return switch (name.kind) {
		case KindComputedPropertyName: b.temp(any(expr(name.expression())));
		case KindNumericLiteral: b.temp(b.runtime("text", [any(EF64(Std.parseFloat(name.text)))]));
		case _: EStr(name.text);
	};

	static function staticName(name:Node):Null<String> return name.kind == KindIdentifier || name.kind == KindStringLiteral || name.kind == KindPrivateIdentifier ? name.text : name.kind == KindNumericLiteral ? Std.string(Std.parseFloat(name.text)) : null;

	// Object literals: plain ones in one call; others property by property
	// (methods and accessors see the object as their home for super).
	function objectLiteral(n:Node):Ex {
		var props = properties(n);
		var plain = true;
		for (prop in props) if (!(prop.kind == KindPropertyAssignment && prop.name().kind != KindComputedPropertyName && prop.name().text != "__proto__" || prop.kind == KindShorthandPropertyAssignment)) plain = false;
		if (plain) {
			var ks:Array<Ex> = [], vs:Array<Ex> = [];
			for (prop in props) {
				ks.push(EStr(prop.kind == KindPropertyAssignment ? staticName(prop.name()) : prop.name().text));
				vs.push(prop.kind == KindPropertyAssignment ? named(prop.initializer(), staticName(prop.name())) : expr(prop.name()));
			}
			return b.runtime("libObject", [pack(ks), pack(vs)]);
		}
		var o = b.temp(b.runtime("libObject", [pack([]), pack([])]));
		var outer = env;
		env = env.copy();
		env.set("%home", {ty: TRef(RAny), cell: b.temp(ENewBox(TRef(RAny), o))});
		for (prop in props) switch (prop.kind) {
			case KindSpreadAssignment: b.runtime("libAssignSpread", [o, any(expr(prop.expression()))]);
			case KindShorthandPropertyAssignment: b.runtime("libDefineField", [o, EStr(prop.name().text), any(expr(prop.name()))]);
			case KindPropertyAssignment if (prop.name().kind != KindComputedPropertyName && prop.name().text == "__proto__"):
				b.runtime("libSetProto", [o, any(expr(prop.initializer()))]);
			case KindPropertyAssignment:
				var key = memberKey(prop.name());
				b.runtime("libDefineField", [o, any(key), any(named(prop.initializer(), staticName(prop.name())))]);
			case KindMethodDeclaration | KindGetAccessor | KindSetAccessor:
				var key = memberKey(prop.name());
				var fn = closure(prop, staticName(prop.name()));
				b.runtime("libDefineMethod", [o, any(key), fn, EInt(prop.kind == KindGetAccessor ? 1 : prop.kind == KindSetAccessor ? 2 : 0), bool(true)]);
			case _: fail(prop, "unsupported object member " + prop.kind.toString());
		}
		env = outer;
		return o;
	}

	// Classes. The constructor and the instance field initializer are closures
	// created before the class object; members are defined on the prototype or
	// the class in order, then static fields and blocks run with `this` as the
	// class. Private names get a brand per class evaluation site.
	function classValue(n:Node, ?name:String):Ex {
		var own = n.name() != null ? n.name().text : name == null ? "" : name;
		var heritage:Node = null;
		var clauses = n.heritageClauses();
		if (clauses != null) for (h in clauses) if (h.token() == KindExtendsKeyword) heritage = h.types()[0].expression();
		var parent = heritage == null ? b.runtime("libHole", []) : any(expr(heritage));
		var outer = env;
		env = env.copy();
		var classCell = b.temp(ENewBox(TRef(RAny), b.runtime("getUndefined", [])));
		var classBinding = {ty: TRef(RAny), cell: classCell};
		var protoCell = b.temp(ENewBox(TRef(RAny), b.runtime("getUndefined", [])));
		var protoBinding = {ty: TRef(RAny), cell: protoCell};
		if (n.name() != null) env.set(own, classBinding);
		env.set("%class", classBinding);
		var serialNumber = classSerial++;
		var scope:Map<String, String> = [];
		for (m in members(n)) if (m.name() != null && m.name().kind == KindPrivateIdentifier) scope.set(m.name().text, m.name().text + "@" + serialNumber);
		privateScopes.push(scope);
		var instanceFields = [for (m in members(n)) if (m.kind == KindPropertyDeclaration && !hasModifier(m, KindStaticKeyword) && !hasModifier(m, KindDeclareKeyword) && !hasModifier(m, KindAbstractKeyword)) m];
		var privateMethods = [for (m in members(n)) if ((m.kind == KindMethodDeclaration || m.kind == KindGetAccessor || m.kind == KindSetAccessor) && m.name().kind == KindPrivateIdentifier && m.body() != null) m];
		// (cells for computed field keys and private methods, filled in member order)
		// (named in the environment, so the field initializer captures them)
		var keyCells:Map<Node, String> = [];
		for (m in instanceFields.concat(privateMethods)) if (m.name().kind == KindComputedPropertyName || privateMethods.indexOf(m) >= 0 && !hasModifier(m, KindStaticKeyword)) {
			var cellName = "%member" + (serial++);
			keyCells.set(m, cellName);
			env.set(cellName, {ty: TRef(RAny), cell: b.temp(ENewBox(TRef(RAny), b.runtime("getUndefined", [])))});
		}
		var ctorNode:Node = null;
		for (m in members(n)) if (m.kind == KindConstructor && m.body() != null) ctorNode = m;
		var derived = heritage != null;
		env.set("%home", protoBinding);
		var ctor = lambda(ctorNode, ["%newTarget"], false, ctorNode == null && derived, f -> {
			b.constructorThis = env.get("this");
			var props:Array<String> = [];
			if (ctorNode != null) for (param in parametersOf(ctorNode)) if (param.name().kind == KindIdentifier && (hasModifier(param, KindPublicKeyword) || hasModifier(param, KindPrivateKeyword) || hasModifier(param, KindProtectedKeyword) || hasModifier(param, KindReadonlyKeyword) || hasModifier(param, KindOverrideKeyword))) props.push(param.name().text);
			b.parameterProperties = props;
			if (ctorNode != null) {
				hoist(ctorNode.body(), false);
				parameterSetup(ctorNode);
			}
			if (!derived) parameterProperties();
			if (ctorNode != null) statement(ctorNode.body());
			else if (derived) {
				var t = b.runtime("libSuperConstruct", [read(env.get("%class")), b.runtime("libList", [read(env.get("%arguments"))]), read(env.get("%newTarget"))]);
				set(env.get("this"), t);
			}
			b.out.push(SReturn(read(env.get("this"))));
		});
		var fields:Ex = ENull(TRef(RAny));
		if (instanceFields.length > 0 || privateMethods.filter(m -> !hasModifier(m, KindStaticKeyword)).length > 0) {
			fields = lambda(null, [], false, false, f -> {
				var self = read(env.get("this"));
				for (m in privateMethods) if (!hasModifier(m, KindStaticKeyword))
					b.runtime("libPrivateDefine", [self, EStr(brand(m.name())), read(env.get(keyCells.get(m))), EInt(m.kind == KindGetAccessor ? 1 : m.kind == KindSetAccessor ? 2 : 3)]);
				for (m in instanceFields) {
					var value = m.initializer() == null ? b.runtime("getUndefined", []) : named(m.initializer(), staticName(m.name()));
					if (m.name().kind == KindPrivateIdentifier) b.runtime("libPrivateDefine", [self, EStr(brand(m.name())), any(value), EInt(0)]);
					else b.runtime("libDefineField", [self, keyCells.exists(m) ? read(env.get(keyCells.get(m))) : memberKey(m.name()), any(value)]);
				}
				b.out.push(SReturn(b.runtime("getUndefined", [])));
			}).clos;
		}
		var c = b.temp(b.runtime("libClass", [EStr(own), parent, ctor.clos, EInt(ctor.arity), bool(ctor.rest), fields]));
		var layout = classes.declared(n);
		if (layout != null) reps.linkClass(b, layout, c);
		set(classBinding, c);
		set(protoBinding, b.runtime("libGet", [c, EStr("prototype")]));
		var statics:Array<Node> = [];
		for (m in members(n)) {
			var isStatic = hasModifier(m, KindStaticKeyword);
			switch (m.kind) {
				case KindMethodDeclaration | KindGetAccessor | KindSetAccessor if (m.body() != null):
					env.set("%home", isStatic ? classBinding : protoBinding);
					var kind = m.kind == KindGetAccessor ? 1 : m.kind == KindSetAccessor ? 2 : 0;
					var fnName = m.name().kind == KindPrivateIdentifier ? m.name().text : staticName(m.name());
					if (m.name().kind == KindPrivateIdentifier) {
						var fn = closure(m, fnName);
						if (isStatic) b.runtime("libPrivateDefine", [c, EStr(brand(m.name())), fn, EInt(kind == 0 ? 3 : kind)]);
						else set(env.get(keyCells.get(m)), fn);
					}
					else {
						var key = memberKey(m.name());
						var fn = closure(m, fnName);
						b.runtime("libDefineMethod", [isStatic ? c : read(protoBinding), any(key), fn, EInt(kind), bool(false)]);
					}
				case KindPropertyDeclaration if (isStatic): statics.push(m);
				case KindPropertyDeclaration: if (keyCells.exists(m)) set(env.get(keyCells.get(m)), memberKey(m.name()));
				case KindClassStaticBlockDeclaration: statics.push(m);
				case KindConstructor | KindMethodDeclaration | KindGetAccessor | KindSetAccessor | KindSemicolonClassElement | KindIndexSignature:
				case _: fail(m, "unsupported class member " + m.kind.toString());
			}
		}
		// (static fields and blocks: `this` is the class)
		env.set("%home", classBinding);
		for (m in statics) {
			var saved = env.get("this");
			env.set("this", classBinding);
			if (m.kind == KindClassStaticBlockDeclaration) {
				var body = m.body();
				var block = lambda(null, [], false, false, f -> {
					hoist(body, false);
					statement(body);
					b.out.push(SReturn(b.runtime("getUndefined", [])));});
				b.runtime("libCall", [b.runtime("libFunction", [block.clos, EInt(0), bool(false), EInt(METHOD), EStr("")]), c, pack([])]);
			}
			else {
				var key = m.name().kind == KindPrivateIdentifier ? null : memberKey(m.name());
				var value = m.initializer() == null ? b.runtime("getUndefined", []) : named(m.initializer(), staticName(m.name()));
				if (key == null) b.runtime("libPrivateDefine", [c, EStr(brand(m.name())), any(value), EInt(0)]);
				else b.runtime("libDefineField", [c, any(key), any(value)]);
			}
			if (saved == null) env.remove("this"); else env.set("this", saved);
		}
		privateScopes.pop();
		env = outer;
		return c;
	}

	// ---- typed values (Reps)
	// (a property access that is neither optional nor through super)
	static function plainAccess(n:Node):Bool return n.flags & NodeFlags.OptionalChain == 0 && n.expression().kind != KindSuperKeyword;

	// `a[k]` with a an array and k a number
	function arrayElement(n:Node):Bool
		return n.kind == KindElementAccessExpression && plainAccess(n) && types.isArray(n.expression().tsType) && types.isNumber(n.argumentExpression().tsType);

	// `obj.name` with obj an instance of a class with a layout that declares the field
	function layoutField(n:Node):Null<ClassLayout> {
		if (n.kind != KindPropertyAccessExpression || n.name().kind == KindPrivateIdentifier || !plainAccess(n)) return null;
		var c = reps.layoutOf(n.expression().tsType);
		return c != null && c.declares(n.name().text) ? c : null;
	}

	// (the program assigns to Math)
	function assignsMath():Bool {
		for (sf in src.files) for (i in 1...sf.count) if (sf.kindAt(i) == KindIdentifier) {
			var id = sf.node(i);
			var parent = id.parent;
			if (id.text == "Math" && parent.kind == KindBinaryExpression && parent.left() == id && parent.operatorToken().kind >= KindFirstAssignment && parent.operatorToken().kind <= KindLastAssignment) return true;
		}
		return false;
	}

	// Math.f(...): the function itself (Math is frozen: Builtins)
	function mathCall(n:Node, callee:Node, actual:Array<Node>):Null<Ex> {
		if (!mathFixed || callee.kind != KindPropertyAccessExpression || callee.expression().kind != KindIdentifier || callee.expression().text != "Math" || env.exists("Math") || n.flags & NodeFlags.OptionalChain != 0 || hasSpread(actual)) return null;
		var name = callee.name().text;
		var unary = ["sqrt" => "mathSqrt", "abs" => "mathAbs", "floor" => "mathFloor", "ceil" => "mathCeil"];
		var others = ["trunc", "round", "sin", "cos", "tan", "asin", "acos", "atan", "exp", "log", "sign", "cbrt", "log2", "log10"];
		var binary = ["min" => "mathMin", "max" => "mathMax"];
		var arity = unary.exists(name) || others.contains(name) ? 1 : binary.exists(name) || name == "atan2" || name == "pow" ? 2 : 0;
		if (arity == 0 || actual.length != arity) return null;
		var args = [for (a in actual) b.temp(number(expr(a)))];
		typedOperations++;
		return if (unary.exists(name)) b.runtime(unary.get(name), args);
		else if (binary.exists(name)) b.runtime(binary.get(name), args);
		else if (arity == 1) b.runtime("mathUnary", [EStr(name), args[0]]);
		else b.runtime("mathBinary", [EStr(name), args[0], args[1]]);
	}

	// (constructor parameter properties: assigned after the fields, and after super() in derived classes)
	function parameterProperties() {
		if (b.parameterProperties == null) return;
		for (name in b.parameterProperties) b.runtime("libPut", [read(env.get("this")), EStr(name), any(read(get(name, null)))]);
	}

	function construct(n:Node):Ex {
		var callee = any(expr(n.expression()));
		return b.runtime("libConstruct", [callee, argumentList(n.arguments() == null ? [] : n.arguments()), callee]);
	}

	// Arguments to a known function: its parameters' types, missing ones
	// undefined, the rest (when it has a rest parameter) as an array.
	function positional(f:FuncInfo, values:Array<Ex>, skip:Int):Array<Ex> {
		var rest = restFunctions.exists(f);
		var fixed = f.args.length - skip - (rest ? 1 : 0);
		var out = [for (i in 0...fixed) store(i < values.length ? values[i] : b.runtime("getUndefined", []), f.args[i + skip].ty)];
		if (rest) out.push(b.runtime("libArray", [pack(values.slice(fixed))]));
		return out;
	}

	function hasSpread(nodes:Array<Node>):Bool {
		for (a in nodes) if (a.kind == KindSpreadElement) return true;
		return false;
	}

	// An argument (or array element) list as a runtime list, spreads expanded and holes kept.
	function spreadList(nodes:Array<Node>):Ex {
		var list = b.temp(ENewArr(TRef(RAny), new Vector(0)));
		for (e in nodes) switch (e.kind) {
			case KindSpreadElement: b.runtime("libAppendAll", [list, any(expr(e.expression()))]);
			case KindOmittedExpression: b.runtime("libAppend", [list, b.runtime("libHole", [])]);
			case _: b.runtime("libAppend", [list, any(expr(e))]);
		}
		return list;
	}

	function argumentList(nodes:Array<Node>):Ex return hasSpread(nodes) ? spreadList(nodes) : pack(actuals(nodes));

	// (in an optional chain, a nullish value at `?.` ends the whole chain with undefined)
	function chainCheck(n:Node, value:Ex) {
		if (n.questionDotToken() == null) return;
		if (b.depth != chainDepth) fail(n, "optional chain inside a nested loop");
		b.out.push(SIf(b.runtime("looseEq", [any(value), ENull(TRef(RAny))]), Vector.fromArrayCopy([SBreak]), new Vector(0)));
	}
	var chainDepth = -1;
	var chainTops:Map<Node, Bool> = [];
	function chainTop(n:Node):Bool {
		if (n.flags & NodeFlags.OptionalChain == 0 || chainTops.exists(n)) return false;
		var parent = n.parent;
		return parent == null || parent.flags & NodeFlags.OptionalChain == 0 || parent.expression() != n
			|| !(parent.kind == KindPropertyAccessExpression || parent.kind == KindElementAccessExpression || parent.kind == KindCallExpression || parent.kind == KindNonNullExpression);
	}

	function optionalChain(n:Node):Ex {
		var l = b.local("chain", TRef(RAny));
		b.out.push(SSet(l, b.runtime("getUndefined", [])));
		var saved = chainDepth;
		chainTops.set(n, true);
		irLoop(() -> {
			chainDepth = b.depth;
			b.out.push(SSet(l, any(expr(n))));
			b.out.push(SBreak);});
		chainTops.remove(n);
		chainDepth = saved;
		return ELocal(l);
	}

	function call(n:Node):Ex {
		var actual = n.arguments();
		if (actual == null) actual = [];
		var callee = n.expression();
		if (callee.kind == KindSuperKeyword) {
			var list = argumentList(actual);
			var t = b.runtime("libSuperConstruct", [read(get("%class", n)), list, read(get("%newTarget", n))]);
			set(get("this", n), t);
			parameterProperties();
			return t;
		}
		if (callee.kind == KindPropertyAccessExpression && callee.expression().kind == KindIdentifier && callee.expression().text == "console" && !env.exists("console") && callee.name().text == "log") {
			// (numbers print through the typed path; other lines through Node's formatting)
			var values = hasSpread(actual) ? null : actuals(actual);
			if (values != null && values.length > 0 && values.filter(v -> Ir.typeOf(v) != TF64).length == 0) {
				for (i in 0...values.length) {
					if (i > 0) b.runtime("print", [EStr(" ")]);
					b.runtime("print", [b.runtime("consoleNumber", [values[i]])]);
				}
			}
			else b.runtime("print", [b.runtime("consoleLine", [values == null ? spreadList(actual) : pack(values)])]);
			b.runtime("print", [EStr("\n")]);
			return b.runtime("getUndefined", []);
		}
		if (callee.kind == KindIdentifier && !env.exists(callee.text) && functions.exists(callee.text) && n.questionDotToken() == null) {
			var f = functions.get(callee.text);
			if (hasSpread(actual)) return apply(read(functionValues.get(callee.text)), spreadList(actual));
			typedOperations++;
			var args = positional(f, actuals(actual), 0);
			if (f.ret == TVoid) {
				b.out.push(SExpr(ECall(f, Vector.fromArrayCopy(args))));
				return b.runtime("getUndefined", []);
			}
			return b.temp(ECall(f, Vector.fromArrayCopy(args)));
		}
		var math = mathCall(n, callee, actual);
		if (math != null) return math;
		var inner = callee;
		while (inner.kind == KindParenthesizedExpression) inner = inner.expression();
		if ((inner.kind == KindPropertyAccessExpression || inner.kind == KindElementAccessExpression) && inner.expression().kind == KindSuperKeyword) {
			var key = inner.kind == KindPropertyAccessExpression ? EStr(inner.name().text) : any(expr(inner.argumentExpression()));
			return b.runtime("libSuperCall", [read(get("%home", n)), thisValue(), key, argumentList(actual)]);
		}
		if (inner.kind == KindPropertyAccessExpression || inner.kind == KindElementAccessExpression) {
			var obj = b.temp(any(expr(inner.expression())));
			chainCheck(inner, obj);
			var key:Ex = inner.kind == KindElementAccessExpression ? b.temp(any(expr(inner.argumentExpression()))) : inner.name().kind == KindPrivateIdentifier ? null : EStr(inner.name().text);
			if (key == null || n.questionDotToken() != null) {
				var fn = key == null ? b.runtime("libPrivateGet", [obj, EStr(brand(inner.name()))]) : b.runtime("libGet", [obj, key]);
				chainCheck(n, fn);
				return b.runtime("libCall", [fn, obj, argumentList(actual)]);
			}
			return b.runtime("libCallMethod", [obj, key, argumentList(actual)]);
		}
		var fn = expr(callee);
		chainCheck(n, fn);
		return apply(fn, argumentList(actual));
	}
}
