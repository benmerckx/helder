package hxmc.ui;

// whether a node's text can be selected by the pointer (CSS's user-select;
// inherited: Auto, null, takes the parent's): None not, Text by a drag, a
// double click (a word) or a triple click (all of it), All all of it at a
// click. A TextNode's own selectable is Text for it.
enum abstract UserSelect(Int) {
	var Auto;
	var None;
	var Text;
	var All;
}
