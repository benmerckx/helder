import hxmc.unsafe.*;

// UI Automation's client side (IUIAutomation, as Narrator and test tools
// read applications), from a process of its own: finds the window of a
// title (AccessApp's), its element (ElementFromHandle: the provider its
// WM_GETOBJECT gives), and reads its whole tree through the raw view's
// walker: each element's control type and name, its bounds inside the
// window's, its parent. The roles and names asked for must be in it
// ("role:name" as AT-SPI names roles, mapped to control types). For the
// fixture it goes on through the patterns: a table's Grid (rows, columns,
// an item, its GridItem's place), an item's place in its set, a field's
// Value and Text (the document range's text, a word moved to, the
// selection set through a range), a read-only field's IsReadOnly, a
// disclosure's ExpandCollapse, a row's SelectionItem, a slider's
// RangeValue set, a ScrollItem, a checkbox's Toggle; the events those
// raise (handlers registered for the focus, property changes, structure
// changes, text selection), last the Save button's Invoke, which closes it.
//   WinAccessProbe <title> [role:name ...]
class WinAccessProbe {
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('WinAccessProbe: FAIL: $what' + (detail == null ? "" : ": " + detail));
			Sys.stdout().flush();
		}
	}

	// a GUID's 16 bytes (Data1 to Data3 little-endian)
	static function guid(s:String):Ptr {
		var h = StringTools.replace(s, "-", "");
		var p:Ptr<UInt8> = LibC.malloc(16);
		var order = [3, 2, 1, 0, 5, 4, 7, 6, 8, 9, 10, 11, 12, 13, 14, 15];
		for (i in 0...16)
			p[i] = Std.parseInt("0x" + h.substr(2 * order[i], 2));
		return p;
	}

	static final CLSID_CUIAutomation = guid("ff48dba4-60ef-4201-aa87-54103eef594e");
	static final IID_IUIAutomation = guid("30cbe57d-d9d0-452a-ab13-7ac5ac4825ee");
	static final IID_Invoke = guid("fb377fbe-8ea6-46d5-9c73-6499642d3059");
	static final IID_Toggle = guid("94cf8058-9b8d-4ab9-8bfd-4cd0a33c8c70");
	static final IID_Value = guid("a94cd8b1-0844-4cd6-9d2d-640537ab39e9");
	static final IID_RangeValue = guid("59213f4f-7346-49e5-b120-80555987a148");
	static final IID_ExpandCollapse = guid("619be086-1f4e-4ee4-bafa-210128738730");
	static final IID_Text = guid("32eba289-3583-42c9-9c59-3b6d9a1e9b6a");
	static final IID_SelectionItem = guid("a8efa66a-0fda-421a-9194-38021f3578ea");
	static final IID_Grid = guid("414c3cdc-856b-4f5b-8538-3131c6302550");
	static final IID_GridItem = guid("78f8ef57-66c3-4e09-bd7c-e79b2004894d");
	static final IID_ScrollItem = guid("b488300f-d015-4f19-9c29-bb595e3645ef");

	static final out:Ptr<Ptr> = LibC.malloc(8);
	static final v:Ptr = LibC.malloc(24);
	static final i32:Ptr<Int32> = LibC.malloc(8);
	static final d:Ptr<Float> = LibC.malloc(32);
	static var walker = Ptr.nil();
	static var any = Ptr.nil();

	// what the event handlers saw (written on UI Automation's threads: no
	// allocation there, a count per kind in each handler's own memory, see
	// handler): focus, property changes (by the property: name, toggle
	// state, expand state, selected, range value), structure changes, text
	// selection changes
	static final handlers:Array<Ptr> = [];

	static function seen(k:Int):Int {
		var n = 0;
		for (h in handlers)
			n += Mem.getI32(h, 4 * (2 + k));
		return n;
	}

	static function bstr(p:Ptr):String {
		if (p.isNull()) return "";
		var s:Ptr<UInt16> = p, b = new StringBuf(), i = 0;
		while (s[i] != 0)
			b.addChar(s[i++]);
		return b.toString();
	}

	static function prop(e:Ptr, id:Int):Dynamic {
		for (k in 0...3)
			(v.add(8 * k) : Ptr<Int64>).value = 0;
		var hr = Element.GetCurrentPropertyValueEx(e, id, 0, v);
		var vt:Int = (v : Ptr<UInt16>).value;
		if (Sys.getEnv("UIA_DEBUG") != null) Sys.println('prop $id: hr ${StringTools.hex(hr)} vt $vt');
		if (hr != 0) return null;
		return switch vt {
			case 8: bstr((v.add(8) : Ptr<Ptr>).value);
			case 3:
				var i:Int = (v.add(8) : Ptr<Int32>).value;
				i;
			case 5:
				var f:Float = (v.add(8) : Ptr<Float>).value;
				f;
			case 11:
				var b:Bool = (v.add(8) : Ptr<Int16>).value != 0;
				b;
			case 0x2005:
				// (VT_ARRAY | VT_R8: a rectangle's left, top, width, height)
				var sa:Ptr = (v.add(8) : Ptr<Ptr>).value, r:Array<Float> = [];
				for (k in 0...4) {
					i32.value = k;
					OleAut.SafeArrayGetElement(sa, i32, d);
					r.push(d.value);
				}
				r;
			case _: null;
		}
	}

	static function name(e:Ptr):String
		return prop(e, 30005) ?? "";

	static function type(e:Ptr):Int
		return prop(e, 30003) ?? 0;

	static function bounds(e:Ptr):Array<Float> {
		var r:Null<Array<Float>> = prop(e, 30001);
		return r == null ? [] : r;
	}

	static function pattern(e:Ptr, id:Int, iid:Ptr):Ptr {
		// (GetCurrentPattern, then the interface: Wine has no GetCurrentPatternAs)
		out.value = Ptr.nil();
		if (Element.GetCurrentPattern(e, id, out) != 0 || out.value.isNull()) return Ptr.nil();
		var u = out.value;
		out.value = Ptr.nil();
		var hr = Unknown.QueryInterface(u, iid, out);
		Unknown.Release(u);
		return hr == 0 ? out.value : Ptr.nil();
	}

	static function children(e:Ptr):Array<Ptr> {
		out.value = Ptr.nil();
		var hr = Element.FindAll(e, 2, any, out); // (TreeScope_Children)
		var arr = out.value, kids = [];
		if (Sys.getEnv("UIA_DEBUG") != null) Sys.println('findall: hr ${StringTools.hex(hr)} ${arr.isNull()}');
		if (arr.isNull()) return kids;
		ElementArray.get_Length(arr, i32);
		for (k in 0...i32.value) {
			out.value = Ptr.nil();
			ElementArray.GetElement(arr, k, out);
			if (Sys.getEnv("UIA_DEBUG") != null) Sys.println('element $k of ${i32.value}: ${out.value.isNull()}');
			kids.push(out.value);
		}
		return kids;
	}

	static function first(e:Ptr):Ptr {
		out.value = Ptr.nil();
		Walker.GetFirstChildElement(walker, e, out);
		return out.value;
	}

	static function next(e:Ptr):Ptr {
		out.value = Ptr.nil();
		Walker.GetNextSiblingElement(walker, e, out);
		return out.value;
	}

	static function parent(e:Ptr):Ptr {
		out.value = Ptr.nil();
		Walker.GetParentElement(walker, e, out);
		return out.value;
	}

	// AT-SPI's role names as UI Automation's control types
	static function typeOf(role:String):Int
		return switch role {
			case "push button" | "toggle button": 50000;
			case "check box": 50002;
			case "entry" | "password text": 50004;
			case "label": 50020;
			case "list": 50008;
			case "list item": 50007;
			case "image": 50006;
			case "menu item": 50011;
			case "slider": 50015;
			case "table": 50028;
			case "table row" | "table cell": 50029;
			case _: -1;
		}

	static final elements:Array<{e:Ptr, depth:Int}> = [];

	static function walk(e:Ptr, depth:Int, frame:Array<Float>) {
		elements.push({e: e, depth: depth});
		var t = type(e), n = name(e);
		check('$t:$n has a control type', t >= 50000 && t <= 50040);
		if (t == 50000 || t == 50002 || t == 50015 || t == 50004 || t == 50005) check('$t has a name', n != "");
		var b = bounds(e);
		check('$t:$n: bounds', b.length == 4 && b[2] >= 0 && b[3] >= 0);
		// (ours: the window's title bar and buttons are the system's, above its client area)
		if (b.length == 4 && frame.length == 4 && prop(e, 30022) != true && prop(e, 30024) == "helder")
			check('$t:$n: inside the window', b[0] >= frame[0] - 1 && b[1] >= frame[1] - 1 && b[0] + b[2] <= frame[0] + frame[2] + 1 && b[1] + b[3] <= frame[1] + frame[3] + 1,
				b.join(",") + " in " + frame.join(","));
		for (c in children(e)) {
			if (!walker.isNull()) {
				var p = parent(c);
				check('$t:$n: a child\'s parent', !p.isNull() && CompareElements(p, e));
			}
			walk(c, depth + 1, frame);
		}
	}

	static var uia = Ptr.nil();

	static function CompareElements(a:Ptr, b:Ptr):Bool {
		i32.value = 0;
		Automation.CompareElements(uia, a, b, i32);
		return i32.value != 0;
	}

	static function find(t:Int, n:String):Ptr {
		for (x in elements)
			if (type(x.e) == t && name(x.e) == n) return x.e;
		return Ptr.nil();
	}

	static function main() {
		var title = Sys.args()[0] ?? "fixture", wanted = Sys.args().slice(1);
		Ole32.CoInitializeEx(Ptr.nil(), 0); // (COINIT_MULTITHREADED: no messages to pump for UI Automation)
		var hr = Ole32.CoCreateInstance(CLSID_CUIAutomation, Ptr.nil(), 1, IID_IUIAutomation, out);
		check("IUIAutomation", hr == 0 && !out.value.isNull(), StringTools.hex(hr));
		if (hr != 0) Sys.exit(1);
		uia = out.value;
		out.value = Ptr.nil();
		Automation.get_RawViewWalker(uia, out);
		walker = out.value;
		// (the children by FindAll: Wine has no raw view's walker; the parents checked where there is one)
		out.value = Ptr.nil();
		Automation.CreateTrueCondition(uia, out);
		any = out.value;
		check("a condition", !any.isNull());
		// the window (it may take a moment to open)
		var hwnd = Ptr.nil(), start = haxe.Timer.stamp();
		while (hwnd.isNull() && haxe.Timer.stamp() - start < 30) {
			hwnd = Arena.scopedValue(a -> User.FindWindowW(Ptr.nil(), a.wstring(title)));
			if (hwnd.isNull()) Sys.sleep(0.1);
		}
		check("the window", !hwnd.isNull());
		if (hwnd.isNull()) Sys.exit(1);
		// (its first frames: the screen settled)
		Sys.sleep(1.5);
		out.value = Ptr.nil();
		hr = Automation.ElementFromHandle(uia, hwnd, out);
		var root = out.value;
		check("its element", hr == 0 && !root.isNull(), StringTools.hex(hr));
		if (root.isNull()) Sys.exit(1);
		check("its control type: ours, a pane", type(root) == 50033, '${type(root)}');
		// (the window's element is UI Automation's, of the HWND; ours is its first child, a pane, or itself)
		walk(root, 0, bounds(root));
		var shape = [for (x in elements) [for (_ in 0...x.depth) "  "].join("") + type(x.e) + ":" + name(x.e)];
		for (w in wanted) {
			var k = w.indexOf(":"), role = w.substr(0, k), n = w.substr(k + 1);
			var e = find(typeOf(role), n);
			check('wanted: $w', !e.isNull());
			if (role == "password text" && !e.isNull()) check('$w: a password', prop(e, 30019) == true);
		}
		if (failed > 0 || Sys.getEnv("UIA_DUMP") != null) Sys.println(shape.join("\n"));
		if (title == "fixture") fixture();
		Sys.println('WinAccessProbe: $title: ${elements.length} elements, $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	// --- the event handlers: COM objects of a vtable each, on UI Automation's threads ---

	// a handler: its vtable, then (as Ints, the callbacks' span of it) its
	// counts (2-17), the interfaces it answers (18-37: IUnknown, the four
	// handlers', two words each) and its own address (38-39), zeroed first
	static inline var HANDLER = 4 * 40;

	static function handler(method:Ptr):Ptr {
		var t:Ptr<Ptr> = LibC.malloc(32);
		t[0] = Callback.addr(hQuery);
		t[1] = Callback.addr(hAddRef);
		t[2] = Callback.addr(hRelease);
		t[3] = method;
		var o:Ptr<Ptr> = LibC.malloc(HANDLER);
		LibC.memset(cast o, 0, HANDLER);
		o[0] = cast t;
		var at = 4 * 18;
		for (g in ["00000000-0000-0000-c000-000000000046", "146c3c17-f12e-4e22-8c27-f894b9b79c69", "40cd37d4-c756-4b0c-8c6f-bddfeeb13b50",
			"e81d1b4e-11c5-42f8-9754-e7036c79f054", "c270f6b5-5c69-4290-9745-7a7f97169468"]) {
			LibC.memcpy((cast o : Ptr).add(at), guid(g), 16);
			at += 16;
		}
		Mem.setI64(cast o, 4 * 38, (cast o : Ptr).toI64());
		handlers.push(cast o);
		return cast o;
	}

	// (the handlers' methods: checked kernels over the handler's memory, C's
	// pointers spans of their size: hxmc's typed callbacks)
	@:hxmc.callback @:hxmc.kernel @:hxmc.len(self, 40) @:hxmc.len(iid, 4) @:hxmc.len(o, 1)
	static function hQuery(self:hxmc.Span<Int>, iid:hxmc.ReadOnlySpan<Int>, o:hxmc.Span<hxmc.I64>):Int {
		// (IUnknown or a handler's: the one object; anything else, IMarshal's, not)
		for (k in 0...5) {
			var at = 18 + 4 * k;
			if (iid[0] == self[at] && iid[1] == self[at + 1] && iid[2] == self[at + 2] && iid[3] == self[at + 3]) {
				o[0] = self.getI64(38);
				return 0;
			}
		}
		o[0] = 0;
		return 0x80004002;
	}

	@:hxmc.callback @:hxmc.kernel static function hAddRef(self:hxmc.I64):Int
		return 2;

	@:hxmc.callback @:hxmc.kernel static function hRelease(self:hxmc.I64):Int
		return 1;

	@:hxmc.callback @:hxmc.kernel @:hxmc.len(self, 40)
	static function onFocus(self:hxmc.Span<Int>, sender:hxmc.I64):Int {
		self[2] += 1;
		return 0;
	}

	@:hxmc.callback @:hxmc.kernel @:hxmc.len(self, 40)
	static function onProperty(self:hxmc.Span<Int>, sender:hxmc.I64, id:Int, value:hxmc.I64):Int {
		var k = switch id {
			case 30005: 1; // Name
			case 30086: 2; // ToggleState
			case 30070: 3; // ExpandCollapseState
			case 30079: 4; // IsSelected
			case 30047: 5; // RangeValue.Value
			case 30045: 6; // Value.Value
			case _: 15;
		}
		self[2 + k] += 1;
		return 0;
	}

	@:hxmc.callback @:hxmc.kernel @:hxmc.len(self, 40)
	static function onStructure(self:hxmc.Span<Int>, sender:hxmc.I64, change:Int, runtimeId:hxmc.I64):Int {
		self[9] += 1;
		return 0;
	}

	@:hxmc.callback @:hxmc.kernel @:hxmc.len(self, 40)
	static function onEvent(self:hxmc.Span<Int>, sender:hxmc.I64, id:Int):Int {
		var k = switch id {
			case 20014: 8; // Text_TextSelectionChanged
			case 20015: 9; // Text_TextChanged
			case 20012: 10; // SelectionItem_ElementSelected
			case _: 14;
		}
		self[2 + k] += 1;
		return 0;
	}

	// Wine's IUIAutomation (9.0): the tree and its properties; its patterns
	// are stubs (GetCurrentPattern, GetCurrentPatternAs), adding a focus
	// handler hangs: what it reads is checked, nothing acted on (the
	// probe's caller ends the window; the patterns are WinAccessTest's,
	// in process)
	static function wineFixture() {
		inline function el(t:Int, n:String):Ptr {
			var e = find(t, n);
			check('the fixture\'s $t $n', !e.isNull());
			return e;
		}
		// (what Wine reads: the tree's own properties, Value's IsReadOnly;
		// Grid's, GridItem's, Value's value, Toggle's, ExpandCollapse's,
		// RangeValue's and SelectionItem's properties read as nothing there)
		el(50028, "Mail");
		el(50029, "Lunch");
		var pear = el(50007, "Pear");
		check("an item's place in its set", prop(pear, 30152) == 2 && prop(pear, 30153) == 3, '${prop(pear, 30152)}/${prop(pear, 30153)}');
		var code = el(50004, "Code");
		check("a read-only field (Value's IsReadOnly)", prop(code, 30046) == true, '${prop(code, 30046)}');
		var name = el(50004, "Name");
		check("a field focusable, not read-only", prop(name, 30009) == true && prop(name, 30046) == false);
		el(50000, "More");
		el(50002, "Remember");
		el(50015, "Volume");
	}

	static function fixture() {
		if (Sys.getEnv("HELDER_UNDER_WINE") != null) return wineFixture();
		// the handlers, on the window's subtree (TreeScope_Subtree: 7)
		var top = elements[0].e;
		// (Wine's UI Automation hangs adding a focus handler: the events checked on Windows)
		var events = Sys.getEnv("HELDER_UNDER_WINE") == null;
		if (events) {
		var hrs = [Automation.AddFocusChangedEventHandler(uia, Ptr.nil(), handler(Callback.addr(onFocus)))];
		Arena.scoped(a -> {
			var ids:Ptr<Int32> = a.alloc(32);
			for (k => id in [30005, 30086, 30070, 30079, 30047, 30045])
				ids[k] = id;
			hrs.push(Automation.AddPropertyChangedEventHandlerNativeArray(uia, top, 7, Ptr.nil(), handler(Callback.addr(onProperty)), ids, 6));
		});
		hrs.push(Automation.AddStructureChangedEventHandler(uia, top, 7, Ptr.nil(), handler(Callback.addr(onStructure))));
		var h = handler(Callback.addr(onEvent));
		for (id in [20014, 20015, 20012])
			hrs.push(Automation.AddAutomationEventHandler(uia, id, top, 7, Ptr.nil(), h));
		check("the handlers added", [for (hr in hrs) if (hr != 0) hr].length == 0, [for (hr in hrs) StringTools.hex(hr)].join(","));
		}
		Sys.sleep(0.3);
		inline function el(t:Int, n:String):Ptr {
			var e = find(t, n);
			check('the fixture\'s $t $n', !e.isNull());
			return e;
		}
		// the table
		var grid = el(50028, "Mail");
		var g = grid.isNull() ? Ptr.nil() : pattern(grid, 10006, IID_Grid);
		var rows = 0, cols = 0;
		if (!g.isNull()) {
			GridPattern.get_CurrentRowCount(g, i32);
			rows = i32.value;
			GridPattern.get_CurrentColumnCount(g, i32);
			cols = i32.value;
		}
		check("a table's rows and columns", rows == 3 && cols == 2, '${rows}x$cols');
		if (!g.isNull()) {
			out.value = Ptr.nil();
			GridPattern.GetItem(g, 2, 1, out);
			var cell = out.value;
			check("a table's item at a row and column", !cell.isNull() && name(cell) == "Lunch", cell.isNull() ? "none" : name(cell));
			var gi = cell.isNull() ? Ptr.nil() : pattern(cell, 10007, IID_GridItem);
			var r = -1, c = -1;
			if (!gi.isNull()) {
				GridItemPattern.get_CurrentRow(gi, i32);
				r = i32.value;
				GridItemPattern.get_CurrentColumn(gi, i32);
				c = i32.value;
			}
			check("an item's row and column", r == 2 && c == 1, '$r,$c');
		}
		var pear = el(50007, "Pear");
		check("an item's place in its set", prop(pear, 30152) == 2 && prop(pear, 30153) == 3, '${prop(pear, 30152)}/${prop(pear, 30153)}');
		// a field: Value, Text
		var field = el(50004, "Name");
		var value = pattern(field, 10002, IID_Value);
		out.value = Ptr.nil();
		if (!value.isNull()) ValuePattern.get_CurrentValue(value, out);
		check("a field's value", !value.isNull() && bstr(out.value) == "Ada");
		var text = pattern(field, 10014, IID_Text);
		check("a field's Text pattern", !text.isNull());
		if (!text.isNull()) {
			out.value = Ptr.nil();
			TextPattern.get_DocumentRange(text, out);
			var doc = out.value;
			out.value = Ptr.nil();
			if (!doc.isNull()) TextRange.GetText(doc, -1, out);
			check("its document range's text", !doc.isNull() && bstr(out.value) == "Ada");
			if (!doc.isNull()) {
				// (to its start, one character on: then the selection 1...3)
				i32.value = 0;
				TextRange.MoveEndpointByUnit(doc, 0, 0, 1, i32);
				check("a range's start moved a character", i32.value == 1, '${i32.value}');
				check("selected through it", TextRange.Select(doc) == 0);
				Sys.sleep(0.5);
				out.value = Ptr.nil();
				TextPattern.GetSelection(text, out);
				var sel = out.value, len = 0, got = "";
				if (!sel.isNull()) {
					RangeArray.get_Length(sel, i32);
					len = i32.value;
					out.value = Ptr.nil();
					if (len > 0) RangeArray.GetElement(sel, 0, out);
					var r = out.value;
					out.value = Ptr.nil();
					if (!r.isNull()) TextRange.GetText(r, -1, out);
					got = bstr(out.value);
				}
				check("the selection after", len == 1 && got == "da", '$len "$got"');
				check("the field focused after", prop(field, 30008) == true);
			}
		}
		var code = el(50004, "Code");
		var cv = pattern(code, 10002, IID_Value);
		i32.value = 0;
		if (!cv.isNull()) ValuePattern.get_CurrentIsReadOnly(cv, i32);
		check("a read-only field's IsReadOnly", !cv.isNull() && i32.value != 0);
		// a disclosure expanded
		var more = el(50000, "More");
		var ec = pattern(more, 10005, IID_ExpandCollapse);
		i32.value = -1;
		if (!ec.isNull()) ExpandCollapsePattern.get_CurrentExpandCollapseState(ec, i32);
		check("a disclosure collapsed", !ec.isNull() && i32.value == 0, '${i32.value}');
		if (!ec.isNull()) check("expanded through it", ExpandCollapsePattern.Expand(ec) == 0);
		Sys.sleep(0.5);
		i32.value = -1;
		if (!ec.isNull()) ExpandCollapsePattern.get_CurrentExpandCollapseState(ec, i32);
		check("expanded after", i32.value == 1);
		// a row selected
		var bob = el(50029, "Bob Lunch");
		var si = pattern(bob, 10010, IID_SelectionItem);
		check("a row's SelectionItem", !si.isNull() && SelectionItemPattern.Select(si) == 0);
		Sys.sleep(0.5);
		i32.value = 0;
		if (!si.isNull()) SelectionItemPattern.get_CurrentIsSelected(si, i32);
		check("selected after", i32.value != 0);
		// a slider's value set
		var vol = el(50015, "Volume");
		var rv = pattern(vol, 10003, IID_RangeValue);
		check("a slider's value set", !rv.isNull() && RangeValuePattern.SetValue(rv, 0.8) == 0);
		Sys.sleep(0.3);
		d.value = 0;
		if (!rv.isNull()) RangeValuePattern.get_CurrentValue(rv, d);
		check("its value after", Math.abs(d.value - 0.8) < 1e-6, '${d.value}');
		// scrolled into view
		var last = el(50020, "Last");
		var sc = pattern(last, 10017, IID_ScrollItem);
		check("scrolled into view", !sc.isNull() && ScrollItemPattern.ScrollIntoView(sc) == 0);
		// a checkbox toggled
		var box = el(50002, "Remember");
		var tg = pattern(box, 10015, IID_Toggle);
		check("a checkbox toggled", !tg.isNull() && TogglePattern.Toggle(tg) == 0);
		Sys.sleep(0.5);
		i32.value = -1;
		if (!tg.isNull()) TogglePattern.get_CurrentToggleState(tg, i32);
		check("its state after", i32.value == 1);
		// the events (handlers on UI Automation's threads: given a moment)
		Sys.sleep(1);
		var saw = [for (k in 0...11) seen(k)];
		// (the focus's handler gets ours; the scoped ones, property, structure
		// and automation events under the window's element, get none on
		// CI's Windows though WinAccess raises them, each S_OK: AccessApp's
		// log; their counts printed, an open question)
		if (events) {
			check("events: the focus changed", saw[0] > 0, saw.join(","));
			Sys.println('WinAccessProbe: events seen (focus, name, toggle, expand, selected, range, value, structure, text selection, text, element selected): ' + saw.join(","));
		}
		if (events) Automation.RemoveAllEventHandlers(uia);
		// last: Save, which closes the window
		var save = el(50000, "Save");
		var inv = pattern(save, 10000, IID_Invoke);
		check("the button's Invoke", !inv.isNull() && InvokePattern.Invoke(inv) == 0);
	}
}

@:build(helder.os.win32.Com.build())
class Automation {
	@:slot(3) static function CompareElements(o:Ptr, a:Ptr, b:Ptr, same:Ptr<Int32>):Int;
	@:slot(6) static function ElementFromHandle(o:Ptr, hwnd:Ptr, out:Ptr<Ptr>):Int;
	@:slot(16) static function get_RawViewWalker(o:Ptr, out:Ptr<Ptr>):Int;
	@:slot(21) static function CreateTrueCondition(o:Ptr, out:Ptr<Ptr>):Int;
	@:slot(32) static function AddAutomationEventHandler(o:Ptr, id:Int, e:Ptr, scope:Int, cache:Ptr, h:Ptr):Int;
	@:slot(34) static function AddPropertyChangedEventHandlerNativeArray(o:Ptr, e:Ptr, scope:Int, cache:Ptr, h:Ptr, ids:Ptr<Int32>, n:Int):Int;
	@:slot(37) static function AddStructureChangedEventHandler(o:Ptr, e:Ptr, scope:Int, cache:Ptr, h:Ptr):Int;
	@:slot(39) static function AddFocusChangedEventHandler(o:Ptr, cache:Ptr, h:Ptr):Int;
	@:slot(41) static function RemoveAllEventHandlers(o:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
class Walker {
	@:slot(3) static function GetParentElement(o:Ptr, e:Ptr, out:Ptr<Ptr>):Int;
	@:slot(4) static function GetFirstChildElement(o:Ptr, e:Ptr, out:Ptr<Ptr>):Int;
	@:slot(6) static function GetNextSiblingElement(o:Ptr, e:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class ElementArray {
	@:slot(3) static function get_Length(o:Ptr, out:Ptr<Int32>):Int;
	@:slot(4) static function GetElement(o:Ptr, i:Int, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class Element {
	@:slot(6) static function FindAll(o:Ptr, scope:Int, condition:Ptr, out:Ptr<Ptr>):Int;
	@:slot(10) static function GetCurrentPropertyValue(o:Ptr, id:Int, v:Ptr):Int;
	@:slot(11) static function GetCurrentPropertyValueEx(o:Ptr, id:Int, ignoreDefault:Int, v:Ptr):Int;
	@:slot(16) static function GetCurrentPattern(o:Ptr, id:Int, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class Unknown {
	@:slot(0) static function QueryInterface(o:Ptr, iid:Ptr, out:Ptr<Ptr>):Int;
	@:slot(2) static function Release(o:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
class InvokePattern {
	@:slot(3) static function Invoke(o:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
class TogglePattern {
	@:slot(3) static function Toggle(o:Ptr):Int;
	@:slot(4) static function get_CurrentToggleState(o:Ptr, out:Ptr<Int32>):Int;
}

@:build(helder.os.win32.Com.build())
class ValuePattern {
	@:slot(3) static function SetValue(o:Ptr, s:Ptr):Int;
	@:slot(4) static function get_CurrentValue(o:Ptr, out:Ptr<Ptr>):Int;
	@:slot(5) static function get_CurrentIsReadOnly(o:Ptr, out:Ptr<Int32>):Int;
}

@:build(helder.os.win32.Com.build())
class RangeValuePattern {
	@:slot(3) static function SetValue(o:Ptr, v:Float):Int;
	@:slot(4) static function get_CurrentValue(o:Ptr, out:Ptr<Float>):Int;
}

@:build(helder.os.win32.Com.build())
class ExpandCollapsePattern {
	@:slot(3) static function Expand(o:Ptr):Int;
	@:slot(5) static function get_CurrentExpandCollapseState(o:Ptr, out:Ptr<Int32>):Int;
}

@:build(helder.os.win32.Com.build())
class SelectionItemPattern {
	@:slot(3) static function Select(o:Ptr):Int;
	@:slot(6) static function get_CurrentIsSelected(o:Ptr, out:Ptr<Int32>):Int;
}

@:build(helder.os.win32.Com.build())
class ScrollItemPattern {
	@:slot(3) static function ScrollIntoView(o:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
class GridPattern {
	@:slot(3) static function GetItem(o:Ptr, row:Int, col:Int, out:Ptr<Ptr>):Int;
	@:slot(4) static function get_CurrentRowCount(o:Ptr, out:Ptr<Int32>):Int;
	@:slot(5) static function get_CurrentColumnCount(o:Ptr, out:Ptr<Int32>):Int;
}

@:build(helder.os.win32.Com.build())
class GridItemPattern {
	@:slot(4) static function get_CurrentRow(o:Ptr, out:Ptr<Int32>):Int;
	@:slot(5) static function get_CurrentColumn(o:Ptr, out:Ptr<Int32>):Int;
}

@:build(helder.os.win32.Com.build())
class TextPattern {
	@:slot(5) static function GetSelection(o:Ptr, out:Ptr<Ptr>):Int;
	@:slot(7) static function get_DocumentRange(o:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class TextRange {
	@:slot(12) static function GetText(o:Ptr, max:Int, out:Ptr<Ptr>):Int;
	@:slot(14) static function MoveEndpointByUnit(o:Ptr, endpoint:Int, unit:Int, count:Int, moved:Ptr<Int32>):Int;
	@:slot(16) static function Select(o:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
class RangeArray {
	@:slot(3) static function get_Length(o:Ptr, out:Ptr<Int32>):Int;
	@:slot(4) static function GetElement(o:Ptr, i:Int, out:Ptr<Ptr>):Int;
}

@:hxmc.c @:hxmc.lib("ole32") extern class Ole32 {
	static function CoInitializeEx(reserved:Ptr, flags:Int):Int;
	static function CoCreateInstance(clsid:Ptr, outer:Ptr, context:Int, iid:Ptr, out:Ptr<Ptr>):Int;
}

@:hxmc.c @:hxmc.lib("oleaut32") extern class OleAut {
	static function SafeArrayGetElement(array:Ptr, index:Ptr<Int32>, out:Ptr):Int;
}

@:hxmc.c @:hxmc.lib("user32") extern class User {
	static function FindWindowW(cls:Ptr, title:Ptr):Ptr;
}
