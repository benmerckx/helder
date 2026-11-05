package helder.ui.actions;

// Where a binding holds (GPUI's KeyBindingContextPredicate): an identifier
// ("Editor": the innermost context has it), key == value, key != value,
// !p, p && q, p || q, parentheses, and a > b (b's context inside one where a
// holds: "Workspace > Editor"). Evaluated against a context stack, root
// first: depth is the deepest prefix of the stack it holds for (0: none,
// the binding does not apply), the innermost context there the one an
// identifier is looked up in. A binding with no predicate holds at depth
// 0's level everywhere (Keymap: below any context's).
enum ContextPredicate {
	Identifier(name:String);
	Equal(key:String, value:String);
	NotEqual(key:String, value:String);
	Not(p:ContextPredicate);
	And(a:ContextPredicate, b:ContextPredicate);
	Or(a:ContextPredicate, b:ContextPredicate);
	Child(outer:ContextPredicate, inner:ContextPredicate);
}

class Predicates {
	public static function parse(s:String):ContextPredicate {
		var p = new Parser(s);
		var r = p.or();
		p.skip();
		if (p.at < s.length) throw "helder.ui: unexpected " + s.substr(p.at) + " in context " + s;
		return r;
	}

	// whether it holds for the stack's first n contexts (the nth innermost)
	public static function eval(p:ContextPredicate, stack:Array<KeyContext>, n:Int):Bool {
		if (n <= 0) return false;
		var c = stack[n - 1];
		return switch p {
			case Identifier(id): c.has(id) || c.values.exists(id);
			case Equal(k, v): c.get(k) == v;
			case NotEqual(k, v): c.get(k) != v;
			case Not(q): !eval(q, stack, n);
			case And(a, b): eval(a, stack, n) && eval(b, stack, n);
			case Or(a, b): eval(a, stack, n) || eval(b, stack, n);
			case Child(outer, inner):
				if (!eval(inner, stack, n)) return false;
				for (i in 1...n)
					if (eval(outer, stack, i)) return true;
				false;
		}
	}

	// the deepest prefix of the stack it holds for (0: none)
	public static function depth(p:ContextPredicate, stack:Array<KeyContext>):Int {
		var n = stack.length;
		while (n > 0) {
			if (eval(p, stack, n)) return n;
			n--;
		}
		return 0;
	}
}

private class Parser {
	final s:String;

	public var at = 0;

	public function new(s:String)
		this.s = s;

	public function skip()
		while (at < s.length && StringTools.isSpace(s, at))
			at++;

	function eat(t:String):Bool {
		skip();
		if (s.substr(at, t.length) != t) return false;
		at += t.length;
		return true;
	}

	public function or():ContextPredicate {
		var l = and();
		while (eat("||"))
			l = Or(l, and());
		return l;
	}

	function and():ContextPredicate {
		var l = child();
		while (eat("&&"))
			l = And(l, child());
		return l;
	}

	function child():ContextPredicate {
		var l = unary();
		while (eat(">"))
			l = Child(l, unary());
		return l;
	}

	function unary():ContextPredicate {
		if (eat("!")) return Not(unary());
		if (eat("(")) {
			var r = or();
			if (!eat(")")) throw "helder.ui: ) expected in context " + s;
			return r;
		}
		var id = ident();
		if (eat("==")) return Equal(id, ident());
		if (eat("!=")) return NotEqual(id, ident());
		return Identifier(id);
	}

	function ident():String {
		skip();
		var start = at;
		while (at < s.length) {
			var c = s.charCodeAt(at);
			if (!(c >= "a".code && c <= "z".code || c >= "A".code && c <= "Z".code || c >= "0".code && c <= "9".code || c == "_".code
				|| c == ".".code || c == ":".code || c == "-".code)) break;
			at++;
		}
		if (at == start) throw "helder.ui: a name expected at " + s.substr(start) + " in context " + s;
		return s.substring(start, at);
	}
}
