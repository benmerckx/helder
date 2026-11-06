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

// A binding's storage: a global (module scope), a box (captured by a
// closure), or a plain local; `outer`: an enclosing function's plain local,
// which no closure can see (Captures)
typedef Binding = {ty:Ty, ?cell:Ex, ?global:Int, ?local:Local, ?outer:String, ?buffer:Local};

// A source file's top-level scope: its bindings (globals), direct functions
// and exports. Imports alias the exporting module's bindings, so they are live.
class Module {
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

// The lowering's state and the helpers every part of it uses: bindings,
// coercions between representations, the program's types. (Frontend:
// the lowering, in layers: Functions, Statements, Expressions, ClassValues,
// ApiCalls, Frontend; what one calls in a later one is declared here.)
abstract class Core {
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
	// (helder's API as the program's declaration files declare it, its manifest: null without any)
	final api:Null<Api>;
	// (calls into it, TSX: with a manifest)
	var bridge:Null<Haxe> = null;
	var tsx:Null<Tsx> = null;
	// (hxmc dev: components mounted with fast refresh's keys)
	final dev:Bool;
	// (helder dev: signals made where no name says, numbered in their function)
	var hotUnnamed:Map<String, Int> = [];

	// definitions' calls (helder/gfx's shader): their handlers' output
	final definitions:Definitions;

	public function new(src:Project, p:Program, ?api:Api, dev = false, ?defined:String->Null<String>) {
		this.src = src;
		this.p = p;
		this.api = api;
		this.dev = dev;
		definitions = new Definitions(src, defined ?? (_ -> null));
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

	// a direct function's result: as its type says
	function ret(n:Node):Ty return n.kind == KindFunctionDeclaration && n.name() != null && n.parent != null && n.parent.kind == KindSourceFile ? reps.rep(n.returnType()) : TRef(RAny);

	// a let or const binding's, or a direct function's parameter's: as its type says
	// (a `yield`'s value is whatever next() is given: TypeScript's TNext does not hold for it)
	function bindingType(n:Node):Ty
		return n.name().kind == KindIdentifier && (n.initializer() == null || n.initializer().kind != KindYieldExpression) ? reps.rep(n.name().tsType) : TRef(RAny);

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
	function placeholder(t:Ty):Ex return t == TF64 ? EF64(0) : t == TBool ? bool(false) : t.match(TRef(RStr)) ? EStr("") : t.match(TRef(RObj(_))) ? ENull(t) : b.runtime("getUndefined", []);

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
	// (a .json file the program imports: resolveJsonModule's, its value its default export)
	static function jsonModule(file:SourceFile):Bool return StringTools.endsWith(file.path, ".json");

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
		if (Ir.typeOf(e) == TF64) {
			// (neither 0 nor NaN)
			typedOperations++;
			var v = b.temp(e), l = b.local("truth", TBool);
			b.out.push(SSet(l, EBin(FNe, v, EF64(0))));
			b.out.push(SIf(ELocal(l), Vector.fromArrayCopy([SSet(l, EBin(FEq, v, v))]), new Vector(0)));
			return ELocal(l);
		}
		dynamicOperations++;
		return b.runtime("truth", [any(e)]);
	}

	function text(e:Ex):Ex return switch (Ir.typeOf(e)) {
		case TRef(RStr): e;
		case TF64: b.runtime("numberText", [e]);
		case _: b.runtime("text", [any(e)]);
	};

	function thisValue():Ex return env.exists("this") ? read(env.get("this")) : b.runtime("getUndefined", []);

	static var compound:Map<Kind, Kind> = [KindPlusEqualsToken => KindPlusToken, KindMinusEqualsToken => KindMinusToken, KindAsteriskEqualsToken => KindAsteriskToken,
		KindAsteriskAsteriskEqualsToken => KindAsteriskAsteriskToken, KindSlashEqualsToken => KindSlashToken, KindPercentEqualsToken => KindPercentToken,
		KindLessThanLessThanEqualsToken => KindLessThanLessThanToken, KindGreaterThanGreaterThanEqualsToken => KindGreaterThanGreaterThanToken,
		KindGreaterThanGreaterThanGreaterThanEqualsToken => KindGreaterThanGreaterThanGreaterThanToken, KindAmpersandEqualsToken => KindAmpersandToken,
		KindBarEqualsToken => KindBarToken, KindCaretEqualsToken => KindCaretToken];
	function bool(v:Bool):Ex return ECast(TBool, EInt(v ? 1 : 0));

	// A suspension point handing out value; returns the value sent back in.
	// With modes, a throw() or return() resumption throws or returns here.
	static inline var YIELD = 0;
	static inline var AWAIT = 1;
	static function staticName(name:Node):Null<String> return name.kind == KindIdentifier || name.kind == KindStringLiteral || name.kind == KindPrivateIdentifier ? name.text : name.kind == KindNumericLiteral ? Std.string(Std.parseFloat(name.text)) : null;

	// ---- classes with layouts (Classes): direct functions on typed `this`
	// (a call to super() in the init function being compiled: the parent's init on this instance)
	var superInit:Null<Array<Node>->Ex> = null;

	// whether an arrow function among these nodes reads `this` (which then lives in a box)
	static function arrowsUseThis(nodes:Array<Node>):Bool {
		function visit(n:Node):Bool {
			if (n == null || n.kind == KindFunctionDeclaration || n.kind == KindFunctionExpression || n.kind == KindClassDeclaration || n.kind == KindClassExpression || n.kind == KindMethodDeclaration) return false;
			if (n.kind == KindArrowFunction) return usesThis(n.body());
			for (c in n.children()) if (visit(c)) return true;
			return false;
		}
		for (n in nodes) if (visit(n)) return true;
		return false;
	}

	var buffering:Map<Node, Bool> = [];

	// ---- helder's API (lower.Api, its manifest): calls into Haxe, members, TSX

	static function strip(n:Node):Node {
		while (n.kind == KindParenthesizedExpression) n = n.expression();
		return n;
	}

	// ---- typed values (Reps)
	// (a property access that is neither optional nor through super)
	static function plainAccess(n:Node):Bool return n.flags & NodeFlags.OptionalChain == 0 && n.expression().kind != KindSuperKeyword;

	var chainDepth = -1;
	var chainTops:Map<Node, Bool> = [];

	// (what the layers define that an earlier one calls)
	abstract function enter(m:Module):Void;
	abstract function anonymousGlobal(name:String):Binding;
	abstract function declared(specifier:Node):Bool;
	public abstract function lower():Void;
	abstract function linkModule(m:Module):Bool;
	abstract function hoist(n:Node, global:Bool):Void;
	abstract function statement(n:Node, top:Bool = false, ?labels:Array<String>):Void;
	abstract function target(labels:Array<String>, kind:JumpKind):JumpTarget;
	abstract function irLoop(build:() -> Void, ?t:JumpTarget):Void;
	abstract function flag(code:Int):Void;
	abstract function insideFinally():Bool;
	abstract function tryStatement(n:Node):Void;
	abstract function expr(n:Node):Ex;
	abstract function lvalue(n:Node):{read:() -> Ex, write:Ex->Void};
	abstract function strictEquals(a:Ex, z:Ex):Ex;
	abstract function closure(n:Node, ?name:String):Ex;
	abstract function brand(name:Node):String;
	abstract function classValue(n:Node, ?name:String):Ex;
	abstract function layoutConstruct(n:Node):Null<Ex>;
	abstract function layoutCall(n:Node, inner:Node, actual:Array<Node>):Null<Ex>;
	abstract function manifest(n:Node):Manifest;
	abstract function apiExpr(n:Node):Null<Ex>;
	abstract function apiTarget(n:Node):Null<{read:() -> Ex, write:Ex->Void}>;
	abstract function layoutField(n:Node):Null<ClassLayout>;
	abstract function mathCall(n:Node, callee:Node, actual:Array<Node>):Null<Ex>;
	abstract function parameterProperties():Void;
	abstract function call(n:Node):Ex;
}
