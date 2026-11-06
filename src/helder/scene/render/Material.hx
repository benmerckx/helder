package helder.scene.render;

import helder.gfx.Texture;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;

// A surface of glTF's metallic-roughness model: base colour (linear,
// times the texture's sRGB colour when there is one), metallic and
// roughness from 0 to 1, emitted light (linear); double-sided ones are
// drawn without back-face culling.
class Material {
	static var count = 0;

	// the material's index (draws sort by it; an index into a material buffer later)
	public final id:Int = count++;

	public var name:String;
	public var baseColor:Vec4;
	public var metallic:Float;
	public var roughness:Float;
	public var emissive:Vec3;
	public var baseColorTexture:Null<Texture>;
	// glTF's other maps: roughness (green) and metallic (blue), times the
	// factors; emitted colour (sRGB), times emissive; ambient occlusion (red)
	public var metallicRoughnessTexture:Null<Texture>;
	public var emissiveTexture:Null<Texture>;
	public var occlusionTexture:Null<Texture>;
	// a tangent-space normal map (drawn with NormalMaps, on primitives with
	// tangents), its x and y scaled by normalScale
	public var normalTexture:Null<Texture>;
	public var normalScale = 1.0;
	public var doubleSided:Bool;
	// how its textures are read (null: the renderer's: linear, mip-mapped,
	// repeating; glTF's samplers otherwise)
	public var sampler:Null<helder.gfx.Sampler>;
	// see-through (glTF's alphaMode BLEND): blended over what is behind,
	// drawn after the opaque surfaces, farthest first, without writing depth
	public var blend = false;
	// how, when blend is on: by the base colour's alpha (Alpha), added to
	// what is behind (Additive: glows, holograms, beams), or premultiplied
	public var blending:helder.gfx.Blend = Alpha;
	// whether it casts a shadow (Shadows: its primitives drawn into the map,
	// their meshes inside the map's bounds); off for glows and glass
	public var castShadows = true;
	// how much of its light it emits only on its night side (0: all of it
	// everywhere, 1: none where the sun shines; city lights on a planet),
	// faded across the terminator
	public var emissiveNight = 0.0;
	// how much it stands on a sphere whose outward normal is its node's up
	// (local +y: a building on a planet, a tree on a globe): 1 and the sun
	// sets on it as on that ground, its direct light and rim faded across
	// the sphere's terminator, so it darkens with its planet's night side
	// (0: lit by its own faces alone)
	public var ground = 0.0;
	// the air between it and the eye (aerial perspective), with ground's
	// up: rgb its colour (linear), w how much at most, reached towards the
	// sphere's limb (where its up turns from the eye), lit by the sun over
	// that ground (0: none)
	public var air = new Vec4(0, 0, 0, 0);
	// how much it is a crystal (0 to 1): polished (roughness 0.07) and a
	// gem's reflectance, the environment's reflection and the rim light
	// strong at grazing angles (Fresnel), lit from inside by its emissive
	// colour lifted towards white, most where it faces the eye (a fake
	// subsurface), the sun through it from behind; its edges opaque, its
	// middle as see-through as its base colour's alpha with blend on
	// (Additive's an additive glass). Faceted by its normals: give its
	// facets flat ones (vertices not shared across their edges)
	public var crystal = 0.0;
	// glTF's KHR_texture_transform: the uvs its textures are read at turned
	// by uvRotation (radians), scaled by uvScale, then moved by uvOffset
	// (one transform for all of a material's textures)
	public var uvOffset = new Vec2(0, 0);
	public var uvRotation = 0.0;
	public var uvScale = new Vec2(1, 1);
	// glTF's alphaMode MASK: fragments whose alpha is below it are dropped,
	// the rest opaque (0: none)
	public var alphaCutoff = 0.0;
	// a shader of its own (MaterialShader.material: pbr with slots
	// replaced), null: the standard one; the blocks of its own, by their
	// parameters' names (its slots' parameters the standard ones are not)
	public var shader:Null<MaterialShader> = null;
	public var uniforms:Null<Map<String, haxe.io.Bytes>> = null;
	// a clear coat over the surface (KHR_materials_clearcoat): how much (0
	// to 1) and its roughness; a polished dielectric layer (f0 0.04) whose
	// reflection, from the sun and the environment, is added over the base
	// and dims it by its Fresnel
	public var clearcoat = 0.0;
	public var clearcoatRoughness = 0.0;
	// how much of the light goes through it (KHR_materials_transmission, 0
	// to 1), a thin surface without refraction: its diffuse light replaced
	// by what is behind it (drawn see-through, Premultiplied, after the
	// opaque surfaces), its reflections kept
	public var transmission = 0.0;

	public function new(?name:String, ?baseColor:Vec4, metallic = 0.0, roughness = 0.5, ?emissive:Vec3, doubleSided = false) {
		this.name = name != null ? name : "";
		this.baseColor = baseColor != null ? baseColor : new Vec4(1, 1, 1, 1);
		this.metallic = metallic;
		this.roughness = roughness;
		this.emissive = emissive != null ? emissive : new Vec3(0, 0, 0);
		this.doubleSided = doubleSided;
	}
}
