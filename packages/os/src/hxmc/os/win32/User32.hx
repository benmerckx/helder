package hxmc.os.win32;

import hxmc.unsafe.*;

// user32 (and kernel32, gdi32: below): the calls a window needs. Handles
// (HWND, HINSTANCE, HCURSOR, HDC) are Ptr, WPARAM and LPARAM Int64, strings
// UTF-16 (Arena.wstring). Calls run in a safe region: most of them call the
// window procedure (a GC callback) before they return.
@:hxmc.c @:hxmc.lib("user32") extern class User32 {
	static function RegisterClassExW(wc:Ptr<WNDCLASSEXW>):UInt16;
	static function UnregisterClassW(name:Ptr, instance:Ptr):Int;
	static function CreateWindowExW(exStyle:Int, cls:Ptr, title:Ptr, style:Int, x:Int, y:Int, width:Int, height:Int, parent:Ptr, menu:Ptr,
		instance:Ptr, param:Ptr):Ptr;
	static function DestroyWindow(hwnd:Ptr):Int;
	static function ShowWindow(hwnd:Ptr, cmd:Int):Int;
	static function DefWindowProcW(hwnd:Ptr, msg:Int, wParam:Int64, lParam:Int64):Int64;
	static function PeekMessageW(msg:Ptr<MSG>, hwnd:Ptr, min:Int, max:Int, remove:Int):Int;
	static function TranslateMessage(msg:Ptr<MSG>):Int;
	static function DispatchMessageW(msg:Ptr<MSG>):Int64;
	static function PostMessageW(hwnd:Ptr, msg:Int, wParam:Int64, lParam:Int64):Int;
	static function PostQuitMessage(code:Int):Void;
	static function GetClientRect(hwnd:Ptr, r:Ptr<RECT>):Int;
	static function AdjustWindowRectEx(r:Ptr<RECT>, style:Int, menu:Int, exStyle:Int):Int;
	static function ScreenToClient(hwnd:Ptr, p:Ptr<POINT>):Int;
	static function GetKeyState(key:Int):Int;
	static function ClientToScreen(hwnd:Ptr, p:Ptr<POINT>):Int;
	static function LoadCursorW(instance:Ptr, name:Ptr):Ptr;
	static function SetCursor(cursor:Ptr):Ptr;
	// the clipboard (CF_UNICODETEXT: 13)
	static function OpenClipboard(hwnd:Ptr):Int;
	static function CloseClipboard():Int;
	static function EmptyClipboard():Int;
	static function SetClipboardData(format:Int, data:Ptr):Ptr;
	static function GetClipboardData(format:Int):Ptr;
	static function MsgWaitForMultipleObjects(count:Int, handles:Ptr, waitAll:Int, ms:Int, wakeMask:Int):Int;
	static function SetWindowTextW(hwnd:Ptr, text:Ptr):Int;
	// Windows 10 1607 and later (pixels, not points)
	static function SetProcessDpiAwarenessContext(context:Ptr):Int;
	static function GetDpiForWindow(hwnd:Ptr):Int;
	static function GetDpiForSystem():Int;
	static function GetDC(hwnd:Ptr):Ptr;
	static function ReleaseDC(hwnd:Ptr, dc:Ptr):Int;
	static function PrintWindow(hwnd:Ptr, dc:Ptr, flags:Int):Int;
}

// the IME's windows: where they show (COMPOSITIONFORM, CANDIDATEFORM: raw Int32s)
@:hxmc.c @:hxmc.lib("imm32") extern class Imm32 {
	static function ImmGetContext(hwnd:Ptr):Ptr;
	static function ImmReleaseContext(hwnd:Ptr, imc:Ptr):Int;
	static function ImmSetCompositionWindow(imc:Ptr, form:Ptr<Int32>):Int;
	static function ImmSetCandidateWindow(imc:Ptr, form:Ptr<Int32>):Int;
}

@:hxmc.c @:hxmc.fast @:hxmc.lib("kernel32") extern class Kernel32 {
	static function GetModuleHandleW(name:Ptr):Ptr;
	static function GetLastError():Int;
	// movable global memory (the clipboard's)
	static function GlobalAlloc(flags:Int, bytes:Int64):Ptr;
	static function GlobalLock(mem:Ptr):Ptr;
	static function GlobalUnlock(mem:Ptr):Int;
	static function GlobalFree(mem:Ptr):Ptr;
	static function GlobalSize(mem:Ptr):Int64;
}

// a window's pixels (GfxTest's capture)
@:hxmc.c @:hxmc.fast @:hxmc.lib("gdi32") extern class Gdi32 {
	static function CreateCompatibleDC(dc:Ptr):Ptr;
	static function DeleteDC(dc:Ptr):Int;
	static function CreateDIBSection(dc:Ptr, info:Ptr<BITMAPINFOHEADER>, usage:Int, bits:Ptr<Ptr>, section:Ptr, offset:Int):Ptr;
	static function SelectObject(dc:Ptr, o:Ptr):Ptr;
	static function DeleteObject(o:Ptr):Int;
	static function BitBlt(dst:Ptr, x:Int, y:Int, w:Int, h:Int, src:Ptr, sx:Int, sy:Int, rop:Int):Int;
	static function GdiFlush():Int;
}

class WM {
	// messages
	public static inline var DESTROY = 0x0002;
	public static inline var SIZE = 0x0005;
	public static inline var CLOSE = 0x0010;
	public static inline var KEYDOWN = 0x0100;
	public static inline var KEYUP = 0x0101;
	public static inline var SYSKEYDOWN = 0x0104;
	public static inline var SYSKEYUP = 0x0105;
	public static inline var CHAR = 0x0102;
	public static inline var MOUSEMOVE = 0x0200;
	public static inline var LBUTTONDOWN = 0x0201;
	public static inline var LBUTTONUP = 0x0202;
	public static inline var RBUTTONDOWN = 0x0204;
	public static inline var RBUTTONUP = 0x0205;
	public static inline var MBUTTONDOWN = 0x0207;
	public static inline var MBUTTONUP = 0x0208;
	public static inline var MOUSEWHEEL = 0x020A;
	// window and class styles, ShowWindow, PeekMessage
	public static inline var WS_OVERLAPPEDWINDOW = 0x00CF0000;
	public static inline var CW_USEDEFAULT = 0x80000000;
	public static inline var CS_HREDRAW = 0x0002;
	public static inline var CS_VREDRAW = 0x0001;
	public static inline var CS_OWNDC = 0x0020;
	public static inline var SW_SHOW = 5;
	public static inline var PM_REMOVE = 1;
	public static inline var IDC_ARROW = 32512;
	public static inline var SETCURSOR = 0x0020;
	public static inline var GETOBJECT = 0x003D;
	public static inline var PAINT = 0x000F;
	public static inline var QS_ALLINPUT = 0x04FF;
	public static inline var HTCLIENT = 1;
	public static inline var PW_CLIENTONLY = 1;
	public static inline var PW_RENDERFULLCONTENT = 2;
	public static inline var SRCCOPY = 0x00CC0020;
	// DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
	public static inline var DPI_PER_MONITOR_AWARE_V2 = -4;
}

@:hxmc.struct @:publicFields class WNDCLASSEXW {
	var cbSize:UInt32;
	var style:UInt32;
	var lpfnWndProc:Ptr;
	var cbClsExtra:Int32;
	var cbWndExtra:Int32;
	var hInstance:Ptr;
	var hIcon:Ptr;
	var hCursor:Ptr;
	var hbrBackground:Ptr;
	var lpszMenuName:Ptr;
	var lpszClassName:Ptr;
	var hIconSm:Ptr;
}

@:hxmc.struct @:publicFields class POINT {
	var x:Int32;
	var y:Int32;
}

@:hxmc.struct @:publicFields class MSG {
	var hwnd:Ptr;
	var message:UInt32;
	var wParam:Int64;
	var lParam:Int64;
	var time:UInt32;
	var pt:POINT;
	var lPrivate:UInt32;
}

@:hxmc.struct @:publicFields class RECT {
	var left:Int32;
	var top:Int32;
	var right:Int32;
	var bottom:Int32;
}

@:hxmc.struct @:publicFields class BITMAPINFOHEADER {
	var biSize:UInt32;
	var biWidth:Int32;
	var biHeight:Int32;
	var biPlanes:UInt16;
	var biBitCount:UInt16;
	var biCompression:UInt32;
	var biSizeImage:UInt32;
	var biXPelsPerMeter:Int32;
	var biYPelsPerMeter:Int32;
	var biClrUsed:UInt32;
	var biClrImportant:UInt32;
}
