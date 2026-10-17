package hxmc.view;

import hxmc.view.Flow.Mountable;
import hxmc.view.Memo;
import hxmc.view.Signal;

// Mounts content into the renderer's nodes (Host), Solid's way: each part
// is made once and bound to what it reads. Content is a View (a markup
// literal), a node, text (String, numbers), an Array of content, null, a
// Mountable (a control flow component), or something reactive: a Signal, a
// Memo or a function () -> content, whose region is drawn again when what
// it reads changes (its nodes replaced before a marker, its computations
// disposed with them).
//
// The markup macro's code calls the rest: attributes (a Signal, Memo or
// function as a value, but an event's, is bound: set again when it
// changes), runs of text and holes whose values are text (one text node,
// reactive if one of them is; in an element that holds text, its own text,
// or spans beside its child elements), components (called once,
// untracked, in an owner of their own).
class Render {
	// renders content into parent (its root: dispose removes it and stops its effects)
	public static function render(content:Any, parent:HostNode):Void->Void {
		return Reactive.root(dispose -> {
			var nodes = insert(content, parent, null);
			Reactive.onCleanup(() -> for (n in nodes)
				detach(parent, n));
			dispose;
		});
	}

	// inserts content into parent before a node (null: at the end); the nodes made
	public static function insert(content:Any, parent:HostNode, before:Null<HostNode>):Array<HostNode> {
		var out:Array<HostNode> = [];
		Reactive.mount(() -> add(content, parent, before, out));
		return out;
	}

	// as insert, the nodes made pushed to out as they are (those made before an error too)
	public static function insertTo(content:Any, parent:HostNode, before:Null<HostNode>, out:Array<HostNode>)
		Reactive.mount(() -> add(content, parent, before, out));

	static function add(v:Dynamic, parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>) {
		if (v == null || v == false || v == true) return;
		if (Std.isOfType(v, View)) (v : View).mount(parent, before, out);
		else if (Host.isNode(v)) put(parent, v, before, out);
		else if (Std.isOfType(v, Mountable)) {
			var nodes = (cast v : Mountable).mount(parent, before);
			if (out != null)
				for (n in nodes)
					out.push(n);
		} else if (Std.isOfType(v, Array)) {
			for (x in (v : Array<Dynamic>))
				add(x, parent, before, out);
		} else if (isReactive(v)) region(v, parent, before, out);
		else put(parent, Host.createText(Std.string(v)), before, out);
	}

	// n put in parent before before, pushed to out
	public static inline function put(parent:HostNode, n:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>) {
		Host.insert(parent, n, before);
		if (out != null) out.push(n);
	}

	// n removed from parent, when it is still there
	public static inline function detach(parent:HostNode, n:HostNode)
		if (Host.parentOf(n) == parent) Host.remove(parent, n);

	// a marker (Host.createMarker) put in parent before before
	public static function marker(parent:HostNode, before:Null<HostNode>, name:String):HostNode {
		var m = Host.createMarker(name);
		Host.insert(parent, m, before);
		return m;
	}

	// a reactive region: its content drawn again before a marker
	static function region(getter:Dynamic, parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>) {
		var anchor = Host.createMarker("anchor");
		put(parent, anchor, before, out);
		var current:Array<HostNode> = [];
		Reactive.effect(() -> {
			var v = read(getter);
			Reactive.untrack(() -> {
				for (n in current)
					detach(parent, n);
				current = insert(v, parent, anchor);
			});
		});
		Reactive.onCleanup(() -> for (n in current)
			detach(parent, n));
	}

	// --- what markup compiles to ---

	// a component: its factory called once, untracked, in an owner of its own
	public static function component(parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>, factory:Void->Any) {
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
	}

	// an element's children, all static text
	public static function textOf(el:HostNode, text:String) {
		if (Host.holdsText(el)) Host.setText(el, text) else Host.insert(el, Host.createText(text), null);
	}

	// an element's children, text and holes only: its own text when it holds
	// text (a hole whose value is not text, nor reactive, is an error), else a run
	public static function flat(el:HostNode, tag:String, parts:Array<Any>) {
		if (!Host.holdsText(el)) {
			run(el, null, null, parts, false);
			return;
		}
		var ps:Array<Dynamic> = [];
		for (p in parts) {
			var t = textPart(p);
			// (a reactive hole that is not text now: bound anyway)
			if (t == null) {
				if (isReactive(p)) t = p else throw 'hxmc.view: <$tag> holds text only';
			}
			ps.push(t);
		}
		bindText(el, ps);
	}

	// static text among other children (span: a span in an element that holds text)
	public static function text(parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>, text:String, span:Bool) {
		if (span) {
			var s = Host.createElement("span");
			put(parent, s, before, out);
			Host.setText(s, text);
		} else put(parent, Host.createText(text), before, out);
	}

	// a hole among other children: text (a text node, bound when reactive) or other content
	public static function hole(parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>, v:Any, span:Bool) {
		var t = textPart(v);
		if (t == null) {
			add(v, parent, before, out);
			return;
		}
		var n = span ? Host.createElement("span") : Host.createText("");
		put(parent, n, before, out);
		bindText(n, [t]);
	}

	// a run of text and holes: those whose values are text joined into text
	// nodes, the others content between them
	public static function run(parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>, parts:Array<Any>, span:Bool) {
		var run:Array<Dynamic> = [];
		function flush() {
			if (run.length == 0) return;
			var n = span ? Host.createElement("span") : Host.createText("");
			put(parent, n, before, out);
			bindText(n, run);
			run = [];
		}
		for (p in parts) {
			var t = textPart(p);
			if (t != null) {
				run.push(t);
				continue;
			}
			flush();
			add(p, parent, before, out);
		}
		flush();
	}

	// the value as a text part (a String, or a reactive one whose value is text now), or null when it is not text
	static function textPart(v:Dynamic):Null<Dynamic> {
		if (isText(v)) return Std.string(v);
		if (isReactive(v) && isText(Reactive.untrack(() -> read(v)))) return v;
		return null;
	}

	static function bindText(n:HostNode, parts:Array<Dynamic>) {
		var reactive = false;
		for (p in parts)
			if (!Std.isOfType(p, String)) reactive = true;
		if (!reactive) {
			Host.setText(n, parts.length == 1 ? parts[0] : parts.join(""));
			return;
		}
		Reactive.effect(() -> {
			var b = new StringBuf();
			for (p in parts) {
				var v:Dynamic = Std.isOfType(p, String) ? p : read(p);
				if (v != null) b.add(Std.string(v));
			}
			Host.setText(n, b.toString());
		});
	}

	// --- attributes ---

	// an attribute by name: an event (on...) listened to, ref called, key
	// ignored, the style, else a property (bound when reactive)
	public static function attr(n:HostNode, name:String, v:Dynamic) {
		if (StringTools.startsWith(name, "on") && name.length > 2) {
			Host.listen(n, name, v);
			return;
		}
		switch name {
			case "ref": ref(n, v);
			case "key":
			case "style": style(n, v);
			case _: prop(n, name, v);
		}
	}

	// a property's value, bound when reactive
	public static function prop(n:HostNode, name:String, v:Dynamic) {
		if (isReactive(v)) Reactive.effect(() -> Host.setProperty(n, name, read(v))) else Host.setProperty(n, name, v);
	}

	public static function style(n:HostNode, v:Dynamic) {
		if (isReactive(v)) Reactive.effect(() -> Host.setStyle(n, read(v))) else Host.setStyle(n, v);
	}

	public static inline function ref(n:HostNode, v:Dynamic)
		(v : HostNode->Void)(n);

	// {...object}: its fields as attributes
	public static function spread(n:HostNode, o:Dynamic)
		for (f in Reflect.fields(o))
			attr(n, f, Reflect.field(o, f));

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
