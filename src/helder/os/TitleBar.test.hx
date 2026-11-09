package helder.os;

import helder.test.Test;
import helder.os.TitleBar;

// An inset title bar's hit-testing (TitleBars.hit) and each system's codes
// for it: Windows' WM_NCHITTEST, Wayland's resize edges, X11's
// _NET_WM_MOVERESIZE (natively and as wasm32-wasi)
@:test.interp function tests() {
	describe("TitleBar", () -> {
		test("the edges first, the corners larger, then the app's answer", () -> {
			equals(TitleBars.hit(400, 2, 800, 600, 6, true, Drag), Top);
			equals(TitleBars.hit(400, 598, 800, 600, 6, true, Content), Bottom);
			equals(TitleBars.hit(1, 300, 800, 600, 6, true, Content), Left);
			equals(TitleBars.hit(799, 300, 800, 600, 6, true, Content), Right);
			// (a corner reaches twice the border along each edge)
			equals(TitleBars.hit(10, 2, 800, 600, 6, true, Drag), TopLeft);
			equals(TitleBars.hit(2, 10, 800, 600, 6, true, Drag), TopLeft);
			equals(TitleBars.hit(795, 590, 800, 600, 6, true, Content), BottomRight);
			equals(TitleBars.hit(400, 10, 800, 600, 6, true, Drag), Drag);
			equals(TitleBars.hit(400, 10, 800, 600, 6, true, Maximize), Maximize);
		});
		test("maximised or full screen: no edges", () -> {
			equals(TitleBars.hit(400, 2, 800, 600, 6, false, Drag), Drag);
			equals(TitleBars.hit(0, 0, 800, 600, 6, false, Close), Close);
			equals(TitleBars.hit(0, 0, 800, 600, 0, true, Content), Content);
		});
		test("each system's codes", () -> {
			equals([for (h in [Content, Drag, Minimize, Maximize, Close, Top, TopLeft, BottomRight]) TitleBars.win32(h)], [1, 2, 1, 9, 1, 12, 13, 17]);
			equals([for (h in [Content, Drag, Top, Bottom, Left, TopLeft, Right, BottomRight]) TitleBars.wayland(h)], [-1, -1, 1, 2, 4, 5, 8, 10]);
			equals([for (h in [Content, TopLeft, Top, Right, Bottom, Left, Drag, Close]) TitleBars.x11(h)], [-1, 0, 1, 3, 5, 7, 8, -1]);
		});
	});
}
