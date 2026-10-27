package helder.web;

#if (js && !macro)
import helder.view.Reactive;
import helder.view.Render;
import js.Browser.document;
import js.html.Element;
import js.html.Node;
#end

#if (js || macro)

// helder.view's renderer for the DOM, in JavaScript (DomRenderer.render's
// content: a DOM Node, which no metadata of ours can name it on): each
// function the DOM call, a node a DOM Node.
//
//   DomRenderer.render(<App/>, document.getElementById("app"));
//
// Elements by tag (SVG's in its namespace: Html.SVG, or svg:a), texts,
// comments for markers; attributes by Html's rules (a few DOM properties,
// else attributes), the style as a string or an object, listeners added to
// the element (onClick: click; on:my-event: my-event). No delegation: each
// listener is the element's own, which keeps stopPropagation and the
// order of handlers the DOM's. The neutral elements (helder.ui's view, text,
// scroll, view:button...) as the DOM's, at compile time: NeutralMacro.
//
// Hydration (hydrate) is a mode of this renderer: the nodes of a page the
// static renderer wrote are claimed in document order instead of made.
class DomRenderer #if !macro implements helder.view.Renders<Node> #end {
	// the neutral elements, their attributes and events (NeutralMacro), and a part (ElementPart: made when a ref asks)
	public static macro function neutralElement(tag:haxe.macro.Expr):haxe.macro.Expr
		return helder.web.NeutralMacro.element(tag);

	public static macro function neutralProperty(el:haxe.macro.Expr, tag:haxe.macro.Expr, name:haxe.macro.Expr, v:haxe.macro.Expr):haxe.macro.Expr
		return helder.web.NeutralMacro.property(el, tag, name, v);

	public static macro function neutralSetter(tag:haxe.macro.Expr, name:haxe.macro.Expr):haxe.macro.Expr
		return helder.web.NeutralMacro.setter(tag, name);

	public static macro function neutralName(tag:haxe.macro.Expr, name:haxe.macro.Expr):haxe.macro.Expr
		return helder.web.NeutralMacro.name(tag, name);

	public static macro function neutralListen(el:haxe.macro.Expr, tag:haxe.macro.Expr, name:haxe.macro.Expr, h:haxe.macro.Expr):haxe.macro.Expr
		return helder.web.NeutralMacro.listen(el, tag, name, h);

	public static macro function part(el:haxe.macro.Expr):haxe.macro.Expr
		return macro helder.web.ElementPart.of($el);

	// renders content into a page's element (Render.render's, for a DOM node: js.html.Node names no renderer)
	public static macro function render(content:haxe.macro.Expr, parent:haxe.macro.Expr):haxe.macro.Expr
		return macro helder.view.Render.renderAs(helder.web.DomRenderer, $content, $parent);

	#if !macro
	// hydrating: what claims the page's nodes (null: making them)
	static var hydration:Null<Hydration> = null;

	public static function createElement(tag:String):Node {
		if (hydration != null) return hydration.element(tag);
		return Html.isSvgTag(tag) ? document.createElementNS(Html.SVG_NS, Html.localName(tag)) : document.createElement(tag);
	}

	public static function createText(text:String):Node {
		if (hydration != null) return hydration.text(text);
		return document.createTextNode(text);
	}

	public static function createMarker(name:String):Node {
		if (hydration != null) return hydration.marker();
		return document.createComment(name);
	}

	public static inline function setText(node:Node, text:String)
		node.nodeValue = text;

	public static inline function holdsText(el:Node):Bool
		return false;

	public static function setProperty(node:Node, name:String, v:Dynamic) {
		var el:Element = cast node;
		if (Html.PROPERTIES.exists(name) && el.namespaceURI != Html.SVG_NS) {
			var content = name == "innerHTML" || name == "textContent" || (name == "value" && el.localName == "textarea");
			// (content the page has already: its nodes not claimed, kept when the same)
			if (hydration != null && content) hydration.skip(el);
			var x:Dynamic = v == null ? (name == "checked" || name == "selected" || name == "muted" || name == "indeterminate" ? false : "") : v;
			if (name == "value" || content) x = Std.string(x);
			if (Reflect.field(el, name) != x) Reflect.setField(el, name, x);
			return;
		}
		var n = Html.attributeName(name);
		var s = Html.attributeValue(n, v);
		if (s == null) el.removeAttribute(n) else if (StringTools.startsWith(n, "xlink:")) el.setAttributeNS("http://www.w3.org/1999/xlink", n, s) else
			el.setAttribute(n, s);
	}

	public static function setStyle(node:Node, v:Dynamic) {
		var el:Element = cast node;
		var s = Html.style(v);
		if (s == "") el.removeAttribute("style") else if (el.getAttribute("style") != s) el.setAttribute("style", s);
	}

	public static function listen(node:Node, name:String, handler:Dynamic)
		if (handler != null) node.addEventListener(Html.eventName(name), handler);

	public static function insert(parent:Node, node:Node, before:Null<Node>) {
		// (hydrating: a claimed node is in its place already)
		if (hydration != null && node.parentNode == parent) return;
		parent.insertBefore(node, before);
	}

	public static inline function remove(parent:Node, node:Node)
		parent.removeChild(node);

	public static inline function parentOf(node:Node):Null<Node>
		return node.parentNode;

	// (from the last: only the nodes out of place moved)
	public static function arrange(parent:Node, nodes:Array<Node>, before:Node) {
		var next = before;
		var i = nodes.length;
		while (i-- > 0) {
			var n = nodes[i];
			if (n.nextSibling != next || n.parentNode != parent) parent.insertBefore(n, next);
			next = n;
		}
	}

	public static inline function isNode(v:Dynamic):Bool
		return Std.isOfType(v, Node);

	// Takes over parent's content, which the static renderer wrote for the
	// same content: the client's code runs as it would to render (listeners
	// added, effects run, values set again), each node it makes claimed from
	// the page in document order (an element of the same tag, a text, the end
	// of a comment pair for a marker) instead of made. When the page differs
	// (another element, nodes missing or left over) the content is rendered
	// again from scratch, with a warning in debug builds. Its dispose, as
	// Render.render's.
	public static function hydrate(content:Any, parent:Node):Void->Void {
		var h = new Hydration(parent);
		var dispose:Null<Void->Void> = null, error:Dynamic = null, failed = false;
		hydration = h;
		Reactive.root(d -> {
			dispose = d;
			try {
				var nodes = Render.insertAs(helder.web.DomRenderer, ([new HydrationEnd(h), content] : Array<Any>), parent, null);
				Reactive.onCleanup(() -> for (n in nodes)
					if (n.parentNode == parent) parent.removeChild(n));
			} catch (e:Mismatch) {
				failed = true;
			} catch (e:Dynamic) {
				error = e;
			}
		});
		hydration = null;
		if (error == null && !failed && h.failed == null) return dispose;
		dispose();
		if (error != null) throw error;
		#if debug
		js.Browser.console.warn("helder.web: hydration mismatch: " + h.failed + "; rendered again");
		#end
		while (parent.firstChild != null)
			parent.removeChild(parent.firstChild);
		return Render.renderAs(helder.web.DomRenderer, content, parent);
	}

	// (Hydration's end, or a mismatch: claiming stops)
	@:allow(helder.web.Hydration) static function stop()
		hydration = null;
	#end
}

#if !macro

// Claiming a page's nodes: a cursor over parent's content in document
// order. Skipped on the way: the separators between texts (<!---->) and the
// ends of pairs (<!--]-->), already claimed by their markers.
private class Hydration {
	final root:Node;
	// the last node claimed (into: its children come next), or where to go on from
	var cursor:Node;
	var into = true;
	// what differed (null: nothing yet)
	public var failed:Null<String>;

	public function new(root:Node) {
		this.root = root;
		this.cursor = root;
	}

	// the node after n in document order, inside root (into n's children when down)
	function step(n:Node, down:Bool):Null<Node> {
		if (down && n.firstChild != null) return n.firstChild;
		while (n != root) {
			if (n.nextSibling != null) return n.nextSibling;
			n = n.parentNode;
		}
		return null;
	}

	// the next node to claim (null: none left)
	function next():Null<Node> {
		var n = step(cursor, into);
		while (n != null && n.nodeType == Node.COMMENT_NODE && (n.nodeValue == "" || n.nodeValue == "]"))
			n = step(n, false);
		return n;
	}

	public function element(tag:String):Node {
		var n = next();
		var name = Html.localName(tag);
		if (n == null || n.nodeType != Node.ELEMENT_NODE
			|| (cast n : Element).localName != (Html.isSvgTag(tag) ? name : name.toLowerCase())) return mismatch('<$tag>', n);
		claim(n);
		return n;
	}

	public function text(t:String):Node {
		var n = next();
		if (n != null && n.nodeType == Node.TEXT_NODE) {
			claim(n);
			if (t != "" && n.nodeValue != t) n.nodeValue = t;
			return n;
		}
		// (an empty text: <!--#-->, which it replaces)
		if (n != null && n.nodeType == Node.COMMENT_NODE && n.nodeValue == "#") {
			var x = document.createTextNode(t);
			n.parentNode.replaceChild(x, n);
			claim(x);
			return x;
		}
		return mismatch("text", n);
	}

	inline function claim(n:Node) {
		cursor = n;
		into = true;
	}

	// a marker: the end of the pair that starts here, its content claimed
	// next; the start removed (a region's or a list's content goes before
	// its marker, as when rendered)
	public function marker():Node {
		var n = next();
		if (n == null || n.nodeType != Node.COMMENT_NODE || n.nodeValue != "[") return mismatch("a marker", n);
		var depth = 0, m = n.nextSibling;
		while (m != null) {
			if (m.nodeType == Node.COMMENT_NODE) {
				if (m.nodeValue == "[") depth++;
				else if (m.nodeValue == "]") {
					if (depth == 0) break;
					depth--;
				}
			}
			m = m.nextSibling;
		}
		if (m == null) return mismatch("the end of a marker", null);
		var prev = n.previousSibling, parent = n.parentNode;
		parent.removeChild(n);
		if (prev != null) {
			cursor = prev;
			into = false;
		} else claim(parent);
		return m;
	}

	// el's content not claimed (set as a property: innerHTML, a textarea's value)
	public function skip(el:Element)
		if (cursor == el) into = false;

	// the end: nothing may be left
	public function finish() {
		if (failed == null) {
			var n = next();
			if (n != null) failed = "left over: " + describe(n);
		}
		DomRenderer.stop();
	}

	function mismatch(want:String, got:Null<Node>):Dynamic {
		failed = '$want expected, ' + (got == null ? "nothing" : describe(got)) + " found";
		DomRenderer.stop();
		throw new Mismatch(failed);
	}

	static function describe(n:Node):String
		return switch n.nodeType {
			case Node.ELEMENT_NODE: "<" + (cast n : Element).localName + ">";
			case Node.TEXT_NODE: "text \"" + n.nodeValue + "\"";
			case _: "<!--" + n.nodeValue + "-->";
		}
}

// (first in a hydrated content: its onMount, at the end of the insertion, ends hydration)
private class HydrationEnd implements helder.view.Flow.Mountable<Node> {
	final h:Hydration;

	public function new(h:Hydration)
		this.h = h;

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		Reactive.onMount(h.finish);
		return [];
	}
}

private class Mismatch {
	public final message:String;

	public function new(message:String)
		this.message = message;
}
#end
#end
