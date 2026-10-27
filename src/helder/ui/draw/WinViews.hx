package helder.ui.draw;

import helder.os.win32.User32;
import helder.ui.*;
import helder.ui.native.win32.Win32;
import hxmc.unsafe.*;

// Windows' own views over a window (Ui.platform there): text editors, EDIT
// controls made children of the window, placed where their nodes are laid
// out (window pixels: the layout's times the window's scale). Each is
// subclassed: the keys it leaves to the program (Tab, Escape; Enter, Up
// and Down on one line) taken before it and queued, its focus queued, and
// an edit seen after any message by its modified flag (EM_GETMODIFY); a
// frame asked of the window, whose next layout polls them. The window
// answers WM_CTLCOLOREDIT with each one's text colour and the background
// behind it (an EDIT cannot be transparent). Its alignment a style an EDIT
// takes when made: one made again when the node's changes. Menus: a popup
// menu (CreatePopupMenu, a submenu's MF_POPUP) tracked at the next poll
// (TrackPopupMenuEx: its own loop until chosen or dismissed), its command
// an item's id plus one. The menu bar: the window's (CreateMenu, SetMenu),
// its commands the window's WM_COMMAND, an item's id plus one again; the
// client area the bar leaves, the window's resize.
@:hxmc.c @:hxmc.lib("user32") extern class WinEdit {
	static function SetWindowLongPtrW(hwnd:Ptr, index:Int, value:Ptr):Ptr;
	static function GetWindowLongPtrW(hwnd:Ptr, index:Int):Int64;
	static function CallWindowProcW(proc:Ptr, hwnd:Ptr, message:Int, wParam:Int64, lParam:Int64):Int64;
	static function SetFocus(hwnd:Ptr):Ptr;
	static function GetFocus():Ptr;
	static function InvalidateRect(hwnd:Ptr, rect:Ptr, erase:Int):Int;
	static function CreatePopupMenu():Ptr;
	static function AppendMenuW(menu:Ptr, flags:Int, id:Int64, item:Ptr):Int;
	static function TrackPopupMenuEx(menu:Ptr, flags:Int, x:Int, y:Int, hwnd:Ptr, params:Ptr):Int;
	static function DestroyMenu(menu:Ptr):Int;
	static function CreateMenu():Ptr;
	static function SetMenu(hwnd:Ptr, menu:Ptr):Int;
	static function DrawMenuBar(hwnd:Ptr):Int;
}

@:hxmc.c @:hxmc.lib("gdi32") extern class WinEditGdi {
	static function CreateSolidBrush(color:Int):Ptr;
	static function SetBkColor(dc:Ptr, color:Int):Int;
}

class WinViews implements PlatformViews {
	static final editors:Array<WinEditor> = [];

	final hwnd:Ptr;
	final ui:Ui;
	// (the window's pixels per layout pixel)
	final scale:Void->Float;
	final queue:Array<{e:WinEditor, kind:Int, key:Int, mods:Int}> = [];
	// (a menu asked for: shown at the next poll)
	var pending:Null<{items:Array<PlatformMenuItem>, x:Float, y:Float, chosen:Int->Void}> = null;

	public function new(hwnd:Ptr, ui:Ui, scale:Void->Float) {
		this.hwnd = hwnd;
		this.ui = ui;
		this.scale = scale;
		helder.os.win32.Win32Window.editColors = colors;
	}

	public function editor(multiline:Bool):Null<PlatformEditor> {
		var h = create(multiline, 0);
		if (h.isNull()) return null;
		var e = new WinEditor(this, h, multiline);
		@:privateAccess e.old = WinEdit.SetWindowLongPtrW(h, -4, Callback.addr(editProc));
		editors.push(e);
		return e;
	}

	// (an EDIT, hidden; align: ES_LEFT 0, ES_CENTER 1, ES_RIGHT 2)
	@:allow(helder.ui.draw.WinEditor) function create(multiline:Bool, align:Int):Ptr {
		// WS_CHILD | WS_CLIPSIBLINGS, ES_AUTOHSCROLL; several lines: ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN
		var style = 0x40000000 | 0x04000000 | 0x80 | align | (multiline ? 0x4 | 0x40 | 0x1000 : 0);
		return Arena.scopedValue(a -> W32.CreateWindowExW(0, a.wstring("EDIT"), Ptr.nil(), style, 0, 0, 10, 10, hwnd, Ptr.nil(), Ptr.nil(), Ptr.nil()));
	}

	@:allow(helder.ui.draw.WinEditor) function push(e:WinEditor, kind:Int, key = 0, mods = 0) {
		queue.push({e: e, kind: kind, key: key, mods: mods});
		ui.requestFrame();
	}

	// (the menu bar set, its chooser: the window's commands)
	var bar = Ptr.nil();
	var barChosen:Null<Int->Void> = null;

	public function menuBar(menus:Array<PlatformMenuItem>, chosen:Int->Void):Bool {
		var old = bar;
		bar = Ptr.nil();
		barChosen = null;
		if (menus.length > 0) {
			bar = WinEdit.CreateMenu();
			for (m in menus) {
				var sub = WinEdit.CreatePopupMenu();
				fill(sub, m.items == null ? [] : m.items);
				Arena.scoped(a -> WinEdit.AppendMenuW(bar, 0x10, sub.toI64(), a.wstring(StringTools.replace(m.label, "&", "&&"))));
			}
			barChosen = chosen;
			helder.os.win32.Win32Window.command = command;
		}
		WinEdit.SetMenu(hwnd, bar);
		WinEdit.DrawMenuBar(hwnd);
		if (!old.isNull()) WinEdit.DestroyMenu(old);
		return true;
	}

	// (WM_COMMAND from the menu bar: its item chosen, in the program's turn)
	function command(window:Ptr, id:Int):Bool {
		if (window != hwnd || barChosen == null || id <= 0) return false;
		var chosen = barChosen;
		ui.requestFrame();
		chosen(id - 1);
		return true;
	}

	// (hxmc dev's host, at a hand-over: the editors, subclassed by this
	// build's code, and the menu bar gone with it; the next build makes its own)
	public function dispose() {
		for (e in editors.copy())
			if (@:privateAccess e.views == this) e.dispose();
		pending = null;
		if (!bar.isNull()) {
			WinEdit.SetMenu(hwnd, Ptr.nil());
			WinEdit.DestroyMenu(bar);
			bar = Ptr.nil();
		}
		barChosen = null;
	}

	public function menu(items:Array<PlatformMenuItem>, x:Float, y:Float, chosen:Int->Void):Bool {
		if (pending != null) pending.chosen(-1);
		pending = {items: items, x: x, y: y, chosen: chosen};
		ui.requestFrame();
		return true;
	}

	// (the menu's items appended: MF_STRING, MF_GRAYED 1, MF_CHECKED 8,
	// MF_POPUP 0x10, MF_SEPARATOR 0x800; "&" doubled, not a mnemonic; the
	// shortcut after a tab, at the right)
	static function fill(m:Ptr, items:Array<PlatformMenuItem>) {
		for (it in items) {
			if (it.separator == true) {
				WinEdit.AppendMenuW(m, 0x800, 0, Ptr.nil());
				continue;
			}
			var text = StringTools.replace(it.label, "&", "&&") + (it.shortcut == null ? "" : "\t" + it.shortcut);
			var flags = (it.disabled == true ? 1 : 0) | (it.checked == true ? 8 : 0);
			if (it.items != null) {
				var sub = WinEdit.CreatePopupMenu();
				fill(sub, it.items);
				Arena.scoped(a -> WinEdit.AppendMenuW(m, flags | 0x10, sub.toI64(), a.wstring(text)));
			} else Arena.scoped(a -> WinEdit.AppendMenuW(m, flags, it.id + 1, a.wstring(text)));
		}
	}

	public function poll() {
		if (pending != null) {
			var p = pending;
			pending = null;
			var m = WinEdit.CreatePopupMenu();
			fill(m, p.items);
			var k = scale();
			var at = Arena.scopedValue(a -> {
				var pt = a.make(helder.os.win32.User32.POINT);
				pt.value.x = Math.round(p.x * k);
				pt.value.y = Math.round(p.y * k);
				User32.ClientToScreen(hwnd, pt);
				[pt.value.x, pt.value.y];
			});
			// TPM_RETURNCMD | TPM_RIGHTBUTTON
			var r = WinEdit.TrackPopupMenuEx(m, 0x100 | 0x2, at[0], at[1], hwnd, Ptr.nil());
			WinEdit.DestroyMenu(m);
			p.chosen(r > 0 ? r - 1 : -1);
		}
		while (queue.length > 0) {
			var q = queue.shift(), e = q.e, l = e.listener;
			if (l == null) continue;
			switch q.kind {
				case 1:
					var sel:Int = W32.SendMessageW(@:privateAccess e.hwnd, 0xB0, 0, 0).toInt(); // EM_GETSEL
					l.editorEdited(@:privateAccess e.text(), sel & 0xFFFF, (sel >>> 16) & 0xFFFF);
				case 2:
					l.editorFocused(true);
				case 3:
					l.editorFocused(false);
				case 4:
					l.editorKey(q.key, q.mods);
				case _:
			}
		}
	}

	// (WM_CTLCOLOREDIT: an editor's colours, its brush)
	static function colors(dc:Ptr, child:Ptr):Int64 {
		for (e in editors)
			if (@:privateAccess e.hwnd == child) return @:privateAccess e.paint(dc);
		return 0;
	}

	@:hxmc.callback static function editProc(hwnd:Ptr, message:Int, wParam:Int64, lParam:Int64):Int64 {
		var e:Null<WinEditor> = null;
		for (x in editors)
			if (@:privateAccess x.hwnd == hwnd) e = x;
		if (e == null) return User32.DefWindowProcW(hwnd, message, wParam, lParam);
		return @:privateAccess e.message(message, wParam, lParam);
	}
}

class WinEditor implements PlatformEditor {
	final views:WinViews;
	var hwnd:Ptr;
	final multiline:Bool;
	var old = Ptr.nil();
	var align = 0;
	// (where it was last placed: kept when it is made again)
	var placed = [0.0, 0.0, 0.0, 0.0];
	var shown = false;
	var font = Ptr.nil();
	var brush = Ptr.nil();
	var color = 0;
	var background = 0xFFFFFF;
	var focusing = false;

	public var listener(default, null):Null<PlatformEditorListener> = null;

	public function new(views:WinViews, hwnd:Ptr, multiline:Bool) {
		this.views = views;
		this.hwnd = hwnd;
		this.multiline = multiline;
	}

	public function listen(l:PlatformEditorListener)
		listener = l;

	function message(message:Int, wParam:Int64, lParam:Int64):Int64 {
		switch message {
			case 0x0100: // WM_KEYDOWN: the keys left to the program
				var key = switch wParam.toInt() {
					case 0x09: Key.TAB;
					case 0x1B: Key.ESCAPE;
					case 0x0D if (!multiline): Key.ENTER;
					case 0x26 if (!multiline): Key.UP;
					case 0x28 if (!multiline): Key.DOWN;
					case _: 0;
				}
				if (key != 0) {
					var mods = (User32.GetKeyState(0x10) < 0 ? Key.MOD_SHIFT : 0) | (User32.GetKeyState(0x11) < 0 ? Key.MOD_CONTROL : 0)
						| (User32.GetKeyState(0x12) < 0 ? Key.MOD_ALT : 0);
					@:privateAccess views.push(this, 4, key, mods);
					return 0;
				}
			case 0x0102: // WM_CHAR: theirs not typed (nor beeped at)
				var c = wParam.toInt();
				if (c == 9 || c == 27 || (c == 13 && !multiline)) return 0;
			case 0x0007: // WM_SETFOCUS
				if (!focusing) @:privateAccess views.push(this, 2);
			case 0x0008: // WM_KILLFOCUS
				if (!focusing) @:privateAccess views.push(this, 3);
			case _:
		}
		var r = WinEdit.CallWindowProcW(old, hwnd, message, wParam, lParam);
		// (an edit: the modified flag, cleared once seen)
		if (message != 0xB8 && message != 0xB9 && message != 0x0082 && W32.SendMessageW(hwnd, 0xB8, 0, 0).toInt() != 0) {
			W32.SendMessageW(hwnd, 0xB9, 0, 0);
			@:privateAccess views.push(this, 1);
		}
		return r;
	}

	function text():String {
		var n = W32.GetWindowTextLengthW(hwnd);
		return Arena.scopedValue(a -> {
			var p:Ptr<UInt16> = a.alloc(2 * n + 2);
			W32.GetWindowTextW(hwnd, p, n + 1);
			var b = new StringBuf(), i = 0;
			while (i < n) {
				var c:Int = p[i++];
				// (a surrogate pair: one code point)
				if (c >= 0xD800 && c < 0xDC00 && i < n) c = 0x10000 + ((c - 0xD800) << 10) + (p[i++] - 0xDC00);
				b.addChar(c);
			}
			b.toString();
		});
	}

	function paint(dc:Ptr):Int64 {
		Gdi.SetTextColor(dc, color);
		WinEditGdi.SetBkColor(dc, background);
		return brush.toI64();
	}

	static function colorref(c:Color):Int
		return c.r | (c.g << 8) | (c.b << 16);

	public function setText(text:String, start:Int, end:Int) {
		Arena.scoped(a -> W32.SetWindowTextW(hwnd, a.wstring(text)));
		W32.SendMessageW(hwnd, 0xB1, start, end); // EM_SETSEL
		W32.SendMessageW(hwnd, 0xB9, 0, 0);
	}

	public function place(x:Float, y:Float, width:Float, height:Float, shown:Bool) {
		placed = [x, y, width, height];
		this.shown = shown;
		var k = @:privateAccess views.scale();
		var x0 = Math.round(x * k), y0 = Math.round(y * k);
		// SWP_NOZORDER | SWP_NOACTIVATE, and SWP_SHOWWINDOW or SWP_HIDEWINDOW
		W32.SetWindowPos(hwnd, Ptr.nil(), x0, y0, Math.round((x + width) * k) - x0, Math.round((y + height) * k) - y0, 0x4 | 0x10 | (shown ? 0x40 : 0x80));
	}

	public function setStyle(font:Font, color:Color, background:Color, placeholder:String, placeholderColor:Color, align:TextAlign, secret:Bool) {
		var al = align == Center ? 1 : align == Right ? 2 : 0;
		if (al != this.align) remake(al);
		var k = @:privateAccess views.scale();
		var f = Arena.scopedValue(a -> Gdi.CreateFontW(-Math.round(font.size * k), 0, 0, 0, font.weight, font.italic ? 1 : 0, 0, 0, 1, 0, 0, 5, 0,
			a.wstring(font.family)));
		W32.SendMessageW(hwnd, 0x30, f.toI64(), 1); // WM_SETFONT
		if (!this.font.isNull()) Gdi.DeleteObject(this.font);
		this.font = f;
		this.color = colorref(color);
		this.background = colorref(background);
		if (!brush.isNull()) Gdi.DeleteObject(brush);
		brush = WinEditGdi.CreateSolidBrush(this.background);
		// (EM_SETCUEBANNER: shown by comctl32 6's edits; EM_SETPASSWORDCHAR: a bullet, or none)
		Arena.scoped(a -> W32.SendMessageW(hwnd, 0x1501, 1, a.wstring(placeholder).toI64()));
		if (!multiline) W32.SendMessageW(hwnd, 0xCC, secret ? 0x25CF : 0, 0);
		WinEdit.InvalidateRect(hwnd, Ptr.nil(), 1);
	}

	// (made again with another alignment: its text, selection, place and
	// focus kept; the new one subclassed once the old one, still this
	// editor's for its last messages, is destroyed)
	function remake(align:Int) {
		var h = views.create(multiline, align);
		if (h.isNull()) return;
		var text = text(), sel:Int = W32.SendMessageW(hwnd, 0xB0, 0, 0).toInt(); // EM_GETSEL
		var had = WinEdit.GetFocus() == hwnd;
		focusing = true;
		if (!font.isNull()) W32.SendMessageW(h, 0x30, font.toI64(), 0); // WM_SETFONT
		Arena.scoped(a -> W32.SetWindowTextW(h, a.wstring(text)));
		W32.SendMessageW(h, 0xB1, sel & 0xFFFF, (sel >>> 16) & 0xFFFF); // EM_SETSEL
		if (had) WinEdit.SetFocus(h);
		User32.DestroyWindow(hwnd);
		hwnd = h;
		old = WinEdit.SetWindowLongPtrW(h, -4, Callback.addr(@:privateAccess WinViews.editProc));
		this.align = align;
		place(placed[0], placed[1], placed[2], placed[3], shown);
		focusing = false;
	}

	public function focus(on:Bool) {
		focusing = true;
		if (on) WinEdit.SetFocus(hwnd) else if (WinEdit.GetFocus() == hwnd) WinEdit.SetFocus(@:privateAccess views.hwnd);
		focusing = false;
	}

	public function dispose() {
		@:privateAccess WinViews.editors.remove(this);
		if (WinEdit.GetFocus() == hwnd) WinEdit.SetFocus(@:privateAccess views.hwnd);
		User32.DestroyWindow(hwnd);
		if (!font.isNull()) Gdi.DeleteObject(font);
		if (!brush.isNull()) Gdi.DeleteObject(brush);
		listener = null;
	}
}
