package hxmc.ui;

// across the main axis (Auto: alignSelf takes the parent's alignItems)
enum abstract Align(Int) {
	var Auto;
	@:css("flex-start") var Start;
	@:css("flex-end") var End;
	var Center;
	var Stretch;
}
