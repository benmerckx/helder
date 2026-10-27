import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The instances' shaders (Instances.hx): the vertex's corner comes from the
// shape's vertex buffer, the rest from the instance buffer (its layout says
// which attribute steps per instance: Instances.layout); each instance is
// the shape turned, scaled and moved, in its colour, shaded towards its rim.
@:structInit @:publicFields class InstanceVertex {
	var corner:Vec2; // per vertex: the shape's corner
	var at:Vec2; // the rest per instance: its centre
	var size:Float;
	var angle:Float; // radians
	var color:Vec3;
}

@:structInit @:publicFields class InstanceVaryings {
	@:position var pos:Vec4;
	var color:Vec3;
	var corner:Vec2;
}

@:structInit @:publicFields class InstanceField {
	var scale:Vec2; // the field's units to clip space (square units)
	var time:Float; // turns every instance by as many radians
}

class InstancesShader implements Shaders {
	@:vertex static function vs(v:InstanceVertex, f:InstanceField):InstanceVaryings {
		var a = v.angle + f.time;
		var c = cos(a), s = sin(a);
		var p = vec2(v.corner.x * c - v.corner.y * s, v.corner.x * s + v.corner.y * c) * v.size + v.at;
		return {pos: vec4(p * f.scale, 0, 1), color: v.color, corner: v.corner};
	}

	@:fragment static function fs(i:InstanceVaryings):Vec4
		return vec4(i.color * (1 - 0.3 * length(i.corner)), 1);
}
