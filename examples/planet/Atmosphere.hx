
import AtmosphereShader;
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.render.Renderer;
import helder.scene.render.Renderer.FrameInfo;

// A planet's air, physically based (AtmosphereShader), ported from
// Expansion's app.Atmosphere (benmerckx/expansion), the example's own code
// (helder's renderer gives it an injection point, nothing more): Rayleigh's and
// Mie's scattering and ozone's absorption in a shell about the sphere, lit
// by the renderer's sun; the limb glowing (bright past 1 in HDR: it
// blooms), the sunrise's and sunset's colours along the terminator, a
// halo about the sun behind the limb. Each frame the program adds its
// planets (add: centre, radius, preset); one instanced draw after the
// opaque surfaces. The sun's transmittance through the
// shell is a LUT (Hillaire's: LUT_W cosines by LUT_H heights, one band
// for each preset), made on the CPU the first time a preset is drawn.
// The march's steps: 8 by default (Expansion's tiers: Low 4, Medium 8, High 16).
class Atmosphere {
	public static inline var LUT_W = 250;
	public static inline var LUT_H = 64;
	// (the transmittance's own march, for the LUT)
	static inline var LUT_STEPS = 24;
	static inline var STRIDE = 96;

	// the air's look: in km for a planet of radius km (scaled to the
	// sphere drawn), per km the coefficients (Rayleigh's scattering,
	// Mie's scattering and extinction, ozone's absorption), the scale
	// heights, Mie's g (its forward halo), ozone's height, the sun's
	// intensity (times the renderer's sun colour)
	public static final EARTH:Preset = {
		name: "earth", radius: 700, height: 70, rayleigh: new Vec3(0.0058, 0.0135, 0.0331), rayleighHeight: 8, mie: 0.003, mieExt: 0.0033,
		mieHeight: 1.2, g: 0.8, ozone: new Vec3(0.00065, 0.00188, 0.00008), ozoneHeight: 25, intensity: 4
	};
	// (Mars's: a dusty orange sky, its sunset blue about the sun)
	public static final MARS:Preset = {
		name: "mars", radius: 700, height: 70, rayleigh: new Vec3(0.019, 0.013, 0.0057), rayleighHeight: 11.1, mie: 0.02, mieExt: 0.022,
		mieHeight: 1.5, g: 0.65, ozone: new Vec3(0, 0, 0), ozoneHeight: 0, intensity: 3.5
	};
	// (thick and toxic: green-teal, red absorbed low down, hazy)
	public static final TOXIC:Preset = {
		name: "toxic", radius: 700, height: 70, rayleigh: new Vec3(0.0045, 0.019, 0.0145), rayleighHeight: 10, mie: 0.009, mieExt: 0.014,
		mieHeight: 2.2, g: 0.72, ozone: new Vec3(0.0032, 0.0002, 0.0011), ozoneHeight: 14, intensity: 3.5
	};
	// (an ice world's: thin, pale, a white-blue haze of fine crystals)
	public static final ICE:Preset = {
		name: "ice", radius: 700, height: 70, rayleigh: new Vec3(0.0085, 0.0125, 0.0185), rayleighHeight: 9, mie: 0.007, mieExt: 0.0075,
		mieHeight: 1.8, g: 0.86, ozone: new Vec3(0.0002, 0.0004, 0.0001), ozoneHeight: 22, intensity: 3.5
	};
	// (violet: red and blue scattered, green taken by its haze)
	public static final VIOLET:Preset = {
		name: "violet", radius: 700, height: 70, rayleigh: new Vec3(0.0135, 0.006, 0.026), rayleighHeight: 9, mie: 0.004, mieExt: 0.0045,
		mieHeight: 1.4, g: 0.78, ozone: new Vec3(0.0003, 0.0016, 0.0002), ozoneHeight: 20, intensity: 3.5
	};
	public static final PRESETS = [EARTH, MARS, TOXIC, ICE, VIOLET];

	final device:Device;
	final renderer:Renderer;
	final pipeline:Pipeline;
	final hdr:Bool;
	// the march's steps (the tier's)
	public final steps:Int;
	// how much of each preset's light
	public var gain = 1.0;
	final sphere:Buffer;
	final sphereIndices:Buffer;
	final sphereCount:Int;
	final lut:Texture;
	final sampler:Sampler;
	final made = [for (_ in PRESETS) false];
	final view = Bytes.alloc(AtmosphereShader.uniforms[0].size);
	var data = Bytes.alloc(STRIDE * 16);
	var instances:Buffer = Buffer.NONE;
	var capacity = 0;
	var count = 0;

	static final LAYOUT:Array<VertexBufferLayout> = [
		{stride: 12, attributes: [{location: 0, format: Float3, offset: 0}]},
		{
			stride: STRIDE,
			step: Instance,
			attributes: [
				{location: 1, format: Float4, offset: 0}, {location: 2, format: Float4, offset: 16}, {location: 3, format: Float4, offset: 32},
				{location: 4, format: Float4, offset: 48}, {location: 5, format: Float4, offset: 64}, {location: 6, format: Float4, offset: 80}
			]
		}
	];

	public function new(renderer:Renderer, steps = 8) {
		this.renderer = renderer;
		device = renderer.device;
		hdr = renderer.hdr;
		this.steps = steps;
		var d = AtmosphereShader.pipeline({blend: Premultiplied, depthCompare: Less, depthWrite: false, cull: Back});
		d.layout = LAYOUT;
		pipeline = renderer.createPipeline(d);
		// (a unit sphere: its outward faces counter-clockwise, as Shapes.sphere's)
		var segments = 48, rings = 24;
		var p = Bytes.alloc((rings + 1) * (segments + 1) * 12), idx:Array<Int> = [];
		for (r in 0...rings + 1) {
			var th = Math.PI * r / rings;
			for (s in 0...segments + 1) {
				var ph = 2 * Math.PI * s / segments, o = (r * (segments + 1) + s) * 12;
				p.setFloat(o, Math.sin(th) * Math.cos(ph));
				p.setFloat(o + 4, Math.cos(th));
				p.setFloat(o + 8, -Math.sin(th) * Math.sin(ph));
			}
		}
		for (r in 0...rings)
			for (s in 0...segments) {
				var a = r * (segments + 1) + s, b = a + segments + 1;
				if (r > 0) for (k in [a, b, a + 1]) idx.push(k);
				if (r < rings - 1) for (k in [a + 1, b, b + 1]) idx.push(k);
			}
		var ib = Bytes.alloc(idx.length * 2);
		for (k in 0...idx.length)
			ib.setUInt16(k * 2, idx[k]);
		sphere = device.createBuffer({size: p.length, usage: Vertex, data: p});
		sphereIndices = device.createBuffer({size: ib.length, usage: Index, data: ib});
		sphereCount = idx.length;
		lut = device.createTexture({width: LUT_W, height: LUT_H * PRESETS.length, format: RGBA8});
		sampler = device.createSampler({filter: Linear, wrap: Clamp});
		renderer.inject(AfterOpaque, (enc, frame) -> draw(enc, frame));
	}

	public function clear()
		count = 0;

	// a planet's air this frame: its centre and radius (world units), its
	// look, its surface's mean colour (linear: the sun reddened on it
	// along the terminator), how much of it (0 to 1: fading in)
	public function add(center:Vec3, radius:Float, preset:Preset, ground:Vec3, strength = 1.0) {
		var band = PRESETS.indexOf(preset);
		if (band < 0 || strength <= 0) return;
		if (!made[band]) {
			made[band] = true;
			device.writeTexture(lut, transmittance(preset), 0, band * LUT_H, LUT_W, LUT_H);
		}
		if ((count + 1) * STRIDE > data.length) {
			var more = Bytes.alloc(data.length * 2);
			more.blit(0, data, 0, data.length);
			data = more;
		}
		var o = count++ * STRIDE, k = preset.radius;
		var f = [
			center.x, center.y, center.z, radius,
			preset.rayleigh.x * k, preset.rayleigh.y * k, preset.rayleigh.z * k, 1 + preset.height / k,
			preset.ozone.x * k, preset.ozone.y * k, preset.ozone.z * k, preset.mie * k,
			preset.mieExt * k, preset.g, preset.rayleighHeight / k, preset.mieHeight / k,
			band, preset.intensity * gain, strength, preset.ozoneHeight / k,
			ground.x, ground.y, ground.z, 0
		];
		for (j in 0...24)
			data.setFloat(o + j * 4, f[j]);
	}

	// the sun's transmittance through a preset's shell (Hillaire's LUT):
	// x the cosine of the sun's angle from the zenith (-1 to 1), y the
	// height (the ground to the shell's top), its rows from the ground up;
	// 0 where the ground is in the way; each channel its square root, in 8
	// bits (AtmosphereShader.sunlight)
	public static function transmittance(p:Preset):Bytes {
		var out = Bytes.alloc(LUT_W * LUT_H * 4);
		var k = p.radius, top = 1 + p.height / k;
		var br = p.rayleigh.x * k, bg = p.rayleigh.y * k, bb = p.rayleigh.z * k;
		var me = p.mieExt * k, hr = p.rayleighHeight / k, hm = p.mieHeight / k, oz = p.ozoneHeight / k;
		var ox = p.ozone.x * k, oy = p.ozone.y * k, ozz = p.ozone.z * k;
		for (y in 0...LUT_H) {
			var r = 1 + y / (LUT_H - 1) * (top - 1);
			for (x in 0...LUT_W) {
				var mu = x / (LUT_W - 1) * 2 - 1, o = (y * LUT_W + x) * 4;
				// (the ground: ahead and in the way; ozone's tent as AtmosphereShader.ozone's)
				var b = r * mu, disc = b * b - (r * r - 1);
				if (disc >= 0 && -b - Math.sqrt(disc) > 0) {
					out.setInt32(o, 0xff000000);
					continue;
				}
				var t = -b + Math.sqrt(Math.max(0, b * b - (r * r - top * top))), dt = t / LUT_STEPS;
				var tr = 0.0, tg = 0.0, tb = 0.0;
				for (s in 0...LUT_STEPS) {
					var u = (s + 0.5) * dt, h = Math.sqrt(r * r + 2 * r * mu * u + u * u) - 1;
					var dr = Math.exp(-h / hr), dm = Math.exp(-h / hm), dz = oz <= 0 ? 0.0 : Math.max(0, 1 - Math.abs(h - oz) / oz);
					tr += (br * dr + me * dm + ox * dz) * dt;
					tg += (bg * dr + me * dm + oy * dz) * dt;
					tb += (bb * dr + me * dm + ozz * dz) * dt;
				}
				out.set(o, Math.round(Math.sqrt(Math.exp(-tr)) * 255));
				out.set(o + 1, Math.round(Math.sqrt(Math.exp(-tg)) * 255));
				out.set(o + 2, Math.round(Math.sqrt(Math.exp(-tb)) * 255));
				out.set(o + 3, 255);
			}
		}
		return out;
	}

	function draw(enc:Encoder, frame:FrameInfo) {
		if (count == 0 || frame.camera == null) return;
		var l = frame.toLight, e = frame.eye, s = renderer.sunColor;
		AtmosphereShader.writeAirView({
			viewProj: frame.viewProj,
			eye: new Vec4(e.x, e.y, e.z, renderer.exposure),
			light: new Vec4(l.x, l.y, l.z, steps),
			sun: new Vec4(s.x, s.y, s.z, hdr ? 1 : 0),
			lut: new Vec4(PRESETS.length, LUT_W, LUT_H, 0)
		}, view);
		if (count * STRIDE > capacity) {
			if (capacity > 0) device.destroyBuffer(instances);
			capacity = data.length;
			instances = device.createBuffer({size: capacity, usage: Vertex});
		}
		device.writeBuffer(instances, 0, data, 0, count * STRIDE);
		enc.setPipeline(pipeline);
		enc.setUniforms(AtmosphereShader.uniforms[0].binding, view);
		enc.setTexture(AtmosphereShader.textures[0].binding, lut, sampler);
		enc.setVertexBuffer(0, sphere);
		enc.setVertexBuffer(1, instances);
		enc.setIndexBuffer(sphereIndices, UInt16);
		enc.drawIndexed(sphereCount, count);
	}

}

typedef Preset = {
	name:String,
	radius:Float,
	height:Float,
	rayleigh:Vec3,
	rayleighHeight:Float,
	mie:Float,
	mieExt:Float,
	mieHeight:Float,
	g:Float,
	ozone:Vec3,
	ozoneHeight:Float,
	intensity:Float
}
