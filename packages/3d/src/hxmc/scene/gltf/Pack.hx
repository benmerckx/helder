package hxmc.scene.gltf;

import haxe.io.Bytes;
import haxe.io.BytesOutput;
import hxmc.scene.math.MathTools;
import hxmc.scene.render.VertexData;

// The asset step (docs/plans/3d.md, step 2): a glTF file read at build time
// (Gltf.parse, the runtime's reader) and written compact for
// PackedModel: each primitive's vertices and indices already in the
// renderer's layout (VertexData), node transforms decomposed, materials'
// factors, cameras; no JSON, so a program loading only packed models links
// no JSON reader. Skins, animations, lights and textures are not packed
// yet (a file with them packs without them).
//
//   bin/hxmc/hxmc -cp packages/os/src -cp packages/gfx/src -cp packages/3d/src \
//     --run hxmc.scene.gltf.Pack <in.glb> <out.hxm3d>
//
// The format (little-endian): "HXM3", version 1, then counts and records:
// materials (name, base colour 4 floats, metallic, roughness, emissive 3
// floats, double-sided byte), vertex data (flags (2: wide indices), index
// count, vertex bytes, index bytes, bounds 6 floats: once per set of
// accessors), meshes (name, primitives: material, vertex data), cameras (perspective byte, yfov or height, near,
// far), nodes in parents-first order (name, parent, mesh, camera, TRS 10
// floats), the roots' scene name.
class Pack {
	public static inline var MAGIC = 0x334D5848; // "HXM3"
	public static inline var VERSION = 1;

	static function main() {
		var args = Sys.args();
		if (args.length != 2) {
			Sys.println("usage: Pack <in.gltf|in.glb> <out.hxm3d>");
			Sys.exit(2);
		}
		var input = sys.io.File.getBytes(args[0]);
		var dir = haxe.io.Path.directory(args[0]);
		var out = pack(Gltf.parse(input, uri -> {
			var f = haxe.io.Path.join([dir, uri]);
			sys.FileSystem.exists(f) ? sys.io.File.getBytes(f) : null;
		}));
		sys.io.File.saveBytes(args[1], out);
		Sys.println('Pack: ${args[0]} (${input.length} bytes) to ${args[1]} (${out.length} bytes)');
	}

	public static function pack(doc:GltfDoc, ?scene:Int):Bytes {
		var o = new BytesOutput();
		o.bigEndian = false;
		function str(s:String) {
			var b = Bytes.ofString(s);
			o.writeUInt16(b.length);
			o.write(b);
		}
		o.writeInt32(MAGIC);
		o.writeInt32(VERSION);
		o.writeInt32(doc.materials.length);
		for (m in doc.materials) {
			str(m.name);
			for (x in [m.baseColor.x, m.baseColor.y, m.baseColor.z, m.baseColor.w, m.metallic, m.roughness, m.emissive.x, m.emissive.y, m.emissive.z])
				o.writeFloat(x);
			o.writeByte(m.doubleSided ? 1 : 0);
		}
		// (the vertex data once per set of accessors: primitives sharing them share it)
		var keys = new Map<String, Int>(), datas:Array<VertexData> = [];
		function dataOf(p:GltfDoc.GltfPrimitive):Int {
			var key = p.position + "," + p.normal + "," + p.texcoord + "," + p.indices;
			if (!keys.exists(key)) {
				// (skins are not packed: their vertices as plain ones)
				datas.push(VertexData.make(doc.floats(p.position), p.normal >= 0 ? doc.floats(p.normal) : null, p.texcoord >= 0 ? doc.floats(p.texcoord) : null,
					p.indices >= 0 ? doc.indices(p.indices) : null));
				keys.set(key, datas.length - 1);
			}
			return keys.get(key);
		}
		var meshPrims = [for (mesh in doc.meshes) [for (p in mesh.primitives) if (p.mode == 4 && p.position >= 0) {material: p.material, data: dataOf(p)}]];
		o.writeInt32(datas.length);
		for (d in datas) {
			o.writeByte(d.wide ? 2 : 0);
			o.writeInt32(d.count);
			o.writeInt32(d.vertices.length);
			o.write(d.vertices);
			o.writeInt32(d.indices.length);
			o.write(d.indices);
			for (x in [d.bounds.min.x, d.bounds.min.y, d.bounds.min.z, d.bounds.max.x, d.bounds.max.y, d.bounds.max.z])
				o.writeFloat(x);
		}
		o.writeInt32(doc.meshes.length);
		for (k in 0...doc.meshes.length) {
			str(doc.meshes[k].name);
			o.writeInt32(meshPrims[k].length);
			for (p in meshPrims[k]) {
				o.writeInt32(p.material);
				o.writeInt32(p.data);
			}
		}
		o.writeInt32(doc.cameras.length);
		for (c in doc.cameras) {
			o.writeByte(c.perspective ? 1 : 0);
			o.writeFloat(c.perspective ? c.yfov : 2 * c.ymag);
			o.writeFloat(c.znear);
			o.writeFloat(c.zfar > 0 ? c.zfar : 1000);
		}
		// (the scene's nodes, parents first, each with its parent's index in this list)
		var order:Array<Int> = [], parentOf:Array<Int> = [];
		function visit(k:Int, parent:Int) {
			order.push(k);
			parentOf.push(parent);
			var me = order.length - 1;
			for (c in doc.nodes[k].children)
				visit(c, me);
		}
		for (r in doc.roots(scene != null ? scene : -1))
			visit(r, -1);
		o.writeInt32(order.length);
		for (i in 0...order.length) {
			var g = doc.nodes[order[i]];
			str(g.name);
			o.writeInt32(parentOf[i]);
			o.writeInt32(g.mesh);
			o.writeInt32(g.camera);
			var t = g.translation, r = g.rotation, s = g.scale;
			if (g.matrix != null) {
				var m = g.matrix;
				var d = MathTools.decompose(new hxmc.gfx.shader.Mat4(new hxmc.gfx.shader.Vec4(m[0], m[1], m[2], m[3]),
					new hxmc.gfx.shader.Vec4(m[4], m[5], m[6], m[7]), new hxmc.gfx.shader.Vec4(m[8], m[9], m[10], m[11]),
					new hxmc.gfx.shader.Vec4(m[12], m[13], m[14], m[15])));
				t = d.t;
				r = d.r;
				s = d.s;
			}
			for (x in [t.x, t.y, t.z, r.x, r.y, r.z, r.w, s.x, s.y, s.z])
				o.writeFloat(x);
		}
		var s = scene != null ? scene : doc.scene;
		str(s >= 0 && s < doc.scenes.length ? doc.scenes[s].name : "gltf");
		return o.getBytes();
	}
}
