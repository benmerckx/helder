package helder.ui;

// a text's letters as shown (CSS's text-transform), letter for letter:
// Capitalize uppercases each word's first (a word: after a space or the start)
enum abstract TextTransform(Int) {
	var None;
	var Uppercase;
	var Lowercase;
	var Capitalize;
}
