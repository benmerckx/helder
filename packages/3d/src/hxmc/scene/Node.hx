package hxmc.scene;

import hxmc.gfx.shader.Mat4;
import hxmc.gfx.shader.Vec3;
import hxmc.scene.math.MathTools;
import hxmc.scene.math.Quat;

// A node of the scene graph: a transform relative to its parent (position,
// rotation, scale: applied to a point as scale, then rotation, then
// translation), its children, and what it carries: a camera, a light, a
// mesh (what the renderer draws; any value: the renderer's own type).
//
// The world matrix is computed when asked and cached: a node keeps the
// version of its parent's world matrix it was computed from, so a change
// high in the tree makes the matrices below it stale without visiting
// them, and still parts of the scene cost nothing per frame.
class Node {
	public var name:String;
	public var position(default, set):Vec3 = new Vec3(0, 0, 0);
	public var rotation(default, set):Quat = Quat.identity();
	public var scale(default, set):Vec3 = new Vec3(1, 1, 1);
	public var parent(default, null):Null<Node>;
	public var children(default, null):Array<Node> = [];
	// what it carries
	public var camera(default, set):Null<Camera>;
	public var mesh:Null<Any>;
	public var light:Null<Any>;
	// hidden: neither it nor its children are drawn
	public var visible = true;

	// (the cached matrices: local stale when dirty; world computed from the
	// parent's world at parentVersion, version bumped when it changes)
	var dirty = true;
	var localMatrix:Mat4 = Mat4.identity();
	var worldMatrix:Mat4 = Mat4.identity();
	var version = 0;
	var parentVersion = -1;
	var worldValid = false;

	public function new(name = "") {
		this.name = name;
	}

	function set_position(v:Vec3):Vec3 {
		dirty = true;
		return position = v;
	}

	function set_rotation(v:Quat):Quat {
		dirty = true;
		return rotation = v;
	}

	function set_scale(v:Vec3):Vec3 {
		dirty = true;
		return scale = v;
	}

	function set_camera(c:Null<Camera>):Null<Camera> {
		if (camera != null) @:privateAccess camera.node = null;
		if (c != null) {
			if (c.node != null) c.node.camera = null;
			@:privateAccess c.node = this;
		}
		return camera = c;
	}

	// the transform from a matrix (glTF's matrix form): its translation,
	// rotation and scale
	public function setMatrix(m:Mat4) {
		var d = MathTools.decompose(m);
		position = d.t;
		rotation = d.r;
		scale = d.s;
	}

	public function add(child:Node):Node {
		var p = this;
		while (p != null) {
			if (p == child) throw "hxmc.scene.Node: a node cannot be added under itself";
			p = p.parent;
		}
		if (child.parent != null) child.parent.remove(child);
		children.push(child);
		child.parent = this;
		child.worldValid = false;
		return child;
	}

	public function remove(child:Node) {
		if (child.parent != this) return;
		children.remove(child);
		child.parent = null;
		child.worldValid = false;
	}

	// the transform relative to the parent
	public function local():Mat4 {
		if (dirty) {
			localMatrix = MathTools.compose(position, rotation, scale);
			dirty = false;
			worldValid = false;
		}
		return localMatrix;
	}

	// the transform to the scene's space
	public function world():Mat4 {
		var l = local();
		if (parent == null) {
			if (!worldValid) {
				worldMatrix = l;
				worldValid = true;
				version++;
			}
			return worldMatrix;
		}
		var pw = parent.world();
		if (!worldValid || parentVersion != parent.version) {
			worldMatrix = pw * l;
			parentVersion = parent.version;
			worldValid = true;
			version++;
		}
		return worldMatrix;
	}

	public inline function worldPosition():Vec3 {
		var c = world().c3;
		return new Vec3(c.x, c.y, c.z);
	}

	// turns the node so that its -z looks at target (a point in its parent's space)
	public function lookAt(target:Vec3, ?up:Vec3) {
		rotation = MathTools.lookRotation(target - position, up != null ? up : new Vec3(0, 1, 0));
	}

	// the first node named name, this one or below it (depth first)
	public function find(name:String):Null<Node> {
		if (this.name == name) return this;
		for (c in children) {
			var n = c.find(name);
			if (n != null) return n;
		}
		return null;
	}

	// f on this node and each one below it, parents first
	public function walk(f:Node->Void) {
		f(this);
		for (c in children)
			c.walk(f);
	}
}
