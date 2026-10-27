import helder.os.*;
import helder.os.x11.Xlib;
import helder.os.objc.*;
import hxmc.unsafe.*;

// helder.os's text input (npm test -- ui-draw under Xvfb; macOS in CI).
// X11: key presses typed through the input method (Xutf8LookupString),
// with the keyboard's last three keycodes given other symbols
// (XChangeKeyboardMapping, which every client hears of: MappingNotify): a
// Cyrillic letter (beyond Latin-1) and a dead key's compose sequence
// (dead_acute then e: one "é"); then the wheel's buttons (4 up, 7 right) as
// Scroll events, their releases as nothing. macOS: with text input on, a key event
// typed through the text view (interpretKeyEvents:), then a composition
// set in it and committed, as an input method does (setMarkedText:,
// insertText:).
//   TextInputTest
class TextInputTest {
	static var failed = 0;
	static var checks = 0;

	public static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('TextInputTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		if (Mem.os() == 1) CocoaTextInput.run() else X11TextInput.run();
		Sys.println('TextInputTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}
}

class X11TextInput {
	public static function run() {
		var check = TextInputTest.check;
		var w = new Window("TextInputTest", 64, 64);
		var d = w.surface.display, id = w.surface.handle.toI64();
		var last = Arena.scopedValue(a -> {
			var lo:Ptr<Int32> = a.alloc(4), hi:Ptr<Int32> = a.alloc(4);
			Xlib.XDisplayKeycodes(d, lo, hi);
			hi.value;
		});
		var first = last - 2;
		// Cyrillic_a, dead_acute, e
		Arena.scoped(a -> {
			var ks:Ptr<Int64> = a.alloc(24);
			ks[0] = 0x6c1;
			ks[1] = 0xfe51;
			ks[2] = 0x65;
			Xlib.XChangeKeyboardMapping(d, first, 1, ks, 3);
		});
		Xlib.XSync(d, 0);
		function press(code:Int)
			Arena.scoped(a -> {
				var raw = a.alloc(X.EVENT_SIZE);
				for (i in 0...X.EVENT_SIZE)
					(raw : Ptr<UInt8>)[i] = 0;
				var k:Ptr<XKeyEvent> = raw;
				k.value.type = X.KeyPress;
				k.value.display = d;
				k.value.window = id;
				k.value.keycode = code;
				k.value.same_screen = 1;
				Xlib.XSendEvent(d, id, 0, X.KeyPressMask, raw);
			});
		function button(press:Bool, b:Int)
			Arena.scoped(a -> {
				var raw = a.alloc(X.EVENT_SIZE);
				for (i in 0...X.EVENT_SIZE)
					(raw : Ptr<UInt8>)[i] = 0;
				var k:Ptr<XKeyEvent> = raw;
				k.value.type = press ? X.ButtonPress : X.ButtonRelease;
				k.value.display = d;
				k.value.window = id;
				k.value.keycode = b;
				k.value.x = 10;
				k.value.y = 12;
				k.value.same_screen = 1;
				Xlib.XSendEvent(d, id, 0, press ? X.ButtonPressMask : X.ButtonReleaseMask, raw);
			});
		var typed = [];
		var scrolls = [];
		var buttons = 0;
		var keys = 0;
		var sent = false;
		var start = haxe.Timer.stamp();
		App.run(() -> {
			if (!sent) {
				// (after the MappingNotify's arrival: the next frame)
				sent = true;
				press(first);
				press(first + 1);
				press(first + 2);
				for (b in [4, 7]) {
					button(true, b);
					button(false, b);
				}
				Xlib.XFlush(d);
			}
			if (typed.length >= 2 && scrolls.length >= 2 || haxe.Timer.stamp() - start > 5) w.close();
			App.wait(0.01);
		}, e -> switch e.kind {
			case TextInput: typed.push(e.text);
			case KeyDown: keys++;
			case Scroll: scrolls.push('${e.deltaX},${e.deltaY}@${e.x},${e.y}');
			case MouseDown | MouseUp: buttons++;
			case _:
		});
		check("a Cyrillic letter typed", typed[0] == "а", typed[0]);
		check("a dead key composed with the next key: one character", typed[1] == "é", typed[1]);
		check("nothing else typed", typed.length == 2, typed.join("|"));
		// (the dead key goes to the input method, not the program)
		check("the keys the program sees", keys == 2, '$keys');
		check("the wheel: scrolls of a notch, up and right", scrolls.join(" ") == "0,-40@10,12 40,0@10,12" && buttons == 0, scrolls.join(" ") + ' $buttons');
	}
}

class CocoaTextInput {
	// NSNotFound (NSIntegerMax)
	static final NOT_FOUND = haxe.Int64.make(0x7FFFFFFF, 0xFFFFFFFF);

	public static function run() {
		var check = TextInputTest.check;
		var w = new Window("TextInputTest", 120, 80);
		w.startTextInput(20, 20, 2, 30);
		// the text view: the first of the content view's subviews
		var content = Msg.id(w.surface.handle, ObjC.sel("superview"));
		var tv = Msg.idInt(Msg.id(content, ObjC.sel("subviews")), ObjC.sel("objectAtIndex:"), 0);
		var nsWindow = Msg.id(tv, ObjC.sel("window"));
		check("the text view is the first responder", Msg.id(nsWindow, ObjC.sel("firstResponder")) == tv);
		var log = [];
		var step = 0, frames = 0;
		var start = haxe.Timer.stamp();
		App.run(() -> {
			frames++;
			switch step {
				case 0:
					// a key typed: "a" (key code 0), posted to the window
					var a = ObjC.str("a");
					// (a location: the mouse's, a struct only a C call gives)
					var ev = Msg.idIntPointIntFloatIntPtrPtrPtrBoolU16(ObjC.cls("NSEvent"),
						ObjC.sel("keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:"),
						10, Msg.point(ObjC.cls("NSEvent"), ObjC.sel("mouseLocation")), 0, 0, Msg.i(nsWindow, ObjC.sel("windowNumber")), Ptr.nil(), a, a, false, 0);
					Msg.vPtrBool(Msg.id(ObjC.cls("NSApplication"), ObjC.sel("sharedApplication")), ObjC.sel("postEvent:atStart:"), ev, false);
					ObjC.release(a);
					step = 1;
				case 1 if (log.length > 0):
					// an input method's composition, its caret at the end (NSNotFound: no replacement)
					var s = ObjC.str("にほ");
					Msg.vPtrIntIntIntInt(tv, ObjC.sel("setMarkedText:selectedRange:replacementRange:"), s, 2, 0, NOT_FOUND, 0);
					ObjC.release(s);
					step = 2;
				case 2 if (log.length > 1):
					var s = ObjC.str("日本");
					Msg.vPtrIntInt(tv, ObjC.sel("insertText:replacementRange:"), s, NOT_FOUND, 0);
					ObjC.release(s);
					step = 3;
				case 3:
					w.stopTextInput();
					check("text input off: not the first responder", Msg.id(nsWindow, ObjC.sel("firstResponder")) != tv);
					w.close();
				case _:
			}
			if (haxe.Timer.stamp() - start > 10) w.close();
			App.wait(0.01);
		}, e -> switch e.kind {
			case TextInput: log.push("input " + e.text);
			case TextEditing: log.push('editing ${e.text} ${e.x}');
			case _:
		});
		check("a key typed through the text view", log[0] == "input a", log.join("|"));
		check("the composition", log[1] == "editing にほ 2", log.join("|"));
		check("committed: the composition ends, its text typed", log[2] == "editing  0" && log[3] == "input 日本" && log.length == 4, log.join("|"));
	}
}
