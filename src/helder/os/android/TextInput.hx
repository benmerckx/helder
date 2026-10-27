package helder.os.android;

import helder.os.Event;
import hxmc.unsafe.*;

// Window.startTextInput on Android: the keyboard and the input method for a
// drawn UI (AndroidWindow), through a hidden EditText in the activity's
// window (NativeActivity's surface is the app's, so the view is never
// drawn; it only holds the input method's connection), focused at the caret
// with the soft keyboard shown, made and driven on the main thread
// (MainThread). Its text (a TextWatcher: helder.os.android.Glue) becomes the
// events: the input method's composition (its composing span) as
// TextEditing (the caret in it; empty when it ends), what it commits as
// TextInput, after which the field is emptied again. Keys (the hardware
// keyboard's, the input method's Delete and Enter) still come through the
// activity's input queue as before: the system gives NativeActivity a key
// before the focused view. The events wait for the program's thread, which
// AndroidWindow.pump hands them to. Enabled by a program that takes text
// (enable: helder.ui's UiWindow does).
@:hxmc.android
class TextInput {
	static final lock = new sys.thread.Mutex();
	static var pending:Array<{kind:EventKind, text:String, caret:Int}> = [];
	// (the main thread's)
	static var edit = Ptr.nil();
	static var imm = Ptr.nil();
	static var on = false;
	static var ignoring = false;
	static var composing = "";
	static var m:Map<String, Ptr>;
	static var connection = Ptr.nil();
	static var selection = Ptr.nil();

	// Window.startTextInput through this from now on (otherwise a program
	// that never takes text has none of this, nor classes.dex)
	public static function enable() {
		AndroidWindow.textInputHook = set;
		AndroidWindow.textEvents = drain;
	}

	// (the program's thread) on at the caret (pixels), or off
	static function set(on:Bool, x:Int, y:Int, width:Int, height:Int)
		MainThread.post(() -> on ? show(x, y) : hide());

	// the hidden EditText (the main thread; null until text input was first on)
	public static function field():Ptr
		return edit;

	static function init() {
		var view = Jni.cls("android.view.View"), text = Jni.cls("android.widget.TextView"), act = Jni.activity;
		var editText = Jni.cls("android.widget.EditText"), manager = Jni.cls("android.view.inputmethod.InputMethodManager");
		connection = Jni.cls("android.view.inputmethod.BaseInputConnection");
		selection = Jni.cls("android.text.Selection");
		m = [
			"setTranslationX" => Jni.method(view, "setTranslationX", "(F)V"),
			"setTranslationY" => Jni.method(view, "setTranslationY", "(F)V"),
			"requestFocus" => Jni.method(view, "requestFocus", "()Z"),
			"clearFocus" => Jni.method(view, "clearFocus", "()V"),
			"getWindowToken" => Jni.method(view, "getWindowToken", "()Landroid/os/IBinder;"),
			"showSoftInput" => Jni.method(manager, "showSoftInput", "(Landroid/view/View;I)Z"),
			"hide" => Jni.method(manager, "hideSoftInputFromWindow", "(Landroid/os/IBinder;I)Z"),
			"getText" => Jni.method(text, "getText", "()Ljava/lang/CharSequence;"),
			"clear" => Jni.method(Jni.cls("android.text.Editable"), "clear", "()V"),
			"spanStart" => Jni.staticMethod(connection, "getComposingSpanStart", "(Landroid/text/Spannable;)I"),
			"spanEnd" => Jni.staticMethod(connection, "getComposingSpanEnd", "(Landroid/text/Spannable;)I"),
			"selectionEnd" => Jni.staticMethod(selection, "getSelectionEnd", "(Ljava/lang/CharSequence;)I")
		];
		var e = Jni.newObject(editText, Jni.method(editText, "<init>", "(Landroid/content/Context;)V"), act.toI64());
		edit = Jni.global(e);
		// (no full-screen editor in landscape: IME_FLAG_NO_EXTRACT_UI, IME_FLAG_NO_FULLSCREEN)
		Jni.call(edit, Jni.method(text, "setImeOptions", "(I)V"), 0x10000000 | 0x2000000);
		Jni.call(edit, Jni.method(view, "setAlpha", "(F)V"), Jni.f(0));
		var l = Glue.listener((kind, o, a, b) -> {
			if (kind == Glue.TEXT) changed(o);
			0;
		});
		Jni.call(edit, Jni.method(text, "addTextChangedListener", "(Landroid/text/TextWatcher;)V"), l.obj.toI64());
		var params = Jni.cls("android.view.ViewGroup$LayoutParams");
		var lp = Jni.newObject(params, Jni.method(params, "<init>", "(II)V"), 1, 1);
		Jni.call(act, Jni.method(Jni.cls("android.app.Activity"), "addContentView", "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V"), edit.toI64(),
			lp.toI64());
		var service = Jni.string("input_method");
		imm = Jni.global(Jni.obj(act, Jni.method(Jni.cls("android.content.Context"), "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;"),
			service.toI64()));
	}

	static function show(x:Int, y:Int) {
		if (edit.isNull()) init();
		on = true;
		Jni.call(edit, m["setTranslationX"], Jni.f(x));
		Jni.call(edit, m["setTranslationY"], Jni.f(y));
		Jni.bool(edit, m["requestFocus"]);
		Jni.bool(imm, m["showSoftInput"], edit.toI64(), 0);
	}

	static function hide() {
		if (edit.isNull() || !on) return;
		on = false;
		Jni.bool(imm, m["hide"], Jni.obj(edit, m["getWindowToken"]).toI64(), 0);
		Jni.call(edit, m["clearFocus"]);
		if (composing != "") push(TextEditing, "", 0);
		composing = "";
		empty(Jni.obj(edit, m["getText"]));
	}

	static function empty(e:Ptr) {
		ignoring = true;
		Jni.call(e, m["clear"]);
		ignoring = false;
	}

	// the field's text changed (e: its Editable): the composition, or a commit
	static function changed(e:Ptr) {
		if (ignoring || !on) return;
		var text = Jni.text(e);
		var start = Jni.staticInt(connection, m["spanStart"], e.toI64()), end = Jni.staticInt(connection, m["spanEnd"], e.toI64());
		if (start >= 0 && end > start) {
			var comp = text.substring(start, end), caret = Jni.staticInt(selection, m["selectionEnd"], e.toI64()) - start;
			if (comp != composing) push(TextEditing, comp, caret < 0 ? 0 : caret > comp.length ? comp.length : caret);
			composing = comp;
			return;
		}
		if (composing != "") push(TextEditing, "", 0);
		composing = "";
		if (text != "") {
			push(TextInput, text, 0);
			empty(e);
		}
	}

	static function push(kind:EventKind, text:String, caret:Int) {
		lock.acquire();
		pending.push({kind: kind, text: text, caret: caret});
		lock.release();
		MainThread.wake();
	}

	// (the program's thread) the events waiting
	static function drain(dispatch:(kind:EventKind, text:String, caret:Int) -> Void) {
		lock.acquire();
		var list = pending;
		pending = [];
		lock.release();
		for (e in list)
			dispatch(e.kind, e.text, e.caret);
	}
}
