package helder.ui.platform;

import hxmc.unsafe.*;

// The user32 and gdi32 calls WinViews makes beside those of
// helder.os.win32 (whose structs it shares).
@:hxmc.c @:hxmc.lib("user32") extern class W32 {
	static function CreateWindowExW(exStyle:Int, cls:Ptr, title:Ptr, style:Int, x:Int, y:Int, width:Int, height:Int, parent:Ptr, menu:Ptr,
		instance:Ptr, param:Ptr):Ptr;
	static function SetWindowPos(hwnd:Ptr, after:Ptr, x:Int, y:Int, cx:Int, cy:Int, flags:Int):Int;
	static function SendMessageW(hwnd:Ptr, msg:Int, wParam:Int64, lParam:Int64):Int64;
	static function SetWindowTextW(hwnd:Ptr, text:Ptr):Int;
	static function GetWindowTextW(hwnd:Ptr, buffer:Ptr, max:Int):Int;
	static function GetWindowTextLengthW(hwnd:Ptr):Int;
}

@:hxmc.c @:hxmc.fast @:hxmc.lib("gdi32") extern class Gdi {
	static function CreateFontW(height:Int, width:Int, escapement:Int, orientation:Int, weight:Int, italic:Int, underline:Int, strikeOut:Int,
		charSet:Int, outPrecision:Int, clipPrecision:Int, quality:Int, pitchAndFamily:Int, face:Ptr):Ptr;
	static function DeleteObject(o:Ptr):Int;
	static function SetTextColor(dc:Ptr, color:Int):Int;
}

