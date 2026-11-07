package helder.syntax;

// The concrete syntax tree of a source file (helder.syntax): every byte in
// a node, whitespace and comments too (Trivia), so the file printed from
// its leaves is the file read (Document.print). Code is tokens and bracket
// groups ((), [], {}), strings with their substitutions; markup (TSX, Haxe
// markup) is elements of tags, attributes, text and {holes} of code.
// Offsets are indices of the file's String (Document converts them to the
// UTF-8 bytes of helder.view.Source and back), end exclusive.
enum abstract Kind(Int) {
	var File;
	// whitespace and comments
	var Trivia;
	var Ident;
	var Num;
	// a string without substitutions: "...", '...' (TypeScript's; Haxe's double-quoted), a markup attribute's
	var Str;
	var Punct;
	var Regex;
	// (...), [...], {...}: its opening Punct, its items, its closing Punct
	var Group;
	// `...` (TypeScript), '...' (Haxe): Chunks of text and Substs
	var Template;
	var Chunk;
	// ${...}: its "${" Punct, its items, its "}" Punct
	var Subst;
	// <name ...>...</name>, <name .../>, <>...</>: its OpenTag, its content (Text, Hole, Element), its CloseTag
	var Element;
	// "<", the TagName, its attributes (Attr, Spread) and Trivia, ">" or "/>"
	var OpenTag;
	// "</", the TagName, ">"
	var CloseTag;
	var TagName;
	// name, name="text", name={code}: its Ident name, "=", its value (Str or Hole)
	var Attr;
	// {...code}
	var Spread;
	// markup's text between tags
	var Text;
	// {code} in markup: its "{" Punct, its items, its "}" Punct
	var Hole;
}

class Node {
	public final kind:Kind;
	public var start:Int;
	public var end:Int;
	// (a token's: none)
	public final children:Null<Array<Node>>;
	public var parent:Null<Node> = null;

	public function new(kind:Kind, start:Int, end:Int, ?children:Array<Node>) {
		this.kind = kind;
		this.start = start;
		this.end = end;
		this.children = children;
		if (children != null)
			for (c in children)
				c.parent = this;
	}

	public inline function isToken():Bool
		return children == null;

	// (a token's text is the document's text between start and end)
	public function text(source:String):String
		return source.substring(start, end);

	// its children but Trivia
	public function significant():Array<Node>
		return children == null ? [] : [for (c in children) if (c.kind != Trivia) c];

	// the first child of that kind (null: none)
	public function first(kind:Kind):Null<Node> {
		if (children != null)
			for (c in children)
				if (c.kind == kind) return c;
		return null;
	}

	// every node below (this one first), depth first
	public function walk(f:Node->Void) {
		f(this);
		if (children != null)
			for (c in children)
				c.walk(f);
	}

	public function toString():String
		return '$kind@$start-$end';
}
