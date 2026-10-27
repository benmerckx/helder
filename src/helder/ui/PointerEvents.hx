package helder.ui;

// whether the pointer finds a node (CSS's pointer-events): None lets it
// through to what is under it; inherited, so a descendant can be Auto again
enum abstract PointerEvents(Int) {
	var Auto;
	var None;
}
