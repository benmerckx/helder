package hxmc.scene.gltf;

import hxmc.gfx.shader.Mat4;
import hxmc.gfx.shader.Vec4;
import hxmc.scene.Camera;
import hxmc.scene.Node;

// A glTF document's node hierarchy as scene nodes: a Node per glTF node
// (its TRS, or its matrix decomposed), named as in the file, under one
// root; cameras made from the document's; what a node's mesh becomes is
// the caller's (mesh(index): the renderer's own mesh, shared by the nodes
// that use it), so the hierarchy needs no renderer.
class GltfNodes {
	public static function build(doc:GltfDoc, ?scene:Int, ?mesh:Int->Any):Node {
		var root = new Node(scene != null && scene >= 0 && scene < doc.scenes.length ? doc.scenes[scene].name : "gltf");
		var made = new Map<Int, Any>();
		function meshOf(k:Int):Any {
			if (!made.exists(k)) made.set(k, mesh(k));
			return made.get(k);
		}
		function make(k:Int):Node {
			var g = doc.nodes[k];
			var n = new Node(g.name);
			if (g.matrix != null) {
				var m = g.matrix;
				n.setMatrix(new Mat4(new Vec4(m[0], m[1], m[2], m[3]), new Vec4(m[4], m[5], m[6], m[7]), new Vec4(m[8], m[9], m[10], m[11]),
					new Vec4(m[12], m[13], m[14], m[15])));
			} else {
				n.position = g.translation;
				n.rotation = g.rotation;
				n.scale = g.scale;
			}
			if (g.mesh >= 0 && mesh != null) n.mesh = meshOf(g.mesh);
			if (g.camera >= 0) {
				var c = doc.cameras[g.camera];
				n.camera = c.perspective ? Camera.perspective(c.yfov, c.znear, c.zfar > 0 ? c.zfar : 1000) : Camera.orthographic(2 * c.ymag, c.znear,
					c.zfar);
			}
			for (c in g.children)
				n.add(make(c));
			return n;
		}
		for (k in doc.roots(scene != null ? scene : -1))
			root.add(make(k));
		return root;
	}
}
