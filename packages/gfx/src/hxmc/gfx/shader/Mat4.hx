package hxmc.gfx.shader;

// A 4x4 matrix of four columns (c0..c3, read only): mat4 in a shader, an
// immutable value in CPU code. m * v transforms a column vector, a * b
// applies b first; uniforms store it column by column (std140).
@:forward(c0, c1, c2, c3)
abstract Mat4(Mat4Data) {
	public inline function new(c0:Vec4, c1:Vec4, c2:Vec4, c3:Vec4)
		this = new Mat4Data(c0, c1, c2, c3);

	@:op(A * B) static inline function mulVec(m:Mat4, v:Vec4):Vec4
		return m.c0 * v.x + m.c1 * v.y + m.c2 * v.z + m.c3 * v.w;

	@:op(A * B) static inline function mulMat(a:Mat4, b:Mat4):Mat4
		return new Mat4(a * b.c0, a * b.c1, a * b.c2, a * b.c3);
}

@:noCompletion final class Mat4Data {
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
