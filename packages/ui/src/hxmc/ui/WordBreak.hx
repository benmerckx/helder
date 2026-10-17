package hxmc.ui;

// where lines may break inside words (CSS's word-break): Normal at spaces,
// hyphens and around CJK characters; BreakAll between any two letters too
// (not before closing punctuation or after opening); KeepAll not between
// CJK characters
enum abstract WordBreak(Int) {
	var Normal;
	var BreakAll;
	var KeepAll;
}
