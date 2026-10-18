import hxmc.dev.Hot;
import hxmc.gfx.*;
import hxmc.os.*;

// hxmc dev's host without a dev server (docs/dev.md, "No reloads"; CI:
// packages/gfx/test/ios-dev.sh on an iPhone simulator, mac-dev.sh on macOS,
// where the builds are all dylibs run by hxmc.dev.DevHost): built as the app
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
				var view = hxmc.dev.Hosted.get(hxmc.dev.Hosted.UI_VIEW);
				Sys.println('DevHostTest: v$version n=${state.n} pid=${hxmc.dev.Hosted.HostThreads.getpid()} view=${StringTools.hex(haxe.Int64.toInt(view.toI64()))} ${device.width}x${device.height}');
			}
		}, e -> {});
	}
}
