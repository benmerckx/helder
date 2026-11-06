package helder.scene.input;

// InputMap's bindings as functions, for TypeScript programs (helder/scene:
// a Binding is an enum, which TypeScript does not construct):
// actions.bind("jump", Bindings.key(0x20)).
class Bindings {
	public static function key(key:Int):Binding
		return Key(key);

	public static function mouse(button:Int):Binding
		return Mouse(button);

	public static function region(x0:Float, y0:Float, x1:Float, y1:Float):Binding
		return Region(x0, y0, x1, y1);

	public static function keyAxis(negative:Int, positive:Int):Binding
		return KeyAxis(negative, positive);

	public static function padButton(button:Int):Binding
		return PadButton(button);

	public static function padAxis(axis:Int, scale:Float):Binding
		return PadAxis(axis, scale);
}
