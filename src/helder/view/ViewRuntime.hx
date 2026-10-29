package helder.view;

// Mounting content into one renderer's nodes, Solid's way: each part is
// made once and bound to what it reads. Written against Host (the
// renderer) and HostNode (its nodes), placeholders: ViewRuntime itself is
// only the template of ViewRuntime_<renderer>, made for each renderer the
// program reaches (HostMacro), so that every call below is a direct call to
// its renderer. (Being copied, it names other types by their full paths.)
//
// Content is a View (a markup literal: its code for this renderer runs, an
// agnostic literal's through late; another renderer's an error), a
// node, text (String, numbers), an Array of content, null, For, Index or
// ErrorBoundary content, a Mountable of this renderer's nodes, or
// something reactive: a Signal, a Memo or a function () -> content, whose
// region is drawn again when what it reads changes (its nodes replaced
// before a marker, its computations disposed with them).
//
// The markup macro's code calls the rest: attributes (a Signal, Memo or
// function as a value, but an event's, is bound: set again when it
// changes), runs of text and holes whose values are text (one text node,
// reactive if one of them is; in an element that holds text, its own text,
// or spans beside its child elements), components (called once,
// untracked, in an owner of their own).
@:build(helder.view.HostMacro.build())
class ViewRuntime {
	// renders content into parent (its root: dispose removes it and stops its effects)
	public static function render(content:Any, parent:HostNode):Void->Void {
		return helder.view.Reactive.root(dispose -> {
			#if hxmc.dev
			// (hxmc dev: its effects' cleanups run before the next build starts)
			helder.view.Reactive.onCleanup(helder.dev.Hot.onDispose(dispose));
			#end
			var nodes = insert(content, parent, null);
			helder.view.Reactive.onCleanup(() -> for (n in nodes)
				detach(parent, n));
			dispose;
		});
	}

	// inserts content into parent before a node (null: at the end); the nodes made
	public static function insert(content:Any, parent:HostNode, before:Null<HostNode>):Array<HostNode> {
		var out:Array<HostNode> = [];
		helder.view.Reactive.mount(() -> add(content, parent, before, out));
		return out;
	}

	// as insert, the nodes made pushed to out as they are (those made before an error too)
	public static function insertTo(content:Any, parent:HostNode, before:Null<HostNode>, out:Array<HostNode>)
		helder.view.Reactive.mount(() -> add(content, parent, before, out));

	static function add(v:Dynamic, parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>) {
		if (v == null || v == false || v == true) return;
		if (Std.isOfType(v, helder.view.View)) view(v, parent, before, out);
		else if (Host.isNode(v)) put(parent, v, before, out);
		else if (Std.isOfType(v, helder.view.Flow.ForList)) mounted(forList(v, parent, before), out);
		else if (Std.isOfType(v, helder.view.Flow.IndexList)) mounted(indexList(v, parent, before), out);
		else if (Std.isOfType(v, helder.view.Flow.Boundary)) mounted(boundary(v, parent, before), out);
		else if (Std.isOfType(v, helder.view.Flow.Waiting)) mounted(loading(v, parent, before), out);
		else if (Std.isOfType(v, helder.view.Flow.Mountable)) {
			var m:helder.view.Flow.Mountable<HostNode> = cast v;
			mounted(m.mount(parent, before), out);
		} else if (Std.isOfType(v, Array)) {
			for (x in (v : Array<Dynamic>))
				add(x, parent, before, out);
		} else if (helder.view.Render.isReactive(v)) region(v, parent, before, out);
		else put(parent, Host.createText(Std.string(v)), before, out);
	}

	// a View: its code for this renderer
	static function view(v:helder.view.View, parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>) {
		if (v.renderer == INDEX) v.mount(parent, before, out);
		else if (v.renderer == 0 && late != null) late(v.key, v.holes, parent, before, out);
		else throw 'helder.view: $v is markup for another renderer than ' + NAME + ', whose node it is mounted into';
	}

	// the agnostic literals' code for this renderer (by key: their holes'
	// values), made after typing (HostMacro.late), set by its __init__
	public static var late:Null<(Int, Array<Any>, HostNode, Null<HostNode>, Null<Array<HostNode>>) -> Void>;

	static inline function mounted(nodes:Array<HostNode>, out:Null<Array<HostNode>>)
		if (out != null)
			for (n in nodes)
				out.push(n);

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
		helder.view.Reactive.effect(() -> {
			var v = helder.view.Render.read(getter);
			helder.view.Reactive.untrack(() -> {
				for (n in current)
					detach(parent, n);
				current = insert(v, parent, anchor);
			});
		});
		helder.view.Reactive.onCleanup(() -> for (n in current)
			detach(parent, n));
	}

	// --- what markup compiles to ---

	// a component: its factory called once, untracked, in an owner of its own
	public static function component(parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>, factory:Void->Any) {
		var o = new helder.view.Owner(helder.view.Reactive.owner);
		var saved = helder.view.Reactive.owner;
		helder.view.Reactive.owner = o;
		helder.view.Render.pass = INDEX;
		try {
			var result = helder.view.Reactive.untrack(factory);
			add(result, parent, before, out);
		} catch (e:helder.view.Pending) {
			// (a value not ready while it was made: nothing of it, the Loading
			// boundary above told, which makes it again once it is)
			helder.view.Reactive.owner = saved;
			o.suspended(e);
			return;
		} catch (e:Dynamic) {
			helder.view.Reactive.owner = saved;
			throw e;
		}
		helder.view.Reactive.owner = saved;
	}

	#if hxmc.dev
	// (hxmc dev: a component in the scope of its name, fast refresh's keys: helder.view.Refresh)
	public static function componentIn(scope:String, parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>, factory:Void->Any)
		helder.dev.Hot.scope(scope, () -> component(parent, before, out, factory));
	#end

	// an element's children, all static text
	public static function textOf(el:HostNode, text:String) {
		if (Host.holdsText(el)) Host.setText(el, text) else Host.insert(el, Host.createText(text), null);
	}

	// an element's children, text and holes only: its own text when it holds
	// text (a hole of null none, as a run's; one whose value is not text, nor
	// reactive, an error naming what it is), else a run
	public static function flat(el:HostNode, tag:String, parts:Array<Any>) {
		if (!Host.holdsText(el)) {
			run(el, null, null, parts, false);
			return;
		}
		var ps:Array<Dynamic> = [];
		for (p in parts) {
			var t = p == null ? "" : textPart(p);
			// (a reactive hole that is not text now: bound anyway)
			if (t == null) {
				if (helder.view.Render.isReactive(p)) t = p else throw 'helder.view: <$tag> holds text only, not ' + describe(p);
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
		// (a value not ready: not known as text, bound as content: its region's
		// effect tells the Loading boundary)
		if (helder.view.Render.isReactive(v) && isText(try helder.view.Reactive.untrack(() -> helder.view.Render.read(v)) catch (_:helder.view.Pending) null)) return v;
		return null;
	}

	// (what a value is, for an error: its class, else its kind)
	static function describe(v:Dynamic):String {
		var c = Type.getClass(v);
		return c != null ? Type.getClassName(c) : Std.string(Type.typeof(v));
	}

	static inline function isText(v:Dynamic):Bool
		return Std.isOfType(v, String) || Std.isOfType(v, Int) || Std.isOfType(v, Float);

	static function bindText(n:HostNode, parts:Array<Dynamic>) {
		var reactive = false;
		for (p in parts)
			if (!Std.isOfType(p, String)) reactive = true;
		if (!reactive) {
			Host.setText(n, parts.length == 1 ? parts[0] : parts.join(""));
			return;
		}
		helder.view.Reactive.effect(() -> {
			var b = new StringBuf();
			for (p in parts) {
				var v:Dynamic = Std.isOfType(p, String) ? p : helder.view.Render.read(p);
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
		if (helder.view.Render.isReactive(v)) helder.view.Reactive.effect(() -> Host.setProperty(n, name, helder.view.Render.read(v))) else
			Host.setProperty(n, name, v);
	}

	// (the same with the renderer's function for the name: Renders' setter)
	public static function propWith(n:HostNode, name:String, v:Dynamic, set:(HostNode, String, Dynamic) -> Void) {
		if (helder.view.Render.isReactive(v)) helder.view.Reactive.effect(() -> set(n, name, helder.view.Render.read(v))) else set(n, name, v);
	}

	public static function style(n:HostNode, v:Dynamic) {
		if (helder.view.Render.isReactive(v)) helder.view.Reactive.effect(() -> Host.setStyle(n, helder.view.Render.read(v))) else Host.setStyle(n, v);
	}

	public static inline function ref(n:HostNode, v:Dynamic)
		(v : HostNode->Void)(n);

	// {...object}: its fields as attributes
	public static function spread(n:HostNode, o:Dynamic)
		for (f in Reflect.fields(o))
			attr(n, f, Reflect.field(o, f));

	// --- control flow (helder.view.Flow) ---

	// For: keyed rows, kept and moved
	static function forList(list:helder.view.Flow.ForList, parent:HostNode, before:Null<HostNode>):Array<HostNode> {
		var anchor = marker(parent, before, "for");
		// (the rows belong to the owner the list is mounted in, not to the
		// effect below: its next run would dispose the rows it keeps)
		var home = helder.view.Reactive.owner;
		var entries:Array<{item:Dynamic, nodes:Array<HostNode>, owner:helder.view.Owner}> = [];
		helder.view.Reactive.effect(() -> {
			var items:Array<Dynamic> = helder.view.Render.read(list.each);
			if (items == null) items = [];
			helder.view.Reactive.untrack(() -> {
				var next = [];
				// (the old entries matched: an item is looked for from the first
				// one not taken, so that a list kept in order matches in one pass)
				var old = entries, taken = [for (_ in old) false], first = 0;
				for (item in items) {
					var k = -1;
					for (j in first...old.length)
						if (!taken[j] && old[j].item == item) {
							k = j;
							break;
						}
					if (k >= 0) {
						next.push(old[k]);
						taken[k] = true;
						while (first < old.length && taken[first])
							first++;
					} else {
						var o = new helder.view.Owner(home);
						var saved = helder.view.Reactive.owner;
						helder.view.Reactive.owner = o;
						#if hxmc.dev
						// (hxmc dev: a row's keys under its position)
						var nodes = try helder.dev.Hot.scope(Std.string(next.length), () -> insert(list.render(item), parent, anchor)) catch (e:Dynamic) {
						#else
						var nodes = try insert(list.render(item), parent, anchor) catch (e:Dynamic) {
						#end
							helder.view.Reactive.owner = saved;
							throw e;
						}
						helder.view.Reactive.owner = saved;
						next.push({item: item, nodes: nodes, owner: o});
					}
				}
				for (j in 0...old.length)
					if (!taken[j]) {
						old[j].owner.dispose();
						for (n in old[j].nodes)
							detach(parent, n);
					}
				// in order, before the anchor (where the rows are: the new ones
				// were put there; a row's node moved out by hand is put back)
				Host.arrange(parent, [for (e in next) for (n in e.nodes) n], anchor);
				entries = next;
			});
		});
		helder.view.Reactive.onCleanup(() -> for (e in entries)
			for (n in e.nodes)
				detach(parent, n));
		return [anchor];
	}

	// Index: a row per index, its item in a signal
	static function indexList(list:helder.view.Flow.IndexList, parent:HostNode, before:Null<HostNode>):Array<HostNode> {
		var anchor = marker(parent, before, "index");
		var home = helder.view.Reactive.owner;
		var rows:Array<{item:helder.view.Signal<Dynamic>, nodes:Array<HostNode>, owner:helder.view.Owner}> = [];
		helder.view.Reactive.effect(() -> {
			var items:Array<Dynamic> = helder.view.Render.read(list.each);
			if (items == null) items = [];
			helder.view.Reactive.untrack(() -> {
				var keep = items.length < rows.length ? items.length : rows.length;
				helder.view.Reactive.batch(() -> for (i in 0...keep)
					rows[i].item.value = items[i]);
				while (rows.length > items.length) {
					var r = rows.pop();
					r.owner.dispose();
					for (n in r.nodes)
						detach(parent, n);
				}
				for (i in rows.length...items.length) {
					var o = new helder.view.Owner(home);
					var saved = helder.view.Reactive.owner;
					helder.view.Reactive.owner = o;
					var item = new helder.view.Signal<Dynamic>(items[i]);
					#if hxmc.dev
					var nodes = try helder.dev.Hot.scope(Std.string(i), () -> insert(list.render(item, i), parent, anchor)) catch (e:Dynamic) {
					#else
					var nodes = try insert(list.render(item, i), parent, anchor) catch (e:Dynamic) {
					#end
						helder.view.Reactive.owner = saved;
						throw e;
					}
					helder.view.Reactive.owner = saved;
					rows.push({item: item, nodes: nodes, owner: o});
				}
			});
		});
		helder.view.Reactive.onCleanup(() -> for (r in rows)
			for (n in r.nodes)
				detach(parent, n));
		return [anchor];
	}

	// ErrorBoundary: its children, or the fallback for an error
	static function boundary(b:helder.view.Flow.Boundary, parent:HostNode, before:Null<HostNode>):Array<HostNode> {
		var anchor = marker(parent, before, "boundary");
		// (the error, boxed: null is none)
		var error = new helder.view.Signal<Null<{e:Dynamic}>>(null);
		var current:Array<HostNode> = [];
		function clear() {
			for (n in current)
				detach(parent, n);
			current = [];
		}
		function show(err:Null<{e:Dynamic}>):Void {
			clear();
			if (err != null) {
				current = insert(b.fallback(err.e, () -> error.value = null), parent, anchor);
				return;
			}
			// the children in an owner of their own, which catches their errors
			var o = new helder.view.Owner(helder.view.Reactive.owner);
			o.onError = e -> error.value = {e: e};
			var saved = helder.view.Reactive.owner;
			helder.view.Reactive.owner = o;
			var made:Array<HostNode> = [];
			try {
				insertTo(b.children, parent, anchor, made);
				current = made;
				helder.view.Reactive.owner = saved;
			} catch (e:Dynamic) {
				helder.view.Reactive.owner = saved;
				// (what was put before the error, removed)
				o.dispose();
				for (n in made)
					detach(parent, n);
				current = insert(b.fallback(e, () -> error.value = null), parent, anchor);
			}
		}
		helder.view.Reactive.effect(() -> {
			var err = error.value;
			helder.view.Reactive.untrack(() -> show(err));
		});
		helder.view.Reactive.onCleanup(clear);
		return [anchor];
	}

	// Loading: its children, the fallback instead while what they read on
	// their first load is not ready (they are dropped and made again once
	// it is); once shown they stay
	static function loading(w:helder.view.Flow.Waiting, parent:HostNode, before:Null<HostNode>):Array<HostNode> {
		var anchor = marker(parent, before, "loading");
		var owner = helder.view.Reactive.owner;
		var current:Array<HostNode> = [], content:Null<helder.view.Owner> = null, shown = false, done = false, tries = 0;
		function clear() {
			if (content != null) content.dispose();
			content = null;
			for (n in current)
				detach(parent, n);
			current = [];
		}
		function attempt() {
			if (done) return;
			var at = ++tries;
			clear();
			var waiting:Array<helder.view.Pending.Loadable> = [];
			var o = new helder.view.Owner(owner);
			// (after the first load: nothing to wait for, the content stays)
			o.onPending = p -> if (!shown && !waiting.contains(p.source)) waiting.push(p.source);
			content = o;
			var saved = helder.view.Reactive.owner;
			helder.view.Reactive.owner = o;
			var made:Array<HostNode> = [];
			try {
				insertTo(w.children, parent, anchor, made);
				helder.view.Reactive.owner = saved;
			} catch (e:helder.view.Pending) {
				// (read while it was made, not in a computation of its own)
				helder.view.Reactive.owner = saved;
				if (!waiting.contains(e.source)) waiting.push(e.source);
			} catch (e:Dynamic) {
				helder.view.Reactive.owner = saved;
				o.dispose();
				for (n in made)
					detach(parent, n);
				content = null;
				// (an ErrorBoundary above takes it)
				if (owner == null || !owner.handle(e)) throw e;
				return;
			}
			current = made;
			if (waiting.length == 0) {
				shown = true;
				return;
			}
			// (not ready: the content dropped, the fallback until all it read is)
			clear();
			var f = new helder.view.Owner(owner);
			content = f;
			helder.view.Reactive.owner = f;
			try current = insert(w.fallback, parent, anchor) catch (e:Dynamic) {
				helder.view.Reactive.owner = saved;
				throw e;
			}
			helder.view.Reactive.owner = saved;
			var left = waiting.length;
			for (l in waiting)
				l.whenReady(() -> if (--left == 0 && at == tries) helder.view.Reactive.runWithOwner(owner, attempt));
		}
		attempt();
		helder.view.Reactive.onCleanup(() -> {
			done = true;
			clear();
		});
		return [anchor];
	}

	// (this runtime's renderer: its id, Render.idOf, and class path)
	static inline var INDEX = 0;
	static inline var NAME = "";
}
