import helder.dev.Hot;
import helder.gfx.*;
import helder.os.*;
import hxmc.unsafe.Mem;

// hxmc dev's host without a dev server (docs/dev.md, "No reloads"; CI:
// tests/gfx/ios-dev.sh on an iPhone simulator, host-dev.sh on macOS
// and Windows, where the builds are all dylibs or DLLs run by
// helder.dev.DevHost): built as the app
// (-D devhost_version=1, -D hxmc.dev-host) and as dylibs of later versions
// (-D hxmc.shared, 2, 3), which the running build hands over to in turn
// (HXMC_DEV_NEXT, a second after its first frame: Hot). Each build draws the
// cube and prints its version, a count kept across builds (Hot.keep: the
// snapshot), the process and the host's view: the same process and view,
// the count one more each time.
class DevHostTest {
	static function main() {
		var version = haxe.macro.Compiler.getDefine("devhost_version");
		var state = Hot.keep("state", () -> {n: 0});
		state.n++;
		var w = new Window("DevHostTest", 320, 240);
		var device = Device.create(w.surface);
		var cube = new Cube(device);
		var start = Sys.time(), frames = 0;
		App.run(() -> {
			var enc = device.beginFrame();
			if (enc == null) return;
			cube.draw(enc, Scene.ANGLE + (Sys.time() - start) * 0.5);
			device.endFrame();
			frames++;
			if (frames == 10) {
				// (the window's view: iOS, macOS; the HWND: Windows)
				var view = helder.dev.Hosted.get(Mem.os() == 2 ? helder.dev.Hosted.UI_WINDOW : helder.dev.Hosted.UI_VIEW);
				Sys.println('DevHostTest: v$version n=${state.n} pid=${helder.dev.Hosted.pid()} view=${haxe.Int64.toStr(view.toI64())} ${device.width}x${device.height}');
			}
		}, e -> {});
	}
}
