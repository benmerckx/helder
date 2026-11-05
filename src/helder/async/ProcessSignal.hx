package helder.async;

// the signals Process.signal sends and Signals.next receives (the same
// numbers on Linux and macOS)
enum abstract ProcessSignal(Int) to Int {
	var SIGINT = 2;
	var SIGKILL = 9;
	var SIGTERM = 15;
}
