package helder.typescript.lower;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;

using Lambda;

// A class with a layout of its own: an hxmc class under the runtime's
// JsObject (Frontend.typedClasses), its declared fields in slots typed as
// their types say. The runtime keeps the slots plain values: a field
// deleted, made read-only or an accessor diverges (Values.JsObject.setOwn).
class ClassLayout {
	public final node:Node;
	public final name:String;
	public final index:Int;
	public final parent:Null<ClassLayout>;
	// own fields in definition order: declared fields, then parameter properties
	public final own:Array<String> = [];
	// their names' nodes (whose types the slots take)
	public final names:Array<Node> = [];
	public var info:Null<hxmc.ir.Ir.ClassInfo> = null;
	// (set by the frontend) its constructor and field initializers on a
	// made instance, its methods on typed `this` (direct functions), and the
	// globals holding its prototype and its instances' runtime Layout
	public var init:Null<hxmc.ir.Ir.FuncInfo> = null;
	public final methods:Map<String, hxmc.ir.Ir.FuncInfo> = [];
	public var prototype = -1;
	public var layout = -1;
	// (the members named on its prototype: methods, accessors)
	public final members:Map<String, Node> = [];

	public function new(node, name, index, parent) {
		this.node = node;
		this.name = name;
		this.index = index;
		this.parent = parent;
	}

	// every field, inherited ones first: their order in the layout
	public function fields():Array<String> return (parent == null ? [] : parent.fields()).concat(own);

	public function declares(f:String):Bool return own.contains(f) || parent != null && parent.declares(f);

	public function isA(other:ClassLayout):Bool return this == other || parent != null && parent.isA(other);

	public function constructor():Null<Node> {
		for (m in node.members()) if (m.kind == KindConstructor && m.body() != null) return m;
		return null;
	}

	// the direct function an instance of this class runs for `name`, or null
	// (an accessor, a generator's or one it does not have: the runtime's way)
	public function method(name:String):Null<hxmc.ir.Ir.FuncInfo> {
		var c = this;
		while (c != null) {
			if (c.members.exists(name) || c.own.contains(name)) return c.methods.get(name);
			c = c.parent;
		}
		return null;
	}
}

// The program's classes with layouts: its top-level class declarations
// whose fields have plain names, extending nothing or another of them.
class Classes {
	public final all:Array<ClassLayout> = [];
	final bySymbol:Map<String, ClassLayout> = [];
	final byNode:Map<Node, ClassLayout> = [];

	public function new(src:Project) {
		for (sf in src.files) for (n in sf.root.statements()) if (n.kind == KindClassDeclaration && n.name() != null) {
			var c = layout(n);
			if (c == null) continue;
			all.push(c);
			bySymbol.set(n.name().symbol, c);
			byNode.set(n, c);
		}
	}

	// the class with a layout a symbol names, else null
	public function of(symbol:Null<String>):Null<ClassLayout> return symbol == null ? null : bySymbol.get(symbol);

	// the class with a layout a declaration makes, else null
	public function declared(classNode:Node):Null<ClassLayout> return byNode.get(classNode);

	// a class and the classes with layouts under it
	public function descendants(c:ClassLayout):Array<ClassLayout> return all.filter(d -> d.isA(c));

	// a method compiled as a direct function: plain name, not static, an accessor, a generator or async
	public static function direct(m:Node):Bool
		return m.kind == KindMethodDeclaration && m.body() != null && (m.name().kind == KindIdentifier || m.name().kind == KindStringLiteral)
			&& m.asteriskToken() == null && !m.modifiers().exists(x -> x.kind == KindStaticKeyword || x.kind == KindAsyncKeyword)
			&& !Frontend.usesArguments(m.body());

	function layout(n:Node):Null<ClassLayout> {
		if (n.modifiers().exists(m -> m.kind == KindDeclareKeyword)) return null;
		var parent:Null<ClassLayout> = null;
		for (h in n.heritageClauses() ?? []) if (h.token() == KindExtendsKeyword) {
			var e = h.types()[0].expression();
			parent = e.kind == KindIdentifier ? bySymbol.get(e.symbol) : null;
			if (parent == null) return null;
		}
		// (its constructor runs on an instance made before: no `return value`, no new.target, no `arguments`)
		var ctor = null;
		for (m in n.members()) if (m.kind == KindConstructor && m.body() != null) ctor = m;
		if (ctor != null && (returnsValue(ctor.body()) || Frontend.usesArguments(ctor.body()))) return null;
		if (mentions(n, KindMetaProperty)) return null;
		var c = new ClassLayout(n, n.name().text, all.length, parent);
		for (m in n.members()) if ((m.kind == KindMethodDeclaration || m.kind == KindGetAccessor || m.kind == KindSetAccessor)
			&& !m.modifiers().exists(x -> x.kind == KindStaticKeyword) && m.name().kind != KindPrivateIdentifier && m.name().kind != KindComputedPropertyName)
			c.members.set(m.name().text, m);
		function field(name:Node):Bool {
			if (name.kind != KindIdentifier && name.kind != KindStringLiteral) return false;
			if (c.declares(name.text)) return false;
			c.own.push(name.text);
			c.names.push(name);
			return true;
		}
		for (m in n.members()) if (m.kind == KindPropertyDeclaration && !m.modifiers().exists(x -> x.kind == KindStaticKeyword || x.kind == KindDeclareKeyword || x.kind == KindAbstractKeyword)) {
			if (m.name().kind == KindPrivateIdentifier) continue;
			if (!field(m.name())) return null;
		}
		for (m in n.members()) if (m.kind == KindConstructor) for (p in Frontend.parametersOf(m))
			if (isParameterProperty(p) && p.name().kind == KindIdentifier && !field(p.name())) return null;
		return c;
	}

	static function returnsValue(n:Node):Bool {
		if (n == null || n.kind == KindFunctionDeclaration || n.kind == KindFunctionExpression || n.kind == KindArrowFunction || n.kind == KindClassDeclaration || n.kind == KindClassExpression) return false;
		if (n.kind == KindReturnStatement && n.expression() != null) return true;
		for (c in n.children()) if (returnsValue(c)) return true;
		return false;
	}

	static function mentions(n:Node, kind:Kind):Bool {
		if (n.kind == kind) return true;
		for (c in n.children()) if (mentions(c, kind)) return true;
		return false;
	}

	public static function isParameterProperty(p:Node):Bool
		return p.modifiers().exists(x -> x.kind == KindPublicKeyword || x.kind == KindPrivateKeyword || x.kind == KindProtectedKeyword || x.kind == KindReadonlyKeyword || x.kind == KindOverrideKeyword);
}
