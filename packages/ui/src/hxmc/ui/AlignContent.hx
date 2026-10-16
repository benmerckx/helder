package hxmc.ui;

// the lines of a wrapping container across the main axis
enum abstract AlignContent(Int) {
	var Start;
	var End;
	var Center;
	var Stretch;
	var SpaceBetween;
	var SpaceAround;
	var SpaceEvenly;
}
