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

	function layout(n:Node):Null<ClassLayout> {
		if (n.modifiers().exists(m -> m.kind == KindDeclareKeyword)) return null;
		var parent:Null<ClassLayout> = null;
		for (h in n.heritageClauses() ?? []) if (h.token() == KindExtendsKeyword) {
			var e = h.types()[0].expression();
			parent = e.kind == KindIdentifier ? bySymbol.get(e.symbol) : null;
			if (parent == null) return null;
		}
		var c = new ClassLayout(n, n.name().text, all.length, parent);
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

	public static function isParameterProperty(p:Node):Bool
		return p.modifiers().exists(x -> x.kind == KindPublicKeyword || x.kind == KindPrivateKeyword || x.kind == KindProtectedKeyword || x.kind == KindReadonlyKeyword || x.kind == KindOverrideKeyword);
}
