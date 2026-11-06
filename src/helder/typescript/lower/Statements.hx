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

// Statements and control flow: blocks, loops, labels and jumps, switch,
// try/finally, variable lists, enums and namespaces.
@:access(helder.typescript.lower.Core)
abstract class Statements extends Functions {
	function statement(n:Node, top = false, ?labels:Array<String>) {
		if (n == null) return;
		if (labels == null) labels = [];
		if (hasModifier(n, KindDeclareKeyword)) return;
		here = n;
		if (buffered(n, labels)) return;
		switch (n.kind) {
			case KindImportDeclaration if (TsAssets.imported(n) != null): assetImport(n);
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
			case KindExpressionStatement if (top && jsonModule(n.file)): set(moduleOf.get(n.file.path).exports.get("default"), expr(n.expression()));
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

	// ---- strings loops only append to
	// A loop that only appends to string locals (`s += x` statements, no
	// other use of s in it): each built in a buffer while it runs, then a
	// string again. Not inside a try (a catch could read s), and leaving it
	// only to its end (no break or continue to a label outside it).
	function buffered(loop:Node, labels:Array<String>):Bool {
		if (!(loop.kind == KindForStatement || loop.kind == KindForOfStatement || loop.kind == KindForInStatement || loop.kind == KindWhileStatement || loop.kind == KindDoStatement) || buffering.exists(loop)) return false;
		var p = loop.parent;
		while (p != null && !Captures.boundary(p)) {
			if (p.kind == KindTryStatement) return false;
			p = p.parent;
		}
		var uses = new Map<String, Bool>(), others = new Map<String, Bool>();
		var jumpsOut = false;
		function visit(n:Node) {
			if (n == null) return;
			switch n.kind {
				case KindIdentifier:
					var parent = n.parent;
					var append = parent.kind == KindBinaryExpression && parent.left() == n && parent.operatorToken().kind == KindPlusEqualsToken && parent.parent.kind == KindExpressionStatement;
					if (append) uses.set(n.text, true) else others.set(n.text, true);
				case KindBreakStatement | KindContinueStatement if (n.label() != null && !labels.contains(n.label().text)):
					// (a label inside the loop is fine; one outside it leaves early)
					var inner = n.parent, found = false;
					while (inner != loop) {
						if (inner.kind == KindLabeledStatement && inner.label().text == n.label().text) found = true;
						inner = inner.parent;
					}
					if (!found) jumpsOut = true;
				case _:
			}
			for (c in n.children()) visit(c);
		}
		visit(loop);
		if (jumpsOut) return false;
		// (an enclosing loop's buffer serves this one too)
		var names = [for (name in uses.keys()) if (!others.exists(name) && env.exists(name) && env.get(name).local != null && env.get(name).buffer == null && env.get(name).ty.match(TRef(RStr))) name];
		if (names.length == 0) return false;
		var saved = [for (name in names) name => env.get(name)];
		for (name in names) {
			var start = b.runtimeCall("libBuffer", [ELocal(saved[name].local)]);
			var buffer = b.local("buffer", Ir.typeOf(start));
			b.out.push(SSet(buffer, start));
			env.set(name, {ty: saved[name].ty, local: saved[name].local, buffer: buffer});
		}
		buffering.set(loop, true);
		statement(loop, false, labels);
		buffering.remove(loop);
		for (name in names) {
			b.out.push(SSet(saved[name].local, b.runtimeCall("libBuffered", [ELocal(env.get(name).buffer)])));
			env.set(name, saved[name]);
		}
		return true;
	}
}
