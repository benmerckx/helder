package helder.syntax;

import helder.syntax.Cst;
import helder.syntax.Scanner;
import helder.syntax.Transaction;

// A source file read from its text alone (helder.syntax: no compiler, so
// the studio reads it again on every edit): its concrete syntax tree, the
// markup elements in it, its calls and object literals (definitions:
// shader({...}), story({...})), and the edits made on them (Edits), each a
// Transaction that apply makes the next Document of.
//
//   var doc = Document.parse(text, Lang.of(path));
//   var el = doc.elementAtByte(source.start);      // a node's helder.view.Source
//   var tx = Edits.setAttribute(doc, el, "padding", ACode("16"));
//   var next = doc.apply(tx);                       // next.text: only that attribute changed
//   var back = next.apply(tx.inverse);              // the text before, byte for byte
class Document {
	public final text:String;
	public final lang:Lang;
	public final root:Node;
	// false: brackets that do not balance (Haxe's #if branches, a file being
	// typed): read as tokens only, no markup or groups to edit (error: why)
	public final structured:Bool;
	public final error:Null<String>;
	// where a "<" that could start markup read as code instead (Scanner's)
	public final backtracks:Array<Int>;

	var elementList:Null<Array<Element>> = null;
	var lineStarts:Null<Array<Int>> = null;
	var bytes:Null<Array<Int>> = null;

	public function new(text:String, lang:Lang) {
		this.text = text;
		this.lang = lang;
		var r = Scanner.read(text, lang);
		root = r.root;
		error = r.error;
		backtracks = r.backtracks;
		structured = r.error == null;
	}

	public static inline function parse(text:String, lang:Lang):Document
		return new Document(text, lang);

	// the file printed from its tree's leaves (the text read, byte for byte)
	public function print():String {
		var b = new StringBuf();
		function leaves(n:Node) {
			if (n.children == null) b.addSub(text, n.start, n.end - n.start);
			else {
				// (a node's bytes between its children's: none, when the tree is whole)
				var at = n.start;
				for (c in n.children) {
					if (c.start != at) throw new SourceError("helder.syntax: a gap in the tree at " + at + " (" + n + ")");
					leaves(c);
					at = c.end;
				}
				if (at != n.end) throw new SourceError("helder.syntax: a gap in the tree at " + at + " (" + n + ")");
			}
		}
		leaves(root);
		return b.toString();
	}

	// the document after tx (made against this one)
	public function apply(tx:Transaction):Document
		return new Document(tx.apply(text), lang);

	// ---- markup

	// every element, in source order (an element before its children)
	public function elements():Array<Element> {
		if (elementList == null) {
			elementList = [];
			root.walk(n -> if (n.kind == Element) elementList.push(new Element(this, n)));
		}
		return elementList;
	}

	// the element starting at offset (its "<"; null: none)
	public function elementAt(offset:Int):Null<Element> {
		for (e in elements())
			if (e.node.start == offset) return e;
		return null;
	}

	// the innermost element holding offset (null: none)
	public function elementHolding(offset:Int):Null<Element> {
		var best:Null<Element> = null;
		for (e in elements())
			if (e.node.start <= offset && offset < e.node.end) best = e;
		return best;
	}

	// the element a helder.view.Source's start (bytes of the file) names
	public inline function elementAtByte(byte:Int):Null<Element>
		return elementAt(fromByte(byte));

	// the elements named name (a tag, or a component), in source order
	public function elementsNamed(name:String):Array<Element>
		return [for (e in elements()) if (e.name == name) e];

	// the first element with an attribute name="value", or name={value} written so (tag="draft")
	public function elementWith(attr:String, value:String):Null<Element> {
		for (e in elements()) {
			var a = e.attr(attr);
			if (a != null && a.valueText() == value) return e;
		}
		return null;
	}

	// ---- code

	// the calls of callee (a name, or a dotted path): callee(args)
	public function calls(callee:String):Array<Call> {
		var out = [];
		var parts = callee.split(".");
		function scan(n:Node) {
			if (n.children == null) return;
			var sig = [for (c in n.children) if (c.kind != Trivia) c];
			for (k in 0...sig.length) {
				var g = sig[k];
				if (g.kind == Group && text.charAt(g.start) == "(" && k >= parts.length * 2 - 1) {
					var ok = true;
					for (p in 0...parts.length) {
						var id = sig[k - 1 - (parts.length - 1 - p) * 2];
						if (id.kind != Ident || id.text(text) != parts[p]) ok = false;
						if (p > 0 && (sig[k - (parts.length - p) * 2].kind != Punct || sig[k - (parts.length - p) * 2].text(text) != ".")) ok = false;
					}
					// (not a member's call of the same name: x.story(...))
					var before = k - parts.length * 2;
					if (ok && before >= 0 && sig[before].kind == Punct && sig[before].text(text) == ".") ok = false;
					if (ok) out.push(new Call(this, sig[k - 1 - (parts.length - 1) * 2], g, binding(sig, k - parts.length * 2 + 1)));
				}
			}
			for (c in n.children)
				scan(c);
		}
		scan(root);
		return out;
	}

	// (the name a call starting at sig[k] is bound to: const name = ..., final name = ..., var name:T = ..., name: ...)
	function binding(sig:Array<Node>, k:Int):Null<String> {
		var j = k - 1;
		if (j < 1 || sig[j].kind != Punct) return null;
		var p = sig[j].text(text);
		if (p == ":") return sig[j - 1].kind == Ident || sig[j - 1].kind == Str ? sig[j - 1].text(text) : null;
		if (p != "=") return null;
		var steps = 0;
		while (--j >= 1 && steps++ < 12) {
			if (sig[j].kind == Punct && [";", "=", ","].indexOf(sig[j].text(text)) >= 0) return null;
			if (sig[j].kind == Ident && sig[j - 1].kind == Ident && ["const", "let", "var", "final"].indexOf(sig[j - 1].text(text)) >= 0) return sig[j].text(text);
		}
		return null;
	}

	// the definition callee({...}) bound to name (null: the first one), its object
	public function definition(callee:String, ?name:String):Null<ObjectLit> {
		for (c in calls(callee))
			if (name == null || c.name == name) {
				var o = c.object(0);
				if (o != null) return o;
			}
		return null;
	}

	// the literal token at offset (a string, a number, true, false, null; null: none)
	public function literalAt(offset:Int):Null<Node> {
		var found:Null<Node> = null;
		root.walk(n -> if (found == null && (n.children == null || n.kind == Template) && n.start <= offset && offset < n.end && isLiteral(n)) found = n);
		return found;
	}

	public function isLiteral(n:Node):Bool
		return switch n.kind {
			case Num | Str: true;
			case Ident: ["true", "false", "null"].indexOf(n.text(text)) >= 0;
			case Template: n.children.length == 1;
			case _: false;
		}

	// ---- lines and offsets

	// the start of the line offset is on
	public function lineStart(offset:Int):Int {
		var k = offset;
		while (k > 0 && StringTools.fastCodeAt(text, k - 1) != "\n".code)
			k--;
		return k;
	}

	// the end of the line offset is on (its "\n", or the text's end)
	public function lineEnd(offset:Int):Int {
		var k = text.indexOf("\n", offset);
		return k < 0 ? text.length : k;
	}

	// the whitespace that starts offset's line
	public function indentOf(offset:Int):String {
		var s = lineStart(offset), k = s;
		while (k < text.length && (text.charAt(k) == " " || text.charAt(k) == "\t"))
			k++;
		return text.substring(s, k);
	}

	// whether only whitespace is before offset on its line
	public function firstOnLine(offset:Int):Bool
		return StringTools.trim(text.substring(lineStart(offset), offset)) == "";

	// whether only whitespace (or a line comment) is after end on its line
	public function lastOnLine(end:Int):Bool {
		var rest = StringTools.trim(text.substring(end, lineEnd(end)));
		return rest == "" || StringTools.startsWith(rest, "//");
	}

	// the file's step of indentation: a tab, or the smallest step of spaces between lines (two by default)
	public function indentUnit():String {
		var tabs = 0, spaces = 0, step = 0, last = 0;
		for (line in text.split("\n")) {
			if (StringTools.trim(line) == "") continue;
			if (StringTools.startsWith(line, "\t")) {
				tabs++;
				continue;
			}
			var k = 0;
			while (k < line.length && line.charAt(k) == " ")
				k++;
			if (k > 0) spaces++;
			var d = k - last;
			if (d > 0 && (step == 0 || d < step)) step = d;
			last = k;
		}
		return tabs >= spaces ? "\t" : StringTools.lpad("", " ", step == 0 ? 2 : step);
	}

	// the line ending the file uses
	public function newline():String
		return text.indexOf("\r\n") >= 0 ? "\r\n" : "\n";

	// 1-based line and column (in Strings' units) of an offset
	public function lineCol(offset:Int):{line:Int, col:Int} {
		if (lineStarts == null) {
			lineStarts = [0];
			for (k in 0...text.length)
				if (StringTools.fastCodeAt(text, k) == "\n".code) lineStarts.push(k + 1);
		}
		var lo = 0, hi = lineStarts.length - 1;
		while (lo < hi) {
			var mid = (lo + hi + 1) >> 1;
			if (lineStarts[mid] <= offset) lo = mid else hi = mid - 1;
		}
		return {line: lo + 1, col: offset - lineStarts[lo] + 1};
	}

	// an offset as bytes of the file's UTF-8 text (helder.view.Source's), and back
	public function toByte(offset:Int):Int {
		var b = byteTable();
		return b == null ? offset : b[offset];
	}

	public function fromByte(byte:Int):Int {
		var b = byteTable();
		if (b == null) return byte;
		var lo = 0, hi = b.length - 1;
		while (lo < hi) {
			var mid = (lo + hi) >> 1;
			if (b[mid] < byte) lo = mid + 1 else hi = mid;
		}
		return lo;
	}

	// (each offset's byte, null when the text is ASCII: the same; a UTF-16
	// target's surrogate pair's four bytes on its first unit, a code point target's on its one)
	function byteTable():Null<Array<Int>> {
		if (bytes != null) return bytes;
		var ascii = true;
		for (k in 0...text.length)
			if (StringTools.fastCodeAt(text, k) >= 0x80) {
				ascii = false;
				break;
			}
		if (ascii) return null;
		bytes = [];
		var at = 0;
		for (k in 0...text.length) {
			bytes.push(at);
			var c = StringTools.fastCodeAt(text, k);
			at += c < 0x80 ? 1 : c < 0x800 ? 2 : c >= 0xD800 && c < 0xDC00 ? 4 : c >= 0xDC00 && c < 0xE000 ? 0 : c > 0xFFFF ? 4 : 3;
		}
		bytes.push(at);
		return bytes;
	}
}

// A markup element (TSX, Haxe markup): its tag's name, attributes and content
class Element {
	public final doc:Document;
	public final node:Node;
	public final open:Node;
	public final close:Null<Node>;
	// (a fragment's: "")
	public final name:String;

	public function new(doc:Document, node:Node) {
		this.doc = doc;
		this.node = node;
		open = node.children[0];
		var last = node.children[node.children.length - 1];
		close = last.kind == CloseTag ? last : null;
		var t = open.first(TagName);
		name = t == null ? "" : t.text(doc.text);
	}

	public var start(get, never):Int;
	public var end(get, never):Int;

	inline function get_start()
		return node.start;

	inline function get_end()
		return node.end;

	public var selfClosing(get, never):Bool;

	function get_selfClosing()
		return close == null;

	public function attrs():Array<Attribute>
		return [for (c in open.children) if (c.kind == Attr || c.kind == Spread) new Attribute(doc, c)];

	// its attribute named name (null: none)
	public function attr(name:String):Null<Attribute> {
		for (a in attrs())
			if (a.name == name) return a;
		return null;
	}

	// its content: text, holes and elements, between its tags
	public function content():Array<Node>
		return close == null ? [] : node.children.slice(1, node.children.length - 1);

	// its children: elements and holes, and text that is not whitespace only
	public function children():Array<Node>
		return [
			for (c in content())
				if (c.kind != Text || StringTools.trim(c.text(doc.text)) != "") c
		];

	// its child elements
	public function elements():Array<Element>
		return [for (c in content()) if (c.kind == Element) new Element(doc, c)];

	// the element it is in (null: none)
	public function parent():Null<Element> {
		var p = node.parent;
		while (p != null && p.kind != Element)
			p = p.parent;
		// (an element in a hole's code: its own literal's root)
		return p == null || node.parent != p ? null : new Element(doc, p);
	}

	public function source():String
		return node.text(doc.text);

	public function toString():String
		return '<$name>@$start';
}

// An attribute: name, name="text", name={code}, or {...code}
class Attribute {
	public final doc:Document;
	public final node:Node;
	// ("...": a spread's)
	public final name:String;
	// its value: a Str, a Hole (null: a flag's)
	public final value:Null<Node>;

	public function new(doc:Document, node:Node) {
		this.doc = doc;
		this.node = node;
		if (node.kind == Spread) {
			name = "...";
			value = node;
		} else {
			name = node.children[0].text(doc.text);
			var last = node.children[node.children.length - 1];
			value = node.children.length > 1 ? last : null;
		}
	}

	// its value's text: a string's without quotes, a hole's code trimmed (null: a flag)
	public function valueText():Null<String> {
		if (value == null) return null;
		var t = value.text(doc.text);
		return value.kind == Str ? t.substring(1, t.length - 1) : StringTools.trim(t.substring(1, t.length - 1));
	}

	// the literal in its hole's code ({24}, {"#fff"}): its token (null: other code, or none)
	public function literal():Null<Node> {
		if (value == null || value.kind != Hole) return null;
		var sig = value.significant();
		return sig.length == 3 && doc.isLiteral(sig[1]) ? sig[1] : null;
	}
}

// A call: callee(args)
class Call {
	public final doc:Document;
	public final callee:Node;
	public final args:Node;
	// the name it is bound to (const name = callee(...)), else null
	public final name:Null<String>;

	public function new(doc:Document, callee:Node, args:Node, name:Null<String>) {
		this.doc = doc;
		this.callee = callee;
		this.args = args;
		this.name = name;
	}

	// its arguments' nodes, each its significant items
	public function arguments():Array<Array<Node>>
		return ObjectLit.split(doc, args);

	// its n-th argument when it is an object literal {...} (null: it is not)
	public function object(n:Int):Null<ObjectLit> {
		var a = arguments();
		if (n >= a.length || a[n].length != 1) return null;
		var g = a[n][0];
		return g.kind == Group && doc.text.charAt(g.start) == "{" ? new ObjectLit(doc, g) : null;
	}
}

// An object literal {key: value, ...} (a definition's)
class ObjectLit {
	public final doc:Document;
	public final node:Node;

	public function new(doc:Document, node:Node) {
		this.doc = doc;
		this.node = node;
	}

	// (a group's items between its brackets, split at its commas: each part's significant nodes)
	public static function split(doc:Document, g:Node):Array<Array<Node>> {
		var out:Array<Array<Node>> = [], cur:Array<Node> = [];
		var inner = g.children.slice(1, g.children.length - 1);
		for (c in inner) {
			if (c.kind == Trivia) continue;
			if (c.kind == Punct && c.text(doc.text) == ",") {
				out.push(cur);
				cur = [];
			} else cur.push(c);
		}
		if (cur.length > 0) out.push(cur);
		return out;
	}

	// its fields key: value (a spread, a method, a shorthand: not listed)
	public function fields():Array<Field> {
		var out = [];
		for (part in split(doc, node))
			if (part.length >= 3 && (part[0].kind == Ident || part[0].kind == Str) && part[1].kind == Punct && part[1].text(doc.text) == ":")
				out.push(new Field(doc, part));
		return out;
	}

	public function field(key:String):Null<Field> {
		for (f in fields())
			if (f.key == key) return f;
		return null;
	}

	// whether its fields are on lines of their own
	public function multiline():Bool {
		var fs = fields();
		return fs.length > 0 ? doc.firstOnLine(fs[0].start) : doc.text.substring(node.start, node.end).indexOf("\n") >= 0;
	}
}

// A field of an object literal: key: value
class Field {
	public final doc:Document;
	public final key:String;
	public final keyNode:Node;
	// its value's first and last nodes
	public final first:Node;
	public final last:Node;

	public function new(doc:Document, part:Array<Node>) {
		this.doc = doc;
		keyNode = part[0];
		var k = keyNode.text(doc.text);
		key = keyNode.kind == Str ? k.substring(1, k.length - 1) : k;
		first = part[2];
		last = part[part.length - 1];
	}

	public var start(get, never):Int;

	inline function get_start()
		return keyNode.start;

	public var end(get, never):Int;

	inline function get_end()
		return last.end;

	// its value's code
	public function value():String
		return doc.text.substring(first.start, last.end);

	// its value as an object literal (null: it is not one)
	public function object():Null<ObjectLit>
		return first == last && first.kind == Group && doc.text.charAt(first.start) == "{" ? new ObjectLit(doc, first) : null;

	// its value's literal token (null: other code)
	public function literal():Null<Node>
		return first == last && doc.isLiteral(first) ? first : null;
}
