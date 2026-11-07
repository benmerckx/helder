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
		if (uis.length == 0) {
			helder.devtools.Agent.method("Ui.getTree", _ -> tree());
			helder.devtools.Agent.method("Ui.nodesAt", p -> nodesAt(p));
		}
		uis.push(ui);
		if (uis.length > KEPT) uis.shift();
	}

	static function tree():Dynamic
		return treeOf(uis);

	// Ui.getTree's answer of these Uis (a story host's: one screen's)
	public static function treeOf(uis:Array<Ui>):Dynamic {
		var seen = new haxe.ds.ObjectMap<Node, Int>();
		var roots = [for (ui in uis) {width: ui.width, height: ui.height, root: node(ui.root, seen), overlay: node(ui.overlay, seen)}];
		ids = seen;
		return {uis: roots};
	}

	// the source map's reverse lookup (NodeSources): {file, line, col} to the
	// nodes made there, {nodes: [{id, tag, source, component}]}, ids as getTree's
	static function nodesAt(p:Dynamic):Dynamic
		return nodesAtOf(uis, p);

	// Ui.nodesAt's answer in these Uis
	public static function nodesAtOf(uis:Array<Ui>, p:Dynamic):Dynamic {
		var roots = [];
		for (ui in uis) {
			roots.push(ui.root);
			roots.push(ui.overlay);
		}
		var found = NodeSources.at(roots, p.file, Std.int(p.line), p.col == null ? 1 : Std.int(p.col));
		return {nodes: [for (n in found) {id: idOf(n, ids), tag: n.tag, source: sourceOf(n), component: componentOf(n)}]};
	}

	static function idOf(n:Node, seen:haxe.ds.ObjectMap<Node, Int>):Int {
		var id = ids.get(n);
		if (id == null) id = nextId++;
		seen.set(n, id);
		return id;
	}

	static function sourceOf(n:Node):Dynamic
		return n.source == null ? null : n.source.data();

	static function componentOf(n:Node):Dynamic
		return n.sourceComponent == null ? null : n.sourceComponent.data();

	static function node(n:Node, seen:haxe.ds.ObjectMap<Node, Int>):Dynamic {
		var id = idOf(n, seen);
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
			source: sourceOf(n),
			component: componentOf(n),
			children: [for (c in n.children) node(c, seen)],
		};
		return o;
	}

	static function color(c:Color):String
		return "#" + StringTools.hex((c : Int), 8).toLowerCase();
}
#end
