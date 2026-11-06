import helder.os.objc.*;
import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.view.*;
import hxmc.unsafe.*;

// helder.ui's NSAccessibility (MacAccess) on AccessFixture's controls, read
// and set in process as assistive technology does through the protocol: a
// table's rows, columns, column headers and a row's index, an item's index
// in its list, a text input's value, characters, a string for a range and
// a line for an index; then the states set (a field's value and focus, a
// disclosure expanded, a row selected, a slider's value) reaching the
// controls, and read back from the tree after.
//   MacPatternsTest
class MacPatternsTest {
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('MacPatternsTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function sel(s:String):Ptr
		return Arena.scopedValue(a -> Runtime.sel_registerName(a.cstring(s)));

	static function str(o:Ptr, s:String):String {
		var v = Msg.id(o, sel(s));
		return v.isNull() ? "" : ObjC.string(Msg.id(v, ObjC.sel("description"))) ?? "";
	}

	static function count(o:Ptr, s:String):Int {
		var a = Msg.id(o, sel(s));
		return a.isNull() ? -1 : Msg.i(a, ObjC.sel("count")).toInt();
	}

	static function children(o:Ptr):Array<Ptr> {
		var a = Msg.id(o, ObjC.sel("accessibilityChildren"));
		if (a.isNull()) return [];
		return [for (i in 0...Msg.i(a, ObjC.sel("count")).toInt()) Msg.idInt(a, ObjC.sel("objectAtIndex:"), i)];
	}

	static function all(o:Ptr, out:Array<Ptr>):Array<Ptr> {
		for (c in children(o)) {
			out.push(c);
			all(c, out);
		}
		return out;
	}

	static function main() {
		var w = new UiWindow("patterns", 400, 640);
		var f = new AccessFixture();
		Render.render(f.view(), w.root);
		var view = w.window.surface.handle, step = 0, els:Array<Ptr> = [];
		function find(role:String, name:String):Ptr {
			for (e in els)
				if (str(e, "accessibilityRole") == role && (str(e, "accessibilityLabel") == name || role == "AXStaticText" && str(e, "accessibilityValue") == name)) return e;
			check('$role $name', false);
			return Ptr.nil();
		}
		w.onFrame = () -> {
			switch step {
				case 0:
					els = all(view, []);
					check("the fixture's elements", els.length == 30, '${els.length}');
					var grid = find("AXTable", "Mail");
					if (!grid.isNull()) {
						check("a table's rows and columns", Msg.i(grid, sel("accessibilityRowCount")).toInt() == 3 && Msg.i(grid, sel("accessibilityColumnCount")).toInt() == 2);
						check("its rows", count(grid, "accessibilityRows") == 3);
						check("its column headers", count(grid, "accessibilityColumnHeaderUIElements") == 2);
						check("its selected row", count(grid, "accessibilitySelectedRows") == 1);
					}
					var bob = find("AXRow", "Bob Lunch");
					if (!bob.isNull()) check("a row's index", Msg.i(bob, sel("accessibilityIndex")).toInt() == 2);
					var pear = find("AXGroup", "Pear");
					if (!pear.isNull()) check("an item's index", Msg.i(pear, sel("accessibilityIndex")).toInt() == 1);
					var name = find("AXTextField", "Name");
					if (!name.isNull()) {
						check("a field's value", str(name, "accessibilityValue") == "Ada");
						check("its characters", Msg.i(name, sel("accessibilityNumberOfCharacters")).toInt() == 3);
						var part = Msg.idIntInt(name, sel("accessibilityStringForRange:"), 1, 2);
						check("a string for a range", ObjC.string(part) == "da");
						Msg.vPtr(name, sel("setAccessibilityValue:"), ObjC.str("Bob"));
						check("its value set", f.name.peek() == "Bob", f.name.peek());
					}
					var notes = find("AXTextArea", "Notes");
					if (!notes.isNull()) check("a line for an index", Msg.iInt(notes, sel("accessibilityLineForIndex:"), 5).toInt() == 1);
					var more = find("AXButton", "More");
					if (!more.isNull()) {
						check("collapsed", Msg.b(more, sel("isAccessibilityExpanded")) == false);
						Msg.vBool(more, sel("setAccessibilityExpanded:"), true);
						check("expanded", f.open.peek());
					}
					if (!bob.isNull()) {
						Msg.vBool(bob, sel("setAccessibilitySelected:"), true);
						check("a row selected", f.row.peek() == 1);
					}
					var vol = find("AXSlider", "Volume");
					if (!vol.isNull()) {
						Msg.vPtr(vol, sel("setAccessibilityValue:"), Msg.idFloat(ObjC.cls("NSNumber"), ObjC.sel("numberWithDouble:"), 0.8));
						check("a slider's value set", Math.abs(f.volume.peek() - 0.8) < 1e-9, '${f.volume.peek()}');
					}
					// (last: the clicks above may move the focus, as a click does)
					if (!name.isNull()) {
						Msg.vBool(name, sel("setAccessibilityFocused:"), true);
						check("focused", w.ui.focus == w.root.find("name"));
					}
					step = 1;
				case 1:
					var name = find("AXTextField", "Name"), bob = find("AXRow", "Bob Lunch"), more = find("AXButton", "More");
					check("after: focused", !name.isNull() && Msg.b(name, sel("isAccessibilityFocused")), w.ui.focus == null ? "none" : w.ui.focus.tag);
					check("after: selected", !bob.isNull() && Msg.b(bob, sel("isAccessibilitySelected")));
					check("after: expanded", !more.isNull() && Msg.b(more, sel("isAccessibilityExpanded")));
					check("after: the field's value", !name.isNull() && str(name, "accessibilityValue") == "Bob");
					step = 2;
					w.close();
				case _:
			}
			w.ui.requestFrame();
		};
		UiWindow.run();
		Sys.println('MacPatternsTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 && checks >= 20 ? 0 : 1);
	}
}
