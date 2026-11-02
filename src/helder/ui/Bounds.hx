package helder.ui;

// A box (x, y, width, height) to fill: what Node.windowBoundsInto and
// rectInto write instead of making one, so a frame's or a gesture's code
// that asks every move allocates nothing (keep one and pass it again).
class Bounds {
	public var x = 0.0;
	public var y = 0.0;
	public var width = 0.0;
	public var height = 0.0;

	public function new() {}
}
