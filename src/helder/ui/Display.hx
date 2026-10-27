package helder.ui;

enum abstract Display(Int) {
	var Flex;
	// not laid out nor drawn, its subtree neither
	var None;
	// its children on CSS grid's tracks (Style's grid properties)
	var Grid;
	// its children one under another at their own heights, as CSS's block
	// layout: a column whose items neither grow nor shrink (a row direction
	// given: a flex row)
	var Block;
}
