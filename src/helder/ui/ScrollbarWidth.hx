package helder.ui;

// a scroller's scrollbar (CSS's scrollbar-width, not inherited): Auto
// (Ui.SCROLLBAR thick), Thin (two thirds of that), None (none drawn or
// grabbed; the wheel and the keys still scroll)
enum abstract ScrollbarWidth(Int) {
	var Auto;
	var Thin;
	var None;
}
