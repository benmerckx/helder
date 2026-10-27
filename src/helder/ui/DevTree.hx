package helder.ui;

#if (hxmc.dev && !macro)
// The devtools' Ui domain (src/helder/devtools/README.md), in dev builds:
// each Ui made registers here (Ui's constructor), the first one the method
// Ui.getTree with helder.devtools.Agent. A snapshot is each Ui's root and
// overlay as plain data: a node's id (kept while the node is in a tree:
// the same node, the same id; not across a reload), tag, box (window
// pixels, after the last update), a few style fields and a text node's text.
class DevTree {
	// (the last few Ui made: a program has one per window)
	static inline var KEPT = 8;

	static final uis:Array<Ui> = [];
	static var ids = new haxe.ds.ObjectMap<Node, Int>();
	static var nextId = 1;

	public static function add(ui:Ui) {
		if (uis.length == 0) helder.devtools.Agent.method("Ui.getTree", _ -> tree());
		uis.push(ui);
		if (uis.length > KEPT) uis.shift();
	}

	static function tree():Dynamic {
		var seen = new haxe.ds.ObjectMap<Node, Int>();
		var roots = [for (ui in uis) {width: ui.width, height: ui.height, root: node(ui.root, seen), overlay: node(ui.overlay, seen)}];
		ids = seen;
		return {uis: roots};
	}

	static function node(n:Node, seen:haxe.ds.ObjectMap<Node, Int>):Dynamic {
		var id = ids.get(n);
		if (id == null) id = nextId++;
		seen.set(n, id);
		var s = n.style;
		var o:Dynamic = {
			id: id,
			tag: n.tag,
			x: n.absX,
			y: n.absY,
			width: n.width,
			height: n.height,
			style: {
				display: ["flex", "none", "grid", "block"][cast s.display],
				direction: ["column", "row", "column-reverse", "row-reverse"][cast s.direction],
				grow: s.grow,
				opacity: s.opacity,
				background: color(s.background),
				color: s.color == null ? null : color(s.color),
				fontSize: s.fontSize,
			},
			text: Std.isOfType(n, TextNode) ? (cast n : TextNode).text : null,
			children: [for (c in n.children) node(c, seen)],
		};
		return o;
	}

	static function color(c:Color):String
		return "#" + StringTools.hex((c : Int), 8).toLowerCase();
}
#end
