package helder.os;

// A window's title bar (Window's titlebar option): the system's
// ("standard"), or the content under it ("inset"), the window's buttons
// in the app's own layout: macOS's own buttons kept and placed over the
// content, elsewhere drawn by the app (helder.ui's <WindowControls/>).
// What a press is in an inset title bar is the app's answer
// (Window.titlebarAt: a drag region, one of its buttons); the window's
// edges resize it where the content reaches them (Wayland, X11, Windows'
// top edge). hit makes the one answer each system's code maps.
enum abstract TitleBar(String) to String {
	var Standard = "standard";
	var Inset = "inset";
}

// what a point of an inset window is
enum abstract TitleHit(Int) to Int {
	var Content = 0;
	var Drag = 1;
	var Minimize = 2;
	var Maximize = 3;
	var Close = 4;
	var Top = 5;
	var Bottom = 6;
	var Left = 7;
	var Right = 8;
	var TopLeft = 9;
	var TopRight = 10;
	var BottomLeft = 11;
	var BottomRight = 12;
}

class TitleBars {
	// the title bar's height and the drawn buttons' width, in points
	// (Windows' caption, 32, its buttons 46 wide; Linux's, GNOME's
	// header bar's round buttons in squares of 36)
	public static inline var HEIGHT = 32;

	public static function button(linux:Bool):Int
		return linux ? 36 : 46;

	// what x, y (pixels) of a window w x h is: an edge within border pixels
	// (corners a little larger, as the systems' own: twice the border along
	// the edge), unless maximised or full screen, else the app's answer
	public static function hit(x:Float, y:Float, w:Float, h:Float, border:Float, edges:Bool, app:TitleHit):TitleHit {
		if (!edges || border <= 0) return app;
		var corner = border * 2;
		var top = y < border, bottom = y >= h - border, left = x < border, right = x >= w - border;
		var nearTop = y < corner, nearBottom = y >= h - corner, nearLeft = x < corner, nearRight = x >= w - corner;
		if ((top && nearLeft) || (left && nearTop)) return TopLeft;
		if ((top && nearRight) || (right && nearTop)) return TopRight;
		if ((bottom && nearLeft) || (left && nearBottom)) return BottomLeft;
		if ((bottom && nearRight) || (right && nearBottom)) return BottomRight;
		if (top) return Top;
		if (bottom) return Bottom;
		if (left) return Left;
		if (right) return Right;
		return app;
	}

	// WM_NCHITTEST's answer (HTCLIENT 1, HTCAPTION 2, HTMAXBUTTON 9; the
	// edges' HTLEFT 10 to HTBOTTOMRIGHT 17). The minimise and close buttons
	// stay the client's (helder's own, clicked as any); the maximise
	// button is HTMAXBUTTON for Windows 11's snap layouts
	public static function win32(h:TitleHit):Int
		return switch h {
			case Drag: 2;
			case Maximize: 9;
			case Left: 10;
			case Right: 11;
			case Top: 12;
			case TopLeft: 13;
			case TopRight: 14;
			case Bottom: 15;
			case BottomLeft: 16;
			case BottomRight: 17;
			case _: 1;
		}

	// xdg_toplevel's resize_edge (none 0); -1: not an edge
	public static function wayland(h:TitleHit):Int
		return switch h {
			case Top: 1;
			case Bottom: 2;
			case Left: 4;
			case TopLeft: 5;
			case BottomLeft: 6;
			case Right: 8;
			case TopRight: 9;
			case BottomRight: 10;
			case _: -1;
		}

	// _NET_WM_MOVERESIZE's direction (8: a move); -1: neither
	public static function x11(h:TitleHit):Int
		return switch h {
			case TopLeft: 0;
			case Top: 1;
			case TopRight: 2;
			case Right: 3;
			case BottomRight: 4;
			case Bottom: 5;
			case BottomLeft: 6;
			case Left: 7;
			case Drag: 8;
			case _: -1;
		}

	// the cursor over an edge (helder's cursors have no diagonals: the
	// corners Default), null elsewhere
	public static function cursor(h:TitleHit):Null<Cursor>
		return switch h {
			case Top | Bottom: ResizeNS;
			case Left | Right: ResizeEW;
			case TopLeft | TopRight | BottomLeft | BottomRight: Default;
			case _: null;
		}
}
