package hxmc.ui;

// what a line too wide for its box shows (CSS's text-overflow): Clip draws
// it on, clipped where the box clips; Ellipsis ends it in "…" within the box
enum abstract TextOverflow(Int) {
	var Clip;
	var Ellipsis;
}
