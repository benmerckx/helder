package helder.ui;

// the lines of a wrapping container across the main axis
enum abstract AlignContent(Int) {
	@:css("flex-start") var Start;
	@:css("flex-end") var End;
	var Center;
	var Stretch;
	var SpaceBetween;
	var SpaceAround;
	var SpaceEvenly;
	// the default: Start in a flex container; a grid's auto rows stretched (CSS's normal)
	var Normal;
}
