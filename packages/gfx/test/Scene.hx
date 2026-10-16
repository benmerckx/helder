import hxmc.gfx.*;

// The tests' scenes (GfxTest, WebTest): the triangle example, or the cube
// example turned by ANGLE radians
class Scene {
	public static inline var ANGLE = 0.6;

	// the scene's frame: a pass recorded by the example
	public static function make(name:String, device:Device):Encoder->Void {
		if (name == "cube") {
			var cube = new Cube(device);
			return enc -> cube.draw(enc, ANGLE);
		}
		var triangle = new Triangle(device);
		return enc -> triangle.draw(enc);
	}
}
