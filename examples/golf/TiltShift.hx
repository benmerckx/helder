import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrShader.aces;
import helder.scene.render.PbrShader.encode;
import helder.scene.render.PostProcess;
import helder.scene.render.PostStage;

// The diorama's lens: a tilt-shift depth of field in screen space. A band
// across the frame stays sharp (the game keeps the ball, the cup and the
// aim's first bounce in it); above and below it the picture softens,
// gently, to at most STRENGTH's blur at the frame's top and bottom.
//
// The blur is made at half the frame's size from the scene's own light
// (the post chain's source: the <Scene>'s RGBA16F target, before bloom and
// the tone curve, so bright specks spread as discs), in the stage's
// prepare (three passes at a quarter of the pixels: down, across, down the
// columns), its radius growing with the distance from the band. The stage
// itself (post.add, after the grade) then mixes it into the finished frame:
// the blurred light graded as the chain grades it, less the sharp light
// graded the same way, added to the frame, so bloom, vignette and grade
// stay as the chain made them. The scene's alpha (its coverage over the
// CSS sky behind it) is blurred with its colour (premultiplied), so the
// islands' edges soften into the sky with no halo. The HUD is ui's, over
// the scene: never blurred.
//
// Without depth (the <Scene>'s is multisampled, and the post chain is
// given none) the band is the screen's, not the world's: a far
// island inside the band stays sharp. Without half floats (no post chain)
// there is no blur.
@:structInit @:publicFields class TiltVertex {
	var pos:Vec2;
}

@:structInit @:publicFields class TiltVaryings {
	var clip:Vec4;
	var uv:Vec2;
}

@:structInit @:publicFields class TiltBlur {
	var step:Vec4; // xy: a texel of the source along the blur's axis (uv), z: the most radius (texels)
	var band:Vec4; // x, y: the sharp band's top and bottom (uv y, 0 the top), z: the falloff (uv), w: the strength (0..1)
}

@:structInit @:publicFields class TiltGrade {
	var band:Vec4; // as TiltBlur's
	var grade:Vec4; // x: saturation, y: contrast, z: vignette, w: exposure (the chain's)
	var lift:Vec4; // rgb: the chain's lift; w: the scene's share beside bloom
	var gain:Vec4; // rgb: the chain's gain; w: the frame's aspect
}

function tiltFull(v:TiltVertex):TiltVaryings
	return {clip: position(vec4(v.pos, 0, 1)), uv: vec2(v.pos.x * 0.5 + 0.5, 0.5 - v.pos.y * 0.5)};

// (how blurred a row is: 0 in the band, the strength at the falloff's end)
function tiltAmount(band:Vec4, y:Float):Float
	return band.w * smoothstep(0, band.z, max(band.x - y, y - band.y));

// (light graded as PostProcess's composite grades it, bloom left out:
// display values; asChain, as the chain does it, the premultiplied colour
// graded as it is (so the frame's own pixels cancel exactly, its edges'
// too); else unpremultiplied, graded, premultiplied again: a soft edge's
// colour graded as the colour it is, not as a darker one, so no bright rim)
function tiltTone(c:Vec4, t:TiltGrade, uv:Vec2, asChain:Float):Vec4 {
	var a = clamp(c.w, 0, 1);
	var hdr = clamp(mix(c.xyz / max(a, 0.004), c.xyz, asChain), 0, 65000) * (t.grade.w * t.lift.w);
	var mapped = encode(aces(hdr));
	var y = dot(mapped, vec3(0.2126, 0.7152, 0.0722));
	mapped = mix(vec3(y), mapped, t.grade.x);
	mapped = (mapped - 0.5) * t.grade.y + 0.5;
	mapped = clamp(mapped * t.gain.xyz + t.lift.xyz * (1 - mapped), 0, 1);
	var at = (uv - 0.5) * vec2(t.gain.w, 1);
	var r = length(at) / length(vec2(t.gain.w, 1) * 0.5);
	mapped *= 1 - t.grade.z * smoothstep(0.35, 1.05, r);
	var chain = vec4(mapped, clamp(max(a, max(mapped.x, max(mapped.y, mapped.z))), 0, 1));
	return mix(vec4(mapped * a, a), chain, asChain);
}

// the scene's light at half size (a bilinear tap between four texels: their mean)
final TiltDownShader = shader({
	vertex: function(v:TiltVertex):TiltVaryings return tiltFull(v),
	fragment: function(i:TiltVaryings, p:{t:TiltBlur, source:Texture2D}):Vec4 {
		return clamp(sampleLevel(p.source, i.uv, 0), 0, 256);
	}
});

// a gaussian along one axis, 9 taps over its radius (the row's: none in the band)
final TiltBlurShader = shader({
	vertex: function(v:TiltVertex):TiltVaryings return tiltFull(v),
	fragment: function(i:TiltVaryings, p:{t:TiltBlur, source:Texture2D}):Vec4 {
		var k = tiltAmount(p.t.band, i.uv.y);
		var d = p.t.step.xy * (p.t.step.z * k * 0.25);
		var c = sampleLevel(p.source, i.uv, 0);
		c += (sampleLevel(p.source, i.uv + d, 0) + sampleLevel(p.source, i.uv - d, 0)) * 0.8825;
		c += (sampleLevel(p.source, i.uv + d * 2, 0) + sampleLevel(p.source, i.uv - d * 2, 0)) * 0.6065;
		c += (sampleLevel(p.source, i.uv + d * 3, 0) + sampleLevel(p.source, i.uv - d * 3, 0)) * 0.3247;
		c += (sampleLevel(p.source, i.uv + d * 4, 0) + sampleLevel(p.source, i.uv - d * 4, 0)) * 0.1353;
		return c / 4.898;
	}
});

// the post chain's stage: the finished frame, the blur's difference added where it is blurred
final TiltStageShader = shader({
	vertex: function(v:TiltVertex):TiltVaryings return tiltFull(v),
	fragment: function(i:TiltVaryings, p:{t:TiltGrade, image:Texture2D, blur:Texture2D, light:Texture2D}):Vec4 {
		var s = sampleLevel(p.image, i.uv, 0);
		var k = tiltAmount(p.t.band, i.uv.y);
		// (the half-size image only once the blur is wider than its texels)
		var m = smoothstep(0.0, 0.3, k);
		var b = tiltTone(sampleLevel(p.blur, i.uv, 0), p.t, i.uv, 0.0);
		var l = tiltTone(sampleLevel(p.light, i.uv, 0), p.t, i.uv, 1.0);
		var o = clamp(s + (b - l) * m, 0, 1);
		return vec4(o.xyz, max(o.w, max(o.x, max(o.y, o.z))));
	}
});

class TiltShift {
	// the blur's strength (1: as tuned, lighter than the mockups; 0: none):
	// the one constant to tune
	public static inline var STRENGTH = 1.0;
	// the most blur's radius at STRENGTH 1, a share of the frame's height
	static inline var RADIUS = 0.011;
	// how far past the band the blur takes to reach its most (a share of the frame's height)
	static inline var FALLOFF = 0.34;

	// off: no passes, the stage passed over (the quality switch's)
	public var enabled = true;
	// the game's ease (1 at rest, less while aiming or flying over)
	public var amount = 1.0;
	// the sharp band (0 the frame's top, 1 its bottom)
	public var top = 0.25;
	public var bottom = 0.75;

	final device:Device;
	final post:PostProcess;
	final stage:PostStage;
	final down:Pipeline;
	final blur:Pipeline;
	final triangle:Buffer;
	final linear:Sampler;
	final blurBytes = Bytes.alloc(TiltBlurShader.uniforms[0].size);
	final stageBytes = Bytes.alloc(TiltStageShader.uniforms[0].size);
	final passA:PassDesc = {colors: [{load: Clear, clear: new Color(0, 0, 0, 0)}]};
	final passB:PassDesc = {colors: [{load: Clear, clear: new Color(0, 0, 0, 0)}]};
	var halfA:Null<Texture> = null;
	var halfB:Null<Texture> = null;
	var hw = 0;
	var hh = 0;

	public function new(post:PostProcess) {
		device = post.device;
		this.post = post;
		var d = TiltDownShader.pipeline({});
		d.colorFormat = RGBA16F;
		down = device.createPipeline(d);
		var b = TiltBlurShader.pipeline({});
		b.colorFormat = RGBA16F;
		blur = device.createPipeline(b);
		var v = TiltDownShader.vertexBytes([{pos: new Vec2(-1, -1)}, {pos: new Vec2(3, -1)}, {pos: new Vec2(-1, 3)}]);
		triangle = device.createBuffer({size: v.length, usage: Vertex, data: v});
		linear = device.createSampler({filter: Linear, wrap: Clamp});
		stage = post.add(TiltStageShader, stageBytes);
		var blurSlot = TiltStageShader.textures[1].binding, lightSlot = TiltStageShader.textures[2].binding;
		stage.bind = enc -> {
			enc.setTexture(blurSlot, halfA, linear);
			enc.setTexture(lightSlot, post.source, linear);
		};
		stage.enabled = false;
		stage.prepare = prepare;
	}

	// (before the chain's passes: the half-size blur from the scene's light, the stage's parameters)
	function prepare(enc:Encoder) {
		var l = post.source, w = post.width, h = post.height;
		var k = STRENGTH * amount;
		var on = enabled && l != null && k > 0.002 && w > 1 && h > 1;
		stage.enabled = on;
		if (!on) return;
		size((w + 1) >> 1, (h + 1) >> 1);
		var band = new Vec4(top, bottom, FALLOFF, Math.min(1, k));
		var radius = RADIUS * h * 0.5 * Math.max(1, k);
		// (down: the light at half size)
		passA.colors[0].texture = halfA;
		enc.beginPass(passA);
		enc.setPipeline(down);
		TiltBlurShader.params.t.write({step: new Vec4(0, 0, 0, 0), band: band}, blurBytes);
		enc.setUniforms(TiltDownShader.uniforms[0].binding, blurBytes);
		enc.setTexture(TiltDownShader.textures[0].binding, l, linear);
		enc.setVertexBuffer(0, triangle);
		enc.draw(3);
		enc.endPass();
		// (across, then down the columns)
		for (axis in 0...2) {
			var pass = axis == 0 ? passB : passA;
			pass.colors[0].texture = axis == 0 ? halfB : halfA;
			enc.beginPass(pass);
			enc.setPipeline(blur);
			TiltBlurShader.params.t.write({step: new Vec4(axis == 0 ? 1 / hw : 0, axis == 0 ? 0 : 1 / hh, radius, 0), band: band}, blurBytes);
			enc.setUniforms(TiltBlurShader.uniforms[0].binding, blurBytes);
			enc.setTexture(TiltBlurShader.textures[0].binding, axis == 0 ? halfA : halfB, linear);
			enc.setVertexBuffer(0, triangle);
			enc.draw(3);
			enc.endPass();
		}
		passA.colors[0].texture = null;
		passB.colors[0].texture = null;
		TiltStageShader.params.t.write({
			band: band,
			grade: new Vec4(post.saturation, post.contrast, post.vignette, post.exposure),
			lift: new Vec4(post.lift.x, post.lift.y, post.lift.z, 1 - (post.bloom > 0 ? Math.min(1, post.bloom) : 0)),
			gain: new Vec4(post.gain.x, post.gain.y, post.gain.z, w / h)
		}, stageBytes);
	}

	// the two half-size targets (made again when the frame's size changes)
	function size(w:Int, h:Int) {
		if (w == hw && h == hh) return;
		if (halfA != null) device.destroyTexture(halfA);
		if (halfB != null) device.destroyTexture(halfB);
		halfA = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
		halfB = device.createTexture({width: w, height: h, format: RGBA16F, renderTarget: true});
		hw = w;
		hh = h;
	}
}
