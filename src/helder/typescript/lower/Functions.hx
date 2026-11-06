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

// Functions: declarations, parameters and patterns, closures and direct
// functions, generators' and async functions' resumable step functions.
@:access(helder.typescript.lower.Core)
abstract class Functions extends Core {
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

	// A compiled closure: (closure, this, hidden..., parameters...). Every
	// binding with a cell in the enclosing scope is captured; `this` is bound
	// from the argument unless it is lexical (arrows). build compiles the body.
	function lambda(n:Null<Node>, hidden:Array<String>, lexicalThis:Bool, restArguments:Bool, build:FuncInfo->Void):{clos:Ex, arity:Int, rest:Bool} {
		var old = b;
		var outer = env;
		var oldVars = functionVars;
		functionVars = [];
		var f = n != null ? declareFunction(n, "lambda" + serial++, false) : Builder.func(p, "lambda" + serial++, TRef(RAny));
		var savedSuper = superInit;
		superInit = null;
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
		superInit = savedSuper;
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

	// a direct function's body: its `this` and parameters bound, then build
	function compileDirect(f:FuncInfo, n:Node, captured:Bool, build:() -> Void) {
		var old = b, oldEnv = env, oldVars = functionVars, saved = here;
		functionVars = [];
		b = new Builder(p, f);
		env = oldEnv.copy();
		here = n;
		env.set("this", captured ? {ty: f.args[0].ty, cell: b.temp(ENewBox(f.args[0].ty, ELocal(f.args[0])))} : {ty: f.args[0].ty, local: f.args[0]});
		var names = parameterNames(n);
		for (a in f.args.slice(1)) env.set(a.name, bind(names.get(a.name), a.ty, ELocal(a)));
		build();
		if (f.ret == TVoid) b.out.push(SReturn(null)); else b.out.push(SReturn(store(b.runtime("getUndefined", []), f.ret)));
		b.finish();
		b = old;
		env = oldEnv;
		functionVars = oldVars;
		here = saved;
	}

	// A direct function as the function object compiled code calls dynamically:
	// (closure, this, [newTarget,] arguments...); body gets them from `this` on.
	function directValue(f:FuncInfo, prelude:Array<String>, body:(Array<Local>) -> Ex):{clos:Ex, arity:Int, rest:Bool} {
		var count = f.args.length - 1;
		var front = ["closure", "this"].concat(prelude);
		var w = Builder.func(p, "direct" + serial++, TRef(RAny));
		w.args = [for (i in 0...front.length) new Local(i, front[i], TRef(RAny))].concat([for (i in 0...count) new Local(front.length + i, f.args[i + 1].name, TRef(RAny))]);
		var li = new LambdaInfo(p.lambdas.length, p.sig([for (a in w.args.slice(1)) a.ty], TRef(RAny)), new Vector(0), w);
		p.lambdas.push(li);
		w.lambda = li;
		var old = b;
		b = new Builder(p, w);
		b.out.push(SReturn(any(body(w.args.slice(1)))));
		b.finish();
		b = old;
		return {clos: any(b.temp(ENewClos(li, new Vector(0)))), arity: count, rest: restFunctions.exists(f)};
	}
}
