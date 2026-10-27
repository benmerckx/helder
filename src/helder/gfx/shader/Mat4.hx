package helder.gfx.shader;

// A 4x4 matrix of four columns (c0..c3, read only): mat4 in a shader, an
// immutable value in CPU code (a @:hxmc.struct value on hxmc's targets, as
// the vectors). m * v transforms a column vector, a * b
// applies b first; uniforms store it column by column (std140).
@:forward(c0, c1, c2, c3)
abstract Mat4(Mat4Data) {
	public inline function new(c0:Vec4, c1:Vec4, c2:Vec4, c3:Vec4)
		this = new Mat4Data(c0, c1, c2, c3);

	@:op(A * B) static inline function mulVec(m:Mat4, v:Vec4):Vec4
		return m.c0 * v.x + m.c1 * v.y + m.c2 * v.z + m.c3 * v.w;

	@:op(A * B) static inline function mulMat(a:Mat4, b:Mat4):Mat4
		return new Mat4(a * b.c0, a * b.c1, a * b.c2, a * b.c3);

	// transforms for CPU code (not shader code): the clip space of every back
	// end (Shaders: y up, z from 0 at the near plane to w at the far one),
	// right-handed (the camera looks down -z), angles in radians

	public static function identity():Mat4
		return scaling(1, 1, 1);

	public static function translation(x:Float, y:Float, z:Float):Mat4
		return new Mat4(new Vec4(1, 0, 0, 0), new Vec4(0, 1, 0, 0), new Vec4(0, 0, 1, 0), new Vec4(x, y, z, 1));

	public static function scaling(x:Float, y:Float, z:Float):Mat4
		return new Mat4(new Vec4(x, 0, 0, 0), new Vec4(0, y, 0, 0), new Vec4(0, 0, z, 0), new Vec4(0, 0, 0, 1));

	public static function rotationX(a:Float):Mat4 {
		var c = Math.cos(a), s = Math.sin(a);
		return new Mat4(new Vec4(1, 0, 0, 0), new Vec4(0, c, s, 0), new Vec4(0, -s, c, 0), new Vec4(0, 0, 0, 1));
	}

	public static function rotationY(a:Float):Mat4 {
		var c = Math.cos(a), s = Math.sin(a);
		return new Mat4(new Vec4(c, 0, -s, 0), new Vec4(0, 1, 0, 0), new Vec4(s, 0, c, 0), new Vec4(0, 0, 0, 1));
	}

	public static function rotationZ(a:Float):Mat4 {
		var c = Math.cos(a), s = Math.sin(a);
		return new Mat4(new Vec4(c, s, 0, 0), new Vec4(-s, c, 0, 0), new Vec4(0, 0, 1, 0), new Vec4(0, 0, 0, 1));
	}

	// a perspective projection: fovY the vertical field of view, aspect width / height
	public static function perspective(fovY:Float, aspect:Float, near:Float, far:Float):Mat4 {
		var f = 1 / Math.tan(fovY / 2), r = far / (near - far);
		return new Mat4(new Vec4(f / aspect, 0, 0, 0), new Vec4(0, f, 0, 0), new Vec4(0, 0, r, -1), new Vec4(0, 0, near * r, 0));
	}

	// an orthographic projection of the box left..right, bottom..top, near..far (distances down -z)
	public static function orthographic(left:Float, right:Float, bottom:Float, top:Float, near:Float, far:Float):Mat4 {
		var w = right - left, h = top - bottom, d = near - far;
		return new Mat4(new Vec4(2 / w, 0, 0, 0), new Vec4(0, 2 / h, 0, 0), new Vec4(0, 0, 1 / d, 0), new Vec4(-(right + left) / w, -(top + bottom) / h, near / d, 1));
	}
}

@:hxmc.struct @:noCompletion final class Mat4Data {
	public final c0:Vec4;
	public final c1:Vec4;
	public final c2:Vec4;
	public final c3:Vec4;

	public inline function new(c0:Vec4, c1:Vec4, c2:Vec4, c3:Vec4) {
		this.c0 = c0;
		this.c1 = c1;
		this.c2 = c2;
		this.c3 = c3;
	}
}
