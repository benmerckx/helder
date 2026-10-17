import hxmc.gfx.*;

// The tests' scenes (GfxTest, WebTest): the triangle example, the cube
// example turned by ANGLE radians, or the instances example at TIME seconds
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
		var triangle = new Triangle(device);
		return enc -> triangle.draw(enc);
	}
}
