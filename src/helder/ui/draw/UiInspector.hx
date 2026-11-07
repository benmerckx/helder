package helder.ui.draw;

import helder.headless.Inspector;
import helder.ui.*;
import helder.ui.menu.DrawnMenu;
import helder.ui.platform.PlatformMenuItem;

// A UiWindow's content as a headless run sees it (helder.headless, a build
// with -D helder.headless): each node displayed, from the root's children
// and the overlay's (popups), where it is drawn (Node.windowBounds: its
// ancestors' scrolling and transforms), its opacity through its
// ancestors', its background and text colour, its state, its role, label
// and value from the accessibility tree (Ui.accessTree), whether a
// transition is moving it; and its pop-up menus (DrawnMenu), chosen from.
class UiInspector implements Inspector {
	final ui:Ui;
	final ids = new haxe.ds.ObjectMap<Node, Int>();
	var nextId = 1;

	public function new(ui:Ui)
		this.ui = ui;

	public function nodes():Array<InspectedNode> {
		var out = [];
		var access = ui.accessTree();
		for (c in ui.root.children)
			visit(c, 0, 0, "", 1, access, out);
		for (c in ui.overlay.children)
			visit(c, 0, 0, "", 1, access, out);
		return out;
	}

	function idOf(n:Node):Int {
		var id = ids.get(n);
		if (id == null) {
			id = nextId++;
			ids.set(n, id);
		}
		return id;
	}

	function visit(n:Node, parent:Int, depth:Int, path:String, opacity:Float, access:helder.ui.access.AccessTree, out:Array<InspectedNode>) {
		var s = n.style;
		if (s.display == None) return;
		var b = n.windowBounds();
		var path = path == "" ? n.tag : path + "/" + n.tag;
		var op = opacity * s.opacity;
		var text = Std.isOfType(n, TextNode) ? (cast n : TextNode).text : null;
		var a = access.nodes.get(@:privateAccess n.accessId);
		if (a != null && access.node(a.id) != n) a = null;
		var themed = @:privateAccess s.themed;
		var node:InspectedNode = {
			id: idOf(n),
			parent: parent,
			depth: depth,
			tag: n.tag,
			path: path,
			role: a == null ? null : a.role.aria(),
			label: a == null || a.name == "" || a.name == text ? null : a.name,
			text: text,
			value: a == null ? null : a.value,
			checked: a == null ? null : a.checked,
			disabled: a != null && a.disabled,
			x: b.x,
			y: b.y,
			width: b.width,
			height: b.height,
			opacity: op,
			fill: s.background == Color.TRANSPARENT ? null : hex(s.background),
			color: text != null ? hex(n.textColor()) : null,
			hover: n.hovered,
			press: n.pressed,
			focus: n.focused,
			transitioning: themed != null && themed.moving != null,
			source: n.source,
			component: n.sourceComponent
		};
		out.push(node);
		for (c in n.children)
			visit(c, node.id, depth + 1, path, op, access, out);
	}

	// "#rrggbb", "#rrggbbaa" when not opaque
	static function hex(c:Color):String {
		var s = "#" + StringTools.hex(c.r, 2) + StringTools.hex(c.g, 2) + StringTools.hex(c.b, 2);
		if (c.a != 255) s += StringTools.hex(c.a, 2);
		return s.toLowerCase();
	}

	public function menuPick(id:Null<Int>, label:Null<String>):Null<String> {
		var m = DrawnMenu.current;
		if (m == null || @:privateAccess m.closed) return "no pop-up menu is open";
		var items:Array<PlatformMenuItem> = @:privateAccess m.items;
		var it = findItem(items, id, label);
		if (it == null) return 'the menu has no item ${label ?? Std.string(id)} (${[for (i in items) if (i.separator != true) '${i.id}: ${i.label}'].join(", ")})';
		if (it.disabled == true) return 'the menu\'s item ${it.label} is disabled';
		@:privateAccess m.closeAll(it.id);
		return null;
	}

	static function findItem(items:Array<PlatformMenuItem>, id:Null<Int>, label:Null<String>):Null<PlatformMenuItem> {
		for (i in items) {
			if (i.separator == true) continue;
			if (i.items == null && (id != null ? i.id == id : i.label == label)) return i;
			if (i.items != null) {
				var f = findItem(i.items, id, label);
				if (f != null) return f;
			}
		}
		return null;
	}

	public function menuCancel():Bool {
		var m = DrawnMenu.current;
		if (m == null || @:privateAccess m.closed) return false;
		@:privateAccess m.closeAll(-1);
		return true;
	}
}
