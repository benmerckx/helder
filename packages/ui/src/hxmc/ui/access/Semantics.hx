package hxmc.ui.access;

// What a node declares about itself for assistive technology (Node.semantics;
// in markup, the attributes role, label, description, checked, selected,
// expanded, level, disabled, value-now, value-min, value-max, value-text,
// hidden). Unset
// fields say nothing: a TextNode is a Label of its text, an ImageNode an
// Image, a focusable node a Group.
@:structInit class Semantics {
	public var role:Null<Role> = null;
	// the name (else from the contents' text, for the roles named by content)
	public var label:Null<String> = null;
	public var description:Null<String> = null;
	public var checked:Null<Bool> = null;
	public var selected:Null<Bool> = null;
	public var expanded:Null<Bool> = null;
	// a tree item's depth (from 1)
	public var level:Null<Int> = null;
	public var disabled:Bool = false;
	// a range's value (Slider, ProgressIndicator) and bounds, and its text
	public var valueNow:Null<Float> = null;
	public var valueMin:Null<Float> = null;
	public var valueMax:Null<Float> = null;
	public var valueText:Null<String> = null;
	// left out with its subtree (decoration)
	public var hidden:Bool = false;
}
