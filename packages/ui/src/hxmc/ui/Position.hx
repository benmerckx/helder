package hxmc.ui;

enum abstract Position(Int) {
	// laid out by its parent's flexbox (left, top, right, bottom then offset it)
	var Relative;
	// out of the flow: placed in the parent's padding box by left, top, right, bottom
	var Absolute;
}
