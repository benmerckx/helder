import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.math.Quat;

// helder's math types (helder.gfx.shader's vectors and matrix, helder.scene's
// quaternion: struct values) crossing to TypeScript as helder/gfx's classes
// (tests/typescript/helder/math.ts): arguments, results, a field, a property.
class MathProbe {
	// where it is (a struct stored in the object)
	public var at:Vec3;
	// its turn (a property: through its accessors)
	public var turn(get, set):Quat;

	var q = Quat.identity();

	public function new(at:Vec3)
		this.at = at;

	function get_turn():Quat
		return q;

	function set_turn(v:Quat):Quat
		return q = v;

	// moved by d: where it is now
	public function moved(d:Vec3):Vec3 {
		at = at + d;
		return at;
	}

	public static function scaled(v:Vec3, s:Float):Vec3
		return v * s;

	public static function sum(a:Vec2, b:Vec4):Float
		return a.x + a.y + b.x + b.y + b.z + b.w;

	public static function translation(x:Float, y:Float, z:Float):Mat4
		return Mat4.translation(x, y, z);

	public static function apply(m:Mat4, v:Vec4):Vec4
		return m * v;

	public static function spin(a:Quat, b:Quat):Quat
		return a * b;
}
