import helder.gfx.*;

// The tests' scenes (GfxTest, WebTest): the triangle example, the cube
// example turned by ANGLE radians, or the instances, targets, mips and
// formats examples at TIME seconds
class Scene {
	public static inline var ANGLE = 0.6;
	public static inline var TIME = 0.4;

	// the scene's frame: a pass recorded by the example
	public static function make(name:String, device:Device):Encoder->Void {
		if (name == "cube") {
			var cube = new Cube(device);
			return enc -> cube.draw(enc, ANGLE);
		}
		if (name == "instances") {
			var instances = new Instances(device);
			return enc -> instances.draw(enc, TIME);
		}
		if (name == "targets") {
			var targets = new Targets(device);
			return enc -> targets.draw(enc, TIME);
		}
		if (name == "mips") {
			var mips = new Mips(device);
			return enc -> mips.draw(enc, TIME);
		}
		if (name == "formats") {
			var formats = new Formats(device);
			return enc -> formats.draw(enc);
		}
		var triangle = new Triangle(device);
		return enc -> triangle.draw(enc);
	}
}
