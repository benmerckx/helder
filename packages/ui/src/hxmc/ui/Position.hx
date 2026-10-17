package hxmc.ui;

enum abstract Position(Int) {
	// laid out by its parent's flexbox (left, top, right, bottom then offset it)
	var Relative;
	// out of the flow: placed in the parent's padding box by left, top, right, bottom
	var Absolute;
	// laid out as Relative but not shifted: moved as its nearest scrolling
	// ancestor scrolls, so as to stay left, top, right or bottom pixels
	// inside its content box, but not out of its parent's content box (CSS's sticky)
	var Sticky;
}
