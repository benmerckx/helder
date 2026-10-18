package hxmc.scene.render;

import hxmc.gfx.shader.Vec3;
import hxmc.scene.Node;
import hxmc.scene.World;

// A light, a component of a node: directional (the sun: it shines down the
// node's -z, as glTF's KHR_lights_punctual), its colour (linear) times
// its intensity. Point and spot lights, shadows: later steps.
class Light {
	public static final KIND = new StoreKind<Light>("light");

	public var color:Vec3;
	public var intensity:Float;

	function new(color:Vec3, intensity:Float) {
		this.color = color;
		this.intensity = intensity;
	}

	public static function directional(color:Vec3, intensity:Float):Light
		return new Light(color, intensity);

	public static inline function attach(node:Node, light:Light):Light
		return node.world.store(KIND).set(node, light);

	public static inline function of(node:Node):Null<Light>
		return node.world.store(KIND).get(node);
}
