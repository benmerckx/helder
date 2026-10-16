package hxmc.ui;

enum abstract Overflow(Int) {
	var Visible;
	// the children are clipped to the padding box
	var Hidden;
	// clipped, and scrolled by the wheel (Node.scrollX, scrollY)
	var Scroll;
}
