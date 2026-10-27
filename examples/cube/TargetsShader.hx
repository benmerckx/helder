import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The render target's shaders (Targets.hx): a backdrop from the fragment's
// position (in the target's pixels from its top left, as in the frame),
// then two panels, their back faces darker.
@:structInit @:publicFields class PanelVertex {
	var pos:Vec3;
	var color:Vec3;
}

@:structInit @:publicFields class PanelVaryings {
	@:position var pos:Vec4;
	var color:Vec3;
}

@:structInit @:publicFields class PanelCamera {
	var mvp:Mat4;
}

class PanelShader implements Shaders {
	@:vertex static function vs(v:PanelVertex, cam:PanelCamera):PanelVaryings
		return {pos: cam.mvp * vec4(v.pos, 1), color: v.color};

	@:fragment static function fs(i:PanelVaryings):Vec4
		return vec4(i.color, 1);
}

@:structInit @:publicFields class FillVertex {
	var pos:Vec2; // clip space: the whole target
}

@:structInit @:publicFields class FillVaryings {
	@:position var pos:Vec4;
}

class FillShader implements Shaders {
	@:vertex static function vs(v:FillVertex):FillVaryings
		return {pos: vec4(v.pos, 0, 1)};

	// warm at the top, cool at the foot, a light band to the left (Targets.SIZE pixels square)
	@:fragment static function fs(i:FillVaryings):Vec4 {
		var p = i.pos.xy / 128;
		return vec4(mix(vec3(0.98, 0.78, 0.45), vec3(0.3, 0.55, 0.75), p.y) + 0.15 * (1 - smoothstep(0.1, 0.35, p.x)), 1);
	}
}
