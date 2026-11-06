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
import helder.typescript.lower.Api;
import helder.typescript.lower.Core;
import helder.typescript.lower.Core.*;

// TypeScript's checked AST lowered to hxmc IR, in evaluation order: the
// modules (their scopes, imports and exports, the order they run in), then
// each part (Core and the layers it extends).
@:access(helder.typescript.lower.Core)
class Frontend extends ApiCalls {
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

	// (a declaration file's: helder's API, which the program calls through its manifest)
	function declared(specifier:Node):Bool {
		var name = src.resolve(specifier);
		return name != null && StringTools.endsWith(name, ".d.ts");
	}

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
				if (spec != null && !declared(spec)) visit(targetModule(spec));
			}
			order.push(m);
		}
		visit(moduleOf.get(src.file.path));
		return order;
	}

	// helder.jobs.script.Entry.call's body: the program's jobs by their number
	function jobCalls() {
		var fi = bridge.fn("helder_jobs_script_Entry_call");
		var outer = b;
		b = new Builder(p, fi);
		for (k in 0...jobs.length) {
			var r = b.block(() -> b.out.push(SReturn(b.coerce(b.temp(ECall(jobs[k], Vector.fromArrayCopy([any(ELocal(fi.args[1])), any(ELocal(fi.args[2]))]))), fi.ret))));
			b.out.push(SIf(EBin(Eq, ELocal(fi.args[0]), EInt(k)), r, Vector.fromArrayCopy([])));
		}
		fi.body = Vector.fromArrayCopy(b.out.concat(fi.body.toArray()));
		b = outer;
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
		if (api != null && api.manifest != null) {
			bridge = new Haxe(this, p, api.manifest);
			tsx = new Tsx(this, bridge, api, dev);
			// (its timers and promises on helder.async's loop: Interop.hostLoop)
			if (eventLoop) bridge.call(bridge.interop("hostLoop"), []);
		}
		for (c in classes.all) declareLayout(c);
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
		// (its agnostic literals' code for each renderer, set first)
		if (tsx != null) body = Vector.fromArrayCopy(tsx.install().concat(body.toArray()));
		if (jobs.length > 0) jobCalls();
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
		// (a JSON module: its value the default export, its one statement)
		if (jsonModule(m.file)) {
			m.exports.set("default", anonymousGlobal("default"));
			return;
		}
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
				if (clause.isTypeOnly() || declared(n.moduleSpecifier())) continue;
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
}
