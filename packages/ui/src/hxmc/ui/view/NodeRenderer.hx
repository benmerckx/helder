package hxmc.ui.view;

#if !macro
import hxmc.ui.*;
#end

// hxmc.view's renderer for hxmc.ui's nodes (-D hxmc.view.renderer.ui=
// hxmc.ui.view.NodeRenderer, which -lib hxmc.ui sets): the tree that the
// drawn backend (hxmc.ui.draw) and the native one (hxmc.ui.native, whose
// Controls are nodes in it) display.
//
// Intrinsic elements: view (a Node), text (a TextNode of its children's
// text; elements in it are its spans: span, b, i, or text again), scroll (a
// Node with Overflow Scroll), image (an ImageNode: src, an Image, an
// AnimatedImage, played, or an Svg, drawn in the node's color; object-position
// ("left top", CSS's), its place; fit, "fill",
// "contain", "cover" or "none"), icon (an image, its Svg); view:button,
// view:label... and text:p, text:h2... (a view, a text: the element of that
// name where a page's renderer realises them, hxmc.web's); elements registers more. Their
// attributes: Style properties (StyleAttrs: direction="row", padding={8},
// background="#3b82f6"; style={StyleProps} for several), the events
// (onClick, onPress (a click, or Enter or Space: Node.onActivate), onPointerDown, onPointerUp, onPointerMove, onPointerEnter,
// onPointerLeave, onWheel, onKeyDown, onKeyUp, onTextInput, onComposition,
// onFocus, onBlur, onFocusIn, onFocusOut, the drag events: Event -> Void), focusable, selectable,
// drag-data, tag, and what the node is to assistive technology (Semantics:
// role, label, description, href, checked, selected, expanded, level, disabled,
// value-now, value-min, value-max, value-text, hidden), and what a theme
// styles it as (Rule: slot, variant, size, data-* and aria-* attributes,
// data-state="checked"). A text node holds
// text: its text children are its text, its elements its spans.
//
// Pay for what is used: markup's literal tags and attribute names are
// resolved at compile time (createElement inline, setProperty and setter
// macros, AttrMacro), so that a program links the nodes, attributes and
// value parsers its markup names; a name known only at run time
// (setAttribute: a spread, Dynamic) reaches them all.
#if !macro
@:build(hxmc.ui.view.AttrMacro.renderer())
#end
class NodeRenderer #if !macro implements hxmc.view.Renders<Node> #end {
	// the property name of n (a literal name: its own function, AttrMacro.setter;
	// else setAttribute)
	public static macro function setProperty(n:haxe.macro.Expr, name:haxe.macro.Expr, v:haxe.macro.Expr):haxe.macro.Expr
		return switch name.expr {
			case EConst(CString(s, _)): macro ${hxmc.ui.view.AttrMacro.setter(s, name.pos)}($n, $name, $v);
			case _: macro hxmc.ui.view.NodeRenderer.setAttribute($n, $name, $v);
		}

	// the function setting the property name (a literal), (n, name, v): markup
	// binds a reactive value with it (hxmc.view.Renders)
	public static macro function setter(name:String):haxe.macro.Expr
		return hxmc.ui.view.AttrMacro.setter(name, haxe.macro.Context.currentPos());

	#if !macro
	// the elements registered besides the intrinsic ones, and the nodes they make
	public static final elements:Map<String, Void->Node> = [];

	// (inline: a literal tag makes its own node alone)
	public static inline function createElement(tag:String):Node
		return switch tag {
			case "view": new Node("view");
			case "text": new TextNode("", "text");
			// (spans in a text: plain, bold, italic)
			case "span": new TextNode("", "span");
			case "b":
				var t = new TextNode("", "b");
				t.style.fontWeight = 700;
				t;
			case "i":
				var t = new TextNode("", "i");
				t.style.italic = true;
				t;
			case "scroll":
				var n = new Node("scroll");
				n.style.overflow = Scroll;
				n;
			case "image": new ImageNode();
			case "icon": new ImageNode(null, "icon");
			// (the neutral elements' DOM names: a view or text here, their element in a page)
			case t if (StringTools.startsWith(t, "view:")): new Node(t.substr(5));
			case t if (StringTools.startsWith(t, "text:")): new TextNode("", t.substr(5));
			case _: registered(tag);
		}

	static function registered(tag:String):Node {
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

	// Its own attributes (AttrMacro: an @:attribute function, named as the
	// attribute or in kebab-case), then Style's (StyleAttrs), data-* and aria-*
	// (a theme's states: data-state="checked", data-disabled={true}; false or
	// null removes it); setAttribute, the one taking any name, is made from them

	@:attribute static function focusable(n:Node, name:String, v:Dynamic)
		n.focusable = v == true || v == "true";

	@:attribute static function selectable(n:Node, name:String, v:Dynamic)
		if (Std.isOfType(n, TextNode)) (cast n : TextNode).selectable = v == true || v == "true" else noAttribute(n, name);

	@:attribute static function dragData(n:Node, name:String, v:Dynamic)
		n.dragData = v;

	@:attribute static function style(n:Node, name:String, v:Dynamic)
		if (v != null) n.style.set(v);

	@:attribute static function text(n:Node, name:String, v:Dynamic)
		if (Std.isOfType(n, TextNode)) (cast n : TextNode).text = v == null ? "" : Std.string(v) else noAttribute(n, name);

	// (null: its tag as it is)
	@:attribute static function tag(n:Node, name:String, v:Dynamic)
		if (v != null) n.tag = v;

	// (a page's element's id, where a page's renderer realises a neutral element: none here, Node.find takes tag;
	// a label's for, html-for, none either)
	@:attribute static function id(n:Node, name:String, v:Dynamic) {}

	@:attribute static function htmlFor(n:Node, name:String, v:Dynamic) {}

	// (what a theme styles it as: Rule)
	@:attribute static function slot(n:Node, name:String, v:Dynamic)
		n.slot = v == null ? null : Std.string(v);

	@:attribute static function variant(n:Node, name:String, v:Dynamic)
		n.variant = v == null ? null : Std.string(v);

	@:attribute static function size(n:Node, name:String, v:Dynamic)
		n.size = v == null ? null : Std.string(v);

	// (what draws its widgets: Host's names, auto, native or drawn)
	@:attribute static function host(n:Node, name:String, v:Dynamic)
		n.host = Host.fromString(v == null ? null : Std.string(v));

	// (group="tabs" and peer mark a node whose states others' rules ask for)
	@:attribute static function group(n:Node, name:String, v:Dynamic)
		setData(n, name, v);

	@:attribute static function peer(n:Node, name:String, v:Dynamic)
		setData(n, name, v);

	public static function setData(n:Node, name:String, v:Dynamic)
		n.setAttr(name, v == null || v == false ? null : v == true ? "" : Std.string(v));

	@:attribute static function role(n:Node, name:String, v:Dynamic)
		semantics(n).role = roleOf(v);

	@:attribute static function label(n:Node, name:String, v:Dynamic)
		semantics(n).label = v == null ? null : Std.string(v);

	@:attribute static function description(n:Node, name:String, v:Dynamic)
		semantics(n).description = v == null ? null : Std.string(v);

	@:attribute static function href(n:Node, name:String, v:Dynamic) {
		var sem = semantics(n);
		sem.href = v == null ? null : Std.string(v);
		if (sem.role == null && v != null) sem.role = Link;
	}

	@:attribute static function checked(n:Node, name:String, v:Dynamic) {
		semantics(n).checked = v == null ? null : v == true || v == "true";
		semantics(n).mixed = v == "mixed";
	}

	@:attribute static function selected(n:Node, name:String, v:Dynamic)
		semantics(n).selected = v == null ? null : v == true || v == "true";

	@:attribute static function live(n:Node, name:String, v:Dynamic)
		semantics(n).live = v == null || v == "off" ? Off : v == "assertive" ? Assertive : v == "polite" ? Polite : v;

	@:attribute static function multiselectable(n:Node, name:String, v:Dynamic)
		semantics(n).multiselectable = v == true || v == "true";

	@:attribute static function current(n:Node, name:String, v:Dynamic)
		semantics(n).current = v == true || v == "true" || v == "page";

	@:attribute static function expanded(n:Node, name:String, v:Dynamic)
		semantics(n).expanded = v == null ? null : v == true || v == "true";

	@:attribute static function level(n:Node, name:String, v:Dynamic)
		semantics(n).level = v == null ? null : Std.int(number(v));

	@:attribute static function disabled(n:Node, name:String, v:Dynamic)
		semantics(n).disabled = v == true || v == "true";

	@:attribute static function valueNow(n:Node, name:String, v:Dynamic)
		semantics(n).valueNow = number(v);

	@:attribute static function valueMin(n:Node, name:String, v:Dynamic)
		semantics(n).valueMin = number(v);

	@:attribute static function valueMax(n:Node, name:String, v:Dynamic)
		semantics(n).valueMax = number(v);

	@:attribute static function hidden(n:Node, name:String, v:Dynamic)
		semantics(n).hidden = v == true || v == "true";

	@:attribute static function valueText(n:Node, name:String, v:Dynamic)
		semantics(n).valueText = v == null ? null : Std.string(v);

	@:attribute static function src(n:Node, name:String, v:Dynamic) {
		if (!Std.isOfType(n, ImageNode)) noAttribute(n, name);
		// (an animation: its image, played)
		if (Std.isOfType(v, AnimatedImage)) {
			var anim:AnimatedImage = v;
			(cast n : ImageNode).image = anim.image;
			anim.play();
		} else if (Std.isOfType(v, Svg)) (cast n : ImageNode).svg = v else (cast n : ImageNode).image = v;
	}

	@:attribute static function objectPosition(n:Node, name:String, v:Dynamic)
		if (Std.isOfType(n, ImageNode)) (cast n : ImageNode).position(v) else noAttribute(n, name);

	@:attribute static function fit(n:Node, name:String, v:Dynamic) {
		if (!Std.isOfType(n, ImageNode)) noAttribute(n, name);
		(cast n : ImageNode).fit = Std.isOfType(v, String) ? switch (v : String).toLowerCase() {
			case "fill": Fill;
			case "contain": Contain;
			case "cover": Cover;
			case "none": ImageFit.None;
			case _: throw 'hxmc.ui: fit="$v" is not fill, contain, cover or none';
		} : v;
	}

	static function noAttribute(n:Node, name:String):Dynamic
		throw 'hxmc.ui: <${n.tag}> has no attribute $name';

	static function semantics(n:Node):hxmc.ui.access.Semantics {
		if (n.semantics == null) n.semantics = {};
		return n.semantics;
	}

	static function number(v:Dynamic):Null<Float>
		return v == null ? null : Std.isOfType(v, String) ? Std.parseFloat(v) : (v : Float);

	// a role as ARIA writes it ("button", "checkbox", "progressbar"), or a Role
	static function roleOf(v:Dynamic):Null<hxmc.ui.access.Role> {
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
			case "onPress": n.onActivate = h;
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
			case "onFocusIn": n.onFocusIn = h;
			case "onFocusOut": n.onFocusOut = h;
			case "onDragStart": n.onDragStart = h;
			case "onDragOver": n.onDragOver = h;
			case "onDragLeave": n.onDragLeave = h;
			case "onDrop": n.onDrop = h;
			case "onDragEnd": n.onDragEnd = h;
			case _: throw 'hxmc.ui: no event $name';
		}
	}
	#end
}
