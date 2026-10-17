package hxmc.ui.view;

import hxmc.ui.*;

// hxmc.view's renderer for hxmc.ui's nodes (-D hxmc.view.renderer=
// hxmc.ui.view.NodeRenderer, which -lib hxmc.ui sets): the tree that the
// drawn backend (hxmc.ui.draw) and the native one (hxmc.ui.native, whose
// Controls are nodes in it) display.
//
// Intrinsic elements: view (a Node), text (a TextNode of its children's
// text; elements in it are its spans: span, b, i, or text again), scroll (a
// Node with Overflow Scroll), image (an ImageNode: src, an Image, an
// AnimatedImage, played, or an Svg, drawn in the node's color; fit, "fill",
// "contain", "cover" or "none"); elements registers more. Their
// attributes: Style properties (StyleAttrs: direction="row", padding={8},
// background="#3b82f6"; style={StyleProps} for several), the events
// (onClick, onPointerDown, onPointerUp, onPointerMove, onPointerEnter,
// onPointerLeave, onWheel, onKeyDown, onKeyUp, onTextInput, onComposition,
// onFocus, onBlur, the drag events: Event -> Void), focusable, selectable,
// drag-data, tag, and what the node is to assistive technology (Semantics:
// role, label, description, checked, selected, expanded, level, disabled,
// value-now, value-min, value-max, value-text, hidden). A text node holds
// text: its text children are its text, its elements its spans.
class NodeRenderer implements hxmc.view.Renders<Node> {
	// intrinsic element names and the nodes they make
	public static final elements:Map<String, Void->Node> = [
		"view" => () -> new Node("view"),
		"text" => () -> new TextNode("", "text"),
		// (spans in a text: plain, bold, italic)
		"span" => () -> new TextNode("", "span"),
		"b" => () -> {
			var t = new TextNode("", "b");
			t.style.fontWeight = 700;
			t;
		},
		"i" => () -> {
			var t = new TextNode("", "i");
			t.style.italic = true;
			t;
		},
		"scroll" => () -> {
			var n = new Node("scroll");
			n.style.overflow = Scroll;
			n;
		},
		"image" => () -> new ImageNode()
	];

	public static function createElement(tag:String):Node {
		var make = elements.get(tag);
		if (make == null) throw 'hxmc.ui: no element <$tag> (NodeRenderer.elements)';
		return make();
	}

	public static inline function createText(text:String):Node
		return new TextNode(text);

	// (a hidden node)
	public static function createMarker(name:String):Node {
		var n = new Node(name);
		n.style.display = None;
		return n;
	}

	public static inline function setText(node:Node, text:String)
		(cast node : TextNode).text = text;

	public static inline function holdsText(el:Node):Bool
		return Std.isOfType(el, TextNode);

	public static function insert(parent:Node, node:Node, before:Null<Node>) {
		var i = before == null ? parent.children.length : parent.indexOf(before);
		parent.insert(node, i < 0 ? parent.children.length : i);
	}

	public static inline function remove(parent:Node, node:Node)
		parent.remove(node);

	public static inline function parentOf(node:Node):Null<Node>
		return node.parent;

	// (in one pass when the rows are already the children just before before)
	public static function arrange(parent:Node, nodes:Array<Node>, before:Node) {
		var at = parent.indexOf(before);
		var inPlace = at >= nodes.length;
		if (inPlace)
			for (k in 0...nodes.length)
				if (nodes[k].parent != parent) {
					inPlace = false;
					break;
				}
		if (inPlace) {
			var set = new haxe.ds.ObjectMap<Node, Bool>();
			for (n in nodes)
				set.set(n, true);
			for (k in at - nodes.length...at)
				if (!set.exists(parent.children[k])) {
					inPlace = false;
					break;
				}
		}
		if (inPlace) parent.reorder(at - nodes.length, nodes) else
			for (n in nodes)
				parent.insert(n, parent.indexOf(before));
	}

	public static inline function isNode(v:Dynamic):Bool
		return Std.isOfType(v, Node);

	public static function setStyle(n:Node, v:Dynamic)
		if (v != null) n.style.set(v);

	public static function setProperty(n:Node, name:String, v:Dynamic) {
		switch name {
			case "focusable":
				n.focusable = v == true || v == "true";
			case "selectable" if (Std.isOfType(n, TextNode)):
				(cast n : TextNode).selectable = v == true || v == "true";
			case "dragData" | "drag-data":
				n.dragData = v;
			case "style":
				if (v != null) n.style.set(v);
			case "text" if (Std.isOfType(n, TextNode)):
				(cast n : TextNode).text = v == null ? "" : Std.string(v);
			case "tag":
				n.tag = v;
			case "role":
				semantics(n).role = role(v);
			case "label":
				semantics(n).label = v == null ? null : Std.string(v);
			case "description":
				semantics(n).description = v == null ? null : Std.string(v);
			case "checked":
				semantics(n).checked = v == null ? null : v == true || v == "true";
			case "selected":
				semantics(n).selected = v == null ? null : v == true || v == "true";
			case "expanded":
				semantics(n).expanded = v == null ? null : v == true || v == "true";
			case "level":
				semantics(n).level = v == null ? null : Std.int(number(v));
			case "disabled":
				semantics(n).disabled = v == true || v == "true";
			case "value-now" | "valueNow":
				semantics(n).valueNow = number(v);
			case "value-min" | "valueMin":
				semantics(n).valueMin = number(v);
			case "value-max" | "valueMax":
				semantics(n).valueMax = number(v);
			case "hidden":
				semantics(n).hidden = v == true || v == "true";
			case "value-text" | "valueText":
				semantics(n).valueText = v == null ? null : Std.string(v);
			case "src" if (Std.isOfType(n, ImageNode)):
				// (an animation: its image, played)
				if (Std.isOfType(v, AnimatedImage)) {
					var anim:AnimatedImage = v;
					(cast n : ImageNode).image = anim.image;
					anim.play();
				} else if (Std.isOfType(v, Svg)) (cast n : ImageNode).svg = v else (cast n : ImageNode).image = v;
			case "fit" if (Std.isOfType(n, ImageNode)):
				(cast n : ImageNode).fit = Std.isOfType(v, String) ? switch (v : String).toLowerCase() {
					case "fill": Fill;
					case "contain": Contain;
					case "cover": Cover;
					case "none": ImageFit.None;
					case _: throw 'hxmc.ui: fit="$v" is not fill, contain, cover or none';
				} : v;
			case _:
				if (!StyleAttrs.apply(n.style, name, v)) throw 'hxmc.ui: <${n.tag}> has no attribute $name';
		}
	}

	static function semantics(n:Node):hxmc.ui.access.Semantics {
		if (n.semantics == null) n.semantics = {};
		return n.semantics;
	}

	static function number(v:Dynamic):Null<Float>
		return v == null ? null : Std.isOfType(v, String) ? Std.parseFloat(v) : (v : Float);

	// a role as ARIA writes it ("button", "checkbox", "progressbar"), or a Role
	static function role(v:Dynamic):Null<hxmc.ui.access.Role> {
		if (v == null || !Std.isOfType(v, String)) return v;
		for (r in ROLES)
			if (r.aria() == v) return r;
		return switch (v : String) {
			case "textarea" | "multiline": MultilineTextInput;
			case "table": Table;
			case "cell": Cell;
			case "label": Label;
			case _: throw 'hxmc.ui: role="$v" is not one of hxmc.ui.access.Role\'s';
		}
	}

	// (every role, in order: the first with an ARIA name is its)
	static final ROLES:Array<hxmc.ui.access.Role> = Enums.values(hxmc.ui.access.Role);

	public static function listen(n:Node, name:String, v:Dynamic) {
		var h:Null<Event->Void> = v;
		switch name {
			case "onClick": n.onClick = h;
			case "onPointerDown": n.onPointerDown = h;
			case "onPointerUp": n.onPointerUp = h;
			case "onPointerMove": n.onPointerMove = h;
			case "onPointerEnter": n.onPointerEnter = h;
			case "onPointerLeave": n.onPointerLeave = h;
			case "onWheel": n.onWheel = h;
			case "onKeyDown": n.onKeyDown = h;
			case "onKeyUp": n.onKeyUp = h;
			case "onComposition": n.onComposition = h;
			case "onTextInput": n.onTextInput = h;
			case "onFocus": n.onFocus = h;
			case "onBlur": n.onBlur = h;
			case "onDragStart": n.onDragStart = h;
			case "onDragOver": n.onDragOver = h;
			case "onDragLeave": n.onDragLeave = h;
			case "onDrop": n.onDrop = h;
			case "onDragEnd": n.onDragEnd = h;
			case _: throw 'hxmc.ui: no event $name';
		}
	}

}
