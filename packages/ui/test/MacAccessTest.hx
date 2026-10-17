import hxmc.esx.Markup;
import hxmc.os.objc.*;
import hxmc.ui.*;
import hxmc.ui.draw.UiWindow;
import hxmc.ui.reactive.*;
import hxmc.ui.reactive.Reactive.*;
import hxmc.ui.widgets.Widgets.Button;
import hxmc.ui.widgets.Widgets.Checkbox;
import hxmc.ui.widgets.Widgets.Slider;
import hxmc.ui.widgets.Widgets.Field;
import hxmc.unsafe.*;

// hxmc.ui's accessibility on macOS (MacAccess; CI's macOS job): a window of
// widgets, its tree read back as assistive technology reads it, through
// the NSAccessibility protocol (the view's children, their roles, labels,
// values and frames; the focused element; a hit test), and the actions
// performed on its elements (press, increment) reaching the widgets.
//   MacAccessTest
class MacAccessTest implements Markup {
	static var failed = 0;
	static var checks = 0;
	// (a point passed by value)
	static final pt:Ptr<CGRect> = LibC.malloc(32);

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('MacAccessTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function str(o:Ptr, sel:String):String {
		var v = Msg.id(o, Arena.scopedValue(a -> Runtime.sel_registerName(a.cstring(sel))));
		if (v.isNull()) return "";
		var d = Msg.id(v, ObjC.sel("description"));
		return ObjC.string(d) ?? "";
	}

	static function main() {
		var w = new UiWindow("MacAccessTest", 320, 240);
		var saved = 0, checked = signal(false), volume = signal(0.5), name = signal("");
		Render.render(<view padding={12} row-gap={8} align-items="start">
			<text>Settings</text>
			<Button tag="save" label="Save" onClick={() -> saved++}/>
			<Checkbox tag="remember" checked={checked} label="Remember"/>
			<Slider tag="volume" value={volume} step={0.1} label="Volume"/>
			<Field tag="name" value={name} placeholder="Name"/>
		</view>, w.root);
		var view = w.window.surface.handle;
		var frames = 0, step = 0;
		var elements:Array<Ptr> = [];
		function children(o:Ptr):Array<Ptr> {
			var a = Msg.id(o, ObjC.sel("accessibilityChildren"));
			if (a.isNull()) return [];
			return [for (i in 0...Msg.i(a, ObjC.sel("count")).toInt()) Msg.idInt(a, ObjC.sel("objectAtIndex:"), i)];
		}
		w.onFrame = () -> {
			frames++;
			switch step {
				case 0:
					var ma:Null<hxmc.ui.draw.MacAccess> = cast @:privateAccess w.macAccess;
					check("no tree before a question", ma != null && @:privateAccess ma.tree == null);
					elements = children(view);
					var shape = [for (e in elements) str(e, "accessibilityRole") + ":" + (str(e, "accessibilityRole") == "AXStaticText" ? str(e, "accessibilityValue") : str(e, "accessibilityLabel"))];
					check("the view's children: roles and names", shape.join(",") == "AXStaticText:Settings,AXButton:Save,AXCheckBox:Remember,AXSlider:Volume,AXTextField:Name", shape.join(","));
					if (elements.length == 5) {
						check("a checkbox's value", str(elements[2], "accessibilityValue") == "0", str(elements[2], "accessibilityValue"));
						check("a slider's value and range", str(elements[3], "accessibilityValue") == "0.5" && str(elements[3], "accessibilityMaxValue") == "1",
							str(elements[3], "accessibilityValue") + " " + str(elements[3], "accessibilityMaxValue"));
						var f = Msg.rect(elements[1], ObjC.sel("accessibilityFrame"));
						check("a frame in screen points", f.size.width > 20 && f.size.height > 10, '${f.size.width}x${f.size.height}');
						check("its parent the view", Msg.id(elements[1], ObjC.sel("accessibilityParent")) == view);
						// a hit test at the button's centre
						pt.value.origin.x = f.origin.x + f.size.width / 2;
						pt.value.origin.y = f.origin.y + f.size.height / 2;
						var hit = @:privateAccess Msg.c_idPoint(Msg.send, view, ObjC.sel("accessibilityHitTest:"), pt.value.origin);
						check("a hit test finds the button", hit == elements[1]);
						// actions
						check("press", Msg.i(elements[1], ObjC.sel("accessibilityPerformPress")).toInt() & 255 == 1 && saved == 1, '$saved');
						Msg.i(elements[2], ObjC.sel("accessibilityPerformPress"));
						Msg.i(elements[3], ObjC.sel("accessibilityPerformIncrement"));
					}
					step = 1;
				case 1:
					if (elements.length == 5) {
						check("the checkbox pressed", checked.value && str(elements[2], "accessibilityValue") == "1", str(elements[2], "accessibilityValue"));
						check("the slider incremented", Math.abs(volume.value - 0.6) < 1e-9 && str(elements[3], "accessibilityValue") == "0.6",
							'${volume.value} ' + str(elements[3], "accessibilityValue"));
						check("the focused element", Msg.id(view, ObjC.sel("accessibilityFocusedUIElement")) == elements[3]);
					}
					step = 2;
					w.close();
				case _:
			}
			// (a frame again: the next step)
			w.ui.requestFrame();
		};
		UiWindow.run();
		Sys.println('MacAccessTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 && checks >= 10 ? 0 : 1);
	}
}
