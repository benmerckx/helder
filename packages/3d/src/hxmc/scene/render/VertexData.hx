package hxmc.scene.render;

import haxe.io.Bytes;
import hxmc.scene.math.Aabb;

// A primitive's vertices and indices in the renderer's layout, made from
// arrays (Mesh.add at run time, the asset step's packer at build time:
// one implementation, free of the GPU so that it runs on Eval): 32 bytes a
// vertex (position, normal, uv), 64 with joints and weights (skinned);
// indices of 16 bits where the vertices allow, else 32.
class VertexData {
	public final vertices:Bytes;
	public final indices:Bytes;
	public final wide:Bool;
	public final count:Int;
	public final skinned:Bool;
	public final bounds:Aabb;

	public function new(vertices:Bytes, indices:Bytes, wide:Bool, count:Int, skinned:Bool, bounds:Aabb) {
		this.vertices = vertices;
		this.indices = indices;
		this.wide = wide;
		this.count = count;
		this.skinned = skinned;
		this.bounds = bounds;
	}

	// normals null: computed from the triangles (smooth where vertices are
	// shared); indices null: 0, 1, 2, ...
	public static function make(positions:Array<Float>, normals:Null<Array<Float>>, uvs:Null<Array<Float>>, indices:Null<Array<Int>>,
			?joints:Array<Float>, ?weights:Array<Float>):VertexData {
		var n = Std.int(positions.length / 3);
		if (indices == null) indices = [for (i in 0...n) i];
		if (normals == null) normals = smoothNormals(positions, indices);
		var skinned = joints != null && weights != null, stride = skinned ? 64 : 32;
		var v = Bytes.alloc(n * stride);
		for (i in 0...n) {
			var p = stride * i;
			for (k in 0...3) {
				v.setFloat(p + 4 * k, positions[3 * i + k]);
				v.setFloat(p + 12 + 4 * k, normals[3 * i + k]);
			}
			v.setFloat(p + 24, uvs != null ? uvs[2 * i] : 0);
			v.setFloat(p + 28, uvs != null ? uvs[2 * i + 1] : 0);
			if (skinned)
				for (k in 0...4) {
					v.setFloat(p + 32 + 4 * k, joints[4 * i + k]);
					v.setFloat(p + 48 + 4 * k, weights[4 * i + k]);
				}
		}
		var wide = n > 65535;
		var ib = Bytes.alloc(indices.length * (wide ? 4 : 2));
		for (k in 0...indices.length)
			if (wide) ib.setInt32(4 * k, indices[k]) else ib.setUInt16(2 * k, indices[k]);
		return new VertexData(v, ib, wide, indices.length, skinned, Aabb.ofPoints(positions));
	}

	// each vertex's normal: the sum of its triangles' (area-weighted), normalized
	public static function smoothNormals(positions:Array<Float>, indices:Array<Int>):Array<Float> {
		var out = [for (_ in 0...positions.length) 0.0];
		var t = 0;
		while (t + 2 < indices.length) {
			var a = 3 * indices[t], b = 3 * indices[t + 1], c = 3 * indices[t + 2];
			var ux = positions[b] - positions[a], uy = positions[b + 1] - positions[a + 1], uz = positions[b + 2] - positions[a + 2];
			var vx = positions[c] - positions[a], vy = positions[c + 1] - positions[a + 1], vz = positions[c + 2] - positions[a + 2];
			var nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
			for (k in [a, b, c]) {
				out[k] += nx;
				out[k + 1] += ny;
				out[k + 2] += nz;
			}
			t += 3;
		}
		var i = 0;
		while (i < out.length) {
			var l = Math.sqrt(out[i] * out[i] + out[i + 1] * out[i + 1] + out[i + 2] * out[i + 2]);
			if (l > 0) {
				out[i] /= l;
				out[i + 1] /= l;
				out[i + 2] /= l;
			} else
				out[i + 1] = 1;
			i += 3;
		}
		return out;
	}
}
