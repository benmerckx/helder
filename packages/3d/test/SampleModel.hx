import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import hxmc.gfx.shader.Vec3;
import hxmc.scene.math.MathTools;
import hxmc.scene.math.Quat;

// The sample glTF scene of packages/3d (examples/sample.glb, MIT as the
// repository), generated here: a ground, a turned pedestal carrying a
// golden ball, a moon on an orbit given as a matrix, a small tilted cube
// and a camera, four materials of the metallic-roughness model. Its data
// covers what the reader must handle: indices of 8, 16 and 32 bits,
// interleaved positions and normals (a byteStride), normalized 16-bit
// texture coordinates, a node matrix, a child hierarchy, min and max,
// animations of each interpolation (linear, step, cubic spline).
//
//   bin/hxmc/hxmc -cp packages/os/src -cp packages/gfx/src -cp packages/3d/src \
//     -cp packages/3d/test --run SampleModel packages/3d/examples/sample.glb
//
// Numbers in the JSON are written with 6 decimals, so the file is the same
// wherever it is generated; GltfTest checks it against the checked-in one.
class SampleModel {
	// the meshes' vertices, as generated (GltfTest reads them back)
	public static var groundPositions:Array<Float>;
	public static var cubePositions:Array<Float>;
	public static var spherePositions:Array<Float>;
	public static var sphereIndices:Array<Int>;

	static function main() {
		var out = Sys.args()[0];
		if (out == null) {
			Sys.println("usage: SampleModel <out.glb>");
			Sys.exit(2);
		}
		sys.io.File.saveBytes(out, glb());
		Sys.println('SampleModel: wrote $out');
	}

	// the .glb file
	public static function glb():Bytes {
		var m = build(null);
		var json = Bytes.ofString(m.json);
		var jlen = (json.length + 3) & ~3, blen = (m.bin.length + 3) & ~3;
		var o = new haxe.io.BytesOutput();
		o.writeInt32(0x46546C67);
		o.writeInt32(2);
		o.writeInt32(12 + 8 + jlen + 8 + blen);
		o.writeInt32(jlen);
		o.writeInt32(0x4E4F534A);
		o.write(json);
		for (_ in json.length...jlen)
			o.writeByte(0x20);
		o.writeInt32(blen);
		o.writeInt32(0x004E4942);
		o.write(m.bin);
		for (_ in m.bin.length...blen)
			o.writeByte(0);
		return o.getBytes();
	}

	// the .gltf form: the same, its buffer a data: URI
	public static function gltf():Bytes {
		var bin = build(null).bin;
		return Bytes.ofString(build("data:application/octet-stream;base64," + haxe.crypto.Base64.encode(bin)).json);
	}

	static function build(uri:Null<String>):{json:String, bin:Bytes} {
		var bin = new BytesBuffer();
		var views:Array<String> = [], accessors:Array<String> = [];
		function align() {
			while (bin.length % 4 != 0)
				bin.addByte(0);
		}
		function view(start:Int, stride:Int, target:Int):Int {
			views.push('{"buffer":0,"byteOffset":$start,"byteLength":${bin.length - start}' + (stride > 0 ? ',"byteStride":$stride' : "")
				+ (target > 0 ? ',"target":$target' : "") + "}");
			return views.length - 1;
		}
		function accessor(view:Int, offset:Int, type:Int, count:Int, kind:String, ?normalized:Bool, ?minmax:Array<Float>):Int {
			var s = '{"bufferView":$view,"byteOffset":$offset,"componentType":$type,"count":$count,"type":"$kind"';
			if (normalized) s += ',"normalized":true';
			if (minmax != null) {
				var b = hxmc.scene.math.Aabb.ofPoints(minmax);
				s += ',"min":[${num(b.min.x)},${num(b.min.y)},${num(b.min.z)}],"max":[${num(b.max.x)},${num(b.max.y)},${num(b.max.z)}]';
			}
			accessors.push(s + "}");
			return accessors.length - 1;
		}
		function floats(a:Array<Float>) {
			for (x in a)
				bin.addFloat(x);
		}
		// the ground: a square of 8 on y = 0; 8-bit indices
		var g = 4.0;
		groundPositions = [-g, 0, g, g, 0, g, g, 0, -g, -g, 0, -g];
		var start = bin.length;
		floats(groundPositions);
		var gPos = accessor(view(start, 0, 34962), 0, 5126, 4, "VEC3", false, groundPositions);
		start = bin.length;
		floats([0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0]);
		var gNor = accessor(view(start, 0, 34962), 0, 5126, 4, "VEC3");
		start = bin.length;
		for (i in [0, 1, 2, 0, 2, 3])
			bin.addByte(i);
		align();
		var gIdx = accessor(view(start, 0, 34963), 0, 5121, 6, "SCALAR");
		// the cube: half size 0.5, positions and normals interleaved; 16-bit indices
		var faces = [
			[[0, 0, 1], [1, 0, 0], [0, 1, 0]], [[0, 0, -1], [-1, 0, 0], [0, 1, 0]], [[1, 0, 0], [0, 0, -1], [0, 1, 0]],
			[[-1, 0, 0], [0, 0, 1], [0, 1, 0]], [[0, 1, 0], [1, 0, 0], [0, 0, -1]], [[0, -1, 0], [1, 0, 0], [0, 0, 1]]
		];
		cubePositions = [];
		var cubeNormals = [], cubeIdx = [];
		for (f in 0...6) {
			var n = faces[f][0], r = faces[f][1], u = faces[f][2];
			for (c in [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
				for (k in 0...3)
					cubePositions.push(0.5 * (n[k] + r[k] * c[0] + u[k] * c[1]));
				for (k in 0...3)
					cubeNormals.push(n[k]);
			}
			for (k in [0, 1, 2, 0, 2, 3])
				cubeIdx.push(4 * f + k);
		}
		start = bin.length;
		for (v in 0...24) {
			for (k in 0...3)
				bin.addFloat(cubePositions[3 * v + k]);
			for (k in 0...3)
				bin.addFloat(cubeNormals[3 * v + k]);
		}
		var cv = view(start, 24, 34962);
		var cPos = accessor(cv, 0, 5126, 24, "VEC3", false, cubePositions);
		var cNor = accessor(cv, 12, 5126, 24, "VEC3");
		start = bin.length;
		for (i in cubeIdx)
			{bin.addByte(i & 0xFF); bin.addByte(i >> 8);}
		align();
		var cIdx = accessor(view(start, 0, 34963), 0, 5123, 36, "SCALAR");
		// the sphere: radius 1, 24 segments and 12 rings, normalized 16-bit UVs; 32-bit indices
		var seg = 24, rings = 12;
		spherePositions = [];
		var uvs = [];
		for (r in 0...rings + 1) {
			var th = Math.PI * r / rings;
			for (s in 0...seg + 1) {
				var ph = 2 * Math.PI * s / seg;
				spherePositions.push(round6(Math.sin(th) * Math.cos(ph)));
				spherePositions.push(round6(Math.cos(th)));
				spherePositions.push(round6(-Math.sin(th) * Math.sin(ph)));
				uvs.push(Math.round(65535 * s / seg));
				uvs.push(Math.round(65535 * r / rings));
			}
		}
		sphereIndices = [];
		for (r in 0...rings)
			for (s in 0...seg) {
				var a = r * (seg + 1) + s, b = a + seg + 1;
				if (r > 0) for (k in [a, b, a + 1]) sphereIndices.push(k);
				if (r < rings - 1) for (k in [a + 1, b, b + 1]) sphereIndices.push(k);
			}
		var nv = (seg + 1) * (rings + 1);
		start = bin.length;
		floats(spherePositions);
		var sPos = accessor(view(start, 0, 34962), 0, 5126, nv, "VEC3", false, spherePositions);
		// (normals: the positions, a view read twice)
		var sNor = accessor(views.length - 1, 0, 5126, nv, "VEC3");
		start = bin.length;
		for (x in uvs)
			{bin.addByte(x & 0xFF); bin.addByte(x >> 8);}
		align();
		var sUv = accessor(view(start, 0, 34962), 0, 5123, nv, "VEC2", true);
		start = bin.length;
		for (i in sphereIndices)
			bin.addInt32(i);
		var sIdx = accessor(view(start, 0, 34963), 0, 5125, sphereIndices.length, "SCALAR");

		// animations: "spin" turns the pedestal (linear rotations), "bounce"
		// moves the ball (step translations), "pulse" scales the moon (a cubic spline)
		start = bin.length;
		floats([0, 1, 2, 3, 4]);
		var times = accessor(view(start, 0, 0), 0, 5126, 5, "SCALAR");
		start = bin.length;
		for (k in 0...5) {
			var q = Quat.axisAngle(new Vec3(0, 1, 0), 0.5 + k * Math.PI / 2);
			floats([round6(q.x), round6(q.y), round6(q.z), round6(q.w)]);
		}
		var spin = accessor(view(start, 0, 0), 0, 5126, 5, "VEC4");
		start = bin.length;
		floats([0, 1.1, 0, 0, 1.6, 0, 0, 1.1, 0, 0, 1.6, 0, 0, 1.1, 0]);
		var bounce = accessor(view(start, 0, 0), 0, 5126, 5, "VEC3");
		start = bin.length;
		for (k in 0...5) {
			var v = k % 2 == 0 ? 0.45 : 0.6;
			// (in-tangent, value, out-tangent)
			floats([0, 0, 0, v, v, v, 0, 0, 0]);
		}
		var pulse = accessor(view(start, 0, 0), 0, 5126, 15, "VEC3");
		var data = bin.getBytes();
		var mesh = (name:String, pos:Int, nor:Int, uv:Int, idx:Int, mat:Int) -> '{"name":"$name","primitives":[{"attributes":{"POSITION":$pos,"NORMAL":$nor'
			+ (uv >= 0 ? ',"TEXCOORD_0":$uv' : "") + '},"indices":$idx,"material":$mat}]}';
		var material = (name:String, c:Array<Float>, metal:Float, rough:Float) ->
			'{"name":"$name","pbrMetallicRoughness":{"baseColorFactor":[${c.map(num).join(",")}],"metallicFactor":${num(metal)},"roughnessFactor":${num(rough)}}}';
		var q = (r:Quat) -> '[${num(r.x)},${num(r.y)},${num(r.z)},${num(r.w)}]';
		var v3 = (x:Float, y:Float, z:Float) -> '[${num(x)},${num(y)},${num(z)}]';
		var orbit = MathTools.compose(new Vec3(0, 0.2, 0), Quat.axisAngle(new Vec3(0, 1, 0), 0.9), new Vec3(1, 1, 1));
		var om = [for (c in [orbit.c0, orbit.c1, orbit.c2, orbit.c3]) for (x in [c.x, c.y, c.z, c.w]) num(x)];
		var eye = new Vec3(4.2, 3.4, 5.6);
		var look = MathTools.lookRotation(new Vec3(0, 0.7, 0) - eye, new Vec3(0, 1, 0));
		var json = '{"asset":{"version":"2.0","generator":"hxmc packages/3d/test/SampleModel.hx"},"scene":0,'
			+ '"scenes":[{"name":"sample","nodes":[0,1,3,5,6]}],'
			+ '"nodes":['
			+ '{"name":"ground","mesh":0},'
			+ '{"name":"pedestal","mesh":1,"translation":${v3(0, 0.5, 0)},"rotation":${q(Quat.axisAngle(new Vec3(0, 1, 0), 0.5))},"children":[2]},'
			+ '{"name":"ball","mesh":2,"translation":${v3(0, 1.1, 0)},"scale":${v3(0.6, 0.6, 0.6)}},'
			+ '{"name":"orbit","matrix":[${om.join(",")}],"children":[4]},'
			+ '{"name":"moon","mesh":3,"translation":${v3(2.3, 0.45, 0)},"scale":${v3(0.45, 0.45, 0.45)}},'
			+ '{"name":"satellite","mesh":4,"translation":${v3(-2, 0.45, 1.3)},"rotation":${q(Quat.axisAngle(new Vec3(1, 1, 0), 0.7))},"scale":${v3(0.5, 0.5, 0.5)}},'
			+ '{"name":"camera","camera":0,"translation":${v3(eye.x, eye.y, eye.z)},"rotation":${q(look)}}'
			+ '],'
			+ '"cameras":[{"name":"view","type":"perspective","perspective":{"yfov":0.7,"znear":0.1,"zfar":100}}],'
			+ '"meshes":[${mesh("ground", gPos, gNor, -1, gIdx, 0)},${mesh("cube", cPos, cNor, -1, cIdx, 1)},${mesh("sphere", sPos, sNor, sUv, sIdx, 2)},'
			+ '${mesh("moon", sPos, sNor, sUv, sIdx, 3)},${mesh("satellite", cPos, cNor, -1, cIdx, 3)}],'
			+ '"materials":[${material("ground", [0.42, 0.45, 0.5, 1], 0, 0.85)},${material("clay", [0.95, 0.42, 0.14, 1], 0, 0.5)},'
			+ '${material("gold", [1, 0.77, 0.34, 1], 1, 0.3)},${material("blue", [0.15, 0.35, 0.9, 1], 0, 0.25)}],'
			+ '"accessors":[${accessors.join(",")}],"bufferViews":[${views.join(",")}],'
			+ '"animations":[{"name":"spin","samplers":[{"input":$times,"output":$spin}],"channels":[{"sampler":0,"target":{"node":1,"path":"rotation"}}]},'
			+ '{"name":"bounce","samplers":[{"input":$times,"output":$bounce,"interpolation":"STEP"}],"channels":[{"sampler":0,"target":{"node":2,"path":"translation"}}]},'
			+ '{"name":"pulse","samplers":[{"input":$times,"output":$pulse,"interpolation":"CUBICSPLINE"}],"channels":[{"sampler":0,"target":{"node":4,"path":"scale"}}]}],'
			+ '"buffers":[{"byteLength":${data.length}' + (uri != null ? ',"uri":"$uri"' : "") + '}]}';
		return {json: json, bin: data};
	}

	static function round6(x:Float):Float
		return Math.fround(x * 1e6) / 1e6;

	// x with 6 decimals at most, trailing zeros dropped, the same on every target
	public static function num(x:Float):String {
		var n = Math.round(Math.abs(x) * 1e6);
		var i = Std.string(Std.int(n / 1000000)), f = Std.string(1000000 + n % 1000000).substr(1);
		while (f.length > 0 && f.charAt(f.length - 1) == "0")
			f = f.substr(0, f.length - 1);
		return (x < 0 && n != 0 ? "-" : "") + i + (f.length > 0 ? "." + f : "");
	}
}
