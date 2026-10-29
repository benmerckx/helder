import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.view.*;
import helder.view.graph.Graph.*;
import Plain.*;

// helder.ui's accessibility on Linux (LinuxAccess; bun run test ui-draw, under
// Xvfb and a D-Bus session with AT-SPI's bus): a window of controls (Plain's) whose
// tree AtspiProbe, another process, reads through libatspi (what Orca
// uses), then presses its Save button, which closes the window. Its exit
// status: whether the press came within 20 seconds, and no tree was built
// before a client asked (after the first frame, before any message).
//   LinuxAccessTest   (with AtspiProbe running)
class LinuxAccessTest implements Markup {
	static function main() {
		var w = new UiWindow("LinuxAccessTest", 320, 240);
		var pressed = false, checked = signal(false), volume = signal(0.5), name = signal("");
		Render.render(<view padding={12} row-gap={8} align-items="start">
			<text>Settings</text>
			<Button tag="save" label="Save" onClick={() -> {
				pressed = true;
				w.close();
			}}/>
			<Checkbox tag="remember" checked={checked} label="Remember"/>
			<Slider tag="volume" value={volume} step={0.1} label="Volume"/>
			<field tag="name" value={name} placeholder="Name" label="Name" onInput={e -> name(e.text)}/>
			<view live="polite"><text>Ready</text></view>
		</view>, w.root);
		var start = haxe.Timer.stamp();
		var frames = 0, lazy = false;
		w.onFrame = () -> {
			if (frames++ == 0) {
				var la:Null<helder.ui.draw.LinuxAccess> = cast @:privateAccess w.linuxAccess;
				lazy = la != null && @:privateAccess la.tree == null;
			}
			if (haxe.Timer.stamp() - start > 20) w.close();
		};
		// (frames go on: the probe's calls are answered each loop turn anyway)
		UiWindow.idleWait = 0.02;
		Clock.add(_ -> !pressed && haxe.Timer.stamp() - start <= 20);
		UiWindow.run();
		if (!lazy) Sys.println("LinuxAccessTest: a tree built before any client asked, FAILED");
		Sys.println("LinuxAccessTest: " + (pressed ? "pressed through AT-SPI, ok" : "not pressed within 20 s, FAILED"));
		Sys.exit(pressed && lazy ? 0 : 1);
	}
}
