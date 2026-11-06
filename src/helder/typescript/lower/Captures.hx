package helder.typescript.lower;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;

// The declarations a nested function may refer to: their bindings live in
// shared boxes (captured by closures); the others are plain locals. By
// name, so it over-approximates: a declaration is captured when its name
// appears in a function or class nested inside the one declaring it, unless
// the checker resolves that name to another declaration.
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
				for (u in list) if (u.scope != d.scope && within(u.scope, d.scope) && !another(d.id, u.id)) {
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

	// (a TSX element and a hole of one too: its components are called, its
	// holes that read evaluated, by functions of their own, later: helder.typescript.lower.Tsx)
	public static function boundary(n:Node):Bool return switch n.kind {
		case KindFunctionDeclaration | KindFunctionExpression | KindArrowFunction | KindMethodDeclaration | KindConstructor | KindGetAccessor
			| KindSetAccessor | KindClassDeclaration | KindClassExpression | KindJsxExpression | KindJsxElement | KindJsxSelfClosingElement: true;
		case _: false;
	}

	// (a use the checker resolves to another declaration: the same name
	// declared again in the nested function; a shorthand property's name
	// resolves to the property, so it counts)
	static function another(declared:Node, use:Node):Bool
		return declared.symbol != null && use.symbol != null && declared.symbol != use.symbol && use.parent.kind != KindShorthandPropertyAssignment;

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
