import helder.os.objc.*;
import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.view.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import helder.view.graph.Read;
import helder.view.Flow.*;
import Plain.*;
import hxmc.unsafe.*;

// helder.ui's accessibility on macOS (MacAccess): a window of controls
// (Plain's), its tree read back as assistive technology reads it, through
// the NSAccessibility protocol (the view's children, their roles, labels,
// values and frames; the focused element; a hit test), and the actions
// performed on its elements (press, increment) reaching the controls. Its
// field native (MacViews: an NSTextField over the window): the program's
// text in it, an edit (its delegate told, as AppKit tells it) in the
// field's signal, Tab left to the window moving its focus on; made a
// password, an NSSecureTextField with the same text. A text area native:
// an NSTextView, the program's text in it, an edit (textDidChange:, as
// AppKit tells it) in the area's signal.
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
		var saved = 0, checked = signal(false), volume = signal(0.5), name = signal(""), areaOn = signal(false), notes = signal("");
		Render.render(<view padding={12} row-gap={8} align-items="start">
			<text>Settings</text>
			<Button tag="save" label="Save" onClick={() -> saved++}/>
			<Checkbox tag="remember" checked={checked} label="Remember"/>
			<Slider tag="volume" value={volume} step={0.1} label="Volume"/>
			<field tag="name" value={name} placeholder="Name" label="Name" onInput={e -> name(e.text)}/>
			<Show when={areaOn}><field:textarea tag="notes" value={notes} onInput={e -> notes(e.text)}/></Show>
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
					var ma:Null<helder.ui.draw.MacAccess> = cast @:privateAccess w.macAccess;
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
						check("the checkbox pressed", checked() && str(elements[2], "accessibilityValue") == "1", str(elements[2], "accessibilityValue"));
						check("the slider incremented", Math.abs(volume() - 0.6) < 1e-9 && str(elements[3], "accessibilityValue") == "0.6",
							'${volume()} ' + str(elements[3], "accessibilityValue"));
						check("the focused element", Msg.id(view, ObjC.sel("accessibilityFocusedUIElement")) == elements[3]);
					}
					var eds:Array<helder.ui.draw.MacViews.MacEditor> = @:privateAccess helder.ui.draw.MacViews.editors;
					check("the field native: one NSTextField", eds.length == 1, "" + eds.length);
					name("Ada");
					flush();
					step = 2;
				case 2:
					var eds:Array<helder.ui.draw.MacViews.MacEditor> = @:privateAccess helder.ui.draw.MacViews.editors;
					if (eds.length == 1) {
						var field = @:privateAccess eds[0].field;
						check("the program's text in the NSTextField", @:privateAccess eds[0].text() == "Ada", @:privateAccess eds[0].text());
						var t = ObjC.str("Adax");
						Msg.vPtr(field, ObjC.sel("setStringValue:"), t);
						var note = Msg.idPtrPtr(ObjC.cls("NSNotification"), ObjC.sel("notificationWithName:object:"), t, field);
						Msg.vPtr(@:privateAccess helder.ui.draw.MacViews.delegate, ObjC.sel("controlTextDidChange:"), note);
						w.ui.setFocus(w.root.find("name"));
					}
					step = 3;
				case 3:
					check("an edit in the NSTextField, the field's signal follows", name() == "Adax", name());
					var eds:Array<helder.ui.draw.MacViews.MacEditor> = @:privateAccess helder.ui.draw.MacViews.editors;
					if (eds.length == 1)
						Msg.idPtrPtrPtr(@:privateAccess helder.ui.draw.MacViews.delegate, ObjC.sel("control:textView:doCommandBySelector:"), @:privateAccess eds[0].field,
							Ptr.nil(), ObjC.sel("insertTab:"));
					step = 4;
				case 4:
					check("Tab left to the window: its focus on", w.ui.focus != null && w.ui.focus.tag == "save", w.ui.focus == null ? "none" : w.ui.focus.tag);
					(cast w.root.find("name") : helder.ui.widgets.EditableText).secret = true;
					step = 5;
				case 5:
					var eds:Array<helder.ui.draw.MacViews.MacEditor> = @:privateAccess helder.ui.draw.MacViews.editors;
					if (eds.length == 1) {
						var field = @:privateAccess eds[0].field;
						check("a password: an NSSecureTextField", str(field, "class") == "NSSecureTextField", str(field, "class"));
						check("a password: the text kept", @:privateAccess eds[0].text() == "Adax", @:privateAccess eds[0].text());
					}
					areaOn(true);
					flush();
					notes("Line");
					flush();
					step = 6;
				case 6:
					var areas = [for (e in (@:privateAccess helder.ui.draw.MacViews.editors : Array<helder.ui.draw.MacViews.MacEditor>)) if (Std.isOfType(e, helder.ui.draw.MacViews.MacAreaEditor)) e];
					check("the text area native: an NSTextView", areas.length == 1 && str(@:privateAccess areas[0].field, "class") == "NSTextView",
						"" + areas.length);
					if (areas.length == 1) {
						var tv = @:privateAccess areas[0].field;
						check("the program's text in the NSTextView", @:privateAccess areas[0].text() == "Line", @:privateAccess areas[0].text());
						var t = ObjC.str("Line\nTwo");
						Msg.vPtr(tv, ObjC.sel("setString:"), t);
						var note = Msg.idPtrPtr(ObjC.cls("NSNotification"), ObjC.sel("notificationWithName:object:"), t, tv);
						Msg.vPtr(@:privateAccess helder.ui.draw.MacViews.delegate, ObjC.sel("textDidChange:"), note);
					}
					step = 7;
				case 7:
					check("an edit in the NSTextView, the area's signal follows", notes() == "Line\nTwo", notes());
					step = 8;
					w.close();
				case _:
			}
			// (a frame again: the next step)
			w.ui.requestFrame();
		};
		UiWindow.run();
		Sys.println('MacAccessTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 && checks >= 19 ? 0 : 1);
	}
}
