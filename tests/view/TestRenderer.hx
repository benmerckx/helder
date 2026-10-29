// A renderer for helder.view's tests (its nodes @:rendered(TestRenderer): the
// contract tested through an explicit mark, as a package's renderer has it):
// elements, texts and markers in a plain tree, written out as HTML
// (markers as comments); a "p" element holds text, as ui's text nodes do,
// so that both content models are tested
class TestRenderer implements helder.view.Renders<TestNode> {
	// the operations, in order (insert, remove, arrange), for checks
	public static final log:Array<String> = [];

	public static function createElement(tag:String):TestNode
		return new TestNode(Element, tag);

	public static function createText(text:String):TestNode {
		var n = new TestNode(Text, "#text");
		n.text = text;
		return n;
	}

	public static function createMarker(name:String):TestNode
		return new TestNode(Marker, name);

	public static function setText(node:TestNode, text:String)
		node.text = text;

	public static function holdsText(el:TestNode):Bool
		return el.kind == Element && (el.tag == "p" || el.tag == "span");

	public static function setProperty(el:TestNode, name:String, value:Dynamic)
		el.props.set(name, value);

	public static function setStyle(el:TestNode, value:Dynamic)
		el.props.set("style", value);

	public static function listen(el:TestNode, name:String, handler:Dynamic)
		el.listeners.set(name, handler);

	public static function insert(parent:TestNode, node:TestNode, before:Null<TestNode>) {
		if (node.parent != null) node.parent.children.remove(node);
		var i = before == null ? -1 : parent.children.indexOf(before);
		if (i < 0) parent.children.push(node) else parent.children.insert(i, node);
		node.parent = parent;
	}

	public static function remove(parent:TestNode, node:TestNode) {
		parent.children.remove(node);
		node.parent = null;
		log.push("remove");
	}

	public static function parentOf(node:TestNode):Null<TestNode>
		return node.parent;

	public static function arrange(parent:TestNode, nodes:Array<TestNode>, before:TestNode) {
		var at = parent.children.indexOf(before);
		var inPlace = at >= nodes.length;
		if (inPlace)
			for (k in 0...nodes.length)
				if (parent.children[at - nodes.length + k] != nodes[k]) inPlace = false;
		if (inPlace) return;
		log.push("arrange");
		for (n in nodes)
			insert(parent, n, before);
	}

	public static function isNode(v:Dynamic):Bool
		return Std.isOfType(v, TestNode);
}

enum TestKind {
	Element;
	Text;
	Marker;
}

@:rendered(TestRenderer)
class TestNode {
	public final kind:TestKind;
	public final tag:String;
	public var text = "";
	public var parent:Null<TestNode>;
	public final children:Array<TestNode> = [];
	public final props = new Map<String, Dynamic>();
	public final listeners = new Map<String, Dynamic>();

	public function new(kind:TestKind, tag:String) {
		this.kind = kind;
		this.tag = tag;
	}

	// (for programs that render into a tree of their own: helder.typescript's tests)
	public static function root(tag:String):TestNode
		return new TestNode(Element, tag);

	// calls the listener for name of the first element with tag here or below
	public function fire(tag:String, name:String) {
		var el = find(tag);
		if (el == null || !el.listeners.exists(name)) throw 'no $name listener on <$tag>';
		el.listeners.get(name)(null);
	}

	// the first element with tag here or below
	public function find(t:String):Null<TestNode> {
		if (kind == Element && tag == t) return this;
		for (c in children) {
			var f = c.find(t);
			if (f != null) return f;
		}
		return null;
	}

	public function toHtml():String
		return switch kind {
			case Text: StringTools.htmlEscape(text);
			case Marker: '<!--$tag-->';
			case Element:
				var keys = [for (k in props.keys()) k];
				keys.sort(Reflect.compare);
				var attrs = [for (k in keys) ' $k="' + StringTools.htmlEscape(Std.string(props.get(k)), true) + '"'].join("");
				'<$tag$attrs>' + StringTools.htmlEscape(text) + [for (c in children) c.toHtml()].join("") + '</$tag>';
		}
}
