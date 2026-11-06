// helder.scene's standard material's variants (PbrShader.hx: the
// renderer's five), as pbr.ts prints TypeScript's (src/helder/scene/pbr.ts).
// (A literal below 1e-4 is printed by each runtime's Std.string: Haxe's
// macros write 1e-06 where helder's compiler writes 0.000001; written here
// as pbr.ts's)
class Pbr {
	static function main() {
		var vs:Array<helder.gfx.shader.Shader<Dynamic, Dynamic>> = [
			cast helder.scene.render.PbrShader.PbrShader,
			cast helder.scene.render.PbrNormalShader.PbrNormalShader,
			cast helder.scene.render.PbrSkinnedShader.PbrSkinnedShader,
			cast helder.scene.render.PbrInstancedShader.PbrInstancedShader,
			cast helder.scene.render.PbrInstancedNormalShader.PbrInstancedNormalShader
		];
		for (v in vs)
			Print.shader(new helder.gfx.shader.Shader<Dynamic, Dynamic>(code(v.vertexCode), code(v.fragmentCode), v.layout, v.uniforms, v.textures, null, null));
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
