package helder.scene;

import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec3;
import helder.scene.math.Quat;

// What helder/scene's Node (src/helder/scene/index.ts, a class of the
// program's over a node's handle) calls for TypeScript programs: Node's
// accessors and methods, whose Haxe ones are inline (a node is an Int:
// World), as functions. A node crosses as helder/scene's Node, its id the
// handle (helder.typescript.lower.Haxe's NODE).
class Script {
	public static function world(n:Node):World
		return n.world;

	public static function valid(n:Node):Bool
		return n.valid;

	public static function name(n:Node):String
		return n.name;

	public static function setName(n:Node, v:String):Void
		n.name = v;

	public static function position(n:Node):Vec3
		return n.position;

	public static function setPosition(n:Node, v:Vec3):Void
		n.position = v;

	public static function rotation(n:Node):Quat
		return n.rotation;

	public static function setRotation(n:Node, v:Quat):Void
		n.rotation = v;

	public static function scale(n:Node):Vec3
		return n.scale;

	public static function setScale(n:Node, v:Vec3):Void
		n.scale = v;

	public static function visible(n:Node):Bool
		return n.visible;

	public static function setVisible(n:Node, v:Bool):Void
		n.visible = v;

	public static function parent(n:Node):Node
		return n.parent;

	public static function add(n:Node, child:Node):Node
		return n.add(child);

	public static function detach(n:Node):Void
		n.detach();

	// its children's ids, in order
	public static function children(n:Node):Array<Int>
		return [for (c in n.children()) c.id()];

	public static function localMatrix(n:Node):Mat4
		return n.localMatrix();

	public static function worldMatrix(n:Node):Mat4
		return n.worldMatrix();

	public static function worldPosition(n:Node):Vec3
		return n.worldPosition();

	public static function setMatrix(n:Node, m:Mat4):Void
		n.setMatrix(m);

	public static function lookAt(n:Node, target:Vec3):Void
		n.lookAt(target);

	public static function lookAtUp(n:Node, target:Vec3, up:Vec3):Void
		n.lookAt(target, up);

	public static function find(n:Node, name:String):Node
		return n.find(name);

	public static function shown(n:Node):Bool
		return n.shown();

	public static function dispose(n:Node):Void
		n.dispose();

	// a material's block of its own (a shader of its own's: MaterialShader.blocks) by its parameter's name
	public static function materialBlock(m:helder.scene.render.Material, name:String, bytes:haxe.io.Bytes):Void {
		if (m.uniforms == null) m.uniforms = [];
		m.uniforms.set(name, bytes);
	}
}
