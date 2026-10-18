package hxmc.scene.gltf;

import hxmc.gfx.Device;
import hxmc.scene.Node;
import hxmc.scene.World;
import hxmc.scene.render.Light;
import hxmc.scene.render.Skin;
import hxmc.scene.render.Material;
import hxmc.scene.render.Mesh;
import hxmc.scene.render.MeshRenderer;

// A glTF document made for the Renderer: its GPU meshes and materials,
// made once (load), then instantiated into worlds as often as wanted
// (instantiate: GltfNodes' hierarchy, each node with a mesh drawing the
// shared Mesh). Triangle primitives (positions, normals, uvs; normals
// computed where the file has none); materials' factors (textures in a
// later step); KHR_lights_punctual's lights as Light components; skins as
// Skin components on the nodes they deform (joints, inverse bind
// matrices; JOINTS_0 and WEIGHTS_0 in the meshes' vertices).
class GltfScene {
	public final doc:GltfDoc;
	public final meshes:Array<Mesh> = [];
	public final materials:Array<Material>;
	final device:Device;

	public function new(doc:GltfDoc, device:Device) {
		this.doc = doc;
		this.device = device;
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
					p.indices >= 0 ? doc.indices(p.indices) : null, material, p.joints >= 0 ? doc.floats(p.joints) : null,
					p.weights >= 0 ? doc.floats(p.weights) : null);
			}
			meshes.push(mesh);
		}
	}

	// the document's scene (by default its own) as nodes of world, under parent
// (made: each glTF node's Node at its index, for an Animator)
	public function instantiate(world:World, ?parent:Node, ?scene:Int, ?made:Array<Node>):Node {
		if (made == null) made = [];
		var top = GltfNodes.build(doc, world, parent, scene, (n, k) -> MeshRenderer.attach(n, meshes[k]), (n, k) -> {
			var l = doc.lights[k];
			// (glTF's units: lux for the sun, candela for the others; spot lights as point lights for now)
			Light.attach(n, l.type == "directional" ? Light.directional(l.color, l.intensity) : Light.pointLight(l.color, l.intensity,
				l.range > 0 ? l.range : 1000));
		}, made);
		// (skins: their joints are this instance's nodes)
		for (k in 0...doc.nodes.length) {
			var sk = doc.nodes[k].skin;
			if (sk < 0 || k >= made.length || made[k].isNone) continue;
			var skin = doc.skins[sk];
			var ibm = skin.inverseBindMatrices >= 0 ? doc.floats(skin.inverseBindMatrices) : [
				for (_ in skin.joints) for (i in 0...16) i % 5 == 0 ? 1.0 : 0.0
			];
			Skin.attach(made[k], new Skin(device, [for (j in skin.joints) made[j]], ibm));
		}
		return top;
	}

	// the GPU buffers released (the instances draw nothing after)
	public function dispose(device:Device)
		for (m in meshes)
			m.dispose(device);
}
