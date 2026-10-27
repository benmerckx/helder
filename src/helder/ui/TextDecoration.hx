package helder.ui;

// A line a text draws (Style.textDecoration): under it, through it, over it
enum abstract TextDecoration(Int) to Int {
	var Underline = 1;
	var LineThrough = 2;
	var Overline = 4;
}
