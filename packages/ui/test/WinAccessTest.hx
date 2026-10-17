import hxmc.esx.Markup;
import hxmc.ui.*;
import hxmc.ui.draw.UiWindow;
import hxmc.ui.draw.WinAccess;
import hxmc.ui.reactive.*;
import hxmc.ui.reactive.Reactive.*;
import hxmc.ui.widgets.Widgets.Button;
import hxmc.ui.widgets.Widgets.Checkbox;
import hxmc.ui.widgets.Widgets.Slider;
import hxmc.ui.widgets.Widgets.Field;
import hxmc.unsafe.*;

// hxmc.ui's accessibility on Windows (WinAccess; CI's Windows jobs): a
// window of widgets, its UI Automation providers called through their COM
// interfaces as UI Automation calls them (navigation, properties, bounds,
// the patterns: invoke, toggle, range value, value), and the window's root
// element asked of UI Automation itself (UiaNodeFromHandle: the provider
// WM_GETOBJECT gives).
//   WinAccessTest
class WinAccessTest implements Markup {
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
		var saved = 0, checked = signal(false), volume = signal(0.5), name = signal("");
		Render.render(<view padding={12} row-gap={8} align-items="start">
			<text>Settings</text>
			<Button tag="save" label="Save" onClick={() -> saved++}/>
			<Checkbox tag="remember" checked={checked} label="Remember"/>
			<Slider tag="volume" value={volume} step={0.1} label="Volume"/>
			<Field tag="name" value={name} placeholder="Name"/>
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
					check("the children: names and control types", shape.join(",") == "Settings:50020,Save:50000,Remember:50002,Volume:50015,Name:50004", shape.join(","));
					if (simples.length == 5) {
						check("focusable and enabled", prop(simples[1], 30009) == "true" && prop(simples[1], 30010) == "true");
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
					step = 2;
					w.close();
				case _:
			}
			w.ui.requestFrame();
		};
		UiWindow.run();
		Sys.println('WinAccessTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 && checks >= 12 ? 0 : 1);
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
