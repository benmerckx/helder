package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrShader.output;
import helder.scene.render.PbrShader.fogAmount;

// GPU particles (GpuParticles): each particle written once, when it is
// emitted (where, how fast, when, for how long, its colour and sizes),
// and moved by this vertex shader from then on: its age the clock's time
// less its birth, its position the start plus its velocity slowed by drag
// (v (1 - e^(-k age)) / k) and gravity's pull, its size from the first to
// the last, its colour fading out (and hotter, whiter, while young: heat).
// A camera-facing quad, or with stretch one along its motion on the
// screen (a spark's or an exhaust's streak, stretch seconds of its path
// long); past its life, or before its birth, a quad of no size. Added to
// the scene behind (premultiplied blending, its coverage none in HDR),
// depth-tested, not written.
@:structInit @:publicFields class GpuParticleVertex {
	var corner:Vec2; // per vertex: -1 to 1
	var start:Vec4; // per instance: the position, w: the birth (seconds)
	var velocity:Vec4; // w: the life (seconds)
	var color:Vec4; // linear colour, w: opacity
	var shape:Vec4; // x: the first size, y: the last, z: stretch, w: heat
}

@:structInit @:publicFields class GpuParticleVaryings {
	var clip:Vec4;
	var corner:Vec2;
	var color:Vec4;
}

@:structInit @:publicFields class GpuParticleView {
	var viewProj:Mat4;
	var right:Vec4; // the camera's right in the world, w: 1 into an HDR target
	var up:Vec4; // its up, w: the time (seconds)
	var forward:Vec4; // the way it looks, w: drag (per second)
	var gravity:Vec4;
	// the fog (Fog.colorOf, shapeOf) and the eye: light added, faded by it
	var fog:Vec4;
	var fogShape:Vec4;
	var eye:Vec4;
}

final GpuParticleShader = shader({
	vertex: function(v:GpuParticleVertex, params:{view:GpuParticleView}):GpuParticleVaryings {
		var age = params.view.up.w - v.start.w, life = v.velocity.w;
		var t = age / max(life, 0.0001);
		var alive = step(0.0, age) * step(t, 1.0);
		var k = max(params.view.forward.w, 0.0001);
		var travel = (1.0 - exp(-k * age)) / k;
		var p = v.start.xyz + v.velocity.xyz * travel + params.view.gravity.xyz * (0.5 * age * age);
		// (its velocity now: for a streak along it)
		var now = v.velocity.xyz * exp(-k * age) + params.view.gravity.xyz * age;
		var size = mix(v.shape.x, v.shape.y, t) * alive;
		// (a streak: along its velocity on the screen, stretch seconds of
		// its path behind it; else facing the camera)
		var speed = length(now);
		var dir = now / max(speed, 0.0001);
		var across = cross(dir, params.view.forward.xyz);
		var l = length(across);
		var s = step(0.0001, v.shape.z) * step(0.0001, speed) * step(0.0001, l);
		var axis = mix(params.view.right.xyz, dir, s);
		var side = mix(params.view.up.xyz, across / max(l, 0.0001), s);
		var len = s * speed * v.shape.z;
		var q = p - axis * (len * 0.5 * (1.0 - v.corner.x)) + axis * (v.corner.x * size) + side * (v.corner.y * size);
		var fade = (1.0 - t) * min(1.0, t * 12.0 + 0.2);
		var hot = 1.0 + v.shape.w * (1.0 - t) * (1.0 - t) * 3.0;
		fade *= 1.0 - fogAmount(params.view.fog, params.view.fogShape, params.view.eye.xyz, p);
		return {clip: position(params.view.viewProj * vec4(q, 1)), corner: v.corner, color: vec4(v.color.xyz * hot, v.color.w * fade * alive)};
	},
	fragment: function(i:GpuParticleVaryings, p:{view:GpuParticleView}):Vec4 {
		var d = 1 - smoothstep(0.15, 1, length(i.corner));
		var c = output(i.color.xyz * (i.color.w * d), p.view.right.w);
		// (light added, coverage untouched: into HDR none, so that a
		// see-through target keeps what is behind; into 8 bits its brightest
		// channel, a glow over it, as the target is composed premultiplied)
		var cover = p.view.right.w > 0.5 ? 0.0 : min(1.0, max(c.x, max(c.y, c.z)));
		return vec4(c, cover);
	}
});
