package helder.ui.widgets;

import helder.ui.Clock;
import helder.view.Signal;
import helder.view.Reactive.signal;

// Toasts: short messages over the window in a corner, the newest last
// (Widgets.Toaster shows them: one in the markup), each for a while
// (duration seconds, 4; 0: until closed) or until its close button or its
// action (a button: onAction runs, the toast closes). Toasts.show adds
// one from anywhere; its kind ("info", "success", "error") colours its
// mark. Its time runs on the animation clock (Clock), held while paused
// (the pointer over them).
class Toasts {
	// the toasts shown, oldest first
	public static final shown:Signal<Array<Toast>> = signal([]);
	// while true their time stands still (Toaster: the pointer over them)
	public static var paused = false;

	public static function show(text:String, ?options:{?kind:String, ?duration:Float, ?action:String, ?onAction:Void->Void}):Toast {
		var t = new Toast(text, options?.kind ?? "info", options?.action, options?.onAction);
		shown.value = shown.peek().concat([t]);
		var duration = options?.duration ?? 4.0, left = duration, last = -1.0;
		// (from the clock's next tick: its last may be long past)
		if (duration > 0)
			Clock.add(now -> {
				if (t.closed) return false;
				if (last >= 0 && !paused) left -= now - last;
				last = now;
				if (left > 0) return true;
				close(t);
				return false;
			});
		return t;
	}

	public static function close(t:Toast) {
		if (t.closed) return;
		@:privateAccess t.closed = true;
		shown.value = shown.peek().filter(x -> x != t);
		// (none left: the pointer leaves no toaster to say it left)
		if (shown.peek().length == 0) paused = false;
	}

	// closes them all
	public static function clear() {
		for (t in shown.peek())
			@:privateAccess t.closed = true;
		shown.value = [];
		paused = false;
	}
}

class Toast {
	public final text:String;
	public final kind:String;
	public final action:Null<String>;
	public final onAction:Null<Void->Void>;
	public var closed(default, null) = false;

	public function new(text:String, kind:String, action:Null<String>, onAction:Null<Void->Void>) {
		this.text = text;
		this.kind = kind;
		this.action = action;
		this.onAction = onAction;
	}
}
