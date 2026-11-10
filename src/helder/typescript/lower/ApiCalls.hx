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

// Calls into helder's API (the manifest's classes and members) and Math's
// functions called directly.
@:access(helder.typescript.lower.Core)
abstract class ApiCalls extends ClassValues {
	function manifest(n:Node):Manifest {
		if (api.manifest == null) fail(n, "helder's API without its manifest (the build's typing made none)");
		return api.manifest;
	}

	// (a class the declarations declare, as the manifest lists it)
	function apiClass(c:ForeignClass, n:Node):MClass {
		var m = manifest(n).cls(c.path);
		if (m == null) fail(n, "helder's " + c.path + " is not in the manifest");
		return m;
	}

	function apiMember(c:MClass, name:String, statics:Bool, n:Node):MMember {
		var m = (statics ? c.statics : c.members).get(name);
		if (m == null) fail(n, c.path + (statics ? "." : "#") + name + " is not a member of helder's the manifest lists");
		return m;
	}

	// what an expression of helder's API lowers to (null: none of its)
	function apiExpr(n:Node):Null<Ex> {
		return switch n.kind {
			case KindJsxElement | KindJsxSelfClosingElement | KindJsxFragment:
				if (tsx == null) fail(n, "TSX is helder.view's markup: the program imports helder/view (or another module of helder's)");
				tsx.literal(n);
			case KindCallExpression: definitions.defines(n) ? null : apiCall(n);
			case KindNewExpression:
				switch api.of(strip(n.expression())) {
					case FClass(c):
						var m = apiClass(c, n);
						if (m.ctor == null) fail(n, c.name + " is not constructed by the program (no constructor of its is declared)");
						bridge.construct(m, apiArguments(n.arguments() ?? [], m.ctor), where());
					case _: null;
				}
			// (the chain's top first made a chain: its loop, then this again)
			case KindPropertyAccessExpression if (n.questionDotToken() != null && n.name().kind != KindPrivateIdentifier && !chainTop(n)):
				// (a?.x: an instance's member, the chain ended where a is nullish)
				var receiver = strip(n.expression());
				var c = api.classOf(types.present(receiver.tsType));
				if (c == null) null else {
					var m = apiClass(c, n);
					var member = apiMember(m, n.name().text, false, n);
					if (member.kind == "method") null else {
						var obj = b.temp(any(expr(receiver)));
						chainCheck(n, obj);
						bridge.getMember(m, member, obj, where());
					}
				}
			case KindPropertyAccessExpression if (n.questionDotToken() == null && n.name().kind != KindPrivateIdentifier):
				var receiver = strip(n.expression());
				switch api.of(receiver) {
					case FClass(c):
						var m = apiClass(c, n);
						bridge.getMember(m, apiMember(m, n.name().text, true, n), null, where());
					case FStatic(_, _): null;
					case null:
						var c = api.classOf(receiver.tsType);
						if (c == null) null else {
							var m = apiClass(c, n);
							var member = apiMember(m, n.name().text, false, n);
							if (member.kind == "method") fail(n, "helder's " + c.name + "." + member.name + " read as a value: call it");
							bridge.getMember(m, member, expr(receiver), where());
						}
				}
			case KindIdentifier if (api.of(n) != null):
				fail(n, "helder's " + n.text + " is used as a value: call it, construct it or read its members");
			case _: null;
		}
	}

	// the program's arguments, in order, the literals among them placed where
	// the parameters' types say (ViewOf<R>: compiled for R, a root's)
	function apiArguments(actual:Array<Node>, t:Null<HType>):Array<Null<Ex>> {
		var params = switch t {
			case HFn(a, _): a;
			case _: [];
		}
		return [for (i in 0...actual.length) {
			var a = actual[i];
			if (a.kind == KindSpreadElement) fail(a, "a spread among the arguments of a call into helder's API");
			var inner = strip(a);
			if (i < params.length && (inner.kind == KindJsxElement || inner.kind == KindJsxSelfClosingElement || inner.kind == KindJsxFragment))
				switch HTypes.bare(params[i].t) {
					case HView(r): tsx.placed.set(inner, r);
					case _:
				}
			expr(a);
		}];
	}

	// a call of helder's: a class's static, an instance's method, a signal (by
	// its type: a read, a write, an update), Render.render's mounting
	function apiCall(n:Node):Null<Ex> {
		var callee = strip(n.expression());
		var actual = n.arguments() ?? [];
		if (n.questionDotToken() == null && !hasSpread(actual) && (api.isSignal(callee.tsType) || api.isMemo(callee.tsType))) {
			if (actual.length == 0) return bridge.call(bridge.interop("signalRead"), [any(expr(callee))]);
			if (actual.length == 1 && api.isSignal(callee.tsType)) {
				var f = b.temp(any(expr(callee)));
				var v = any(expr(actual[0]));
				var a = strip(actual[0]);
				var update = a.kind == KindArrowFunction || a.kind == KindFunctionExpression || types.callable(a.tsType);
				return update ? bridge.call(bridge.interop("signalUpdate"), [f, v]) : bridge.call(bridge.interop("signalWrite"), [f, v, EStr(where())]);
			}
		}
		switch callee.kind {
			case KindIdentifier:
				switch api.of(callee) {
					case FStatic(c, name):
						var m = apiClass(c, n);
						var member = apiMember(m, name, true, n);
						if (member.mount) return mount(n, member);
						var r = bridge.callStatic(m, member, apiArguments(actual, member.type), where());
						return dev && c.path == "helder.view.graph.Graph" && name == "signalValue" && actual.length == 1 ? hotSignal(n, r) : r;
					case FClass(c): return fail(n, c.name + " is a class: construct it with new");
					case null: return null;
				}
			case KindPropertyAccessExpression if (n.questionDotToken() == null && callee.name().kind != KindPrivateIdentifier):
				var receiver = strip(callee.expression());
				// (a?.m(): an instance's method, the chain ended where a is nullish)
				if (callee.questionDotToken() != null) {
					if (chainTop(n)) return null;
					var c = api.classOf(types.present(receiver.tsType));
					if (c == null) return null;
					var m = apiClass(c, n);
					var member = apiMember(m, callee.name().text, false, n);
					var obj = b.temp(any(expr(receiver)));
					chainCheck(callee, obj);
					return bridge.callMethod(m, member, bridge.instance(m, obj, where()), apiArguments(actual, member.type), where());
				}
				switch api.of(receiver) {
					case FClass(c):
						var m = apiClass(c, n);
						var member = apiMember(m, callee.name().text, true, n);
						if (member.mount) return mount(n, member);
						return bridge.callStatic(m, member, apiArguments(actual, member.type), where());
					case FStatic(_, _): return null;
					case null:
						var c = api.classOf(receiver.tsType);
						if (c == null) return null;
						var m = apiClass(c, n);
						var member = apiMember(m, callee.name().text, false, n);
						var obj = b.temp(any(expr(receiver)));
						return bridge.callMethod(m, member, bridge.instance(m, obj, where()), apiArguments(actual, member.type), where());
				}
			case _:
				return null;
		}
	}

	// (helder dev) a signal made by signal(value), kept across reloads as
	// Haxe's (helder.view.Refresh): keyed by where it is made (the module,
	// the function or class, the variable; Hot's scope adds the component
	// instance's), its value's type by the type argument written, its
	// initial value's source hashed (an edit to it starts afresh)
	function hotSignal(n:Node, made:Ex):Ex {
		var parts = [Project.relative(n.file.path).split(".")[0]];
		var name:Null<String> = null;
		var p = n.parent;
		while (p != null && p.kind == KindParenthesizedExpression) p = p.parent;
		if (p != null && (p.kind == KindVariableDeclaration || p.kind == KindPropertyDeclaration || p.kind == KindPropertyAssignment) && p.name() != null && p.name().kind == KindIdentifier)
			name = p.name().text;
		var outer = p;
		while (outer != null && outer.kind != KindSourceFile) {
			var found:Null<String> = switch outer.kind {
				case KindFunctionDeclaration | KindMethodDeclaration | KindClassDeclaration if (outer.name() != null): outer.name().text;
				case KindArrowFunction | KindFunctionExpression if (outer.parent != null && outer.parent.kind == KindVariableDeclaration && outer.parent.name().kind == KindIdentifier):
					outer.parent.name().text;
				case _: null;
			}
			if (found != null) {
				parts.push(found);
				break;
			}
			outer = outer.parent;
		}
		var scope = parts.join(".");
		if (name == null) {
			var seen = hotUnnamed.get(scope) ?? 0;
			hotUnnamed.set(scope, seen + 1);
			name = "#" + seen;
		}
		var text = n.file.text();
		function source(x:Node):String return text.substring(n.file.skipTrivia(x.pos), x.end);
		var type = "ts:" + [for (t in n.typeArguments() ?? []) source(t)].join(",");
		var init = haxe.crypto.Md5.encode(source(n.arguments()[0])).substr(0, 8);
		return bridge.call(bridge.interop("hotSignal"), [any(made), EStr(scope + "." + name), EStr(type), EStr(init)]);
	}

	// Render.render(content, parent) and insert(content, parent, before): the
	// runtime of the renderer whose node parent is (its class's @:rendered),
	// a literal given compiled for it
	function mount(n:Node, member:MMember):Ex {
		var actual = n.arguments() ?? [];
		var insert = actual.length == 3;
		if (actual.length != 2 && !insert) fail(n, "Render." + member.name + " takes content and a parent" + (member.name == "insert" ? " and a node to insert before" : ""));
		var parent = api.classOf(actual[1].tsType);
		var m = parent == null ? null : manifest(n).cls(parent.path);
		var renderer = m == null ? null : m.rendered;
		if (renderer == null) fail(actual[1], "helder.view: this is no renderer's node (its class names its renderer with @:rendered(...))");
		var r = manifest(n).renderers.get(renderer);
		var content = strip(actual[0]);
		if (content.kind == KindJsxElement || content.kind == KindJsxSelfClosingElement || content.kind == KindJsxFragment) tsx.placed.set(content, renderer);
		var c = expr(actual[0]);
		var node = bridge.classInfo(r.node);
		var p = b.temp(any(expr(actual[1])));
		var args = [any(bridge.call(bridge.interop("toHaxe"), [any(c)])), bridge.instance(m, p, where())];
		if (insert) args.push(b.coerce(bridge.call(bridge.interop("toHaxe"), [any(expr(actual[2]))]), TRef(RObj(node))));
		var rt = bridge.fn(r.runtime.split(".").join("_") + "_" + (insert ? "insert" : "render"));
		return bridge.toJs(bridge.call(rt, args), HDynamic);
	}

	// a member of helder's as a target: read and written, its receiver once
	function apiTarget(n:Node):Null<{read:() -> Ex, write:Ex->Void}> {
		if (n.kind != KindPropertyAccessExpression || n.questionDotToken() != null || n.name().kind == KindPrivateIdentifier) return null;
		var receiver = strip(n.expression());
		var name = n.name().text;
		switch api.of(receiver) {
			case FClass(c):
				var m = apiClass(c, n);
				var member = apiMember(m, name, true, n);
				return {read: () -> bridge.getMember(m, member, null, where()), write: e -> bridge.setMember(m, member, null, e, where())};
			case FStatic(_, _): return null;
			case null:
				var c = api.classOf(receiver.tsType);
				if (c == null) return null;
				var m = apiClass(c, n);
				var member = apiMember(m, name, false, n);
				var obj = b.temp(any(expr(receiver)));
				return {read: () -> bridge.getMember(m, member, obj, where()), write: e -> bridge.setMember(m, member, obj, e, where())};
		}
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
		var args = [for (a in actual) b.temp(number(numeric(a, false)))];
		typedOperations++;
		return if (unary.exists(name)) b.runtime(unary.get(name), args);
		else if (binary.exists(name)) b.runtime(binary.get(name), args);
		else if (arity == 1) b.runtime("mathUnary", [EStr(name), args[0]]);
		else b.runtime("mathBinary", [EStr(name), args[0], args[1]]);
	}
}
