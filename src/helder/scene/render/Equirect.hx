package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// Equirectangular environment maps in shader code: the environment's
// background (EnvironmentShader) and the standard material's lookups
// (PbrShader). (A module of functions only, with no static values, so that
// the shaders' modules that call it start in no particular order.)

// a unit direction's place in an equirectangular map (-z at its centre,
// up at its top)
function equirect(d:Vec3):Vec2
	return vec2(arcTan2(d.x, -d.z) * 0.15915494 + 0.5, arcCos(clamp(d.y, -1, 1)) * 0.31830989);

// a prefiltered atlas's colour (Environment.prefiltered: levels rows of
// the sphere by roughness and the irradiance's below them, all of a
// size) at a direction's place uv in its row (edge: half a texel of a
// row, kept from the next one's)
function atlas(t:Texture2D, uv:Vec2, row:Float, levels:Float, edge:Float):Vec3
	return sampleLevel(t, vec2(uv.x, (row + clamp(uv.y, edge, 1 - edge)) / (levels + 1)), 0).xyz;

// (the shaders have no inverse trigonometry: polynomial fits, within
// 2e-5 radians of atan2 and 7e-5 of acos)
function arcTan2(y:Float, x:Float):Float {
	var ax = abs(x), ay = abs(y);
	var a = min(ax, ay) / max(max(ax, ay), 0.000001);
	var s = a * a;
	var r = a * (0.999866 + s * (-0.3302995 + s * (0.180141 + s * (-0.085133 + s * 0.0208351))));
	if (ay > ax) r = 1.5707964 - r;
	if (x < 0) r = 3.1415927 - r;
	if (y < 0) r = -r;
	return r;
}

function arcCos(x:Float):Float {
	var ax = abs(x);
	var r = sqrt(1 - ax) * (1.5707288 + ax * (-0.2121144 + ax * (0.074261 - 0.0187293 * ax)));
	if (x < 0) r = 3.1415927 - r;
	return r;
}
