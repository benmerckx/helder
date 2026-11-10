package helder.async;

// A write or a connect on a socket or pipe the program closed (its close
// while the operation waited, or before it). A read there ends as the end
// of the stream (0) and an accept as no connection (null) instead: the
// loops reading or accepting end as they would at the other side's end.
class Closed extends haxe.Exception {
	public function new()
		super("closed");
}
