package helder.os;

// A pointer's last change (Pointer.phase): None before its first, then
// Down, Move, Up or Cancel (the system took it: a call, a system gesture,
// the browser panning the page; it must not tap, and what it held lets go)
enum abstract PointerPhase(Int) to Int {
	var None;
	var Down;
	var Move;
	var Up;
	var Cancel;
}
