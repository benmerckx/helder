import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.MaterialShader;
import helder.scene.render.PbrShader;

// The greens' turf: the standard material with its colour slot mown into
// stripes across the world's z (the holes run along it): soft-edged bands
// half a metre apart, 8% lighter and darker in linear light (3 to 4% on
// screen), felt rolled one way, then the other. Its lights, shadows and
// fog are pbr's (MaterialShader: compiled at build time into every variant).
final TurfShader = MaterialShader.material(pbr.with({
	color: function(s:PbrSurface, p:{}):Vec3 {
		var band = smoothstep(0.3, 0.7, abs(fract(s.world.z * 1.1) * 2 - 1));
		return s.baseColor.xyz * (1 + (band - 0.5) * 0.16);
	}
}));
