package hxmc.ui.reactive;

import hxmc.esx.Esx;
import hxmc.esx.Template;
import hxmc.ui.*;
import hxmc.ui.reactive.Flow.Mountable;
import hxmc.ui.reactive.Reactive;
import hxmc.ui.reactive.Signal;
import hxmc.ui.reactive.Memo;

// Mounts content into hxmc.ui nodes, Solid's way: each part is created
// once and bound to what it reads. Content is an Esx (a markup literal), a
// Node, text (String, numbers), an Array of content, null, or something
// reactive: a Signal, a Memo, or a function () -> content, whose region is
// redrawn when what it reads changes (its nodes replaced before an anchor,
// a hidden node, its computations disposed with them).
//
// Intrinsic elements: view (a Node), text (a TextNode of its children's
// text; elements in it are its spans: span, b, i, or text again), scroll (a Node with Overflow Scroll), image (an ImageNode: src, an
// Image, an AnimatedImage, played, or an Svg, drawn in the node's color; fit, "fill", "contain", "cover" or "none"); elements registers more.
// Their attributes: Style properties (StyleAttrs: direction="row",
// padding={8}, background="#3b82f6"; style={StyleProps} for several), the
// events (onClick, onPointerDown, onPointerUp, onPointerMove,
// onPointerEnter, onPointerLeave, onWheel, onKeyDown, onKeyUp,
// onTextInput, onComposition, onFocus, onBlur: Event -> Void), focusable, ref (a
// function given the node), and what the node is to assistive technology
// (Semantics: role, label, description, checked, selected, expanded,
// disabled, value-now, value-min, value-max, value-text, hidden). A Signal, Memo or function as a value (but an
// event's) is bound: set again when it changes. In a view, a run of text
// and holes whose values are text becomes one TextNode (reactive if one of
// them is). A component's factory is called once, untracked, inside its
// own owner.
class Render {
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

	// renders content into parent (its root: dispose removes it and stops its effects)
	public static function render(content:Any, parent:Node):Void->Void {
		return Reactive.root(dispose -> {
			var nodes = insert(content, parent, null);
			Reactive.onCleanup(() -> for (n in nodes)
				if (n.parent == parent) parent.remove(n));
			dispose;
		});
	}

	// inserts content into parent before a node (null: at the end); the nodes made
	public static function insert(content:Any, parent:Node, before:Null<Node>):Array<Node> {
		var out:Array<Node> = [];
		Reactive.mount(() -> add(content, parent, before, out));
		return out;
	}

	static function add(v:Dynamic, parent:Node, before:Null<Node>, out:Array<Node>) {
		if (v == null || v == false || v == true) return;
		if (Std.isOfType(v, Esx)) {
			var e:Esx = v;
			node(e.template.root, e.values, parent, before, out);
		} else if (Std.isOfType(v, Node)) put(v, parent, before, out);
		else if (Std.isOfType(v, Mountable)) {
			for (n in (cast v : Mountable).mount(parent, before))
				out.push(n);
		}
		else if (Std.isOfType(v, Array)) {
			for (x in (v : Array<Dynamic>))
				add(x, parent, before, out);
		} else if (isReactive(v)) region(v, parent, before, out);
		else put(new TextNode(Std.string(v)), parent, before, out);
	}

	static function put(n:Node, parent:Node, before:Null<Node>, out:Array<Node>) {
		var i = before == null ? parent.children.length : parent.indexOf(before);
		parent.insert(n, i < 0 ? parent.children.length : i);
		out.push(n);
	}

	// a reactive region: its content redrawn before an anchor
	static function region(getter:Dynamic, parent:Node, before:Null<Node>, out:Array<Node>) {
		var anchor = new Node("anchor");
		anchor.style.display = None;
		put(anchor, parent, before, out);
		var current:Array<Node> = [];
		Reactive.effect(() -> {
			var v = read(getter);
			Reactive.untrack(() -> {
				for (n in current)
					if (n.parent == parent) parent.remove(n);
				current = insert(v, parent, anchor);
			});
		});
		Reactive.onCleanup(() -> for (n in current)
			if (n.parent == parent) parent.remove(n));
	}

	// --- templates ---

	static function node(n:TNode, values:Array<Any>, parent:Node, before:Null<Node>, out:Array<Node>) {
		switch n.kind {
			case Text:
				put(new TextNode(n.text), parent, before, out);
			case Hole:
				add(values[n.hole], parent, before, out);
			case Fragment:
				children(n.children, values, parent, before, out, true);
			case Component:
				var factory:Void->Any = values[n.hole];
				var o = new Owner(Reactive.owner);
				var saved = Reactive.owner;
				Reactive.owner = o;
				try {
					var result = Reactive.untrack(factory);
					add(result, parent, before, out);
				} catch (e:Dynamic) {
					Reactive.owner = saved;
					throw e;
				}
				Reactive.owner = saved;
			case Element:
				var make = elements.get(n.name);
				if (make == null) throw 'hxmc.ui: no element <${n.name}> (Render.elements)';
				var el = make();
				put(el, parent, before, out);
				for (a in n.attrs)
					switch a.kind {
						case Static: attr(el, a.name, a.value);
						case Flag: attr(el, a.name, true);
						case Dynamic: attr(el, a.name, values[a.hole]);
						case Spread:
							var o:Dynamic = values[a.hole];
							for (f in Reflect.fields(o))
								attr(el, f, Reflect.field(o, f));
					}
				if (Std.isOfType(el, TextNode)) textContent(cast el, n.children, values) else children(n.children, values, el, null, [], true);
		}
	}

	// children, runs of text (and text holes) joined into TextNodes
	static function children(cs:Array<TNode>, values:Array<Any>, parent:Node, before:Null<Node>, out:Array<Node>, joinText:Bool) {
		var run:Array<Dynamic> = [];
		function flush() {
			if (run.length == 0) return;
			var parts = run;
			run = [];
			var t = new TextNode();
			put(t, parent, before, out);
			bindText(t, parts);
		}
		for (c in cs) {
			var part = joinText ? textPart(c, values) : null;
			if (part != null) {
				run.push(part);
				continue;
			}
			flush();
			node(c, values, parent, before, out);
		}
		flush();
	}

	// the child as a text part (a String, or a reactive one), or null when it is not text
	static function textPart(c:TNode, values:Array<Any>):Null<Dynamic> {
		if (c.kind == Text) return c.text;
		if (c.kind != Hole) return null;
		var v:Dynamic = values[c.hole];
		if (isText(v)) return Std.string(v);
		if (isReactive(v) && isText(Reactive.untrack(() -> read(v)))) return v;
		return null;
	}

	static function textContent(t:TextNode, cs:Array<TNode>, values:Array<Any>) {
		// (elements inside: spans, the text around them spans of their own)
		var nested = false;
		for (c in cs)
			if (c.kind == Element || c.kind == Component) nested = true;
		if (nested) {
			var run:Array<Dynamic> = [];
			function flush() {
				if (run.length == 0) return;
				var span = new TextNode("", "span");
				t.append(span);
				bindText(span, run);
				run = [];
			}
			for (c in cs) {
				var p = textPart(c, values);
				if (p != null) {
					run.push(p);
					continue;
				}
				flush();
				node(c, values, t, null, []);
			}
			flush();
			return;
		}
		var parts:Array<Dynamic> = [];
		for (c in cs) {
			var p = textPart(c, values);
			if (p == null) {
				var v:Dynamic = c.kind == Hole ? values[c.hole] : null;
				// (a reactive hole that is not text now: bound anyway)
				if (v != null && isReactive(v)) p = v else throw "hxmc.ui: <text> holds text only";
			}
			parts.push(p);
		}
		bindText(t, parts);
	}

	static function bindText(t:TextNode, parts:Array<Dynamic>) {
		var reactive = false;
		for (p in parts)
			if (!Std.isOfType(p, String)) reactive = true;
		if (!reactive) {
			t.text = parts.join("");
			return;
		}
		Reactive.effect(() -> {
			var b = new StringBuf();
			for (p in parts) {
				var v:Dynamic = Std.isOfType(p, String) ? p : read(p);
				if (v != null) b.add(Std.string(v));
			}
			t.text = b.toString();
		});
	}

	// --- attributes ---

	public static function attr(n:Node, name:String, v:Dynamic) {
		if (StringTools.startsWith(name, "on") && name.length > 2) {
			event(n, name, v);
			return;
		}
		switch name {
			case "ref":
				(v : Node->Void)(n);
				return;
			case "key":
				return;
			case _:
		}
		if (isReactive(v)) {
			Reactive.effect(() -> set(n, name, read(v)));
		} else set(n, name, v);
	}

	static function set(n:Node, name:String, v:Dynamic) {
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

	static final ROLES:Array<hxmc.ui.access.Role> = [
		Group, Button, CheckBox, Switch, RadioGroup, RadioButton, Slider, ProgressIndicator, TextInput, Label, Image, TabList, Tab, TabPanel, ScrollView,
		List, ListItem, Heading, Link, Dialog, Menu, MenuItem, ListBox, ListBoxOption, ComboBox, Tooltip, Table, Row, Cell, ColumnHeader
	];

	static function event(n:Node, name:String, v:Dynamic) {
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

	// --- values ---

	public static function isReactive(v:Dynamic):Bool
		return v != null && (Std.isOfType(v, SignalBase) || Std.isOfType(v, MemoBase) || Reflect.isFunction(v));

	// a reactive value's value (tracked)
	public static function read(v:Dynamic):Dynamic {
		if (Std.isOfType(v, SignalBase)) return (cast v : Signal<Dynamic>).value;
		if (Std.isOfType(v, MemoBase)) return (cast v : Memo<Dynamic>).value;
		if (Reflect.isFunction(v)) return (v : Void->Dynamic)();
		return v;
	}

	static inline function isText(v:Dynamic):Bool
		return Std.isOfType(v, String) || Std.isOfType(v, Int) || Std.isOfType(v, Float);
}
