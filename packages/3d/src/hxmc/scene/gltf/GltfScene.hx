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
// computed where the file has none); materials' factors and textures
// (base colour, metallic-roughness, emissive, occlusion, normal: tangents from the file, else computed) (decoded by decodeImage, which the program gives); KHR_lights_punctual's lights as Light components; skins as
// Skin components on the nodes they deform (joints, inverse bind
// matrices; JOINTS_0 and WEIGHTS_0 in the meshes' vertices).
class GltfScene {
	// the image decoder, given by the program (no decoder is linked unless
	// named): mime type and bytes to RGBA8 pixels, rows top to bottom, or
	// null for a format it does not read. @hxmc/ui's:
	//   GltfScene.decodeImage = (mime, b) -> mime == "image/jpeg" ? hxmc.ui.JpegDecoder.decode(b) : hxmc.ui.PngDecoder.decode(b);
	// Without one, textures are left out (materials keep their factors).
	public static var decodeImage:Null<(String, haxe.io.Bytes) -> Null<{width:Int, height:Int, rgba:haxe.io.Bytes}>>;

	// glTF's sampler (filters and wraps: WebGL's constants) as gfx's, or null
	// where it reads as the renderer's own (linear, trilinear between mip
	// levels, repeating); wrapS and wrapT differing: wrapS's (gfx wraps both
	// directions alike)
	public static function samplerDesc(magFilter:Int, minFilter:Int, wrapS:Int, wrapT:Int):Null<hxmc.gfx.SamplerDesc> {
		var filter:hxmc.gfx.Filter = magFilter == 9728 ? Nearest : Linear;
		var mip:Null<hxmc.gfx.Filter> = switch minFilter {
			case 9728 | 9729: null; // (no mip levels)
			case 9984 | 9985: Nearest;
			default: Linear;
		}
		var wrap:hxmc.gfx.Wrap = switch wrapS {
			case 33071: Clamp;
			case 33648: Mirror;
			default: Repeat;
		}
		if (filter == Linear && mip == Linear && wrap == Repeat) return null;
		return mip == null ? {filter: filter, wrap: wrap} : {filter: filter, mipFilter: mip, wrap: wrap};
	}

	public final doc:GltfDoc;
	// the samplers made for the materials (samplerDesc)
	public final samplers:Array<hxmc.gfx.Sampler> = [];
	public final meshes:Array<Mesh> = [];
	public final materials:Array<Material>;
	// the images' textures (null: not decoded), made once
	public final textures:Array<Null<hxmc.gfx.Texture>> = [];
	final device:Device;

	public function new(doc:GltfDoc, device:Device) {
		this.doc = doc;
		this.device = device;
		for (k in 0...doc.images.length) {
			var bytes = decodeImage != null ? doc.imageBytes(k) : null;
			var image = bytes != null ? decodeImage(doc.images[k].mimeType, bytes) : null;
			if (image == null) {
				textures.push(null);
				continue;
			}
			// (sRGB colours: decoded by the shader; mip levels for minified textures)
			var t = device.createTexture({width: image.width, height: image.height, data: image.rgba, mipLevels: 0});
			device.generateMips(t);
			textures.push(t);
		}
		function textureOf(index:Int):Null<hxmc.gfx.Texture> {
			if (index < 0) return null;
			var source = doc.textures[index].source;
			return source >= 0 ? textures[source] : null;
		}
		// (glTF's samplers as gfx's, made when a material reads with one
		// that differs from the renderer's)
		var samplers = new Map<Int, hxmc.gfx.Sampler>();
		function samplerOf(index:Int):Null<hxmc.gfx.Sampler> {
			if (index < 0 || doc.textures[index].sampler < 0) return null;
			var k = doc.textures[index].sampler;
			var s = doc.samplers[k];
			var desc = samplerDesc(s.magFilter, s.minFilter, s.wrapS, s.wrapT);
			if (desc == null) return null;
			if (!samplers.exists(k)) {
				var made = device.createSampler(desc);
				samplers.set(k, made);
				this.samplers.push(made);
			}
			return samplers.get(k);
		}
		materials = [
			for (m in doc.materials) {
				var mat = new Material(m.name, m.baseColor, m.metallic, m.roughness, m.emissive, m.doubleSided);
				mat.baseColorTexture = textureOf(m.baseColorTexture);
				mat.metallicRoughnessTexture = textureOf(m.metallicRoughnessTexture);
				mat.emissiveTexture = textureOf(m.emissiveTexture);
				mat.occlusionTexture = textureOf(m.occlusionTexture);
				mat.normalTexture = textureOf(m.normalTexture);
				mat.normalScale = m.normalScale;
				// (MASK is drawn opaque for now: gfx's shaders have no discard)
				mat.blend = m.alphaMode == "BLEND";
				// (one sampler a material: its base colour's, else its first map's)
				for (t in [m.baseColorTexture, m.metallicRoughnessTexture, m.normalTexture, m.emissiveTexture, m.occlusionTexture])
					if (t >= 0) {
						mat.sampler = samplerOf(t);
						break;
					}
				mat;
			}
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
				var positions = doc.floats(p.position), normals = p.normal >= 0 ? doc.floats(p.normal) : null;
				var uvs = p.texcoord >= 0 ? doc.floats(p.texcoord) : null, indices = p.indices >= 0 ? doc.indices(p.indices) : null;
				// (tangents where a normal map is drawn, with NormalMaps made: the
				// file's, else from the uvs)
				var tangents:Null<Array<Float>> = null, make = hxmc.scene.render.VertexData.tangentsFrom;
				if (make != null && material.normalTexture != null && uvs != null && p.joints < 0) {
					if (p.tangent >= 0) tangents = doc.floats(p.tangent) else {
						if (indices == null) indices = [for (i in 0...Std.int(positions.length / 3)) i];
						if (normals == null) normals = Mesh.smoothNormals(positions, indices);
						tangents = make(positions, normals, uvs, indices);
					}
				}
				mesh.add(device, positions, normals, uvs, indices, material, p.joints >= 0 ? doc.floats(p.joints) : null,
					p.weights >= 0 ? doc.floats(p.weights) : null, tangents);
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
			// (glTF's units: lux for the sun, candela for the others)
			var range = l.range > 0 ? l.range : 1000;
			Light.attach(n, switch l.type {
				case "directional": Light.directional(l.color, l.intensity);
				case "spot": Light.spot(l.color, l.intensity, range, l.innerCone, l.outerCone);
				case _: Light.pointLight(l.color, l.intensity, range);
			});
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
	public function dispose(device:Device) {
		for (m in meshes)
			m.dispose(device);
		for (t in textures)
			if (t != null) device.destroyTexture(t);
	}
}
