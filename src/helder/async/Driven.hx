package helder.async;

// A loop another loop drives (helder.os's App.run: its frames), typed
// without the rest of helder.async: `MainLoop.main` is the main thread's
// Loop once something made one, else null, and App.run then links none of
// it.
interface Driven {
	// what is ready runs, then due timers, then a wait of at most seconds; whether anything is left
	function turn(seconds:Float):Bool;
	// a wait of at most seconds (-1: no limit) for the loop's I/O, a post from
	// another thread or the descriptor fd (-1: none) to be readable, bounded
	// by the next timer; nothing runs (what completes runs at the next turn)
	function wait(seconds:Float, fd:Int):Void;
	// seconds (-1: no limit) bounded by the next timer, by 0 while something
	// is ready, and by 10 ms while I/O or a post may come that a wait of the
	// driver's own does not watch (its descriptors are not the loop's)
	function bound(seconds:Float):Float;
}

class MainLoop {
	// (the first Loop made: the main thread's, as nothing makes one on another thread first)
	public static var main:Null<Driven>;
}
