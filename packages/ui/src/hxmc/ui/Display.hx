package hxmc.ui;

enum abstract Display(Int) {
	var Flex;
	// not laid out nor drawn, its subtree neither
	var None;
	// its children on CSS grid's tracks (Style's grid properties)
	var Grid;
}
