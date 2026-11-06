import haxe.io.Bytes;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.MaterialShader;
import helder.scene.render.PbrShader;

// examples/glow's material (MaterialShader.material(pbr.with({...}))), as
// material.ts prints TypeScript's: its five variants, its block's slots,
// its writer's bytes. (A literal below 1e-4: as Pbr.hx writes it)
typedef GlowParams = {
	var color:Vec4;
	var time:Vec4;
}

final GlowShader = MaterialShader.material(pbr.with({
	emissive: function(s:PbrSurface, p:{glow:GlowParams}):Vec3 return p.glow.color.xyz * (0.6 + 0.4 * sin(p.glow.time.x * 3 + s.world.x)),
	color: function(s:PbrSurface, p:{}):Vec3 return s.baseColor.xyz * 1.4
}));

class Material {
	static function main() {
		for (v in [GlowShader.plain, GlowShader.normalMapped, GlowShader.skinned, GlowShader.instanced, GlowShader.instancedNormalMapped])
			Print.shader(new helder.gfx.shader.Shader<Dynamic, Dynamic>(code(v.vertexCode), code(v.fragmentCode), v.layout, v.uniforms, v.textures, null, null));
		for (b in GlowShader.blocks)
			Sys.println('block ${b.name} ' + b.bindings.join(" "));
		var bytes = Bytes.alloc(32);
		GlowShader.params.glow.write({color: new Vec4(1, 0.55, 0.2, 1), time: new Vec4(2.5, 0, 0, 0)}, bytes);
		Sys.println(GlowShader.params.glow.block.binding + " " + GlowShader.params.glow.block.size + " " + [for (i in 0...32) bytes.get(i)].join(" "));
	}

	static function code(c:helder.gfx.ShaderCode):helder.gfx.ShaderCode {
		function fix(s:Null<String>):Null<String>
			return s == null ? null : StringTools.replace(s, "1e-06", "0.000001");
		return {
			glsl: fix(c.glsl),
			wgsl: fix(c.wgsl),
			msl: fix(c.msl),
			hlsl: fix(c.hlsl),
			bindings: c.bindings
		};
	}
}
