package helder.headless;

// What a headless run sees of a window's content, given by the library that
// draws it (helder.ui's UiWindow: helder.ui.draw.UiInspector): its nodes as
// presented, for --tree, --trace and a script's targets, and its pop-up
// menus, for menu-pick. A window without one (a scene's, gfx's) has
// pixels only: its script aims at x, y.
interface Inspector {
	// the nodes presented now, in tree order (a parent before its children),
	// those not displayed left out
	function nodes():Array<InspectedNode>;

	// the open pop-up menu's item of that id or label chosen: null when it
	// was, else what was wrong (no menu open, no such item)
	function menuPick(id:Null<Int>, label:Null<String>):Null<String>;

	// the open pop-up menu closed without a choice: whether one was open
	function menuCancel():Bool;
}

// A node as presented: where it is drawn (points, through its ancestors'
// scrolling and transforms), how (its opacity through its ancestors', its
// fill and text colours as "#rrggbb" or "#rrggbbaa"), what assistive
// technology reads of it (role: ARIA's; label; checked, selected, value; its
// place in its set), its state
// (hovered, pressed, focused), whether a transition is moving it, and
// where its markup is (its tag's span, the component mounting it)
@:structInit class InspectedNode {
	// (the same node, the same id, for the run's life)
	public var id:Int;
	public var parent:Int;
	public var depth:Int;
	public var tag:String;
	// its tags from the root's child down, "/" between
	public var path:String;
	public var role:Null<String> = null;
	public var label:Null<String> = null;
	public var text:Null<String> = null;
	public var value:Null<String> = null;
	public var checked:Null<Bool> = null;
	public var selected:Null<Bool> = null;
	// an item's place in its set, from 1, and the set's size (0: none)
	public var posInSet:Int = 0;
	public var setSize:Int = 0;
	public var disabled:Bool = false;
	public var x:Float;
	public var y:Float;
	public var width:Float;
	public var height:Float;
	public var opacity:Float;
	public var fill:Null<String> = null;
	public var color:Null<String> = null;
	public var hover:Bool = false;
	public var press:Bool = false;
	public var focus:Bool = false;
	public var transitioning:Bool = false;
	// where markup wrote it, and the component mounting it (helder.view.Source)
	public var source:Null<helder.view.Source> = null;
	public var component:Null<helder.view.Source.SourceComponent> = null;
}
