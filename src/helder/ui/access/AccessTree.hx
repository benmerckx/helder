package helder.ui.access;

import helder.ui.*;

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
		var top:AccessNode = {id: idOf(ui.root), role: Group, width: ui.width, height: ui.height};
		root = top.id;
		add(ui.root, top);
		for (c in ui.root.children)
			visit(c, top, 0, 0, false, ui.root.visible(), ui);
		// (the popups: after the tree)
		for (c in ui.overlay.children)
			visit(c, top, 0, 0, false, ui.overlay.visible(), ui);
		var f = ui.focus;
		focus = f != null && byId.exists(f.accessId) ? f.accessId : 0;
		counted();
	}

	// the items' places in their sets, the tables' rows and cells
	function counted() {
		for (id in order) {
			var a = nodes.get(id);
			if (a.role == Table) table(a);
			// (siblings of a kind: a set; a tree's by level, a run of them)
			var kids = a.children;
			var i = 0;
			while (i < kids.length) {
				var k = nodes.get(kids[i]), kind = setKind(k.role);
				if (kind == 0) {
					i++;
					continue;
				}
				var run = [k], j = i + 1;
				while (j < kids.length && setKind(nodes.get(kids[j]).role) == kind)
					run.push(nodes.get(kids[j++]));
				if (kind == 4) {
					// (each level's items between the items above it)
					for (x in 0...run.length) {
						var lv = run[x].level ?? 1, pos = 0, size = 0, seen = false;
						for (y in 0...run.length) {
							var l = run[y].level ?? 1;
							if (l < lv) {
								if (seen) break;
								pos = size = 0;
								continue;
							}
							if (l != lv) continue;
							size++;
							if (y <= x) pos = size;
							if (y == x) seen = true;
						}
						run[x].posInSet = pos;
						run[x].setSize = size;
					}
				} else
					for (x in 0...run.length) {
						// (given by its node: a set not all in the tree)
						var sem = byId.get(run[x].id).semantics;
						if (sem != null && sem.setSize > 0) continue;
						run[x].posInSet = x + 1;
						run[x].setSize = run.length;
					}
				i = j;
			}
		}
	}

	// (the roles counted as one set: 0, none)
	static function setKind(r:Role):Int
		return switch r {
			case ListItem | ListBoxOption: 1;
			case Tab: 2;
			case RadioButton: 3;
			case TreeItem: 4;
			case MenuItem | MenuItemCheckBox | MenuItemRadio: 5;
			case _: 0;
		}

	// a table's rows (below it, not in another table) and their cells
	function table(t:AccessNode) {
		var rows = tableRows(t.id);
		var cols = 0;
		for (i in 0...rows.length) {
			rows[i].rowIndex = i;
			var cells = rowCells(rows[i].id);
			for (j in 0...cells.length) {
				cells[j].rowIndex = i;
				cells[j].colIndex = j;
			}
			if (cells.length > cols) cols = cells.length;
		}
		t.rowCount = rows.length;
		t.colCount = cols;
	}

	// (the nodes of a kind below one, not inside another table or row)
	function find(id:Int, want:Role->Bool, out:Array<AccessNode>):Array<AccessNode> {
		for (k in nodes.get(id).children) {
			var c = nodes.get(k);
			if (want(c.role)) out.push(c) else if (c.role != Table && c.role != Row) find(k, want, out);
		}
		return out;
	}

	// a table's rows, in order
	public function tableRows(id:Int):Array<AccessNode>
		return find(id, r -> r == Row, []);

	// a row's cells (its column headers' too), in order
	public function rowCells(id:Int):Array<AccessNode>
		return find(id, r -> r == Cell || r == ColumnHeader, []);

	// a table's cell at a row and column (null: none)
	public function cellAt(table:Int, row:Int, col:Int):Null<AccessNode> {
		var rows = tableRows(table);
		if (row < 0 || row >= rows.length) return null;
		var cells = rowCells(rows[row].id);
		return col >= 0 && col < cells.length ? cells[col] : null;
	}

	// a column's header (null: none): the first row's cell there, when a ColumnHeader
	public function columnHeader(table:Int, col:Int):Null<AccessNode> {
		for (r in tableRows(table)) {
			var cells = rowCells(r.id);
			if (col < cells.length && cells[col].role == ColumnHeader) return cells[col];
		}
		return null;
	}

	// the parent of each node (the root's: 0)
	public function parents():Map<Int, Int> {
		var out = new Map<Int, Int>();
		for (id in order)
			for (k in nodes.get(id).children)
				out.set(k, id);
		return out;
	}

	// the node of an id's nearest ancestor of a role (0: none)
	public function ancestor(id:Int, role:Role, ?parents:Map<Int, Int>):Int {
		var p = parents ?? this.parents();
		var at = p.get(id);
		while (at != null) {
			if (nodes.get(at).role == role) return at;
			at = p.get(at);
		}
		return 0;
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
	// scrolling; inName: inside a node named by its content (its text taken);
	// seen: the parent visible (Style.visibility: a hidden node's own
	// semantics left out, its visible descendants not)
	function visit(n:Node, parent:AccessNode, sx:Float, sy:Float, inName:Bool, seen:Bool, ui:Ui) {
		var s = n.style;
		if (s.display == None || s.opacity <= 0) return;
		var sem = n.semantics;
		if (sem != null && sem.hidden) return;
		if (s.visibility != null) seen = s.visibility == Visible;
		var role:Null<Role> = !seen ? null : sem != null ? sem.role : null;
		if (role == null && seen) {
			if (Std.isOfType(n, ImageNode)) role = sem != null && sem.label != null ? Image : null else if (Std.isOfType(n, TextNode))
				role = inName || (cast n : TextNode).allText() == "" ? null : Label else if (n.focusable || sem != null && sem.live != Off) role = Group;
		}
		var here = parent;
		if (role != null) {
			// (where it is drawn: scrolled, transformed)
			var b = sx == 0 && sy == 0 && !transformed(n) ? null : n.windowBounds();
			var a:AccessNode = {
				id: idOf(n),
				role: role,
				x: b == null ? n.absX : b.x,
				y: b == null ? n.absY : b.y,
				width: b == null ? n.width : b.width,
				height: b == null ? n.height : b.height,
				focusable: n.focusable
			};
			if (sem != null) {
				a.description = sem.description;
				a.href = sem.href;
				a.checked = sem.checked;
				a.mixed = sem.mixed;
				a.selected = sem.selected;
				a.multiselectable = sem.multiselectable;
				a.current = sem.current;
				if (sem.live != Off) {
					a.live = sem.live;
					a.liveText = textOf(n);
				}
				a.expanded = sem.expanded;
				a.level = sem.level;
				a.disabled = sem.disabled;
				a.valueNow = sem.valueNow;
				a.valueMin = sem.valueMin;
				a.valueMax = sem.valueMax;
				a.valueText = sem.valueText;
				if (sem.setSize > 0) {
					a.posInSet = sem.posInSet;
					a.setSize = sem.setSize;
				}
			}
			a.name = sem != null && sem.label != null ? sem.label : role == Label ? (cast n : TextNode).allText() : role.namedByContent() ? textOf(n) : "";
			var own = Std.isOfType(n, TextNode) ? null : n.accessValue();
			if ((role == TextInput || role == MultilineTextInput || role == ComboBox || role == SpinButton) && (own != null || Std.isOfType(n, TextNode))) {
				var text = own != null ? own : (cast n : TextNode).text;
				a.value = sem != null && sem.secret ? StringTools.lpad("", "\u2022", text.length) : text;
				a.secret = sem != null && sem.secret;
				var t = n.accessText();
				if (t != null) {
					a.textStart = t.start;
					a.textEnd = t.end;
					a.caret = t.caret;
					a.readOnly = t.readOnly;
				}
			}
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
				visit(c, here, sx, sy, named, seen, ui);
	}

	// whether it or an ancestor has a transform
	static function transformed(n:Null<Node>):Bool {
		while (n != null) {
			if (n.style.transform != null) return true;
			n = n.parent;
		}
		return false;
	}

	// the text of the TextNodes in n (space separated): a name from content
	public static function textOf(n:Node):String {
		var parts = [];
		function walk(m:Node) {
			// (hidden text, a decoration such as a menu's triangle, is not part of the name)
			if (m.style.display == None || m.semantics != null && m.semantics.hidden) return;
			if (Std.isOfType(m, TextNode)) {
				if (!m.visible()) return;
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

	// what the live regions say since prev: each one there before whose text
	// changed, its new text (what was added at its end, when it grew)
	public function announcements(prev:Null<AccessTree>):Array<{id:Int, text:String, live:Live}> {
		var out = [];
		if (prev == null) return out;
		for (id in order) {
			var a = nodes.get(id);
			if (a.live == Off) continue;
			var b = prev.nodes.get(id);
			if (b == null || b.liveText == a.liveText || a.liveText == null || a.liveText == "") continue;
			var old = b.liveText ?? "", text = a.liveText;
			if (old != "" && StringTools.startsWith(text, old)) text = StringTools.trim(text.substr(old.length));
			if (text != "") out.push({id: id, text: text, live: a.live});
		}
		return out;
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
