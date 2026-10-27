// A second renderer for ViewTest (its nodes @:rendered(OtherRenderer)),
// its nodes unrelated to TestRenderer's: the same components rendered by
// both, and boundaries between them (a tree of one inside the other's)
class OtherRenderer implements helder.view.Renders<OtherNode> {
	public static function createElement(tag:String):OtherNode
		return new OtherNode(tag);

	public static function createText(text:String):OtherNode {
		var n = new OtherNode("#");
		n.text = text;
		return n;
	}

	public static function createMarker(name:String):OtherNode
		return new OtherNode("!" + name);

	public static function setText(node:OtherNode, text:String)
		node.text = text;

	public static function holdsText(el:OtherNode):Bool
		return false;

	public static function setProperty(el:OtherNode, name:String, value:Dynamic)
		el.attrs.push(name + "=" + value);

	public static function setStyle(el:OtherNode, value:Dynamic) {}

	public static function listen(el:OtherNode, name:String, handler:Dynamic) {}

	public static function insert(parent:OtherNode, node:OtherNode, before:Null<OtherNode>) {
		if (node.parent != null) node.parent.children.remove(node);
		var i = before == null ? -1 : parent.children.indexOf(before);
		if (i < 0) parent.children.push(node) else parent.children.insert(i, node);
		node.parent = parent;
	}

	public static function remove(parent:OtherNode, node:OtherNode) {
		parent.children.remove(node);
		node.parent = null;
	}

	public static function parentOf(node:OtherNode):Null<OtherNode>
		return node.parent;

	public static function arrange(parent:OtherNode, nodes:Array<OtherNode>, before:OtherNode)
		for (n in nodes)
			insert(parent, n, before);

	public static function isNode(v:Dynamic):Bool
		return Std.isOfType(v, OtherNode);
}

@:rendered(OtherRenderer)
class OtherNode {
	public final name:String;
	public var text = "";
	public var parent:Null<OtherNode>;
	public final children:Array<OtherNode> = [];
	public final attrs:Array<String> = [];

	public function new(name:String)
		this.name = name;

	// [name attrs text children], markers left out
	public function toString():String
		return name == "#" ? text : StringTools.startsWith(name, "!") ? "" : "[" + [name].concat(attrs).join(" ") + (text == "" ? "" : " " + text)
			+ [for (c in children) c.toString()].join("") + "]";
}
