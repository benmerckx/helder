package helder.view;

// Mounting content into one renderer's nodes on helder.view.graph, Solid
// 2's way: each part is made once, and what it reads is bound by a render
// effect whose compute reads (tracked, in the graph) and whose apply
// touches the nodes (after the commit: a change that waits on a value not
// ready is held, the nodes keeping what they showed). Written against Host
// (the renderer) and HostNode (its nodes), placeholders: ViewRuntime itself
// is only the template of ViewRuntime_<renderer>, made for each renderer
// the program reaches (HostMacro), so that every call below is a direct
// call to its renderer. (Being copied, it names other types by their full
// paths.)
//
// Content is a View (a markup literal: its code for this renderer runs, an
// agnostic literal's through late; another renderer's an error), a node,
// text (String, numbers), an Array of content, null, For, Loading or
// Errored content, a Mountable of this renderer's nodes, or something
// reactive: a node (a signal, a memo), a Read of one, a function () ->
// content (a hole that may read), whose region is drawn again when what it
// reads changes (its nodes replaced before a marker, its computations
// disposed with them).
//
// The markup macro's code calls the rest: attributes (a reactive value, but
// an event's, is bound: set again when it changes), runs of text and holes
// whose values are text (one text node, bound if one of them is reactive;
// in an element that holds text, its own text, or spans beside its child
// elements), components (called once, untracked, in an owner of their own;
// one that reads a value not ready while it is made is made once it is).
@:build(helder.view.HostMacro.build())
class ViewRuntime {
	// renders content into parent (its root: dispose removes it and stops its
	// effects); at the top (no owner), what it scheduled flushed before it returns
	public static function render(content:Any, parent:HostNode):Void->Void {
		var top = helder.view.graph.Graph.getOwner() == null;
		var d = helder.view.graph.Graph.root(dispose -> {
			#if hxmc.dev
			// (hxmc dev: its effects' cleanups run before the next build starts)
			helder.view.graph.Graph.onCleanup(helder.dev.Hot.onDispose(dispose));
			#end
			var nodes = insert(content, parent, null);
			helder.view.graph.Graph.onCleanup(() -> for (n in nodes)
				detach(parent, n));
			dispose;
		});
		if (top) helder.view.graph.Graph.flush();
		return d;
	}

	// inserts content into parent before a node (null: at the end); the nodes made
	public static function insert(content:Any, parent:HostNode, before:Null<HostNode>):Array<HostNode> {
		var out:Array<HostNode> = [];
		add(content, parent, before, out);
		return out;
	}

	// as insert, the nodes made pushed to out as they are (those made before an error too)
	public static function insertTo(content:Any, parent:HostNode, before:Null<HostNode>, out:Array<HostNode>)
		add(content, parent, before, out);

	// (end: v is its parent's last child, nothing put after it: a region of it needs no marker)
	static function add(v:Dynamic, parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>, end = false) {
		if (v == null || v == false || v == true) return;
		if (Std.isOfType(v, helder.view.View)) view(v, parent, before, out);
		else if (Host.isNode(v)) put(parent, v, before, out);
		else if (Std.isOfType(v, helder.view.Flow.ForList)) mounted(forList(v, parent, before), out);
		else if (Std.isOfType(v, helder.view.Flow.Boundary)) mounted(errored(v, parent, before), out);
		else if (Std.isOfType(v, helder.view.Flow.Waiting)) mounted(loading(v, parent, before), out);
		else if (Std.isOfType(v, helder.view.Flow.Deferred)) component(parent, before, out, (v : helder.view.Flow.Deferred).factory);
		else if (Std.isOfType(v, helder.view.Flow.Mountable)) {
			var m:helder.view.Flow.Mountable<HostNode> = cast v;
			mounted(m.mount(parent, before), out);
		} else if (Std.isOfType(v, Array)) {
			var a:Array<Dynamic> = v;
			for (k in 0...a.length)
				add(a[k], parent, before, out, end && k == a.length - 1);
		} else if (Std.isOfType(v, helder.view.graph.Read.Const)) add((v : helder.view.graph.Read.Const<Dynamic>).value, parent, before, out, end);
		else if (helder.view.Render.isReactive(v)) region(v, parent, before, out, end);
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

	// (the boundaries mounted: the nodes their content keeps in their parents)
	static final captures:Array<helder.view.Mounted.Capture<HostNode>> = [];
	// (a boundary's fallback being put before its anchor: not its content)
	static var fallbackOf:Null<helder.view.Mounted.Capture<HostNode>> = null;

	// n put in parent before before, pushed to out (into a boundary's content
	// while its fallback shows: kept, put in place when it shows)
	public static function put(parent:HostNode, n:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>) {
		var hidden = false;
		for (c in captures)
			if (c != fallbackOf && c.parent == parent && c.owns(before)) {
				c.put(n, before);
				if (!c.attached) hidden = true;
			}
		if (!hidden) Host.insert(parent, n, before);
		if (out != null) out.push(n);
	}

	// n removed from parent, when it is still there
	public static function detach(parent:HostNode, n:HostNode) {
		if (Host.parentOf(n) == parent) Host.remove(parent, n);
		for (c in captures)
			if (c.parent == parent) c.remove(n);
	}

	// (Host.arrange, the boundaries told)
	static function arrange(parent:HostNode, nodes:Array<HostNode>, before:HostNode) {
		var hidden = false;
		for (c in captures)
			if (c.parent == parent && c.owns(before)) {
				c.arranged(nodes, before);
				if (!c.attached) hidden = true;
			}
		if (!hidden) Host.arrange(parent, nodes, before);
	}

	// a marker (Host.createMarker) put in parent before before
	public static function marker(parent:HostNode, before:Null<HostNode>, name:String):HostNode {
		var m = Host.createMarker(name);
		put(parent, m, before, null);
		return m;
	}

	// (content mounted in an owner of its own under home: its nodes; replaced: the old ones removed, their owner disposed)
	static function mountIn(home:Null<helder.view.graph.Owner>, content:Dynamic, parent:HostNode, anchor:Null<HostNode>):helder.view.Mounted.Shown<HostNode> {
		var o = new helder.view.graph.Owner(home);
		var nodes:Array<HostNode> = [];
		try helder.view.graph.Graph.runWithOwner(o, () -> insertTo(content, parent, anchor, nodes)) catch (e:Dynamic) {
			o.dispose();
			for (n in nodes)
				detach(parent, n);
			throw e;
		}
		return new helder.view.Mounted.Shown(o, nodes);
	}

	static function unmount(s:Null<helder.view.Mounted.Shown<HostNode>>, parent:HostNode) {
		if (s == null) return;
		s.owner.dispose();
		for (n in s.nodes)
			detach(parent, n);
	}

	// a reactive region: its content drawn again before a marker
	static function region(getter:Dynamic, parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>, end:Bool) {
		// (its parent's last child: drawn at the end)
		var anchor = end ? null : Host.createMarker("anchor");
		if (anchor != null) put(parent, anchor, before, out);
		var home = helder.view.graph.Graph.getOwner();
		var current:Null<helder.view.Mounted.Shown<HostNode>> = null;
		helder.view.graph.Graph.renderEffect(() -> helder.view.Render.read(getter), (v:Dynamic) -> {
			unmount(current, parent);
			current = null;
			current = mountIn(home, v, parent, anchor);
		});
		helder.view.graph.Graph.onCleanup(() -> unmount(current, parent));
	}

	// --- what markup compiles to ---

	// a component: its factory called once, untracked, in an owner of its own;
	// one that reads a value not ready while it is made: a region that waits
	// for that value (an armed <Loading> above shows its fallback), then makes it
	public static function component(parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>, factory:Void->Any) {
		var o = new helder.view.graph.Owner(helder.view.graph.Graph.getOwner());
		helder.view.Render.pass = INDEX;
		var result:Any = null;
		try result = helder.view.graph.Graph.runWithOwner(o, factory) catch (e:helder.view.graph.Awaitable.NotReady) {
			o.dispose();
			var source:helder.view.graph.Read.Reader<Dynamic> = @:privateAccess helder.view.graph.Node.notReadyNode;
			var ready = false, deferred = new helder.view.Flow.Deferred(factory);
			region(() -> {
				if (!ready) {
					source.read();
					ready = true;
				}
				deferred;
			}, parent, before, out, false);
			return;
		}
		helder.view.graph.Graph.runWithOwner(o, () -> add(result, parent, before, out));
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
			run(el, null, null, parts, false, true);
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
	public static function hole(parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>, v:Any, span:Bool, end = false) {
		var t = textPart(v);
		if (t == null) {
			add(v, parent, before, out, end);
			return;
		}
		var n = span ? Host.createElement("span") : Host.createText("");
		put(parent, n, before, out);
		bindText(n, [t]);
	}

	// a run of text and holes: those whose values are text joined into text
	// nodes, the others content between them
	public static function run(parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>, parts:Array<Any>, span:Bool, end = false) {
		var run:Array<Dynamic> = [];
		function flush() {
			if (run.length == 0) return;
			var n = span ? Host.createElement("span") : Host.createText("");
			put(parent, n, before, out);
			bindText(n, run);
			run = [];
		}
		for (k in 0...parts.length) {
			var p = parts[k];
			var t = textPart(p);
			if (t != null) {
				run.push(t);
				continue;
			}
			flush();
			add(p, parent, before, out, end && k == parts.length - 1);
		}
		flush();
	}

	// the value as a text part (a String, or a reactive one whose value is text now), or null when it is not text
	static function textPart(v:Dynamic):Null<Dynamic> {
		if (isText(v)) return Std.string(v);
		if (Std.isOfType(v, helder.view.graph.Read.Const)) {
			var c = (v : helder.view.graph.Read.Const<Dynamic>).value;
			return isText(c) ? Std.string(c) : null;
		}
		// (a value not ready, or one that fails: not known as text, bound as content: its region waits, or fails)
		if (helder.view.Render.isReactive(v)
			&& isText(try helder.view.graph.Graph.untrack(() -> helder.view.Render.read(v)) catch (_:Dynamic) null)) return v;
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
		if (parts.length == 1) {
			var p = parts[0];
			helder.view.graph.Graph.renderEffect(() -> helder.view.Render.read(p), (v:Dynamic) -> Host.setText(n, v == null ? "" : Std.string(v)));
			return;
		}
		helder.view.graph.Graph.renderEffect(() -> {
			var b = new StringBuf();
			for (p in parts) {
				var v:Dynamic = Std.isOfType(p, String) ? p : helder.view.Render.read(p);
				if (v != null) b.add(Std.string(v));
			}
			b.toString();
		}, (t:String) -> Host.setText(n, t));
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
		if (helder.view.Render.isReactive(v)) helder.view.graph.Graph.renderEffect(() -> helder.view.Render.read(v), (x:Dynamic) -> Host.setProperty(n, name, x));
		else Host.setProperty(n, name, constant(v));
	}

	// (the same with the renderer's function for the name: Renders' setter)
	public static function propWith(n:HostNode, name:String, v:Dynamic, set:(HostNode, String, Dynamic) -> Void) {
		if (helder.view.Render.isReactive(v)) helder.view.graph.Graph.renderEffect(() -> helder.view.Render.read(v), (x:Dynamic) -> set(n, name, x));
		else set(n, name, constant(v));
	}

	public static function style(n:HostNode, v:Dynamic) {
		if (helder.view.Render.isReactive(v)) helder.view.graph.Graph.renderEffect(() -> helder.view.Render.read(v), (x:Dynamic) -> Host.setStyle(n, x));
		else Host.setStyle(n, constant(v));
	}

	// (a Read's constant: its value)
	static inline function constant(v:Dynamic):Dynamic
		return Std.isOfType(v, helder.view.graph.Read.Const) ? (v : helder.view.graph.Read.Const<Dynamic>).value : v;

	public static inline function ref(n:HostNode, v:Dynamic)
		(v : HostNode->Void)(n);

	// {...object}: its fields as attributes
	public static function spread(n:HostNode, o:Dynamic)
		for (f in Reflect.fields(o))
			attr(n, f, Reflect.field(o, f));

	// --- control flow (helder.view.Flow) ---

	// For: rows kept and moved, keyed by item (a row's Read its item) or by index (its Read a signal of what is there)
	static function forList(list:helder.view.Flow.ForList, parent:HostNode, before:Null<HostNode>):Array<HostNode> {
		var anchor = marker(parent, before, "for");
		// (the rows belong to the owner the list is mounted in)
		var home = helder.view.graph.Graph.getOwner();
		var entries:Array<helder.view.Mounted.Row<HostNode>> = [];
		function make(item:Dynamic, at:Int):helder.view.Mounted.Row<HostNode> {
			var cell = list.keyed ? null : helder.view.graph.Node.signal((item : Dynamic), {ownedWrite: true});
			var read:helder.view.graph.Read<Dynamic> = cell != null ? (cell : helder.view.graph.Read.Reader<Dynamic>) : (new helder.view.graph.Read.Const<Dynamic>(item) : helder.view.graph.Read.Reader<Dynamic>);
			#if hxmc.dev
			// (hxmc dev: a row's keys under its position)
			var s = helder.dev.Hot.scope(Std.string(at), () -> mountIn(home, list.render(read), parent, anchor));
			#else
			var s = mountIn(home, list.render(read), parent, anchor);
			#end
			return new helder.view.Mounted.Row(item, s, cell);
		}
		helder.view.graph.Graph.renderEffect(() -> {
			var items:Null<Array<Dynamic>> = list.each.read();
			items == null ? [] : items;
		}, (items:Array<Dynamic>) -> {
			var next:Array<helder.view.Mounted.Row<HostNode>> = [];
			if (!list.keyed) {
				// (by index: the rows kept set to what is at their index, the rest made or removed)
				for (i in 0...items.length) {
					if (i < entries.length) {
						var r = entries[i];
						r.item = items[i];
						r.cell.write(items[i]);
						next.push(r);
					} else next.push(make(items[i], i));
				}
				for (j in items.length...entries.length)
					unmount(entries[j].shown, parent);
				entries = next;
				return;
			}
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
				} else next.push(make(item, next.length));
			}
			for (j in 0...old.length)
				if (!taken[j]) unmount(old[j].shown, parent);
			// in order, before the anchor (where the rows are: the new ones
			// were put there; a row's node moved out by hand is put back)
			arrange(parent, [for (e in next) for (n in e.shown.nodes) n], anchor);
			entries = next;
		});
		helder.view.graph.Graph.onCleanup(() -> for (e in entries)
			unmount(e.shown, parent));
		return [anchor];
	}

	// a boundary's content made (in its compute: what it reads inside waits
	// under it) before anchor, its nodes kept by the capture (the last run's
	// taken out first); what it made before an error taken out
	static function boundaryContent(content:Any, parent:HostNode, c:helder.view.Mounted.Capture<HostNode>) {
		hide(c);
		c.nodes.resize(0);
		c.attached = true;
		var made:Array<HostNode> = [];
		try helder.view.graph.Graph.untrack(() -> insertTo(content, parent, c.anchor, made)) catch (e:Dynamic) {
			hide(c);
			c.nodes.resize(0);
			c.attached = true;
			throw e;
		}
	}

	// (a boundary's content out of the tree, and back before its anchor)
	static function hide(c:helder.view.Mounted.Capture<HostNode>) {
		if (!c.attached) return;
		c.attached = false;
		for (n in c.nodes)
			if (Host.parentOf(n) == c.parent) Host.remove(c.parent, n);
	}

	// (those of its nodes an inner boundary showing its fallback keeps out stay out)
	static function show(c:helder.view.Mounted.Capture<HostNode>) {
		if (c.attached) return;
		c.attached = true;
		for (n in c.nodes) {
			var out = false;
			for (o in captures)
				if (o != c && !o.attached && o.parent == c.parent && o.nodes.indexOf(n) >= 0) out = true;
			if (!out) Host.insert(c.parent, n, c.anchor);
		}
	}

	// (a boundary's fallback mounted before its anchor)
	static function fallbackIn(c:helder.view.Mounted.Capture<HostNode>, home:Null<helder.view.graph.Owner>, content:Any, parent:HostNode,
			anchor:HostNode):helder.view.Mounted.Shown<HostNode> {
		var saved = fallbackOf;
		fallbackOf = c;
		var s = try mountIn(home, content, parent, anchor) catch (e:Dynamic) {
			fallbackOf = saved;
			throw e;
		}
		fallbackOf = saved;
		return s;
	}

	// (a boundary's capture, kept while it is mounted)
	static function captureAt(parent:HostNode, anchor:HostNode):helder.view.Mounted.Capture<HostNode> {
		var c = new helder.view.Mounted.Capture(parent, anchor);
		captures.push(c);
		helder.view.graph.Graph.onCleanup(() -> {
			hide(c);
			captures.remove(c);
		});
		return c;
	}

	// Loading: its children, made at once; the fallback instead while what
	// they read on their first load is pending (Graph.loadingBoundary), their
	// nodes taken out meanwhile and put back when it lands
	static function loading(w:helder.view.Flow.Waiting, parent:HostNode, before:Null<HostNode>):Array<HostNode> {
		var anchor = marker(parent, before, "loading");
		var home = helder.view.graph.Graph.getOwner();
		var content = captureAt(parent, anchor);
		var fallback:Null<helder.view.Mounted.Shown<HostNode>> = null;
		var shows = helder.view.graph.Graph.loadingBoundary(() -> {
			boundaryContent(w.children, parent, content);
			true;
		}, () -> false);
		helder.view.graph.Graph.renderEffect(() -> shows(), (on:Bool) -> {
			if (on) {
				show(content);
				unmount(fallback, parent);
				fallback = null;
			} else {
				hide(content);
				if (fallback == null) fallback = fallbackIn(content, home, w.fallback, parent, anchor);
			}
		});
		helder.view.graph.Graph.onCleanup(() -> unmount(fallback, parent));
		return [anchor];
	}

	// Errored: its children, or the fallback for an error (Graph.errorBoundary)
	static function errored(b:helder.view.Flow.Boundary, parent:HostNode, before:Null<HostNode>):Array<HostNode> {
		var anchor = marker(parent, before, "boundary");
		var home = helder.view.graph.Graph.getOwner();
		var content = captureAt(parent, anchor);
		var fallback:Null<helder.view.Mounted.Shown<HostNode>> = null;
		var shows = helder.view.graph.Graph.errorBoundary(() -> {
			boundaryContent(b.children, parent, content);
			(null : Dynamic);
		}, (error, reset) -> (new helder.view.Mounted.FallbackOf(b.fallback(error(), reset)) : Dynamic));
		helder.view.graph.Graph.renderEffect(() -> shows(), (v:Dynamic) -> {
			unmount(fallback, parent);
			fallback = null;
			if (Std.isOfType(v, helder.view.Mounted.FallbackOf)) {
				hide(content);
				fallback = fallbackIn(content, home, (v : helder.view.Mounted.FallbackOf).content, parent, anchor);
			} else show(content);
		});
		helder.view.graph.Graph.onCleanup(() -> unmount(fallback, parent));
		return [anchor];
	}

	// (this runtime's renderer: its id, Render.idOf, and class path)
	static inline var INDEX = 0;
	static inline var NAME = "";
}
