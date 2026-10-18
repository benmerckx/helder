package hxmc.scene;

import hxmc.gfx.shader.Mat4;
import hxmc.gfx.shader.Vec3;
import hxmc.gfx.shader.Vec4;
import hxmc.scene.math.MathTools;

// A camera, carried by a node (node.camera = camera): it looks down the
// node's -z, its up the node's +y. Projections are gfx's (Mat4.perspective,
// Mat4.orthographic: clip space y up, z from 0 at the near plane).
class Camera {
	public var isPerspective:Bool;
	// perspective: the vertical field of view (radians); orthographic: the
	// height of the view (scene units)
	public var fovY:Float;
	public var height:Float;
	public var near:Float;
	public var far:Float;
	public var node(default, null):Null<Node>;

	function new(perspective:Bool, fovY:Float, height:Float, near:Float, far:Float) {
		this.isPerspective = perspective;
		this.fovY = fovY;
		this.height = height;
		this.near = near;
		this.far = far;
	}

	public static function perspective(fovY:Float, near:Float, far:Float):Camera
		return new Camera(true, fovY, 0, near, far);

	public static function orthographic(height:Float, near:Float, far:Float):Camera
		return new Camera(false, 0, height, near, far);

	// the scene's space to the camera's (its node's world matrix inverted)
	public function view():Mat4
		return node == null ? Mat4.identity() : MathTools.inverse(node.world());

	public function projection(aspect:Float):Mat4 {
		if (isPerspective) return Mat4.perspective(fovY, aspect, near, far);
		var h = height / 2, w = h * aspect;
		return Mat4.orthographic(-w, w, -h, h, near, far);
	}

	public inline function viewProjection(aspect:Float):Mat4
		return projection(aspect) * view();

	// the camera's position in the scene
	public function eye():Vec3
		return node == null ? new Vec3(0, 0, 0) : node.worldPosition();

	// the ray through a point of the view (x, y from -1 to 1, y up), in the
	// scene's space: from the near plane, dir of unit length
	public function ray(x:Float, y:Float, aspect:Float):{origin:Vec3, dir:Vec3} {
		var inv = MathTools.inverse(viewProjection(aspect));
		var a = MathTools.transformPoint(inv, new Vec3(x, y, 0)), b = MathTools.transformPoint(inv, new Vec3(x, y, 1));
		var d = b - a;
		return {origin: a, dir: d / Math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)};
	}
}
