package helder.scene.view;

import helder.gfx.shader.Vec3;
import helder.scene.Camera;
import helder.ui.Event;
import helder.ui.gesture.Gesture;
import helder.ui.gesture.Scale;

// A camera orbiting a target, driven by the pointers over a <Scene>'s box
// (three.js's OrbitControls, its names): one finger or the mouse's left
// button turns it round the target (yaw, pitch), two fingers pinch it
// nearer or further (distance, about their centre: the point under them
// stays) and move the target with their centre, a twist of two fingers
// turns it too; the mouse's right (or middle) button moves the target,
// the wheel zooms about the pointer. Let go moving, it glides on, slowing
// by damping a frame (0: it stops). It reads the box's Scale gesture, in
// the box's arena with its scene nodes' taps: a tap on a mesh still
// selects it, a drag from it orbits. In markup: <OrbitControls target=
// {...} minDistance={3} maxDistance={20}/> in a <Scene> (SceneTags).
class OrbitControls {
	public final box:SceneBox;
	// the camera it moves (the box's view by default)
	public var camera:Camera;
	// what it turns about, and the camera's place round it
	public var target:Vec3;
	public var distance = 5.0;
	public var yaw = 0.0;
	public var pitch = 0.0;
	public var minDistance = 0.5;
	public var maxDistance = 100.0;
	// (radians, short of straight up and down)
	public var minPitch = -1.5;
	public var maxPitch = 1.5;
	// radians a point dragged; the zoom's and the move's factors
	public var rotateSpeed = 0.008;
	public var zoomSpeed = 1.0;
	public var panSpeed = 1.0;
	public var enableRotate = true;
	public var enableZoom = true;
	public var enablePan = true;
	// a two-finger twist turns it too
	public var enableTwist = true;
	// the glide's loss a frame (60 a second): 0.1 three.js's dampingFactor's default
	public var damping = 0.1;
	public final gesture:Scale;

	// (the glide's speeds, radians a second; the wheel's handler before it)
	var yawSpeed = 0.0;
	var pitchSpeed = 0.0;
	var wheel:Null<Event->Void>;

	public function new(box:SceneBox, ?camera:Camera, ?target:Vec3) {
		this.box = box;
		this.camera = camera ?? box.view();
		this.target = target ?? new Vec3(0, 0, 0);
		gesture = box.addGesture(new Scale());
		gesture.onGesture = moved;
		wheel = box.onWheel;
		box.onWheel = zoomed;
		box.controls.push(this);
		look();
	}

	// the yaw, pitch and distance of where the camera is now (after it was moved elsewhere)
	public function look() {
		var e = camera.eye() - target;
		distance = Math.max(1e-6, Math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z));
		yaw = Math.atan2(e.x, e.z);
		pitch = Math.asin(Math.max(-1, Math.min(1, e.y / distance)));
	}

	public function dispose() {
		box.removeGesture(gesture);
		box.onWheel = wheel;
		box.controls.remove(this);
	}

	// the camera placed (target, distance, yaw, pitch: clamped), the box drawn again
	public function apply() {
		distance = Math.max(minDistance, Math.min(maxDistance, distance));
		pitch = Math.max(minPitch, Math.min(maxPitch, pitch));
		var n = camera.node;
		if (n.isNone) return;
		var c = Math.cos(pitch);
		n.position = new Vec3(target.x + distance * c * Math.sin(yaw), target.y + distance * Math.sin(pitch), target.z + distance * c * Math.cos(yaw));
		n.lookAt(target);
		if (box.ui != null) box.ui.requestFrame();
	}

	function moved(g:Gesture) {
		yawSpeed = pitchSpeed = 0;
		var two = g.pointers > 1;
		if (!two && g.pointerType == helder.os.PointerType.Mouse && g.button != 1) {
			if (enablePan) pan(g.dx, g.dy);
		} else if (!two) {
			if (enableRotate) {
				yaw -= g.dx * rotateSpeed;
				pitch += g.dy * rotateSpeed;
				// (let go moving: on at its speed)
				if (g.state == Ended && damping > 0) {
					yawSpeed = -g.vx * rotateSpeed;
					pitchSpeed = g.vy * rotateSpeed;
				}
			}
		} else {
			// (the point under the fingers follows them, then stays under them as it zooms)
			if (enablePan) pan(g.dx, g.dy);
			if (enableZoom && g.dscale > 0) zoom(Math.pow(g.dscale, zoomSpeed), g.x, g.y);
			if (enableTwist) yaw -= g.dangle;
		}
		apply();
	}

	function zoomed(e:Event) {
		if (wheel != null) wheel(e);
		if (!enableZoom || e.defaultPrevented) return;
		// (the page's not to scroll: the wheel is the camera's here)
		e.preventDefault();
		zoom(Math.exp(-e.deltaY * 0.002 * zoomSpeed), e.localX, e.localY);
		apply();
	}

	// nearer by factor (> 1) or further, the point under x, y (the box's points) staying there
	function zoom(factor:Float, x:Float, y:Float) {
		var before = distance;
		distance = Math.max(minDistance, Math.min(maxDistance, distance / factor));
		// (the target moved toward the point under the focus, on the plane through it)
		var k = 1 - distance / before;
		var r = box.rect(), per = perPoint(before);
		var ox = (x - r.width / 2) * per, oy = (r.height / 2 - y) * per;
		var right = axisRight(), up = axisUp(right);
		target = target + (right * ox + up * oy) * k;
	}

	// the target moved with the pointers (points), the content following them
	function pan(dx:Float, dy:Float) {
		var per = perPoint(distance) * panSpeed, right = axisRight(), up = axisUp(right);
		target = target - right * (dx * per) + up * (dy * per);
	}

	// (the scene's units a point of the box at that distance)
	function perPoint(d:Float):Float {
		var h = Math.max(1, box.rect().height);
		return camera.isPerspective ? 2 * d * Math.tan(camera.fovY / 2) / h : camera.height / h;
	}

	inline function axisRight():Vec3
		return new Vec3(Math.cos(yaw), 0, -Math.sin(yaw));

	// (the camera's up: toward the target's side of the pitch)
	inline function axisUp(right:Vec3):Vec3 {
		var s = Math.sin(pitch), c = Math.cos(pitch);
		return new Vec3(-s * Math.sin(yaw), c, -s * Math.cos(yaw));
	}

	// a frame of seconds (the box's, before it draws): the glide; whether it still moves
	@:allow(helder.scene.view) function update(seconds:Float):Bool {
		if (yawSpeed == 0 && pitchSpeed == 0) return false;
		yaw += yawSpeed * seconds;
		pitch += pitchSpeed * seconds;
		var keep = Math.pow(1 - damping, seconds * 60);
		yawSpeed *= keep;
		pitchSpeed *= keep;
		if (Math.abs(yawSpeed) < 1e-3 && Math.abs(pitchSpeed) < 1e-3) yawSpeed = pitchSpeed = 0;
		apply();
		return true;
	}
}
