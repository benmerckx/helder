package hxmc.ui.access;

// A node of the accessibility tree as AccessTree builds it: what a screen
// reader sees of one Node (its id stays the node's), with its children's ids
@:structInit class AccessNode {
	public var id:Int;
	public var role:Role;
	public var name:String = "";
	public var description:Null<String> = null;
	// a text input's text
	public var value:Null<String> = null;
	public var checked:Null<Bool> = null;
	public var selected:Null<Bool> = null;
	public var expanded:Null<Bool> = null;
	public var disabled:Bool = false;
	public var focusable:Bool = false;
	public var valueNow:Null<Float> = null;
	public var valueMin:Null<Float> = null;
	public var valueMax:Null<Float> = null;
	public var valueText:Null<String> = null;
	// the box in window pixels
	public var x:Float = 0;
	public var y:Float = 0;
	public var width:Float = 0;
	public var height:Float = 0;
	public var children:Array<Int> = [];

	// the same as another (an incremental update leaves it out)
	public function equals(o:AccessNode):Bool {
		if (o.role != role || o.name != name || o.description != description || o.value != value || o.checked != checked || o.selected != selected
			|| o.expanded != expanded || o.disabled != disabled || o.focusable != focusable || o.valueNow != valueNow || o.valueMin != valueMin
			|| o.valueMax != valueMax || o.valueText != valueText || o.x != x || o.y != y || o.width != width || o.height != height
			|| o.children.length != children.length)
			return false;
		for (i in 0...children.length)
			if (o.children[i] != children[i]) return false;
		return true;
	}

	// as JSON's fields (the browser adapter's format): unset ones left out
	public function toJson():Dynamic {
		var o:Dynamic = {id: id, role: role.aria(), name: name, x: x, y: y, w: width, h: height, children: children};
		if (description != null) o.description = description;
		if (value != null) o.value = value;
		if (checked != null) o.checked = checked;
		if (selected != null) o.selected = selected;
		if (expanded != null) o.expanded = expanded;
		if (disabled) o.disabled = true;
		if (focusable) o.focusable = true;
		if (valueNow != null) o.valueNow = valueNow;
		if (valueMin != null) o.valueMin = valueMin;
		if (valueMax != null) o.valueMax = valueMax;
		if (valueText != null) o.valueText = valueText;
		if (role == MultilineTextInput) o.multiline = true;
		return o;
	}
}
