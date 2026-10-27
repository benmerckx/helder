package helder.ui;

// where a word too wide for its line may be cut (CSS's overflow-wrap):
// Normal lets it overflow; BreakWord cuts it where it must (its min-content
// width still the word's); Anywhere cuts it so, the min-content width each
// character's
enum abstract OverflowWrap(Int) {
	var Normal;
	var BreakWord;
	var Anywhere;
}
