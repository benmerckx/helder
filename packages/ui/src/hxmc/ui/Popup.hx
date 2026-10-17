package hxmc.ui;

// A layer above the tree (Ui.open: a child of Ui.overlay): drawn after the
// tree and over it, hit first, not clipped by the tree's overflow; the
// later opened on top. Anchored to a node of the tree (anchor), it is
// placed by placement (Below: under it, their left edges lined up; Above;
// Right: beside it, their tops lined up; Left), flipped to the other side
// when it does not fit and kept inside the window; Center centres it in
// the window; Manual leaves it to its style (left, top). A modal one
// covers the window (its own style: a backdrop; its content centred, as
// Ui.open makes it) and keeps the keyboard focus inside: Tab cycles in
// it, the tree under it takes no pointer events. onDismiss: asked to close
// by a click outside it (not on its anchor) or by Escape; Ui.close closes
// it and gives the focus back to where it was.
class Popup extends Node {
	public var anchor:Null<Node>;
	public var placement:Placement = Below;
	// the space between the anchor and the popup
	public var gap = 4.0;
	public var modal = false;
	public var onDismiss:Null<Void->Void>;
	// the focus when it opened (given back when it closes)
	@:allow(hxmc.ui.Ui) var returnFocus:Null<Node>;

	public function new(?tag:String) {
		super(tag == null ? "popup" : tag);
		style.position = Absolute;
	}
}

enum abstract Placement(Int) {
	var Below;
	var Above;
	var Right;
	var Left;
	var Center;
	var Manual;

	@:from public static function parse(s:String):Placement
		return switch s.toLowerCase() {
			case "below" | "bottom": Below;
			case "above" | "top": Above;
			case "right": Right;
			case "left": Left;
			case "center": Center;
			case "manual": Manual;
			case _: throw "Placement: not a placement: " + s;
		}
}
