package hxmc.ui.native.win32;

import hxmc.unsafe.*;

// The user32, gdi32 and comctl32 calls Win32Backend makes beside those of
// hxmc.os.win32 (whose structs it shares: RECT, MSG, WNDCLASSEXW).
@:hxmc.c @:hxmc.lib("user32") extern class W32 {
	static function CreateWindowExW(exStyle:Int, cls:Ptr, title:Ptr, style:Int, x:Int, y:Int, width:Int, height:Int, parent:Ptr, menu:Ptr,
		instance:Ptr, param:Ptr):Ptr;
	static function SetWindowPos(hwnd:Ptr, after:Ptr, x:Int, y:Int, cx:Int, cy:Int, flags:Int):Int;
	static function SendMessageW(hwnd:Ptr, msg:Int, wParam:Int64, lParam:Int64):Int64;
	static function SetWindowTextW(hwnd:Ptr, text:Ptr):Int;
	static function GetWindowTextW(hwnd:Ptr, buffer:Ptr, max:Int):Int;
	static function GetWindowTextLengthW(hwnd:Ptr):Int;
	static function EnableWindow(hwnd:Ptr, enable:Int):Int;
	static function GetDlgCtrlID(hwnd:Ptr):Int;
	static function DrawTextW(dc:Ptr, text:Ptr, count:Int, rect:Ptr<hxmc.os.win32.User32.RECT>, format:Int):Int;
	static function GetMessageW(msg:Ptr<hxmc.os.win32.User32.MSG>, hwnd:Ptr, min:Int, max:Int):Int;
	static function IsDialogMessageW(dialog:Ptr, msg:Ptr<hxmc.os.win32.User32.MSG>):Int;
	static function GetSysColorBrush(index:Int):Ptr;
	static function MapWindowPoints(from:Ptr, to:Ptr, points:Ptr, count:Int):Int;
	static function GetWindowRect(hwnd:Ptr, r:Ptr<hxmc.os.win32.User32.RECT>):Int;
	static function GetDpiForWindow(hwnd:Ptr):Int;
}

@:hxmc.c @:hxmc.fast @:hxmc.lib("gdi32") extern class Gdi {
	static function CreateFontW(height:Int, width:Int, escapement:Int, orientation:Int, weight:Int, italic:Int, underline:Int, strikeOut:Int,
		charSet:Int, outPrecision:Int, clipPrecision:Int, quality:Int, pitchAndFamily:Int, face:Ptr):Ptr;
	static function SelectObject(dc:Ptr, o:Ptr):Ptr;
	static function DeleteObject(o:Ptr):Int;
	static function SetTextColor(dc:Ptr, color:Int):Int;
	static function SetBkMode(dc:Ptr, mode:Int):Int;
}

@:hxmc.c @:hxmc.lib("comctl32") extern class ComCtl {
	// INITCOMMONCONTROLSEX: its size (8), the classes (ICC_BAR_CLASSES 4, ICC_PROGRESS_CLASS 0x20)
	static function InitCommonControlsEx(init:Ptr):Int;
}
