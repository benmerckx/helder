package hxmc.scene.gltf;

import hxmc.gfx.Device;
import hxmc.scene.Node;
import hxmc.scene.World;
import hxmc.scene.render.Material;
import hxmc.scene.render.Mesh;
import hxmc.scene.render.MeshRenderer;

// A glTF document made for the Renderer: its GPU meshes and materials,
// made once (load), then instantiated into worlds as often as wanted
// (instantiate: GltfNodes' hierarchy, each node with a mesh drawing the
// shared Mesh). Triangle primitives (positions, normals, uvs; normals
// computed where the file has none); materials' factors (textures in a
// later step).
class GltfScene {
	public final doc:GltfDoc;
	public final meshes:Array<Mesh> = [];
	public final materials:Array<Material>;

	public function new(doc:GltfDoc, device:Device) {
		this.doc = doc;
		materials = [
			for (m in doc.materials)
				new Material(m.name, m.baseColor, m.metallic, m.roughness, m.emissive, m.doubleSided)
		];
		var fallback:Null<Material> = null;
		for (gm in doc.meshes) {
			var mesh = new Mesh();
			for (p in gm.primitives) {
				// (triangles only: points, lines and strips later)
				if (p.mode != 4 || p.position < 0) continue;
				var material = if (p.material >= 0) materials[p.material] else {
					if (fallback == null) fallback = new Material("default");
					fallback;
				}
				mesh.add(device, doc.floats(p.position), p.normal >= 0 ? doc.floats(p.normal) : null, p.texcoord >= 0 ? doc.floats(p.texcoord) : null,
					p.indices >= 0 ? doc.indices(p.indices) : null, material);
			}
			meshes.push(mesh);
		}
	}

	// the document's scene (by default its own) as nodes of world, under parent
	public function instantiate(world:World, ?parent:Node, ?scene:Int):Node
		return GltfNodes.build(doc, world, parent, scene, (n, k) -> MeshRenderer.attach(n, meshes[k]));

	// the GPU buffers released (the instances draw nothing after)
	public function dispose(device:Device)
		for (m in meshes)
			m.dispose(device);
}
