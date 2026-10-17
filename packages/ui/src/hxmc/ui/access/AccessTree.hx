package hxmc.ui.access;

import hxmc.ui.*;

// The accessibility tree of a Ui (AccessKit's model): the nodes assistive
// technology sees, built from the Node tree after layout. A Node is in it
// when it has a role (its semantics, or by kind: a TextNode is a Label of
// its text, an ImageNode with a label an Image, a focusable node a Group);
// the others only group (their children go to the nearest node in it).
// The roles named by their content (a button) take their text from the
// TextNodes inside, which are then not nodes of their own. Ids are the
// Nodes' (stable while a node lives). changes() gives what changed since
// another tree: the incremental update an adapter applies.
class AccessTree {
	public final root:Int;
	// the focused node's id (0: none)
	public final focus:Int;
	public final nodes:Map<Int, AccessNode> = [];
	// the ids in tree order
	public final order:Array<Int> = [];
	final byId:Map<Int, Node> = [];

	static var nextId = 1;

	function new(ui:Ui) {
		var top:AccessNode = {id: idOf(ui.root), role: Group};
		root = top.id;
		add(ui.root, top);
		for (c in ui.root.children)
			visit(c, top, 0, 0, false, ui);
		// (the popups: after the tree)
		for (c in ui.overlay.children)
			visit(c, top, 0, 0, false, ui);
		var f = ui.focus;
		focus = f != null && byId.exists(f.accessId) ? f.accessId : 0;
	}

	public static function build(ui:Ui):AccessTree
		return new AccessTree(ui);

	// the Node of an id in this tree (null: none)
	public function node(id:Int):Null<Node>
		return byId.get(id);

	static function idOf(n:Node):Int {
		if (n.accessId == 0) n.accessId = nextId++;
		return n.accessId;
	}

	function add(n:Node, a:AccessNode) {
		nodes.set(a.id, a);
		order.push(a.id);
		byId.set(a.id, n);
	}

	// n under parent (the nearest node in the tree); sx, sy: the ancestors'
	// scrolling; inName: inside a node named by its content (its text taken)
	function visit(n:Node, parent:AccessNode, sx:Float, sy:Float, inName:Bool, ui:Ui) {
		var s = n.style;
		if (s.display == None || s.opacity <= 0) return;
		var sem = n.semantics;
		if (sem != null && sem.hidden) return;
		var role:Null<Role> = sem != null ? sem.role : null;
		if (role == null) {
			if (Std.isOfType(n, ImageNode)) role = sem != null && sem.label != null ? Image : null else if (Std.isOfType(n, TextNode))
				role = inName || (cast n : TextNode).allText() == "" ? null : Label else if (n.focusable) role = Group;
		}
		var here = parent;
		if (role != null) {
			var a:AccessNode = {
				id: idOf(n),
				role: role,
				x: n.absX - sx,
				y: n.absY - sy,
				width: n.width,
				height: n.height,
				focusable: n.focusable
			};
			if (sem != null) {
				a.description = sem.description;
				a.checked = sem.checked;
				a.selected = sem.selected;
				a.expanded = sem.expanded;
				a.level = sem.level;
				a.disabled = sem.disabled;
				a.valueNow = sem.valueNow;
				a.valueMin = sem.valueMin;
				a.valueMax = sem.valueMax;
				a.valueText = sem.valueText;
			}
			a.name = sem != null && sem.label != null ? sem.label : role == Label ? (cast n : TextNode).allText() : role.namedByContent() ? textOf(n) : "";
			if ((role == TextInput || role == MultilineTextInput) && Std.isOfType(n, TextNode)) a.value = (cast n : TextNode).text;
			parent.children.push(a.id);
			add(n, a);
			here = a;
		}
		var named = inName || (role != null && role.namedByContent());
		if (s.overflow == Scroll) {
			sx += n.scrollX;
			sy += n.scrollY;
		}
		// (a TextNode's text is its own, its spans' included: no children to visit)
		if (!Std.isOfType(n, TextNode))
			for (c in n.children)
				visit(c, here, sx, sy, named, ui);
	}

	// the text of the TextNodes in n (space separated)
	static function textOf(n:Node):String {
		var parts = [];
		function walk(m:Node) {
			// (hidden text, a decoration such as a menu's triangle, is not part of the name)
			if (m.style.display == None || m.semantics != null && m.semantics.hidden) return;
			if (Std.isOfType(m, TextNode)) {
				var t = StringTools.trim((cast m : TextNode).allText());
				if (t != "") parts.push(t);
				return;
			}
			for (c in m.children)
				walk(c);
		}
		walk(n);
		return parts.join(" ");
	}

	// what changed since prev (null: everything): the nodes new or changed,
	// the ids gone, the root and the focus
	public function changes(prev:Null<AccessTree>):{nodes:Array<AccessNode>, removed:Array<Int>, root:Int, focus:Int} {
		var changed = [], removed = [];
		for (id in order) {
			var a = nodes.get(id), b = prev == null ? null : prev.nodes.get(id);
			if (b == null || !a.equals(b)) changed.push(a);
		}
		if (prev != null)
			for (id in prev.order)
				if (!nodes.exists(id)) removed.push(id);
		return {nodes: changed, removed: removed, root: root, focus: focus};
	}

	// changes as JSON (the browser adapter's update): null when nothing changed
	public function changesJson(prev:Null<AccessTree>):Null<String> {
		var c = changes(prev);
		if (prev != null && c.nodes.length == 0 && c.removed.length == 0 && c.focus == prev.focus) return null;
		return haxe.Json.stringify({
			full: prev == null,
			root: c.root,
			focus: c.focus,
			nodes: [for (n in c.nodes) n.toJson()],
			removed: c.removed
		});
	}
}
