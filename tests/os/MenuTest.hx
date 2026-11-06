import helder.ui.Key;
import helder.ui.actions.Actions;
import helder.ui.actions.Keymap;
import helder.ui.draw.UiWindow;
import helder.ui.menu.DrawnMenu;
import helder.ui.menu.Menu;
import helder.ui.menu.Menus;
import hxmc.unsafe.*;

// helder.ui.menu in a real window (`bun run test window`): one model, its
// labels from the keymap and its states from the handlers, made into each
// platform's menus and read back through the platform's own calls:
//
// - macOS: NSApp's main menu (File and View after the application's menu,
//   About moved to the top of it, the window menu's own item in Window), an
//   item's title, key equivalent and its modifiers, checked and disabled
//   ones; a context menu's NSMenu;
// - Windows: the window's HMENU (GetMenu: File, View, Window), an item's
//   text with its accelerator after a tab ("Open…\tCtrl+O"), MF_CHECKED and
//   MF_GRAYED; a context menu's popup HMENU;
// - Linux: the drawn bar in the window, F10's menu and a context menu
//   driven by the keys, an action dispatched; each drawn, read back
//   (bin/os/menus-linux.png, menus-linux-context.png).
class MenuTest {
	static var failed = 0;

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println('MenuTest: ${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	static function main() {
		var out = Sys.args().length > 0 ? Sys.args()[0] : "bin/os";
		Keymap.mac = Mem.os() == 1;
		Menus.appName = "MenuTest";
		actions("menutest", TestAction);
		var k = Keymap.global;
		k.bind("secondary-o", Open).bind("f11", Full).bind("secondary-k secondary-t", Tile);
		var w = new UiWindow("MenuTest", 480, 320);
		w.background = helder.ui.Color.rgb(0x161618);
		w.ui.dark = true;
		var log = [], full = true;
		w.ui.root.on(TestAction, a -> {
			log.push(Std.string(a));
			true;
		}, a -> switch a {
			case Close: Disabled;
			case Full: full ? Checked : Unchecked;
			case _: Enabled;
		});
		var menus:Array<Menu> = [
			{label: "File", items: [Role(About), Item("Open…", Open), Separator, Role(Quit)]},
			{label: "View", items: [Item("Full Screen", Full), Item("Close", Close)]},
			{label: "Window", role: Window, items: [Role(Minimize), Item("Tile", Tile)]}
		];
		var bar = new MenuBar(w.ui, menus);
		w.ui.root.insert(bar.node, 0);
		var frames = 0;
		var pixels:Null<haxe.io.Bytes> = null;
		w.onFrame = () -> {
			frames++;
			if (frames == 3) {
				if (Mem.os() == 1) cocoa(w, bar) else if (Mem.os() == 2) win32(w, bar) else {
					check("linux: drawn, not the platform's", !bar.native && bar.node.style.display != None);
					check("linux: the bar's titles", [for (c in bar.node.children) c.children.length].length == 3);
					w.ui.keyDown(Key.F10, 0);
					var m = bar.current;
					check("linux: F10 opens File", m != null && m.labels().join(",") == "About MenuTest,Open…,-,Quit MenuTest", m == null ? "" : m.labels().join(","));
					w.ui.keyDown(Key.DOWN, 0);
					w.ui.keyDown(Key.RIGHT, 0);
					check("linux: Right moves to View", bar.current != null && bar.current.labels().join(",") == "Full Screen,Close");
					w.ui.requestFrame();
				}
			}
			if (Mem.os() == 0 && frames == 5) {
				pixels = haxe.io.Bytes.alloc(w.device.width * w.device.height * 4);
				w.capture = pixels;
				w.ui.requestFrame();
			}
			if (Mem.os() == 0 && frames == 6) {
				save(pixels, w, out + "/menus-linux.png");
				w.ui.keyDown(Key.ENTER, 0);
				check("linux: Enter dispatches Full Screen", log.join(",") == "Full", log.join(","));
				Menus.popup(w.ui, [Item("Open…", Open), Item("Tile", Tile), Separator, Item("Close", Close)], 200, 120);
				var c = DrawnMenu.current;
				w.ui.keyDown(Key.DOWN, 0);
				check("linux: a context menu, Down", c != null && c.highlighted == 1, c == null ? "" : "" + c.highlighted);
				pixels = haxe.io.Bytes.alloc(w.device.width * w.device.height * 4);
				w.capture = pixels;
				w.ui.requestFrame();
			}
			if (Mem.os() == 0 && frames == 7) {
				save(pixels, w, out + "/menus-linux-context.png");
				w.ui.keyDown(Key.ENTER, 0);
				check("linux: the context menu's choice", log.join(",") == "Full,Tile", log.join(","));
			}
			if (frames >= 8) {
				bar.dispose();
				w.close();
			}
			w.ui.requestFrame();
		};
		UiWindow.run();
		Sys.println('MenuTest: ${failed == 0 ? "ok" : failed + " failed"}');
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function save(pixels:Null<haxe.io.Bytes>, w:UiWindow, path:String) {
		if (pixels == null) return;
		try sys.FileSystem.createDirectory(haxe.io.Path.directory(path)) catch (_:Dynamic) {}
		sys.io.File.saveBytes(path, helder.image.PngEncoder.encode(pixels, w.device.width, w.device.height, false));
		Sys.println('MenuTest: $path');
	}

	static function win32(w:UiWindow, bar:MenuBar) {
		#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
		check("windows: the platform's bar", bar.native);
		var hwnd = w.window.surface.handle;
		var m = WinMenu.GetMenu(hwnd);
		check("windows: GetMenu: File, View, Window", !m.isNull() && WinMenu.GetMenuItemCount(m) == 3, m.isNull() ? "none" : "" + WinMenu.GetMenuItemCount(m));
		if (m.isNull()) return;
		var file = WinMenu.GetSubMenu(m, 0), view = WinMenu.GetSubMenu(m, 1);
		check("windows: the accelerator after a tab", text(file, 1) == "Open…\tCtrl+O", text(file, 1));
		check("windows: a role's label", text(file, 3) == "Quit MenuTest", text(file, 3));
		check("windows: checked", WinMenu.GetMenuState(view, 0, 0x400) & 8 != 0);
		check("windows: disabled (grayed)", WinMenu.GetMenuState(view, 1, 0x400) & 1 != 0);
		// (a context menu's HMENU, as WinViews tracks it)
		var a = [];
		var items = Menus.resolve(w.ui, [Item("Tile", Tile), Separator, Item("Open…", Open)], null, a);
		var p = WinMenu.CreatePopupMenu();
		@:privateAccess helder.ui.platform.WinViews.fill(p, items);
		check("windows: a context menu's items", WinMenu.GetMenuItemCount(p) == 3 && text(p, 2) == "Open…\tCtrl+O", text(p, 2));
		WinMenu.DestroyMenu(p);
		#end
	}

	#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
	static function text(m:Ptr, i:Int):String
		return Arena.scopedValue(a -> {
			var buf:Ptr<UInt16> = cast a.alloc(512);
			var n = WinMenu.GetMenuStringW(m, i, cast buf, 256, 0x400);
			var s = new StringBuf();
			for (j in 0...n)
				s.addChar((buf[j] : Int));
			s.toString();
		});
	#end

	static function cocoa(w:UiWindow, bar:MenuBar) {
		#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		var app = helder.os.objc.Msg.id(helder.os.objc.ObjC.cls("NSApplication"), helder.os.objc.ObjC.sel("sharedApplication"));
		var main = helder.os.objc.Msg.id(app, helder.os.objc.ObjC.sel("mainMenu"));
		check("cocoa: the platform's bar", bar.native);
		var n = helder.os.objc.Msg.i(main, helder.os.objc.ObjC.sel("numberOfItems")).toInt();
		check("cocoa: the application's menu, File, View, Window", n == 4, "" + n);
		function sub(i:Int):Ptr
			return helder.os.objc.Msg.id(helder.os.objc.Msg.idInt(main, helder.os.objc.ObjC.sel("itemAtIndex:"), i), helder.os.objc.ObjC.sel("submenu"));
		function item(m:Ptr, i:Int):Ptr
			return helder.os.objc.Msg.idInt(m, helder.os.objc.ObjC.sel("itemAtIndex:"), i);
		function title(it:Ptr):String
			return helder.os.objc.ObjC.string(helder.os.objc.Msg.id(it, helder.os.objc.ObjC.sel("title"))) ?? "";
		var own = sub(0), file = sub(1), view = sub(2);
		check("cocoa: About first in the application's menu", title(item(own, 0)) == "About MenuTest", title(item(own, 0)));
		var open = item(file, 0);
		check("cocoa: File's Open…, Quit left to the application's menu", title(open) == "Open…"
			&& helder.os.objc.Msg.i(file, helder.os.objc.ObjC.sel("numberOfItems")) == 1, title(open));
		check("cocoa: its key equivalent, Command",
			helder.os.objc.ObjC.string(helder.os.objc.Msg.id(open, helder.os.objc.ObjC.sel("keyEquivalent"))) == "o"
			&& helder.os.objc.Msg.i(open, helder.os.objc.ObjC.sel("keyEquivalentModifierMask")) == 1 << 20);
		check("cocoa: checked", helder.os.objc.Msg.i(item(view, 0), helder.os.objc.ObjC.sel("state")) == 1);
		check("cocoa: disabled", !helder.os.objc.Msg.b(item(view, 1), helder.os.objc.ObjC.sel("isEnabled")));
		var windows = helder.os.objc.Msg.id(app, helder.os.objc.ObjC.sel("windowsMenu"));
		var count = helder.os.objc.Msg.i(windows, helder.os.objc.ObjC.sel("numberOfItems")).toInt();
		var found = false;
		for (i in 0...count)
			if (title(item(windows, i)) == "Tile") found = true;
		check("cocoa: the window menu's own item in Window", found);
		// (a context menu's NSMenu, as MacViews pops it up)
		var a = [];
		var items = Menus.resolve(w.ui, [Item("Tile", Tile), Separator, Item("Open…", Open)], null, a);
		var m = @:privateAccess helder.ui.platform.MacViews.nsMenu(items);
		check("cocoa: a context menu's items", helder.os.objc.Msg.i(m, helder.os.objc.ObjC.sel("numberOfItems")) == 3 && title(item(m, 2)) == "Open…");
		helder.os.objc.ObjC.release(m);
		#end
	}
}

enum TestAction {
	Open;
	Full;
	Close;
	Tile;
}

#if (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64")
@:hxmc.c @:hxmc.lib("user32") extern class WinMenu {
	static function GetMenu(hwnd:Ptr):Ptr;
	static function GetSubMenu(menu:Ptr, pos:Int):Ptr;
	static function GetMenuItemCount(menu:Ptr):Int;
	static function GetMenuStringW(menu:Ptr, item:Int, buf:Ptr, max:Int, flags:Int):Int;
	static function GetMenuState(menu:Ptr, item:Int, flags:Int):Int;
	static function CreatePopupMenu():Ptr;
	static function DestroyMenu(menu:Ptr):Int;
}
#end
