import hxmc.ui.*;
import hxmc.ui.draw.UiWindow;
import hxmc.ui.draw.WinAccess;
import hxmc.ui.draw.WinViews;
import hxmc.ui.native.win32.Win32;
import hxmc.view.*;
import hxmc.view.Reactive.*;
import hxmc.view.Flow.*;
import hxmc.ui.widgets.Widgets.Button;
import hxmc.ui.widgets.Widgets.Checkbox;
import hxmc.ui.widgets.Widgets.Slider;
import hxmc.ui.widgets.Widgets.Input;
import hxmc.ui.widgets.Widgets.ContextMenu;
import hxmc.ui.widgets.Widgets.Menubar;
import hxmc.unsafe.*;

// hxmc.ui's accessibility on Windows (WinAccess; CI's Windows jobs): a
// window of widgets, its UI Automation providers called through their COM
// interfaces as UI Automation calls them (navigation, properties, bounds,
// the patterns: invoke, toggle, range value, value), and the window's root
// element asked of UI Automation itself (UiaNodeFromHandle: the provider
// WM_GETOBJECT gives). Its field native (WinViews: an EDIT over the window):
// the value set through UI Automation in it, a character typed into it in
// the field's signal, Tab from it moving the window's focus on; centred,
// an EDIT made again ES_CENTER with the same text. A context menu native
// (a popup menu tracked: Down and Enter posted to it from a timer, as a
// user's keys; EndMenu later in case they are not taken), its item chosen.
// A menu bar native (the window's menu: its menus, the drawn bar hidden;
// an item's command posted to the window, the item chosen).
//   WinAccessTest
@:hxmc.c @:hxmc.lib("user32") extern class WinMenuTest {
	static function FindWindowW(cls:Ptr, name:Ptr):Ptr;
	static function SetTimer(hwnd:Ptr, id:Int64, ms:Int, proc:Ptr):Int64;
	static function KillTimer(hwnd:Ptr, id:Int64):Int;
	static function EndMenu():Int;
	static function GetMenu(hwnd:Ptr):Ptr;
	static function GetMenuItemCount(menu:Ptr):Int;
}

class WinAccessTest implements Markup {
	// (the menu's window, found by the timer)
	static var menuFound = false;

	// (the menu up: Down to its first item, Enter to choose it; the second timer ends it whatever happened)
	@:hxmc.callback static function menuKeys(hwnd:Ptr, msg:Int, id:Int64, time:Int) {
		WinMenuTest.KillTimer(hwnd, id);
		if (id == 2) {
			WinMenuTest.EndMenu();
			return;
		}
		var m = Arena.scopedValue(a -> WinMenuTest.FindWindowW(a.wstring("#32768"), Ptr.nil()));
		if (m.isNull()) return;
		menuFound = true;
		hxmc.os.win32.User32.User32.PostMessageW(m, 0x100, 0x28, 0);
		hxmc.os.win32.User32.User32.PostMessageW(m, 0x100, 0x0D, 0);
	}

	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('WinAccessTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
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

	static final FRAGMENT = guid("f7063da8-8359-439c-9297-bbc5299a7d87");
	static final SIMPLE = guid("d6dd68d1-86fd-4332-8666-9abedea2d24c");

	static function main() {
		var w = new UiWindow("WinAccessTest", 320, 240);
		var saved = 0, checked = signal(false), volume = signal(0.5), name = signal(""), menuOn = signal(false), menuChosen = "", barOn = signal(false), barChosen = "";
		Render.render(<view padding={12} row-gap={8} align-items="start">
			<text>Settings</text>
			<Button tag="save" label="Save" onClick={() -> saved++}/>
			<Checkbox tag="remember" checked={checked} label="Remember"/>
			<Slider tag="volume" value={volume} step={0.1} label="Volume"/>
			<Input tag="name" value={name} placeholder="Name"/>
			<view live="polite"><text>Ready</text></view>
			<Show when={menuOn}><ContextMenu tag="cm" items={[{label: "Copy", onSelect: () -> menuChosen += "copy"}, {label: "Paste", onSelect: () -> menuChosen += "paste"}]}>
				<view tag="cm-area" width={60} height={20}/>
			</ContextMenu></Show>
			<Show when={barOn}><Menubar tag="bar" label="App" menus={[
				{label: "File", items: [{label: "New", onSelect: () -> barChosen += "new"}, {label: "Open", onSelect: () -> barChosen += "open"}]},
				{label: "Edit", items: [{label: "Undo", shortcut: "Mod+Z", onSelect: () -> barChosen += "undo"}]}
			]}/></Show>
		</view>, w.root);
		var step = 0;
		var out:Ptr<Ptr> = LibC.malloc(8), v:Ptr = LibC.malloc(24), d:Ptr<Float> = LibC.malloc(32), i32:Ptr<Int32> = LibC.malloc(4);
		function qi(o:Ptr, iid:Ptr):Ptr {
			out.value = Ptr.nil();
			return Unknown.QueryInterface(o, iid, out) == 0 ? out.value : Ptr.nil();
		}
		function prop(simple:Ptr, id:Int):String {
			Simple.GetPropertyValue(simple, id, v);
			var vt:Int = (v : Ptr<UInt16>).value;
			return switch vt {
				case 8:
					var s:Ptr<UInt16> = (v.add(8) : Ptr<Ptr>).value, b = new StringBuf(), i = 0;
					while (s[i] != 0)
						b.addChar(s[i++]);
					b.toString();
				case 3: Std.string((v.add(8) : Ptr<Int32>).value);
				case 11: (v.add(8) : Ptr<Int16>).value != 0 ? "true" : "false";
				case _: "";
			}
		}
		var kids:Array<Ptr> = [];
		w.onFrame = () -> {
			switch step {
				case 0:
					var a:WinAccess = cast @:privateAccess w.winAccess;
					var root = a.rootProvider();
					check("the root's provider", !root.isNull());
					var f = qi(root, FRAGMENT);
					check("the root is a fragment", !f.isNull());
					out.value = Ptr.nil();
					Fragment.Navigate(f, 3, out);
					var k = out.value;
					while (!k.isNull()) {
						kids.push(k);
						out.value = Ptr.nil();
						Fragment.Navigate(k, 1, out);
						k = out.value;
					}
					var simples = [for (k in kids) qi(k, SIMPLE)];
					var shape = [for (s in simples) prop(s, 30005) + ":" + prop(s, 30003)];
					check("the children: names and control types", shape.join(",") == "Settings:50020,Save:50000,Remember:50002,Volume:50015,Name:50004,:50026", shape.join(","));
					if (simples.length == 6) {
						check("focusable and enabled", prop(simples[1], 30009) == "true" && prop(simples[1], 30010) == "true");
						check("a live region's LiveSetting (Polite)", prop(simples[5], 30135) == "1", prop(simples[5], 30135));
						Fragment.get_BoundingRectangle(kids[1], d);
						check("bounds in screen pixels", d[2] > 20 && d[3] > 10, '${d[2]}x${d[3]}');
						out.value = Ptr.nil();
						Fragment.Navigate(kids[1], 0, out);
						check("the parent: the root", !out.value.isNull() && qi(out.value, SIMPLE) == root);
						// patterns
						out.value = Ptr.nil();
						Simple.GetPatternProvider(simples[1], 10000, out);
						check("invoke", !out.value.isNull() && Invoke.Invoke(out.value) == 0 && saved == 1, '$saved');
						out.value = Ptr.nil();
						Simple.GetPatternProvider(simples[2], 10015, out);
						check("toggle", !out.value.isNull() && Toggle.Toggle(out.value) == 0 && checked.value);
						out.value = Ptr.nil();
						Simple.GetPatternProvider(simples[3], 10003, out);
						var range = out.value;
						check("a range's value and maximum", !range.isNull() && RangeValue.get_Value(range, d) == 0 && d[0] == 0.5 && RangeValue.get_Maximum(range, d) == 0 && d[0] == 1);
						out.value = Ptr.nil();
						Simple.GetPatternProvider(simples[4], 10002, out);
						var value = out.value;
						var set = Arena.scopedValue(m -> ValuePattern.SetValue(value, m.wstring("Ada")));
						check("a value set", !value.isNull() && set == 0 && name.value == "Ada", name.value);
						Simple.GetPatternProvider(simples[1], 10015, out);
						check("no pattern a node has not", out.value.isNull());
					}
					// UI Automation itself: the window's element, from our root
					var node:Ptr<Ptr> = LibC.malloc(8);
					var hr = UiaClient.UiaNodeFromHandle(w.window.surface.handle, node);
					check("UI Automation's element of the window", hr == 0 && !node.value.isNull(), StringTools.hex(hr));
					if (hr == 0) {
						UiaClient.UiaGetPropertyValue(node.value, 30003, v);
						check("its control type, ours (a pane)", (v : Ptr<UInt16>).value == 3 && (v.add(8) : Ptr<Int32>).value == 50033,
							'vt ${(v : Ptr<UInt16>).value} ${(v.add(8) : Ptr<Int32>).value}');
						UiaClient.UiaNodeRelease(node.value);
					}
					step = 1;
				case 1:
					if (kids.length == 5) {
						var t = qi(kids[2], SIMPLE);
						out.value = Ptr.nil();
						Simple.GetPatternProvider(t, 10015, out);
						check("the toggle state after it", !out.value.isNull() && Toggle.get_ToggleState(out.value, i32) == 0 && i32.value == 1);
					}
					var eds:Array<WinEditor> = @:privateAccess WinViews.editors;
					check("the field native: one EDIT", eds.length == 1, "" + eds.length);
					if (eds.length == 1) {
						var edit:Ptr = @:privateAccess eds[0].hwnd;
						check("the value set in the EDIT", @:privateAccess eds[0].text() == "Ada", @:privateAccess eds[0].text());
						W32.SendMessageW(edit, 0xB1, 3, 3);
						W32.SendMessageW(edit, 0x102, "x".code, 0);
						w.ui.setFocus(w.root.find("name"));
					}
					step = 2;
				case 2:
					check("typed into the EDIT, the field's signal follows", name.value == "Adax", name.value);
					var eds:Array<WinEditor> = @:privateAccess WinViews.editors;
					if (eds.length == 1) W32.SendMessageW(@:privateAccess eds[0].hwnd, 0x100, 9, 0);
					step = 3;
				case 3:
					check("Tab from the EDIT: the window's focus on", w.ui.focus != null && w.ui.focus.tag == "save", w.ui.focus == null ? "none" : w.ui.focus.tag);
					w.root.find("name").style.textAlign = Center;
					step = 4;
				case 4:
					var eds:Array<WinEditor> = @:privateAccess WinViews.editors;
					if (eds.length == 1) {
						var style = WinEdit.GetWindowLongPtrW(@:privateAccess eds[0].hwnd, -16).toInt(); // GWL_STYLE
						check("centred: the EDIT made again ES_CENTER", style & 3 == 1, "" + (style & 3));
						check("centred: its text kept", @:privateAccess eds[0].text() == "Adax", @:privateAccess eds[0].text());
					}
					menuOn.value = true;
					step = 5;
				case 5:
					var area = w.root.find("cm-area");
					if (area != null) {
						var hwnd = @:privateAccess (cast w.ui.platform : WinViews).hwnd;
						WinMenuTest.SetTimer(hwnd, 1, 300, Callback.addr(menuKeys));
						WinMenuTest.SetTimer(hwnd, 2, 3000, Callback.addr(menuKeys));
						w.ui.pointerDown(area.absX + 4, area.absY + 4, 3);
						w.ui.pointerUp(area.absX + 4, area.absY + 4, 3);
					}
					step = 6;
				case 6:
					// (the menu tracked in this frame's poll, chosen before this step)
					step = 7;
				case 7:
					check("a native context menu: its popup menu shown", menuFound);
					check("a native context menu: its first item chosen by the keys", menuChosen == "copy", menuChosen);
					barOn.value = true;
					step = 8;
				case 8:
					// (the window's menu bar: its two menus; Undo's command, its id plus one, posted)
					var hwnd = @:privateAccess (cast w.ui.platform : WinViews).hwnd;
					var bar = WinMenuTest.GetMenu(hwnd);
					check("a native menu bar: the window's menu", !bar.isNull());
					check("a native menu bar: its two menus", !bar.isNull() && WinMenuTest.GetMenuItemCount(bar) == 2);
					var drawn = w.root.find("bar");
					check("a native menu bar: the drawn one hidden", drawn != null && drawn.style.display == None);
					hxmc.os.win32.User32.User32.PostMessageW(hwnd, 0x111, 3, 0);
					step = 9;
				case 9:
					step = 10;
				case 10:
					check("a native menu bar: an item chosen by its command", barChosen == "undo", barChosen);
					step = 11;
					w.close();
				case _:
			}
			w.ui.requestFrame();
		};
		UiWindow.run();
		Sys.println('WinAccessTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 && checks >= 24 ? 0 : 1);
	}
}

@:build(hxmc.os.win32.Com.build())
class Unknown {
	@:slot(0) static function QueryInterface(o:Ptr, iid:Ptr, out:Ptr<Ptr>):Int;
}

@:build(hxmc.os.win32.Com.build())
class Simple {
	@:slot(4) static function GetPatternProvider(o:Ptr, id:Int, out:Ptr<Ptr>):Int;
	@:slot(5) static function GetPropertyValue(o:Ptr, id:Int, v:Ptr):Int;
}

@:build(hxmc.os.win32.Com.build())
class Fragment {
	@:slot(3) static function Navigate(o:Ptr, dir:Int, out:Ptr<Ptr>):Int;
	@:slot(5) static function get_BoundingRectangle(o:Ptr, r:Ptr<Float>):Int;
}

@:build(hxmc.os.win32.Com.build())
class Invoke {
	@:slot(3) static function Invoke(o:Ptr):Int;
}

@:build(hxmc.os.win32.Com.build())
class Toggle {
	@:slot(3) static function Toggle(o:Ptr):Int;
	@:slot(4) static function get_ToggleState(o:Ptr, out:Ptr<Int32>):Int;
}

@:build(hxmc.os.win32.Com.build())
class RangeValue {
	@:slot(4) static function get_Value(o:Ptr, out:Ptr<Float>):Int;
	@:slot(6) static function get_Maximum(o:Ptr, out:Ptr<Float>):Int;
}

@:build(hxmc.os.win32.Com.build())
class ValuePattern {
	@:slot(3) static function SetValue(o:Ptr, s:Ptr):Int;
}

@:hxmc.c @:hxmc.lib("uiautomationcore") extern class UiaClient {
	static function UiaNodeFromHandle(hwnd:Ptr, node:Ptr<Ptr>):Int;
	static function UiaGetPropertyValue(node:Ptr, id:Int, v:Ptr):Int;
	static function UiaNodeRelease(node:Ptr):Int;
}
