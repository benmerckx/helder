package helder.ui;

enum abstract TextAlign(Int) {
	var Left;
	var Center;
	var Right;
	// both edges: the room left on each line but the last shared among its spaces
	var Justify;
}
