import hxmc.os.*;
import hxmc.os.android.Jni;
import hxmc.os.android.MainThread;
import hxmc.os.android.TextInput;

// Text input in a window the program draws (NativeActivity's, as a drawn
// UI has it) on Android (CI's android job, read from logcat by
// packages/ui/test/android-mix.sh): Window.startTextInput shows the soft
// keyboard for a hidden EditText (the script reads the input method's
// state); keys typed by adb come as KeyDown and TextInput; an input
// method's composition and commit through the field's InputConnection (the
// calls an input method makes) as TextEditing and TextInput; then
// stopTextInput hides the keyboard and the window closes.
//   haxe -cp packages/os/src -cp packages/os/test -main AndroidTextTest
//     --custom-target hxmc=AndroidTextTest.apk -D hxmc.target=android-x86_64 -D hxmc.android-package=org.hxmc.texttest
class AndroidTextTest {
	static function main() {
		Sys.println("AndroidTextTest: start");
		TextInput.enable();
		var w = new Window("AndroidTextTest", 0, 0);
		Sys.println('AndroidTextTest: window ${w.width}x${w.height}');
		w.startTextInput(40, 80, 200, 40);
		var typed = "", events = [], phase = 0, start = Sys.time(), until = 0.0;
		App.run(() -> {
			Sys.sleep(0.02);
			// (the script typed "hello": an input method's composition and commit next)
			if (phase == 0 && typed == "hello") {
				phase = 1;
				MainThread.post(() -> {
					var cls = Jni.cls("android.view.inputmethod.EditorInfo"), cs = "Ljava/lang/CharSequence;";
					var info = Jni.newObject(cls, Jni.method(cls, "<init>", "()V"));
					var ic = Jni.obj(TextInput.field(), Jni.method(Jni.cls("android.view.View"), "onCreateInputConnection",
						"(Landroid/view/inputmethod/EditorInfo;)Landroid/view/inputmethod/InputConnection;"), info.toI64());
					var conn = Jni.cls("android.view.inputmethod.InputConnection");
					var compose = Jni.method(conn, "setComposingText", '(${cs}I)Z'), commit = Jni.method(conn, "commitText", '(${cs}I)Z');
					Jni.bool(ic, compose, Jni.string("wor").toI64(), 1);
					Jni.bool(ic, compose, Jni.string("world").toI64(), 1);
					Jni.bool(ic, commit, Jni.string("world!").toI64(), 1);
				});
			}
			if (phase == 1 && typed == "helloworld!") {
				phase = 2;
				Sys.println("AndroidTextTest: events " + events.join(" | "));
				var want = "TextEditing wor | TextEditing world | TextEditing  | TextInput world!";
				Sys.println("AndroidTextTest: " + (events.join(" | ").indexOf(want) >= 0 ? "ok" : "FAIL") + ": the input method's composition and commit");
				w.stopTextInput();
				Sys.println("AndroidTextTest: text input off");
				until = Sys.time() + 4;
			}
			if (phase == 2 && Sys.time() > until || Sys.time() - start > 90) {
				Sys.println("AndroidTextTest: " + (phase == 2 ? "done" : "FAIL: typed \"" + typed + "\""));
				w.close();
			}
		}, e -> switch e.kind {
			case TextInput:
				typed += e.text;
				events.push("TextInput " + e.text);
				Sys.println('AndroidTextTest: typed "$typed"');
			case TextEditing:
				events.push('TextEditing ${e.text}');
				Sys.println('AndroidTextTest: composition "${e.text}", caret ${e.x}');
			case KeyDown:
				if (e.key == 0xFF1B) w.close();
			case Close:
				w.close();
			case _:
		});
		Sys.println("AndroidTextTest: end");
	}
}
