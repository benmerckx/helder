package hxmc.ui;

// across the main axis (Auto: alignSelf takes the parent's alignItems;
// Baseline: a row's items on their first baselines, a text's first line's or
// else their first item's, one without any on its bottom edge, as CSS's
// flexbox; in a column on their start edges, the largest start margin
// before them all, as Chromium; in a grid and for an absolute box, as Start)
enum abstract Align(Int) {
	var Auto;
	@:css("flex-start") var Start;
	@:css("flex-end") var End;
	var Center;
	var Stretch;
	var Baseline;
}
