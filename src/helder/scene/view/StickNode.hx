package helder.scene.view;

import helder.scene.input.VirtualStick;
import helder.ui.Canvas;
import helder.ui.Color;

// <Stick>'s node: a VirtualStick drawn over the window (helder.ui), its base
// a ring of its radius and its knob a disc, where the thumb holds it, else
// at rest at left, bottom (points from the window's lower left corner).
// It fills its parent and lets the pointer through (pointerEvents None:
// the stick's finger is the game's, Actions'); drawn again when the stick
// changes (VirtualStick.changed).
class StickNode extends helder.ui.Node {
	public final stick:VirtualStick;
	public var restLeft = 24.0;
	public var restBottom = 24.0;
	public var color:Color = Color.rgba(0xFFFFFF, 0.35);
	public var knobColor:Color = Color.rgba(0xFFFFFF, 0.7);

	public function new(stick:VirtualStick) {
		super("stick");
		this.stick = stick;
		style.position = Absolute;
		style.inset = 0;
		style.pointerEvents = None;
		stick.changed = redraw;
	}

	function redraw()
		if (ui != null) ui.requestFrame();

	override public function hasContent():Bool
		return true;

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		var k = ui == null ? 1.0 : ui.scale, r = stick.radius, knob = r * 0.45;
		// (the window's pixels to this node's points; at rest: its place)
		var cx = stick.active ? stick.centerX / k - absX : restLeft + r;
		var cy = stick.active ? stick.centerY / k - absY : height - restBottom - r;
		var kx = stick.active ? stick.knobX / k - absX : cx, ky = stick.active ? stick.knobY / k - absY : cy;
		canvas.rect(x + cx - r, y + cy - r, 2 * r, 2 * r, r, 0, 2, color);
		canvas.rect(x + kx - knob, y + ky - knob, 2 * knob, 2 * knob, knob, knobColor, 0, 0);
	}
}
