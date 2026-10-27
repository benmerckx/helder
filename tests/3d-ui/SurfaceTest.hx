import haxe.io.Bytes;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Camera;
import helder.scene.World;
import helder.scene.view.SceneTags.*;
import helder.scene.view.SceneEvent;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.Reactive.*;

// The boundary tags in windows (bun run test 3d: under Xvfb, Mesa): two
// <Surface>s, one with a reactive title, opened by Render.open; in the
// first a <Scene> box in ui's layout drawing a mesh (its pixels the
// scene's), a click over the mesh routed by ui's hit testing into the
// scene (picked), <Ui> over the mesh; the second window closed by a Show,
// both by the root's dispose.
class SurfaceTest implements Markup {
	static var checks = 0;
	static var failed = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('SurfaceTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var title = signal("one");
		var second = signal(true);
		var picked = signal("");
		var windows:Array<UiWindow> = [];
		var world = new World("test"), eye = world.node("eye");
		eye.position = new Vec3(0, 0, 4);
		eye.lookAt(new Vec3(0, 0, 0));
		var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 100));
		var dispose = Render.open(<>
			<Surface title={title} width={320} height={200} background={0xFFFFFFFF} ref={w -> windows.push(w)}>
				<view direction="row" grow={1}>
					<view width={120}><text tag="label">{picked}</text></view>
					<Scene world={world} camera={camera} grow={1}>
						<mesh shape="box" size={1.4} color={new Vec4(1, 0.2, 0.1, 1)} onClick={(e:SceneEvent) -> picked.value = "box"}/>
						<light kind="directional" intensity={2.0}/>
						<Ui><text tag="over">over</text></Ui>
					</Scene>
				</view>
			</Surface>
			<Show when={second}><Surface title="two" width={160} height={100} ref={w -> windows.push(w)}><text>two</text></Surface></Show>
		</>);
		check("two windows", windows.length == 2 && windows[0].window.title == "one" && windows[1].window.title == "two",
			[for (w in windows) w.window.title].join(", "));
		title.value = "uno";
		check("a reactive title", windows[0].window.title == "uno", windows[0].window.title);
		var w = windows[0];
		var pixels = Bytes.alloc(w.device.width * w.device.height * 4);
		// (UiWindow.run's loop for a few frames: the windows mapped, their events handled; the fifth frame captured)
		var frames = 0;
		helder.os.App.run(() -> {
			for (x in windows)
				if (!x.window.closed && x.needsFrame()) x.frame();
			frames++;
			if (frames == 5) w.capture = pixels;
			w.ui.requestFrame();
			if (frames == 7) helder.os.App.quit();
			helder.os.App.wait(0.02);
		}, e -> for (x in windows) if (x.window == e.window) x.handle(e));
		// (the box: x 120 to 320, y 0 to 200 in points; the mesh at its centre)
		var s = w.renderer.scale, pw = w.device.width;
		function at(x:Float, y:Float):Array<Int> {
			var o = (Std.int(y * s) * pw + Std.int(x * s)) * 4;
			return [pixels.get(o), pixels.get(o + 1), pixels.get(o + 2)];
		}
		if (Sys.args().length > 0) sys.io.File.saveBytes(Sys.args()[0], Png.encode(pixels, pw, w.device.height));
		// (the mesh's face: off the <Ui>'s label at the centre)
		var mid = at(185, 70), corner = at(124, 4), panel = at(60, 150);
		check("the scene drawn in its box: the mesh", mid[0] > 120 && mid[0] > mid[1] + 30 && mid[0] > mid[2] + 30, Std.string(mid));
		check("the scene drawn in its box: its clear colour", corner[0] < 40 && corner[1] < 40 && corner[2] < 50, Std.string(corner));
		check("ui's beside it", panel[0] > 240 && panel[1] > 240 && panel[2] > 240, Std.string(panel));
		// (ui's hit testing: the box under the pointer, the scene's picking then)
		w.ui.pointerMove(220, 100);
		w.ui.pointerDown(220, 100, 1);
		w.ui.pointerUp(220, 100, 1);
		check("a click routed into the scene: the mesh picked", picked.value == "box", picked.value);
		w.ui.pointerDown(130, 10, 1);
		w.ui.pointerUp(130, 10, 1);
		check("a click beside the mesh: none", picked.value == "box");
		w.ui.requestFrame();
		w.frame();
		var over = w.root.find("over");
		var r = over == null ? null : over.windowBounds();
		check("<Ui> over its node: the box's centre", r != null && Math.abs(r.x + r.width / 2 - 220) < 4 && Math.abs(r.y + r.height / 2 - 100) < 4,
			r == null ? "none" : '${r.x},${r.y} ${r.width}x${r.height}');
		check("the label follows the pick", w.root.find("label") != null);
		second.value = false;
		check("a Show's <Surface> closed", windows[1].window.closed);
		dispose();
		check("the root disposed: closed", windows[0].window.closed);
		Sys.println('SurfaceTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}
}
