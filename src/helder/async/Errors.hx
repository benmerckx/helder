package helder.async;

import haxe.Exception;

// The program's hook for errors nothing caught: an exception out of a frame
// or an event (helder.os.App.run, every platform), an error in a task nobody
// awaits or observes, a failed Async.main. The handler gets the error and
// where it came from ("frame", "event", "task", "main") and answers whether
// it was handled: then the program goes on (the frame or event abandoned
// where it threw), else it fails as without one (printed, exit code 1). An
// error in the handler itself counts as not handled.
//
//   helder.os.App.onError = (e, source) -> { show(e.message, e.stack); true; };
class Errors {
	public static var handler:Null<(error:Exception, source:String) -> Bool> = null;
	static var reporting = false;

	// e handed to the handler: whether it was handled
	public static function report(e:Exception, source:String):Bool {
		var h = handler;
		if (h == null || reporting) return false;
		reporting = true;
		var handled = try h(e, source) catch (_:Exception) false;
		reporting = false;
		return handled;
	}

	// f run, an error out of it reported (rethrown when not handled)
	public static inline function guard(f:Void->Void, source:String) {
		try f() catch (e:Exception) if (!report(e, source)) throw e;
	}
}
