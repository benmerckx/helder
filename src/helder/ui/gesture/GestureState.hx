package helder.ui.gesture;

// A recogniser's state (UIKit's): Possible until it is sure; a discrete one
// (Tap) then Ended (recognised) or Failed; a continuous one (Pan, Scale)
// Began, Changed while its pointers move, then Ended when they lift, or
// Cancelled (a cancel, its pointers taken: Gesture.cancel, the node gone)
enum abstract GestureState(Int) to Int {
	var Possible;
	var Began;
	var Changed;
	var Ended;
	var Cancelled;
	var Failed;
}
