package hxmc.ui;

// whether text wraps at its box's width (CSS's text-wrap-mode): NoWrap
// keeps each line (from a line break to the next) whole, as wide as it is;
// Balance wraps it, two to six lines at the narrowest width that keeps
// their number (CSS's text-wrap: balance, as Chromium's)
enum abstract TextWrap(Int) {
	var Wrap;
	var NoWrap;
	var Balance;
}
