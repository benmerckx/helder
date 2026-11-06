import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.ui.draw.WinAccess;
import helder.view.*;
import hxmc.unsafe.*;

// helder.ui's UI Automation patterns (WinAccess), in process: AccessFixture's
// controls, their providers called through their COM interfaces as UI
// Automation calls them (Wine's own client has no patterns, so this is
// what runs them there; WinAccessProbe's client does on Windows): a
// table's Grid and Table (rows, columns, an item, its GridItem's place, the
// column headers), a row's SelectionItem and its container's Selection, a
// disclosure's ExpandCollapse, a slider's RangeValue set, a ScrollItem, a
// field's Text: its document range's text, a range moved by words and
// characters, its bounding rectangles, selected (the field's selection
// after), found text.
//   WinPatternsTest
class WinPatternsTest {
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('WinPatternsTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function guid(s:String):Ptr {
		var h = StringTools.replace(s, "-", "");
		var p:Ptr<UInt8> = LibC.malloc(16);
		var order = [3, 2, 1, 0, 5, 4, 7, 6, 8, 9, 10, 11, 12, 13, 14, 15];
		for (i in 0...16)
			p[i] = Std.parseInt("0x" + h.substr(2 * order[i], 2));
		return p;
	}

	static final FRAGMENT = guid("f7063da8-8359-439c-9297-bbc5299a7d87");
	static final SIMPLE = guid("d6dd68d1-86fd-4332-8666-9abedea2d24c");
	static final out:Ptr<Ptr> = LibC.malloc(8);
	static final v:Ptr = LibC.malloc(24);
	static final i32:Ptr<Int32> = LibC.malloc(8);
	static final d:Ptr<Float> = LibC.malloc(64);

	static function qi(o:Ptr, iid:Ptr):Ptr {
		out.value = Ptr.nil();
		return Unknown.QueryInterface(o, iid, out) == 0 ? out.value : Ptr.nil();
	}

	static function bstr(p:Ptr):String {
		if (p.isNull()) return "";
		var s:Ptr<UInt16> = p, b = new StringBuf(), i = 0;
		while (s[i] != 0)
			b.addChar(s[i++]);
		return b.toString();
	}

	static function name(simple:Ptr):String {
		(v : Ptr<Int64>).value = 0;
		Simple.GetPropertyValue(simple, 30005, v);
		return (v : Ptr<UInt16>).value == 8 ? bstr((v.add(8) : Ptr<Ptr>).value) : "";
	}

	static function prop(simple:Ptr, id:Int):Int {
		(v : Ptr<Int64>).value = 0;
		Simple.GetPropertyValue(simple, id, v);
		return (v : Ptr<UInt16>).value == 3 ? (v.add(8) : Ptr<Int32>).value : -1;
	}

	static function pattern(simple:Ptr, id:Int):Ptr {
		out.value = Ptr.nil();
		Simple.GetPatternProvider(simple, id, out);
		return out.value;
	}

	// every node's simple provider, depth first
	static function all(f:Ptr, list:Array<Ptr>):Array<Ptr> {
		list.push(qi(f, SIMPLE));
		out.value = Ptr.nil();
		Fragment.Navigate(f, 3, out);
		var k = out.value;
		while (!k.isNull()) {
			all(k, list);
			out.value = Ptr.nil();
			Fragment.Navigate(k, 1, out);
			k = out.value;
		}
		return list;
	}

	static function main() {
		var w = new UiWindow("patterns", 400, 640);
		var f = new AccessFixture();
		Render.render(f.view(), w.root);
		var step = 0, nodes:Array<Ptr> = [];
		function find(n:String):Ptr {
			for (s in nodes)
				if (name(s) == n) return s;
			check('a node named $n', false);
			return Ptr.nil();
		}
		w.onFrame = () -> {
			switch step {
				case 0:
					var a:WinAccess = cast @:privateAccess w.winAccess;
					nodes = all(qi(a.rootProvider(), FRAGMENT), []);
					check("the fixture's nodes", nodes.length == 31, '${nodes.length}');
					// a table
					var grid = find("Mail"), g = pattern(grid, 10006);
					check("Grid", !g.isNull() && Grid.get_RowCount(g, i32) == 0 && i32.value == 3 && Grid.get_ColumnCount(g, i32) == 0 && i32.value == 2);
					out.value = Ptr.nil();
					if (!g.isNull()) Grid.GetItem(g, 2, 1, out);
					var cell = out.value;
					check("Grid's item", !cell.isNull() && name(cell) == "Lunch");
					var gi = cell.isNull() ? Ptr.nil() : pattern(cell, 10007);
					check("GridItem's place", !gi.isNull() && GridItem.get_Row(gi, i32) == 0 && i32.value == 2 && GridItem.get_Column(gi, i32) == 0 && i32.value == 1);
					var t = pattern(grid, 10012);
					out.value = Ptr.nil();
					if (!t.isNull()) Table.GetColumnHeaders(t, out);
					var n = 0;
					if (!out.value.isNull()) {
						OleAut.SafeArrayGetUBound(out.value, 1, i32);
						n = i32.value + 1;
					}
					check("Table's column headers", n == 2, '$n');
					check("an item's place in its set", prop(find("Pear"), 30152) == 2 && prop(find("Pear"), 30153) == 3);
					// a row selected
					var bob = find("Bob Lunch"), si = pattern(bob, 10010);
					check("SelectionItem", !si.isNull() && SelectionItem.get_IsSelected(si, i32) == 0 && i32.value == 0 && SelectionItem.Select(si) == 0 && f.row.peek() == 1);
					out.value = Ptr.nil();
					if (!si.isNull()) SelectionItem.get_SelectionContainer(si, out);
					check("its container: the table", !out.value.isNull() && name(out.value) == "Mail");
					// a disclosure
					var more = find("More"), ec = pattern(more, 10005);
					check("ExpandCollapse", !ec.isNull() && ExpandCollapse.get_State(ec, i32) == 0 && i32.value == 0 && ExpandCollapse.Expand(ec) == 0 && f.open.peek());
					// a slider
					var rv = pattern(find("Volume"), 10003);
					check("RangeValue set", !rv.isNull() && RangeValue.SetValue(rv, 0.8) == 0 && Math.abs(f.volume.peek() - 0.8) < 1e-9, '${f.volume.peek()}');
					// scrolled into view
					var sc = pattern(find("Last"), 10017);
					check("ScrollItem", !sc.isNull() && ScrollItem.ScrollIntoView(sc) == 0 && w.root.find("scroller").scrollY > 0);
					// a field's text
					var field = find("Name"), tp = pattern(field, 10014);
					check("Text", !tp.isNull());
					if (!tp.isNull()) {
						out.value = Ptr.nil();
						Text.get_DocumentRange(tp, out);
						var r = out.value;
						out.value = Ptr.nil();
						TextRange.GetText(r, -1, out);
						check("its document range", bstr(out.value) == "Ada");
						TextRange.ExpandToEnclosingUnit(r, 0);
						out.value = Ptr.nil();
						TextRange.GetText(r, -1, out);
						check("expanded to a character", bstr(out.value) == "A");
						TextRange.Move(r, 0, 1, i32);
						out.value = Ptr.nil();
						TextRange.GetText(r, -1, out);
						check("moved a character", i32.value == 1 && bstr(out.value) == "d", bstr(out.value));
						TextRange.MoveEndpointByUnit(r, 1, 0, 1, i32);
						out.value = Ptr.nil();
						TextRange.GetText(r, -1, out);
						check("its end a character on", bstr(out.value) == "da");
						out.value = Ptr.nil();
						TextRange.GetBoundingRectangles(r, out);
						var rects = 0;
						if (!out.value.isNull()) {
							OleAut.SafeArrayGetUBound(out.value, 1, i32);
							rects = i32.value + 1;
						}
						check("its bounding rectangle", rects == 4, '$rects');
						check("selected", TextRange.Select(r) == 0);
						out.value = Ptr.nil();
						Text.get_DocumentRange(tp, out);
						var doc = out.value;
						Arena.scoped(m -> {
							out.value = Ptr.nil();
							TextRange.FindText(doc, m.wstring("da"), 0, 0, out);
						});
						check("text found", !out.value.isNull());
					}
					step = 1;
				case 1:
					var a:WinAccess = cast @:privateAccess w.winAccess;
					var t = @:privateAccess a.tree, field = 0;
					for (id in t.order)
						if (t.nodes.get(id).name == "Name") field = id;
					var n = t.nodes.get(field);
					check("the field's selection after", n != null && n.textStart == 1 && n.textEnd == 3 && t.focus == field);
					check("expanded after", w.root.find("extra") != null);
					step = 2;
					w.close();
				case _:
			}
			w.ui.requestFrame();
		};
		UiWindow.run();
		Sys.println('WinPatternsTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 && checks >= 21 ? 0 : 1);
	}
}

@:build(helder.os.win32.Com.build())
class Unknown {
	@:slot(0) static function QueryInterface(o:Ptr, iid:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class Simple {
	@:slot(4) static function GetPatternProvider(o:Ptr, id:Int, out:Ptr<Ptr>):Int;
	@:slot(5) static function GetPropertyValue(o:Ptr, id:Int, v:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
class Fragment {
	@:slot(3) static function Navigate(o:Ptr, dir:Int, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class Grid {
	@:slot(3) static function GetItem(o:Ptr, row:Int, col:Int, out:Ptr<Ptr>):Int;
	@:slot(4) static function get_RowCount(o:Ptr, out:Ptr<Int32>):Int;
	@:slot(5) static function get_ColumnCount(o:Ptr, out:Ptr<Int32>):Int;
}

@:build(helder.os.win32.Com.build())
class GridItem {
	@:slot(3) static function get_Row(o:Ptr, out:Ptr<Int32>):Int;
	@:slot(4) static function get_Column(o:Ptr, out:Ptr<Int32>):Int;
}

@:build(helder.os.win32.Com.build())
class Table {
	@:slot(4) static function GetColumnHeaders(o:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class SelectionItem {
	@:slot(3) static function Select(o:Ptr):Int;
	@:slot(6) static function get_IsSelected(o:Ptr, out:Ptr<Int32>):Int;
	@:slot(7) static function get_SelectionContainer(o:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class ExpandCollapse {
	@:slot(3) static function Expand(o:Ptr):Int;
	@:slot(5) static function get_State(o:Ptr, out:Ptr<Int32>):Int;
}

@:build(helder.os.win32.Com.build())
class RangeValue {
	@:slot(3) static function SetValue(o:Ptr, v:Float):Int;
}

@:build(helder.os.win32.Com.build())
class ScrollItem {
	@:slot(3) static function ScrollIntoView(o:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
class Text {
	@:slot(7) static function get_DocumentRange(o:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class TextRange {
	@:slot(6) static function ExpandToEnclosingUnit(o:Ptr, unit:Int):Int;
	@:slot(8) static function FindText(o:Ptr, s:Ptr, backward:Int, ignoreCase:Int, out:Ptr<Ptr>):Int;
	@:slot(10) static function GetBoundingRectangles(o:Ptr, out:Ptr<Ptr>):Int;
	@:slot(12) static function GetText(o:Ptr, max:Int, out:Ptr<Ptr>):Int;
	@:slot(13) static function Move(o:Ptr, unit:Int, count:Int, moved:Ptr<Int32>):Int;
	@:slot(14) static function MoveEndpointByUnit(o:Ptr, endpoint:Int, unit:Int, count:Int, moved:Ptr<Int32>):Int;
	@:slot(16) static function Select(o:Ptr):Int;
}

@:hxmc.c @:hxmc.lib("oleaut32") extern class OleAut {
	static function SafeArrayGetUBound(array:Ptr, dim:Int, out:Ptr<Int32>):Int;
}
