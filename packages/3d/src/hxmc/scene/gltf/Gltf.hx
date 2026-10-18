package hxmc.scene.gltf;

import haxe.io.Bytes;
import hxmc.gfx.shader.Vec3;
import hxmc.gfx.shader.Vec4;
import hxmc.scene.gltf.GltfDoc;
import hxmc.scene.math.Quat;

// glTF 2.0 files read into a GltfDoc: the JSON form (.gltf: buffers as
// data: URIs, or files that resolve returns) and the binary form (.glb: a
// JSON chunk and a BIN chunk, the first buffer's bytes). The JSON is read
// once into typed data and checked (every index in range, every buffer
// view inside its buffer, every accessor inside its view), so nothing
// after parse sees Dynamic or reads out of bounds. Errors throw a String
// starting with "glTF: ".
class Gltf {
	// whether bytes are a .glb file
	public static inline function isGlb(b:Bytes):Bool
		return GltfFile.isGlb(b);

	// a .gltf or .glb file; resolve(uri) gives the bytes of a file it names
	// (a buffer, an image: relative to the file), null when there is none
	public static function parse(bytes:Bytes, ?resolve:String->Null<Bytes>):GltfDoc {
		var parts = GltfFile.split(bytes);
		return read(haxe.Json.parse(parts.json), parts.bin, resolve);
	}

	static function read(root:Dynamic, bin:Null<Bytes>, resolve:Null<String->Null<Bytes>>):GltfDoc {
		var doc = new GltfDoc();
		var asset = obj(root, "asset");
		if (asset == null) throw "glTF: no asset";
		var version = str(asset, "version", "");
		if (version.charAt(0) != "2") throw 'glTF: version $version';
		doc.generator = str(asset, "generator", "");
		function uriBytes(uri:String, what:String):Null<Bytes> {
			if (StringTools.startsWith(uri, "data:")) {
				var comma = uri.indexOf(",");
				if (comma < 0 || uri.lastIndexOf(";base64", comma) < 0) throw 'glTF: $what: a data URI not in base64';
				return haxe.crypto.Base64.decode(uri.substr(comma + 1));
			}
			return resolve != null ? resolve(StringTools.urlDecode(uri)) : null;
		}
		var i = 0;
		for (b in list(root, "buffers")) {
			var length = int(b, "byteLength", -1);
			if (length < 0) throw 'glTF: buffer $i: no byteLength';
			var uri = str(b, "uri", null);
			var data = if (uri == null) {
				if (i != 0 || bin == null) throw 'glTF: buffer $i: no uri and no BIN chunk';
				bin;
			} else uriBytes(uri, 'buffer $i');
			if (data == null) throw 'glTF: buffer $i: $uri not found';
			if (data.length < length) throw 'glTF: buffer $i: ${data.length} bytes, not $length';
			doc.buffers.push(data);
			i++;
		}
		i = 0;
		for (v in list(root, "bufferViews")) {
			var view:GltfBufferView = {
				buffer: index(v, "buffer", doc.buffers.length, 'bufferView $i', false),
				byteOffset: int(v, "byteOffset", 0),
				byteLength: int(v, "byteLength", -1),
				byteStride: int(v, "byteStride", 0)
			};
			if (view.byteLength < 0 || view.byteOffset < 0 || view.byteOffset + view.byteLength > doc.buffers[view.buffer].length)
				throw 'glTF: bufferView $i: out of its buffer';
			if (view.byteStride != 0 && (view.byteStride < 4 || view.byteStride > 252)) throw 'glTF: bufferView $i: byteStride ${view.byteStride}';
			doc.bufferViews.push(view);
			i++;
		}
		i = 0;
		for (a in list(root, "accessors")) {
			var type = str(a, "type", "");
			var components = switch type {
				case "SCALAR": 1;
				case "VEC2": 2;
				case "VEC3": 3;
				case "VEC4": 4;
				case "MAT2": 4;
				case "MAT3": 9;
				case "MAT4": 16;
				case t: throw 'glTF: accessor $i: type $t';
			}
			var acc:GltfAccessor = {
				bufferView: index(a, "bufferView", doc.bufferViews.length, 'accessor $i', true),
				byteOffset: int(a, "byteOffset", 0),
				componentType: int(a, "componentType", 0),
				normalized: Reflect.field(a, "normalized") == true,
				count: int(a, "count", -1),
				components: components,
				min: floats(a, "min"),
				max: floats(a, "max")
			};
			if (acc.count < 1) throw 'glTF: accessor $i: count ${acc.count}';
			if (obj(a, "sparse") != null) throw 'glTF: accessor $i: sparse accessors are not read yet';
			var size = GltfDoc.componentSize(acc.componentType);
			if (acc.bufferView >= 0) {
				var v = doc.bufferViews[acc.bufferView];
				var stride = v.byteStride > 0 ? v.byteStride : size * components;
				if (acc.byteOffset < 0 || acc.byteOffset % size != 0 || acc.byteOffset + (acc.count - 1) * stride + size * components > v.byteLength)
					throw 'glTF: accessor $i: out of its bufferView';
			}
			doc.accessors.push(acc);
			i++;
		}
		i = 0;
		for (im in list(root, "images")) {
			var uri = str(im, "uri", null);
			var view = index(im, "bufferView", doc.bufferViews.length, 'image $i', true);
			if (uri == null && view < 0) throw 'glTF: image $i: no uri and no bufferView';
			doc.images.push({
				name: str(im, "name", ""),
				mimeType: str(im, "mimeType", ""),
				bufferView: view,
				uri: uri != null ? uri : "",
				data: uri != null ? uriBytes(uri, 'image $i') : null
			});
			i++;
		}
		i = 0;
		for (s in list(root, "samplers"))
			doc.samplers.push({
				magFilter: int(s, "magFilter", 0),
				minFilter: int(s, "minFilter", 0),
				wrapS: int(s, "wrapS", 10497),
				wrapT: int(s, "wrapT", 10497)
			});
		i = 0;
		for (t in list(root, "textures")) {
			doc.textures.push({
				sampler: index(t, "sampler", doc.samplers.length, 'texture $i', true),
				source: index(t, "source", doc.images.length, 'texture $i', true)
			});
			i++;
		}
		i = 0;
		for (m in list(root, "materials")) {
			var pbr = obj(m, "pbrMetallicRoughness");
			var what = 'material $i';
			function tex(o:Dynamic, f:String):Int {
				var t = o != null ? obj(o, f) : null;
				return t == null ? -1 : index(t, "index", doc.textures.length, what, false);
			}
			var bc = floats(pbr, "baseColorFactor"), em = floats(m, "emissiveFactor");
			doc.materials.push({
				name: str(m, "name", ""),
				baseColor: bc != null && bc.length == 4 ? new Vec4(bc[0], bc[1], bc[2], bc[3]) : new Vec4(1, 1, 1, 1),
				metallic: num(pbr, "metallicFactor", 1),
				roughness: num(pbr, "roughnessFactor", 1),
				emissive: em != null && em.length == 3 ? new Vec3(em[0], em[1], em[2]) : new Vec3(0, 0, 0),
				baseColorTexture: tex(pbr, "baseColorTexture"),
				metallicRoughnessTexture: tex(pbr, "metallicRoughnessTexture"),
				normalTexture: tex(m, "normalTexture"),
				occlusionTexture: tex(m, "occlusionTexture"),
				emissiveTexture: tex(m, "emissiveTexture"),
				alphaMode: str(m, "alphaMode", "OPAQUE"),
				alphaCutoff: num(m, "alphaCutoff", 0.5),
				doubleSided: Reflect.field(m, "doubleSided") == true
			});
			i++;
		}
		i = 0;
		for (m in list(root, "meshes")) {
			var prims = [];
			var what = 'mesh $i';
			for (p in list(m, "primitives")) {
				var at = obj(p, "attributes");
				if (at == null) throw 'glTF: $what: a primitive without attributes';
				var n = doc.accessors.length;
				var prim:GltfPrimitive = {
					position: index(at, "POSITION", n, what, true),
					normal: index(at, "NORMAL", n, what, true),
					texcoord: index(at, "TEXCOORD_0", n, what, true),
					tangent: index(at, "TANGENT", n, what, true),
					color: index(at, "COLOR_0", n, what, true),
					indices: index(p, "indices", n, what, true),
					material: index(p, "material", doc.materials.length, what, true),
					mode: int(p, "mode", 4)
				};
				if (prim.position >= 0 && doc.accessors[prim.position].components != 3) throw 'glTF: $what: POSITION not VEC3';
				if (prim.normal >= 0 && doc.accessors[prim.normal].count != doc.accessors[prim.position].count) throw 'glTF: $what: NORMAL count';
				if (prim.indices >= 0) {
					var count = prim.position >= 0 ? doc.accessors[prim.position].count : 0;
					for (k in doc.indices(prim.indices))
						if (k < 0 || k >= count) throw 'glTF: $what: index $k out of its vertices';
				}
				prims.push(prim);
			}
			doc.meshes.push({name: str(m, "name", ""), primitives: prims});
			i++;
		}
		i = 0;
		for (c in list(root, "cameras")) {
			var type = str(c, "type", "");
			var p = obj(c, "perspective"), o = obj(c, "orthographic");
			if (type == "perspective" && p == null || type == "orthographic" && o == null || type != "perspective" && type != "orthographic")
				throw 'glTF: camera $i: type $type';
			doc.cameras.push({
				name: str(c, "name", ""),
				perspective: type == "perspective",
				yfov: num(p, "yfov", 0.8),
				aspect: num(p, "aspectRatio", 0),
				znear: num(p != null ? p : o, "znear", 0.1),
				zfar: num(p != null ? p : o, "zfar", 0),
				xmag: num(o, "xmag", 1),
				ymag: num(o, "ymag", 1)
			});
			i++;
		}
		var nodes = list(root, "nodes");
		i = 0;
		for (n in nodes) {
			var what = 'node $i';
			var t = floats(n, "translation"), r = floats(n, "rotation"), s = floats(n, "scale"), m = floats(n, "matrix");
			if (m != null && m.length != 16) throw 'glTF: $what: a matrix of ${m.length} values';
			var children = [for (c in list(n, "children")) checked(c, nodes.length, what)];
			doc.nodes.push({
				name: str(n, "name", ""),
				children: children,
				mesh: index(n, "mesh", doc.meshes.length, what, true),
				camera: index(n, "camera", doc.cameras.length, what, true),
				translation: t != null && t.length == 3 ? new Vec3(t[0], t[1], t[2]) : new Vec3(0, 0, 0),
				rotation: r != null && r.length == 4 ? new Quat(r[0], r[1], r[2], r[3]) : Quat.identity(),
				scale: s != null && s.length == 3 ? new Vec3(s[0], s[1], s[2]) : new Vec3(1, 1, 1),
				matrix: m
			});
			i++;
		}
		// (a node has one parent at most, and no node is its own ancestor)
		var parent = [for (_ in 0...doc.nodes.length) -1];
		for (k in 0...doc.nodes.length)
			for (c in doc.nodes[k].children) {
				if (parent[c] >= 0) throw 'glTF: node $c: two parents';
				parent[c] = k;
			}
		for (k in 0...doc.nodes.length) {
			var p = parent[k], steps = 0;
			while (p >= 0) {
				if (p == k || ++steps > doc.nodes.length) throw 'glTF: node $k: a cycle';
				p = parent[p];
			}
		}
		i = 0;
		for (s in list(root, "scenes")) {
			var ns = [for (n in list(s, "nodes")) checked(n, doc.nodes.length, 'scene $i')];
			for (n in ns)
				if (parent[n] >= 0) throw 'glTF: scene $i: node $n is not a root';
			doc.scenes.push({name: str(s, "name", ""), nodes: ns});
			i++;
		}
		doc.scene = index(root, "scene", doc.scenes.length, "the document", true);
		return doc;
	}

	// (the JSON's values, read with their defaults)

	static function obj(o:Dynamic, f:String):Dynamic {
		if (o == null) return null;
		var v:Dynamic = Reflect.field(o, f);
		return Reflect.isObject(v) && !Std.isOfType(v, String) && !Std.isOfType(v, Array) ? v : null;
	}

	static function list(o:Dynamic, f:String):Array<Dynamic> {
		var v:Dynamic = o == null ? null : Reflect.field(o, f);
		return Std.isOfType(v, Array) ? (v : Array<Dynamic>) : [];
	}

	static function str(o:Dynamic, f:String, def:String):String {
		var v:Dynamic = o == null ? null : Reflect.field(o, f);
		return Std.isOfType(v, String) ? (v : String) : def;
	}

	static function num(o:Dynamic, f:String, def:Float):Float {
		var v:Dynamic = o == null ? null : Reflect.field(o, f);
		return Std.isOfType(v, Float) || Std.isOfType(v, Int) ? (v : Float) : def;
	}

	static function int(o:Dynamic, f:String, def:Int):Int {
		var v:Dynamic = o == null ? null : Reflect.field(o, f);
		if (Std.isOfType(v, Int)) return (v : Int);
		if (Std.isOfType(v, Float)) {
			var x:Float = v;
			if (x == Math.ffloor(x) && Math.abs(x) < 2147483648.0) return Std.int(x);
		}
		return def;
	}

	static function floats(o:Dynamic, f:String):Null<Array<Float>> {
		var v:Dynamic = o == null ? null : Reflect.field(o, f);
		if (!Std.isOfType(v, Array)) return null;
		return [for (x in (v : Array<Dynamic>)) Std.isOfType(x, Float) || Std.isOfType(x, Int) ? (x : Float) : throw 'glTF: $f: not a number'];
	}

	// an index into a list of n, -1 when absent and optional
	static function index(o:Dynamic, f:String, n:Int, what:String, optional:Bool):Int {
		var v:Dynamic = o == null ? null : Reflect.field(o, f);
		if (v == null) {
			if (optional) return -1;
			throw 'glTF: $what: no $f';
		}
		var k = int(o, f, -1);
		if (k < 0 || k >= n) throw 'glTF: $what: $f $k out of range';
		return k;
	}

	static function checked(v:Dynamic, n:Int, what:String):Int {
		var k = Std.isOfType(v, Int) ? (v : Int) : -1;
		if (k < 0 || k >= n) throw 'glTF: $what: node $v out of range';
		return k;
	}
}
