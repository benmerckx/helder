package helder.web;

enum abstract HtmlKind(Int) {
	var Element;
	var Text;
	var Comment;
	// the end of a region or list (a pair of comments, its start in open)
	var Marker;
	// a fragment's top: its children only
	var Root;
}

// The static renderer's nodes: elements, texts and comments in a plain tree,
// written out as HTML (toHtml) once a page is rendered.
//
// What hydration reads back (DomRenderer.hydrate): a region's or a list's
// marker is a pair of comments, <!--[--> before its content and <!--]-->
// (the marker itself) after it; adjacent texts are separated by <!---->, so
// that the parser keeps them apart; an empty text is <!--#-->, which the
// parser would otherwise lose.
class HtmlNode {
	public final kind:HtmlKind;
	// an element's name (svg:a written a), a marker's name
	public final tag:String;
	// a text's text; an element's raw content (innerHTML), when set
	public var text:Null<String>;
	public var parent:Null<HtmlNode>;
	public final children:Array<HtmlNode> = [];
	// a marker's start, put before it
	public var open:Null<HtmlNode>;
	// attributes, in the order they were first set (name, value: null when removed)
	final names:Array<String> = [];
	final values:Array<Null<String>> = [];

	public function new(kind:HtmlKind, tag:String) {
		this.kind = kind;
		this.tag = tag;
	}

	public function setAttribute(name:String, value:Null<String>) {
		var i = names.indexOf(name);
		if (i >= 0) values[i] = value else if (value != null) {
			names.push(name);
			values.push(value);
		}
	}

	public function getAttribute(name:String):Null<String> {
		var i = names.indexOf(name);
		return i < 0 ? null : values[i];
	}

	public function insertBefore(node:HtmlNode, before:Null<HtmlNode>) {
		if (node.parent != null) node.parent.children.remove(node);
		var i = before == null ? -1 : children.indexOf(before);
		if (i < 0) children.push(node) else children.insert(i, node);
		node.parent = this;
	}

	public function removeChild(node:HtmlNode) {
		children.remove(node);
		node.parent = null;
	}

	// the node as HTML
	public function toHtml():String {
		var b = new StringBuf();
		write(b);
		return b.toString();
	}

	// its children as HTML
	public function innerHtml():String {
		var b = new StringBuf();
		writeChildren(b);
		return b.toString();
	}

	public function write(b:StringBuf) {
		switch kind {
			case Text:
				var t:String = text;
				if (parent != null && parent.kind == Element && RAW.exists(parent.tag))
					b.add(parent.tag == "script" ? StringTools.replace(t, "</", "<\\/") : parent.tag == "style" ? t : Html.escapeText(t));
				else b.add(t == "" ? "<!--#-->" : Html.escapeText(t));
			case Comment:
				b.add("<!--");
				b.add(text);
				b.add("-->");
			case Marker:
				b.add("<!--]-->");
			case Root:
				writeChildren(b);
			case Element:
				var name = Html.localName(tag);
				b.add("<");
				b.add(name);
				for (i in 0...names.length) {
					var v = values[i];
					if (v == null) continue;
					b.add(" ");
					b.add(names[i]);
					if (v != "" || !Html.BOOLEAN.exists(names[i])) {
						b.add('="');
						b.add(Html.escapeAttribute(v));
						b.add('"');
					}
				}
				b.add(">");
				if (Html.VOID.exists(name)) return;
				// (the parser drops a newline that starts a pre's or a textarea's content)
				if ((name == "pre" || name == "textarea" || name == "listing") && startsWithNewline()) b.add("\n");
				if (text != null) b.add(text) else writeChildren(b);
				b.add("</");
				b.add(name);
				b.add(">");
		}
	}

	function writeChildren(b:StringBuf) {
		var afterText = false, raw = kind == Element && RAW.exists(tag);
		for (c in children) {
			if (raw) {
				c.write(b);
				continue;
			}
			var isText = c.kind == Text && c.text != "";
			if (isText && afterText) b.add("<!---->");
			c.write(b);
			afterText = isText;
		}
	}

	function startsWithNewline():Bool {
		if (text != null) return StringTools.startsWith(text, "\n");
		var first = children[0];
		return first != null && first.kind == Text && StringTools.startsWith(first.text, "\n");
	}

	// elements whose content is text only, which the parser takes as one text
	// (no separators, no comments): script and style as they are (a script's
	// </ written <\/), textarea and title escaped
	static final RAW = ["script" => true, "style" => true, "textarea" => true, "title" => true];

	public function toString():String
		return toHtml();
}
