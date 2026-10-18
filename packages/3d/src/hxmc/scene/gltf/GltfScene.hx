package hxmc.scene.gltf;

import hxmc.gfx.Device;
import hxmc.scene.Node;
import hxmc.scene.render.Material;
import hxmc.scene.render.Mesh;

// A glTF document as scene nodes the Renderer draws: GltfNodes' hierarchy,
// each glTF mesh a Mesh (its triangle primitives; positions, normals,
// uvs; normals computed where the file has none), each material a
// Material (its factors; textures in a later step).
class GltfScene {
	public static function build(doc:GltfDoc, device:Device, ?scene:Int):Node {
		var materials = [
			for (m in doc.materials)
				new Material(m.name, m.baseColor, m.metallic, m.roughness, m.emissive, m.doubleSided)
		];
		var fallback:Null<Material> = null;
		return GltfNodes.build(doc, scene, k -> {
			var mesh = new Mesh();
			for (p in doc.meshes[k].primitives) {
				// (triangles only: points, lines and strips later)
				if (p.mode != 4 || p.position < 0) continue;
				var material = if (p.material >= 0) materials[p.material] else {
					if (fallback == null) fallback = new Material("default");
					fallback;
				}
				mesh.add(device, doc.floats(p.position), p.normal >= 0 ? doc.floats(p.normal) : null, p.texcoord >= 0 ? doc.floats(p.texcoord) : null,
					p.indices >= 0 ? doc.indices(p.indices) : null, material);
			}
			mesh;
		});
	}
}
