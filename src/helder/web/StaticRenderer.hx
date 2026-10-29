package helder.web;

import helder.web.HtmlNode;

// helder.view's renderer for static HTML (HtmlNode names it: @:rendered;
// Static.render's and Static.document's content): pages rendered at build time, natively or on Eval (or in
// node), written out once (Static.render). Listeners are dropped, effects
// run once. Attributes follow Html's rules, as the DOM renderer's do, so
// that a page hydrates into the same nodes: a region's marker is a pair of
// comments (HtmlNode). Elements hold no text of their own: text is text
// nodes, as in the DOM.
@:events(helder.web.DomEvents)
class StaticRenderer implements helder.view.Renders<HtmlNode> {
	public static inline function createElement(tag:String):HtmlNode
		return new HtmlNode(Element, tag);

	public static function createText(text:String):HtmlNode {
		var n = new HtmlNode(Text, "#text");
		n.text = text;
		return n;
	}

	// (the end of a pair; its start goes in with it)
	public static function createMarker(name:String):HtmlNode {
		var n = new HtmlNode(Marker, name);
		n.open = new HtmlNode(Comment, "#comment");
		n.open.text = "[";
		return n;
	}

	public static inline function setText(node:HtmlNode, text:String)
		node.text = text;

	public static inline function holdsText(el:HtmlNode):Bool
		return false;

	public static function setProperty(el:HtmlNode, name:String, value:Dynamic) {
		switch name {
			case "innerHTML":
				el.text = value == null ? "" : Std.string(value);
			case "textContent":
				el.text = Html.escapeText(value == null ? "" : Std.string(value));
			case "value" if (el.tag == "textarea"):
				el.text = Html.escapeText(value == null ? "" : Std.string(value));
			case _:
				var n = Html.attributeName(name);
				el.setAttribute(n, Html.attributeValue(n, value));
		}
	}

	public static function setStyle(el:HtmlNode, value:Dynamic) {
		var s = Html.style(value);
		el.setAttribute("style", s == "" ? null : s);
	}

	public static inline function listen(el:HtmlNode, name:String, handler:Dynamic) {}

	public static function insert(parent:HtmlNode, node:HtmlNode, before:Null<HtmlNode>) {
		if (node.open != null) parent.insertBefore(node.open, before);
		parent.insertBefore(node, before);
	}

	public static function remove(parent:HtmlNode, node:HtmlNode) {
		if (node.open != null && node.open.parent == parent) parent.removeChild(node.open);
		parent.removeChild(node);
	}

	public static inline function parentOf(node:HtmlNode):Null<HtmlNode>
		return node.parent;

	public static function arrange(parent:HtmlNode, nodes:Array<HtmlNode>, before:HtmlNode)
		for (n in nodes)
			insert(parent, n, before);

	// (a region that ends its parent marked too: hydration reads the markers)
	public static function markEnds() {}

	public static inline function isNode(v:Dynamic):Bool
		return Std.isOfType(v, HtmlNode);
}
