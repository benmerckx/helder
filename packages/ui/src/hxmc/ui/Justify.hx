package hxmc.ui;

// along the main axis
enum abstract Justify(Int) {
	var Start;
	var End;
	var Center;
	var SpaceBetween;
	var SpaceAround;
	var SpaceEvenly;
	// the default: Start in a flex container; a grid's auto columns stretched (CSS's normal)
	var Normal;
}
