package helder.typescript.lower;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;

// The declarations a nested function may refer to: their bindings live in
// shared boxes (captured by closures); the others are plain locals. By
// name, so it over-approximates: a declaration is captured when its name
// appears in a function or class nested inside the one declaring it.
class Captures {
	final captured:Map<Node, Bool> = [];

	public function new(src:Project) {
		for (sf in src.files) {
			var byName = new Map<String, Array<{id:Node, scope:Node}>>();
			for (i in 1...sf.count) if (sf.kindAt(i) == KindIdentifier) {
				var id = sf.node(i);
				var list = byName.get(id.text);
				if (list == null) byName.set(id.text, list = []);
				list.push({id: id, scope: scope(id)});
			}
			for (list in byName) for (d in list) if (declares(d.id))
				for (u in list) if (u.scope != d.scope && within(u.scope, d.scope)) {
					captured.set(d.id, true);
					break;
				}
		}
	}

	// whether a declared name's binding must be shared (a box)
	public function shared(name:Node):Bool return captured.exists(name);

	// the function or class an identifier is in (its closures' boundary), or the file
	static function scope(n:Node):Node {
		var p = n.parent;
		// (a function's or class's own name is bound where it is declared)
		if (p != null && boundary(p) && p.name() == n) p = p.parent;
		while (p != null && !boundary(p)) p = p.parent;
		return p == null ? n.file.root : p;
	}

	public static function boundary(n:Node):Bool return switch n.kind {
		case KindFunctionDeclaration | KindFunctionExpression | KindArrowFunction | KindMethodDeclaration | KindConstructor | KindGetAccessor
			| KindSetAccessor | KindClassDeclaration | KindClassExpression: true;
		case _: false;
	}

	static function within(inner:Node, outer:Node):Bool {
		var p = inner;
		while (p != null) {
			if (p == outer) return true;
			p = p.parent;
		}
		return false;
	}

	static function declares(id:Node):Bool {
		var p = id.parent;
		return switch p.kind {
			case KindVariableDeclaration | KindParameter | KindBindingElement | KindFunctionDeclaration | KindClassDeclaration | KindEnumDeclaration
				| KindModuleDeclaration: p.name() == id;
			case _: false;
		}
	}
}
