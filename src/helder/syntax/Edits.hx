package helder.syntax;

import helder.syntax.Cst;
import helder.syntax.Document;
import helder.syntax.Scanner;
import helder.syntax.Transaction;

// An attribute's value as written: name="text", name={code}, a flag (name)
enum AttrValue {
	AString(s:String);
	ACode(code:String);
	AFlag;
}

// The structured edits of a Document (helder.syntax): each a Transaction
// against its text that changes only the region edited, written in the
// file's style (its indentation step, tabs or spaces; an element's
// attributes on one line or one a line, an object's fields the same; its
// line endings), with its inverse (tx.inverse). Markup: an attribute set,
// added or removed; a child inserted, an element moved or deleted, wrapped
// in an element or unwrapped; a component renamed. Code: a literal changed,
// a definition's object field set or removed. A node it cannot edit (a
// document that does not read structurally, an element in a hole's code
// moved into its own) is a SourceError.
class Edits {
	// ---- attributes

	// name set to value: the attribute's value replaced, or the attribute
	// added after the last (on a line of its own when they are one a line)
	public static function setAttribute(doc:Document, el:Element, name:String, value:AttrValue):Transaction {
		check(doc, el.doc);
		var a = el.attr(name);
		var written = attribute(doc, name, value);
		if (a != null) return tx(doc, [new Change(a.node.start, a.node.end, written)]);
		var attrs = el.attrs();
		var tag = el.open.first(TagName);
		if (tag == null) throw new SourceError("helder.syntax: a fragment has no attributes");
		if (attrs.length == 0) return tx(doc, [new Change(tag.end, tag.end, " " + written)]);
		var last = attrs[attrs.length - 1].node;
		var lined = attrs.length > 1 ? doc.firstOnLine(last.start) && doc.lineStart(last.start) != doc.lineStart(attrs[attrs.length - 2].node.start) : doc.firstOnLine(last.start);
		var sep = lined ? doc.newline() + doc.indentOf(last.start) : " ";
		return tx(doc, [new Change(last.end, last.end, sep + written)]);
	}

	// the attribute named name removed, with the space before it (none: no change)
	public static function removeAttribute(doc:Document, el:Element, name:String):Transaction {
		check(doc, el.doc);
		var a = el.attr(name);
		if (a == null) return tx(doc, []);
		var from = a.node.start;
		var kids = el.open.children, k = kids.indexOf(a.node);
		if (k > 0 && kids[k - 1].kind == Trivia) from = kids[k - 1].start;
		return tx(doc, [new Change(from, a.node.end, "")]);
	}

	// an attribute as written: name="text" (text with a double quote: name={"text"}), name={code}, name
	public static function attribute(doc:Document, name:String, value:AttrValue):String
		return switch value {
			case AString(s) if (s.indexOf('"') < 0 && s.indexOf("\n") < 0 && (doc.lang == Haxe || s.indexOf("{") < 0)): name + '="' + s + '"';
			case AString(s): name + "={" + quote(doc, s, '"') + "}";
			case ACode(code): name + "={" + code + "}";
			case AFlag: name;
		}

	// ---- elements

	// a component (or a tag) renamed: its opening and closing tags
	public static function rename(doc:Document, el:Element, name:String):Transaction {
		check(doc, el.doc);
		var changes = [];
		var t = el.open.first(TagName);
		if (t == null) throw new SourceError("helder.syntax: a fragment has no name");
		changes.push(new Change(t.start, t.end, name));
		if (el.close != null) {
			var c = el.close.first(TagName);
			if (c != null) changes.push(new Change(c.start, c.end, name));
		}
		return tx(doc, changes);
	}

	// a component renamed in its file: its function's name, each element of
	// it (both tags), each name of it in code (not a field of something
	// else's: x.Name; not in strings or comments)
	public static function renameComponent(doc:Document, from:String, to:String):Transaction {
		var changes = [];
		doc.root.walk(n -> {
			if ((n.kind == TagName || n.kind == Ident) && n.text(doc.text) == from && !afterDot(doc, n)) changes.push(new Change(n.start, n.end, to));
		});
		return tx(doc, changes);
	}

	static function afterDot(doc:Document, n:Node):Bool {
		var p = n.parent == null ? null : n.parent.children;
		if (p == null) return false;
		var k = p.indexOf(n) - 1;
		while (k >= 0 && p[k].kind == Trivia)
			k--;
		return k >= 0 && p[k].kind == Punct && p[k].text(doc.text) == ".";
	}

	// markup inserted as parent's child at index (of its children: elements,
	// holes, text that is not whitespace), on a line of its own when they are
	// (its lines indented as theirs); a self-closing parent opened
	public static function insertChild(doc:Document, parent:Element, index:Int, markup:String):Transaction {
		check(doc, parent.doc);
		return tx(doc, [insertion(doc, parent, index, markup, null)]);
	}

	// an element deleted, with its line when it is alone on it
	public static function delete(doc:Document, el:Element):Transaction {
		check(doc, el.doc);
		return tx(doc, [deletion(doc, el)]);
	}

	// an element moved to be parent's child at index (counted as before the move), indented as its new siblings
	public static function move(doc:Document, el:Element, parent:Element, index:Int):Transaction {
		check(doc, el.doc);
		check(doc, parent.doc);
		if (parent.start >= el.start && parent.end <= el.end) throw new SourceError("helder.syntax: an element moved into itself");
		var del = deletion(doc, el);
		var ins = insertion(doc, parent, index, el.source(), el);
		if (ins.start > del.start && ins.start < del.end) throw new SourceError("helder.syntax: an element moved into the place it leaves");
		return tx(doc, [del, ins]);
	}

	// an element wrapped in <tag attrs>...</tag> (on lines of their own when it is alone on its line)
	public static function wrap(doc:Document, el:Element, tag:String, ?attrs:Array<{name:String, value:AttrValue}>):Transaction {
		check(doc, el.doc);
		var open = "<" + tag + [for (a in attrs ?? []) " " + attribute(doc, a.name, a.value)].join("") + ">", close = "</" + tag + ">";
		if (!block(doc, el)) return tx(doc, [new Change(el.start, el.end, open + el.source() + close)]);
		var nl = doc.newline(), indent = doc.indentOf(el.start), inner = indent + doc.indentUnit();
		return tx(doc, [new Change(el.start, el.end, open + nl + inner + reindent(el.source(), indent, inner, nl) + nl + indent + close)]);
	}

	// an element replaced by its content (its lines indented as it was; a self-closing one deleted)
	public static function unwrap(doc:Document, el:Element):Transaction {
		check(doc, el.doc);
		if (el.close == null) return delete(doc, el);
		// (a literal's root of other than one element: a fragment of its content, the code around it one expression still)
		var kids = el.children();
		if (el.parent() == null && (kids.length != 1 || kids[0].kind != Element))
			return tx(doc, [new Change(el.open.start, el.open.end, "<>"), new Change(el.close.start, el.close.end, "</>")]);
		var from = el.open.end, to = el.close.start;
		var inner = doc.text.substring(from, to);
		var nl = doc.newline();
		if (inner.indexOf("\n") < 0) return tx(doc, [new Change(el.start, el.end, inner)]);
		// (block content: its first and last line breaks dropped, a step of indentation less)
		if (kids.length == 0) return delete(doc, el);
		var first = kids[0].start, last = kids[kids.length - 1].end;
		var indent = doc.indentOf(el.start), own = doc.indentOf(first);
		var body = doc.text.substring(first, last);
		return tx(doc, [new Change(el.start, el.end, reindent(body, own, indent, nl))]);
	}

	// ---- code

	// the literal at offset (a string, a number, true, false, null: a token
	// literalAt finds) set to value, written as the language does (a
	// string in the quotes it had)
	public static function setLiteral(doc:Document, offset:Int, value:Dynamic):Transaction {
		var t = doc.literalAt(offset);
		if (t == null) throw new SourceError("helder.syntax: no literal at " + offset);
		return tx(doc, [literalChange(doc, t, value)]);
	}

	// a definition's field (callee({...}), its object: Document.definition) set to code: its value replaced, or
	// the field added (last, as the others are: on a line of its own, a trailing comma kept)
	public static function setField(doc:Document, obj:ObjectLit, key:String, code:String):Transaction {
		check(doc, obj.doc);
		var f = obj.field(key);
		if (f != null) return tx(doc, [new Change(f.first.start, f.last.end, code)]);
		var fields = obj.fields();
		var close = obj.node.children[obj.node.children.length - 1];
		var name = ~/^[A-Za-z_$][A-Za-z0-9_$]*$/.match(key) ? key : quote(doc, key, '"');
		var entry = name + ": " + code;
		if (fields.length == 0) return tx(doc, [new Change(obj.node.start + 1, close.start, obj.multiline() ? doc.newline() + doc.indentOf(obj.node.start) + doc.indentUnit() + entry + doc.newline() + doc.indentOf(close.start) : entry)]);
		var last = fields[fields.length - 1];
		// (a comma after the last field: kept after the new one)
		var after = nextSignificant(obj.node, last.last);
		var trailing = after != null && after.kind == Punct && after.text(doc.text) == ",";
		if (obj.multiline()) {
			var sep = doc.newline() + doc.indentOf(last.start);
			return trailing ? tx(doc, [new Change(after.end, after.end, sep + entry + ",")]) : tx(doc, [new Change(last.end, last.end, "," + sep + entry)]);
		}
		return trailing ? tx(doc, [new Change(after.end, after.end, " " + entry + ",")]) : tx(doc, [new Change(last.end, last.end, ", " + entry)]);
	}

	// a field removed, with its comma and its line when it has one of its own
	public static function removeField(doc:Document, obj:ObjectLit, key:String):Transaction {
		check(doc, obj.doc);
		var f = obj.field(key);
		if (f == null) return tx(doc, []);
		var after = nextSignificant(obj.node, f.last);
		var end = after != null && after.kind == Punct && after.text(doc.text) == "," ? after.end : f.end;
		var start = f.start;
		if (doc.firstOnLine(start) && doc.lastOnLine(end)) {
			start = doc.lineStart(start);
			end = doc.lineEnd(end) + 1;
		} else if (end == f.end) {
			// (the last field: the comma before it goes)
			var fields = obj.fields(), k = fields.indexOf(Lambda.find(fields, x -> x.key == key));
			if (k > 0) {
				var comma = nextSignificant(obj.node, fields[k - 1].last);
				if (comma != null && comma.text(doc.text) == ",") start = comma.start;
			}
		} else {
			while (end < doc.text.length && doc.text.charAt(end) == " ")
				end++;
		}
		return tx(doc, [new Change(start, Std.int(Math.min(end, doc.text.length)), "")]);
	}

	// a literal written in the language: a string in quote (escaped), a number, a Bool, null
	public static function literal(doc:Document, value:Dynamic, quoteChar = '"'):String {
		if (value == null) return "null";
		if (Std.isOfType(value, Bool)) return value ? "true" : "false";
		if (Std.isOfType(value, String)) return quote(doc, value, quoteChar);
		if (Std.isOfType(value, Int)) return Std.string(value);
		var f:Float = value;
		var s = Std.string(f);
		return s;
	}

	public static function quote(doc:Document, s:String, q:String):String {
		var b = new StringBuf();
		b.add(q);
		for (k in 0...s.length) {
			var c = s.charAt(k);
			b.add(switch c {
				case "\\": "\\\\";
				case "\n": "\\n";
				case "\r": "\\r";
				case "\t": "\\t";
				case "$" if (doc.lang == Haxe && q == "'"): "$$";
				case "$" if (q == "`" && s.charAt(k + 1) == "{"): "\\$";
				case _ if (c == q): "\\" + c;
				case _: c;
			});
		}
		b.add(q);
		return b.toString();
	}

	// ---- helpers

	static function tx(doc:Document, changes:Array<Change>):Transaction {
		if (!doc.structured) throw new SourceError("helder.syntax: can't edit structurally: " + doc.error);
		return new Transaction(changes, null, doc.text);
	}

	static function check(doc:Document, of:Document)
		if (doc != of) throw new SourceError("helder.syntax: a node of another document (read it again from this one)");

	static function literalChange(doc:Document, t:Node, value:Dynamic):Change {
		var old = t.text(doc.text);
		var q = old.charAt(0);
		var written = literal(doc, value, q == "'" || q == '"' || q == "`" ? q : '"');
		var start = t.start;
		// (a negative number written with a sign before: the sign replaced too)
		var p = t.parent == null ? null : t.parent.children;
		if (p != null && t.kind == Num) {
			var k = p.indexOf(t) - 1;
			while (k >= 0 && p[k].kind == Trivia)
				k--;
			if (k >= 0 && p[k].kind == Punct && p[k].text(doc.text) == "-" && unary(doc, p, k)) start = p[k].start;
		}
		return new Change(start, t.end, written);
	}

	// (the "-" at p[k] is a sign: after an operator, an opening bracket, or nothing)
	static function unary(doc:Document, p:Array<Node>, k:Int):Bool {
		var j = k - 1;
		while (j >= 0 && p[j].kind == Trivia)
			j--;
		return j < 0 || p[j].kind == Punct;
	}

	static function nextSignificant(group:Node, after:Node):Null<Node> {
		var k = group.children.indexOf(after) + 1;
		while (k < group.children.length && group.children[k].kind == Trivia)
			k++;
		return k < group.children.length ? group.children[k] : null;
	}

	// whether an element is alone on its lines
	static function block(doc:Document, el:Element):Bool
		return doc.firstOnLine(el.start) && doc.lastOnLine(el.end);

	// text's lines after its first: from (their indentation's start) to, others as they are
	static function reindent(text:String, from:String, to:String, nl:String):String {
		var lines = text.split("\n");
		for (k in 1...lines.length)
			if (StringTools.startsWith(lines[k], from)) lines[k] = to + lines[k].substr(from.length);
		return lines.join("\n");
	}

	// (deleting an element: its line too when it is alone on it)
	static function deletion(doc:Document, el:Element):Change {
		if (block(doc, el)) {
			var s = doc.lineStart(el.start);
			// (from the line break before it: the next line stays where it is)
			if (s > 0) return new Change(s - 1 - (s > 1 && doc.text.charAt(s - 2) == "\r" ? 1 : 0), doc.lineEnd(el.end), "");
			return new Change(s, Std.int(Math.min(doc.lineEnd(el.end) + 1, doc.text.length)), "");
		}
		return new Change(el.start, el.end, "");
	}

	// (markup as parent's child at index: moved from moving, reindented from its indentation)
	static function insertion(doc:Document, parent:Element, index:Int, markup:String, moving:Null<Element>):Change {
		var nl = doc.newline();
		var kids = [for (k in parent.children()) if (moving == null || k != moving.node) k];
		// (index counted as before the move)
		if (moving != null) {
			var all = parent.children(), at = all.indexOf(moving.node);
			if (at >= 0 && at < index) index--;
		}
		if (index < 0 || index > kids.length) throw new SourceError("helder.syntax: no child " + index + " of " + parent);
		var from = moving == null ? "" : doc.indentOf(moving.start);
		var parentIndent = doc.indentOf(parent.start);
		if (parent.close == null) {
			// (<tag .../>: <tag ...>, the child on a line of its own, </tag>)
			var slash = parent.open.children[parent.open.children.length - 1];
			var k = parent.open.children.length - 2, from2 = slash.start;
			if (k >= 0 && parent.open.children[k].kind == Trivia) from2 = parent.open.children[k].start;
			var inner = parentIndent + doc.indentUnit();
			return new Change(from2, slash.end, ">" + nl + inner + reindent(markup, from, inner, nl) + nl + parentIndent + "</" + parent.name + ">");
		}
		var blockContent = doc.text.substring(parent.open.end, parent.close.start).indexOf("\n") >= 0;
		if (kids.length == 0) {
			if (!blockContent) return new Change(parent.open.end, parent.open.end, markup);
			var inner = parentIndent + doc.indentUnit();
			return new Change(parent.open.end, parent.open.end, nl + inner + reindent(markup, from, inner, nl));
		}
		if (index < kids.length) {
			var anchor = kids[index];
			if (blockContent && doc.firstOnLine(anchor.start)) {
				var indent = doc.indentOf(anchor.start);
				return new Change(anchor.start, anchor.start, reindent(markup, from, indent, nl) + nl + indent);
			}
			return new Change(anchor.start, anchor.start, reindent(markup, from, doc.indentOf(anchor.start), nl));
		}
		var last = kids[kids.length - 1];
		if (blockContent && doc.firstOnLine(last.start)) {
			var indent = doc.indentOf(last.start);
			return new Change(last.end, last.end, nl + indent + reindent(markup, from, indent, nl));
		}
		return new Change(last.end, last.end, reindent(markup, from, doc.indentOf(last.start), nl));
	}
}
