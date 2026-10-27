package helder.ui;

// the inline direction (CSS's direction, HTML's dir): Rtl lays a row's
// items out from the right, a column's across from the right, a grid's
// columns from the right, and aligns text to the right by default
enum abstract Dir(Int) {
	var Ltr;
	var Rtl;
}
