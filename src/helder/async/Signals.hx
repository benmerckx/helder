package helder.async;

import haxe.io.Bytes;
import helder.async.Io;

// The signals this process receives (SIGINT, SIGTERM), on the loop: once
// asked for, a signal no longer ends the process; next() returns it, and
// the program ends as it chooses (its children stopped, 128 + the signal).
// Natively on POSIX: a handler that writes the signal's number to a pipe
// the backend polls (the self-pipe trick: nothing else is safe in a
// handler). Elsewhere (Windows, Eval, the browser) next() returns only when
// cancelled, keeping nothing alive, and the signals keep their default action.
//
//   task.async(_ -> {
//     var sig = Signals.next([SIGINT, SIGTERM]);
//     server.stop();
//     Sys.exit(128 + sig);
//   });
class Signals {
	#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
	static var readEnd:Null<Handle>;
	static var writeFd = -1;
	static final caught:Array<Int> = [];
	#end

	// the next of these signals this process receives (suspends until then)
	@:coroutine public static function next(signals:Array<Signal>):Signal {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		if (!Handle.WINDOWS) {
			for (s in signals) catchSignal(s);
			var b = Bytes.alloc(1);
			while (true) {
				if (new Op(Read, readEnd, b, 0, 1).run().result <= 0) break;
				var s:Signal = cast b.get(0);
				if (signals.contains(s)) return s;
			}
		}
		#end
		return Async.suspendCancellable(_ -> null);
	}

	#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
	static function catchSignal(s:Int) {
		if (readEnd == null) {
			var r = pipe();
			if (r < 0) throw new haxe.Exception("Signals: no pipe");
			hxmc.NativeSys.fileSetBlocking(r, false);
			hxmc.NativeSys.fileSetBlocking(writeFd, false);
			readEnd = new Handle(null, r);
		}
		if (caught.contains(s)) return;
		caught.push(s);
		hxmc.unsafe.Posix.signal(s, hxmc.unsafe.Callback.addr(onSignal));
	}

	// (the pipe: its read end, the write end in writeFd; -1 on a failure)
	@:hxmc.unsafe static function pipe():Int {
		var fds = hxmc.unsafe.Mem.stack(8);
		if (hxmc.unsafe.Posix.pipe(fds) != 0) return -1;
		writeFd = hxmc.unsafe.Mem.getI32(fds, 4);
		return hxmc.unsafe.Mem.getI32(fds, 0);
	}

	// (in the handler: the signal's number written to the pipe, a full pipe dropping it)
	@:hxmc.callback @:hxmc.unsafe static function onSignal(sig:Int):Void {
		var b = hxmc.unsafe.Mem.stack(8);
		hxmc.unsafe.Mem.setI8(b, 0, sig);
		hxmc.unsafe.Posix.write(writeFd, b, 1);
	}
	#end
}
