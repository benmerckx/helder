package hxmc.ui;

// The pointer's shape over a node (Style.cursor): Auto takes the parent's
// (the root's: Default); a window shows the hovered node's (Ui.cursor).
enum abstract Cursor(Int) to Int {
	var Auto;
	var Default;
	var Pointer;
	var Text;
	var Crosshair;
	var Move;
	var NotAllowed;
	var ResizeEW;
	var ResizeNS;
}
