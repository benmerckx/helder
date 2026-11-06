import helder.os.objc.*;
import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.view.*;
import hxmc.unsafe.*;

// helder.ui's UIAccessibility on iOS (IosAccess; CI's ios-simulator job,
// tests/pack/ios.sh): AccessFixture's controls, the window's view read as
// VoiceOver reads it (not an element, its accessibilityElements: their
// labels, values, traits and frames), a button activated and a slider
// incremented through them; its lines end with "access: ... ok" or FAILED.
//   helder run tests/ui/IosAccessCheck.hx --target ios -d <simulator>
class IosAccessCheck {
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('access: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function sel(s:String):Ptr
		return Arena.scopedValue(a -> Runtime.sel_registerName(a.cstring(s)));

	static function str(o:Ptr, s:String):String {
		var v = Msg.id(o, sel(s));
		return v.isNull() ? "" : ObjC.string(Msg.id(v, ObjC.sel("description"))) ?? "";
	}

	static function main() {
		Sys.println("access: started");
		var w = new UiWindow("fixture", 400, 640);
		var f = new AccessFixture();
		Render.render(f.view(), w.root);
		var frames = 0, step = 0, els:Array<Ptr> = [];
		function find(label:String):Ptr {
			for (e in els)
				if (str(e, "accessibilityLabel") == label) return e;
			check('an element $label', false);
			return Ptr.nil();
		}
		w.onFrame = () -> {
			if (++frames == 1) Sys.println("access: a first frame");
			// (a few frames first: the layout settled; each asks for the next)
			if (frames < 3) {
				w.ui.requestFrame();
				return;
			}
			var view = w.window.surface.handle;
			switch step {
				case 0:
					check("the view a container, not an element", !Msg.b(view, sel("isAccessibilityElement")));
					var a = Msg.id(view, sel("accessibilityElements"));
					els = a.isNull() ? [] : [for (i in 0...Msg.i(a, ObjC.sel("count")).toInt()) Msg.idInt(a, ObjC.sel("objectAtIndex:"), i)];
					Sys.println('access: ${els.length} elements: ' + [for (e in els) str(e, "accessibilityLabel")].join(", "));
					check("its elements", els.length >= 20, '${els.length}');
					var save = find("Save"), vol = find("Volume"), name = find("Name");
					if (!save.isNull()) {
						var t = Msg.i(save, sel("accessibilityTraits")).toInt();
						check("a button's traits", t & 1 != 0, '$t');
						var fr = Msg.rect(save, sel("accessibilityFrame"));
						check("a button's frame", fr.size.width > 20 && fr.size.height > 10, '${fr.size.width}x${fr.size.height}');
						check("activated", Msg.b(save, sel("accessibilityActivate")) && f.saved == 1);
					}
					if (!vol.isNull()) {
						check("a slider's value", str(vol, "accessibilityValue") == "50%", str(vol, "accessibilityValue"));
						Msg.v(vol, sel("accessibilityIncrement"));
						check("incremented", Math.abs(f.volume.peek() - 0.6) < 1e-9, '${f.volume.peek()}');
					}
					if (!name.isNull()) check("a field's value", str(name, "accessibilityValue") == "Ada");
					step = 1;
				case 1:
					var vol = find("Volume");
					if (!vol.isNull()) check("the slider's value after", str(vol, "accessibilityValue") == "60%", str(vol, "accessibilityValue"));
					Sys.println('access: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
					Sys.exit(failed == 0 ? 0 : 1);
				case _:
			}
			w.ui.requestFrame();
		};
		UiWindow.run();
	}
}
