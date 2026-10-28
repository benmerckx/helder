package helder.os;

// Who a pointer down belongs to (Pointer.owner, cleared at each press):
// nobody yet (None: the game's to take), a ui node it went down on (Ui:
// helder.ui's window marks it, so that a touch on a button does not reach
// the game's controls), or a game control that claimed it (Control: an
// on-screen stick, button or look zone of helder.scene's Actions)
enum abstract PointerOwner(Int) to Int {
	var None;
	var Ui;
	var Control;
}
