import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.view.*;

// helder.ui's accessibility on Linux (LinuxAccess; bun run test ui-draw, under
// Xvfb and a D-Bus session with AT-SPI's bus): AccessFixture's controls in a
// window titled "fixture", whose tree AtspiProbe, another process, reads
// through libatspi (what Orca uses) and acts on, last pressing its Save
// button, which closes the window. Its exit status: whether the press came
// within 30 seconds, and no tree was built before a client asked (after the
// first frame, before any message).
//   LinuxAccessTest   (with AtspiProbe fixture running)
class LinuxAccessTest {
	static function main() {
		var w = new UiWindow("fixture", 400, 640);
		var f = new AccessFixture();
		Render.render(f.view(), w.root);
		var start = haxe.Timer.stamp();
		var frames = 0, lazy = false;
		w.onFrame = () -> {
			if (frames++ == 0) {
				var la:Null<helder.ui.draw.LinuxAccess> = cast @:privateAccess w.linuxAccess;
				lazy = la != null && @:privateAccess la.tree == null;
			}
			if (f.saved > 0 || haxe.Timer.stamp() - start > 30) w.close();
		};
		// (frames go on: the probe's calls are answered each loop turn anyway)
		UiWindow.idleWait = 0.02;
		Clock.add(_ -> f.saved == 0 && haxe.Timer.stamp() - start <= 30);
		UiWindow.run();
		if (!lazy) Sys.println("LinuxAccessTest: a tree built before any client asked, FAILED");
		Sys.println("LinuxAccessTest: " + (f.saved > 0 ? "pressed through AT-SPI, ok" : "not pressed within 30 s, FAILED"));
		Sys.exit(f.saved > 0 && lazy ? 0 : 1);
	}
}
