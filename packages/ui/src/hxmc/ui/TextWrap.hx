package hxmc.ui;

// whether text wraps at its box's width (CSS's text-wrap-mode): NoWrap
// keeps each line (from a line break to the next) whole, as wide as it is
enum abstract TextWrap(Int) {
	var Wrap;
	var NoWrap;
}
