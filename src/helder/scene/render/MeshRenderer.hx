package helder.scene.render;

import helder.scene.Node;
import helder.scene.World;

// The mesh a node draws: a component (a store keyed by node), several
// nodes may share one Mesh.
class MeshRenderer {
	public static final KIND = new StoreKind<Mesh>("mesh");

	public static inline function attach(node:Node, mesh:Mesh):Mesh
		return node.world.store(KIND).set(node, mesh);

	public static inline function of(node:Node):Null<Mesh>
		return node.world.store(KIND).get(node);

	public static inline function detach(node:Node)
		node.world.store(KIND).remove(node);

	// a node's tint: rgb times its materials' base colour (1, 1, 1 when
	// none), per node: nodes sharing a mesh and a material in one
	// instanced draw each their own (a building in its planet's palette)
	public static final TINT = new StoreKind<helder.gfx.shader.Vec3>("tint");

	public static inline function tint(node:Node, color:helder.gfx.shader.Vec3)
		node.world.store(TINT).set(node, color);
}
