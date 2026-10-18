package hxmc.scene.render;

import haxe.io.Bytes;
import hxmc.gfx.Buffer;
import hxmc.gfx.Device;
import hxmc.gfx.IndexFormat;
import hxmc.scene.math.Aabb;

// What a node draws (node.mesh): primitives, each a vertex buffer in the
// renderer's layout (PbrVertex: position, normal, uv; 32 bytes a vertex),
// triangles' indices and a material, and the bounds of them all.
class Mesh {
	public var primitives(default, null):Array<Primitive> = [];
	public var bounds(default, null):Aabb = Aabb.empty();

	public function new() {}

	// a primitive from positions, normals and uvs (x, y, z / u, v per
	// vertex; normals null: computed from the triangles, smooth where
	// vertices are shared) and triangles' indices (null: 0, 1, 2, ...)
	public function add(device:Device, positions:Array<Float>, normals:Null<Array<Float>>, uvs:Null<Array<Float>>, indices:Null<Array<Int>>,
			material:Material):Primitive {
		var n = Std.int(positions.length / 3);
		if (indices == null) indices = [for (i in 0...n) i];
		if (normals == null) normals = smoothNormals(positions, indices);
		var v = Bytes.alloc(n * 32);
		for (i in 0...n) {
			var p = 32 * i;
			for (k in 0...3) {
				v.setFloat(p + 4 * k, positions[3 * i + k]);
				v.setFloat(p + 12 + 4 * k, normals[3 * i + k]);
			}
			v.setFloat(p + 24, uvs != null ? uvs[2 * i] : 0);
			v.setFloat(p + 28, uvs != null ? uvs[2 * i + 1] : 0);
		}
		var wide = n > 65535;
		var ib = Bytes.alloc(indices.length * (wide ? 4 : 2));
		for (k in 0...indices.length)
			if (wide) ib.setInt32(4 * k, indices[k]) else ib.setUInt16(2 * k, indices[k]);
		var prim = new Primitive(device.createBuffer({size: v.length, usage: Vertex, data: v}),
			device.createBuffer({size: ib.length, usage: Index, data: ib}), wide ? UInt32 : UInt16, indices.length, material, Aabb.ofPoints(positions));
		primitives.push(prim);
		bounds = bounds.union(prim.bounds);
		return prim;
	}

	public function dispose(device:Device) {
		for (p in primitives) {
			device.destroyBuffer(p.vertices);
			device.destroyBuffer(p.indices);
		}
		primitives = [];
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

class Primitive {
	static var made = 0;

	// (draws of one primitive are batched by it)
	public final id:Int = made++;

	public final vertices:Buffer;
	public final indices:Buffer;
	public final indexFormat:IndexFormat;
	public final count:Int;
	public var material:Material;
	public final bounds:Aabb;

	public function new(vertices:Buffer, indices:Buffer, indexFormat:IndexFormat, count:Int, material:Material, bounds:Aabb) {
		this.vertices = vertices;
		this.indices = indices;
		this.indexFormat = indexFormat;
		this.count = count;
		this.material = material;
		this.bounds = bounds;
	}
}
