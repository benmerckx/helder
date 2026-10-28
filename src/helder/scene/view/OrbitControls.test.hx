package helder.scene.view;

#if (target.name == "hxmc")
import helder.gfx.shader.Vec3;
import helder.scene.Camera;
import helder.scene.World;
import helder.test.Test;
import helder.ui.Ui;

// OrbitControls on a <Scene>'s box without a GPU (ui's pointers fed as
// UiWindow does; natively and as wasm32-wasi): a finger turns the camera,
// a pinch brings it nearer about its centre, two fingers move the target,
// the mouse's right button too, the wheel zooms (not the page's), a flick
// glides on and slows, the limits hold. The taps on a mesh beside the
// orbit: tests/3d-ui/SurfaceTest.hx (a GPU's).
function tests() {
	describe("OrbitControls", () -> {
		var t = 0.0;
		var ui:Ui = null, box:SceneBox = null, orbit:OrbitControls = null, camera:Camera = null;
		beforeEach(() -> {
			t = 0;
			Ui.now = () -> t;
			ui = new Ui(null, 200, 200);
			var world = new World("orbit"), eye = world.node("eye");
			eye.position = new Vec3(0, 0, 10);
			eye.lookAt(new Vec3(0, 0, 0));
			camera = Camera.attach(eye, Camera.perspective(1, 0.1, 100));
			box = new SceneBox(world, camera);
			box.style.width = 200;
			box.style.height = 200;
			ui.root.append(box);
			ui.update();
			orbit = new OrbitControls(box, camera);
		});
		function drag(id:Int, x0:Float, y0:Float, x1:Float, y1:Float) {
			ui.pointerDown(x0, y0, 1, id, Touch);
			for (k in 1...5) {
				t += 0.016;
				ui.pointerMove(x0 + (x1 - x0) * k / 4, y0 + (y1 - y0) * k / 4, id);
			}
			ui.pointerUp(x1, y1, 1, id);
		}
		test("from where the camera is", () -> {
			approx(orbit.distance, 10, 1e-9);
			approx(orbit.yaw, 0, 1e-9);
			approx(orbit.pitch, 0, 1e-9);
		});
		test("a finger turns it round the target", () -> {
			orbit.damping = 0;
			drag(1, 100, 100, 140, 100);
			approx(orbit.yaw, -40 * orbit.rotateSpeed, 1e-9);
			var e = camera.eye();
			approx(Math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z), 10, 1e-6, "on its sphere");
			assert(e.x < 0, "dragged right: the camera to the left, the scene turning with the finger");
			drag(1, 100, 100, 100, 60);
			approx(orbit.pitch, -40 * orbit.rotateSpeed, 1e-9, "dragged up: from below");
		});
		test("a pinch about the centre: nearer, the target kept", () -> {
			ui.pointerDown(80, 100, 1, 1, Touch);
			ui.pointerDown(120, 100, 1, 2, Touch);
			t += 0.016;
			ui.pointerMove(60, 100, 1);
			ui.pointerMove(140, 100, 2);
			ui.pointerUp(60, 100, 1, 1);
			ui.pointerUp(140, 100, 1, 2);
			approx(orbit.distance, 5, 1e-9);
			approx(orbit.target.x, 0, 1e-9);
		});
		test("a pinch off the centre: the point under the fingers stays", () -> {
			ui.pointerDown(140, 100, 1, 1, Touch);
			ui.pointerDown(160, 100, 1, 2, Touch);
			t += 0.016;
			ui.pointerMove(130, 100, 1);
			ui.pointerMove(170, 100, 2);
			// (at distance 10, fov 1: 2 * 10 * tan(0.5) / 200 units a point; the focus 50 points right)
			var per = 2 * 10 * Math.tan(0.5) / 200;
			approx(orbit.distance, 5, 1e-9);
			approx(orbit.target.x, 50 * per * 0.5, 1e-9);
		});
		test("two fingers moved together move the target, the content following", () -> {
			ui.pointerDown(80, 100, 1, 1, Touch);
			ui.pointerDown(120, 100, 1, 2, Touch);
			t += 0.016;
			ui.pointerMove(90, 100, 1);
			ui.pointerMove(130, 100, 2);
			assert(orbit.target.x < 0 && Math.abs(orbit.target.y) < 1e-9, '${orbit.target.x}');
		});
		test("the mouse: the left button turns, the right moves, the wheel zooms", () -> {
			orbit.damping = 0;
			ui.pointerDown(100, 100, 1);
			ui.pointerMove(120, 100);
			ui.pointerUp(120, 100, 1);
			approx(orbit.yaw, -20 * orbit.rotateSpeed, 1e-9);
			ui.pointerDown(100, 100, 3);
			ui.pointerMove(100, 120);
			ui.pointerUp(100, 120, 3);
			assert(orbit.target.y > 0, "dragged down: the target up");
			var d = orbit.distance;
			ui.wheel(100, 100, 0, -100);
			approx(orbit.distance, d / Math.exp(0.2), 1e-9);
		});
		test("a flick glides on, slowing; the limits hold", () -> {
			drag(1, 60, 100, 160, 100);
			var after = orbit.yaw;
			for (_ in 0...30)
				@:privateAccess orbit.update(1 / 60);
			assert(orbit.yaw < after - 0.05, 'glided from $after to ${orbit.yaw}');
			orbit.maxDistance = 6;
			ui.wheel(100, 100, 0, 1000);
			equals(orbit.distance, 6.0);
			orbit.pitch = 3;
			orbit.apply();
			equals(orbit.pitch, orbit.maxPitch);
		});
	});
}
#else
function tests() {}
#end
