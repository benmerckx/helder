package hxmc.ui;

// A layer above the tree (Ui.open: a child of Ui.overlay): drawn after the
// tree and over it, hit first, not clipped by the tree's overflow; the
// later opened on top. Anchored to a node of the tree (anchor), it is
// placed by placement (Below: under it, their left edges lined up; Above;
// Right: beside it, their tops lined up; Left), flipped to the other side
// when it does not fit and kept inside the window; Center centres it in
// the window; Point puts its top left at (atX, atY) in the window, flipped
// left or up where it would not fit (a context menu); TopLeft, TopRight,
// BottomLeft and BottomRight put it in that corner of the window, gap from
// its edges (notifications); Manual leaves it to its style (left, top). A modal one
// covers the window (its own style: a backdrop; its content centred, as
// Ui.open makes it) and keeps the keyboard focus inside: Tab cycles in
// it, the tree under it takes no pointer events. onDismiss: asked to close
// by a click outside it (not on its anchor; unless dismissOnOutside is
// false, as an alert dialog) or by Escape; Ui.close closes it and gives the
// focus back to where it was.
class Popup extends Node {
	public var anchor:Null<Node>;
	public var placement:Placement = Below;
	// the space between the anchor and the popup
	public var gap = 4.0;
	// Point's place, in window pixels
	public var atX = 0.0;
	public var atY = 0.0;
	public var modal = false;
	public var onDismiss:Null<Void->Void>;
	public var dismissOnOutside = true;
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
	var Point;
	var TopLeft;
	var TopRight;
	var BottomLeft;
	var BottomRight;

	@:from public static function parse(s:String):Placement
		return switch s.toLowerCase() {
			case "below" | "bottom": Below;
			case "above" | "top": Above;
			case "right": Right;
			case "left": Left;
			case "center": Center;
			case "manual": Manual;
			case "point": Point;
			case "top-left": TopLeft;
			case "top-right": TopRight;
			case "bottom-left": BottomLeft;
			case "bottom-right": BottomRight;
			case _: throw "Placement: not a placement: " + s;
		}
}
