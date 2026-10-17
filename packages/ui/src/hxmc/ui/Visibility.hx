package hxmc.ui;

// whether a node is seen (CSS's visibility): Hidden keeps its place in the
// layout but draws nothing of it, nor hits, focuses or shows it to
// assistive technology; inherited, so a descendant can be Visible again
enum abstract Visibility(Int) {
	var Visible;
	var Hidden;
}
