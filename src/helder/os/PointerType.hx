package helder.os;

// What a pointer is (Pointer.type): the mouse (or a trackpad's cursor), a
// finger on a touch screen, a pen or stylus. Kept apart so that gestures can
// differ (hover only for the mouse and a pen, a finger's larger slop).
enum abstract PointerType(Int) to Int {
	var Mouse;
	var Touch;
	var Pen;
}
