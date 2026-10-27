package helder.ui.native.android;

import helder.gfx.Device;
import helder.gfx.Encoder;
import helder.os.android.ChildSurface;
import helder.os.android.MainThread;
import helder.ui.*;

// A GPU view among a NativeHost's views on Android (the design's GPU view
// inside native controls): a node laid out like any other (its size from
// its style), shown by a SurfaceView (helder.os.android.ChildSurface) at its
// box, where helder.gfx draws: once its surface exists, a Device on it
// (onDevice, to make what draw uses), then draw with each frame's encoder,
// on the main thread's frames, every frame while animate, else after
// redraw() or a change of its surface (a resize, the app back from the
// background). Its device keeps its GPU objects while the surface comes and
// goes. One per window: each frame does not make its context current again.
class GpuView extends Node {
	public var onDevice:Null<Device->Void> = null;
	public var draw:Null<Encoder->Void> = null;
	public var animate(default, set) = false;
	public var device(default, null):Null<Device> = null;
	// frames drawn (tests)
	public var frames(default, null) = 0;

	@:allow(helder.ui.native.android) var child:Null<ChildSurface> = null;
	@:allow(helder.ui.native.android) var wanted = true;

	public function new(?tag:String)
		super(tag == null ? "gpu" : tag);

	// whether its SurfaceView has a surface now
	public function hasSurface():Bool
		return child != null && !child.surface.handle.isNull();

	// another frame drawn soon
	public function redraw() {
		wanted = true;
		if (MainThread.isMain()) MainThread.requestFrame();
	}

	function set_animate(v:Bool):Bool {
		animate = v;
		if (v) redraw();
		return v;
	}

	// a frame, when there is a surface (the main thread)
	@:allow(helder.ui.native.android) function frame() {
		if (child == null || child.surface.handle.isNull() || !(animate || wanted)) return;
		if (device == null) {
			device = Device.create(child.surface);
			if (onDevice != null) onDevice(device);
		}
		var enc = device.beginFrame();
		if (enc == null) return;
		wanted = false;
		if (draw != null) draw(enc);
		device.endFrame();
		frames++;
	}
}
