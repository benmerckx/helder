package helder.ui.gesture;

// the directions a Pan takes (Pan.axis): a drag along the other one is
// left to what else wants it (a scroller around it)
enum abstract Axis(Int) to Int {
	var Both;
	var X;
	var Y;
}
