import LitShader;
import haxe.io.Bytes;
import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

// The shader macro's tests, on Eval (make gfx-shader-check):
//
//   <tool> -cp packages/gfx/src -cp packages/gfx/examples -cp packages/gfx/test
//     --run ShaderTest <tool> [--bless]
//
// - the math types and the shaders' functions run on the CPU (TriangleShader,
//   LitShader with Lighting's helpers): their values
// - the generated members: the vertex layout and bytes, the uniform blocks'
//   std140 layout and writers
// - the emitted source in all four languages (Eval: all of them), against
//   test/shader/<Class>.<vert|frag>.<glsl|wgsl|msl|hlsl> (--bless rewrites them)
// - the programs test/reject/*.hx the compiler must reject: each `// expect:
//   <text>` line of one is in the compiler's output (as hxmc/test/reject)
// - the tests' PNG files (Png.hx, as GfxTest --bless writes them, in stored
//   blocks of 65535 bytes) read back by Png.decode, pixel for pixel
class ShaderTest {
	static var failures = 0;
	static var checks = 0;

	static function main() {
		var args = Sys.args();
		var tool = args[0], bless = args.contains("--bless");
		var here = haxe.io.Path.directory(Sys.programPath());
		if (here == "") here = ".";
		math();
		shaders();
		layouts();
		png();
		golden(here + "/shader", bless);
		if (tool != null && tool != "--bless") rejects(tool, here);
		Sys.println('ShaderTest: $checks checks, ' + (failures == 0 ? "ok" : '$failures FAILED'));
		Sys.exit(failures == 0 ? 0 : 1);
	}

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failures++;
			Sys.println('ShaderTest: FAIL: $what' + (detail != null ? ": " + detail : ""));
		}
	}

	static function near(what:String, got:Float, want:Float)
		check(what, Math.abs(got - want) < 1e-9, 'got $got, want $want');

	static function nearVec(what:String, got:Vec4, want:Array<Float>)
		for (i in 0...4)
			near(what + "." + "xyzw".charAt(i), [got.x, got.y, got.z, got.w][i], want[i]);

	// Png: encode (stored blocks) then decode, at sizes of one block and of
	// several full ones (InflateImpl's window: 32 KiB at once)
	static function png() {
		for (size in [[4, 3], [256, 192], [640, 480]]) {
			var w = size[0], h = size[1];
			var rgba = Bytes.alloc(w * h * 4);
			for (i in 0...rgba.length)
				rgba.set(i, (i * 31 + (i >> 9)) & 0xFF);
			var g = try Png.decode(Png.encode(rgba, w, h)) catch (e:Dynamic) {
				check('png ${w}x$h', false, Std.string(e));
				continue;
			}
			var same = g.width == w && g.height == h;
			for (p in 0...w * h)
				for (k in 0...3)
					if (same && g.rgba.get(4 * p + k) != rgba.get(4 * p + k)) same = false;
			check('png ${w}x$h', same, "other pixels read back");
		}
	}

	// the math types and ShaderMath as ordinary Haxe
	static function math() {
		var a = vec3(1, 2, 3), b = vec3(-2, 0.5, 4);
		near("dot", dot(a, b), -2 + 1 + 12);
		var c = cross(a, b);
		nearVec("cross", vec4(c, 0), [2 * 4 - 3 * 0.5, 3 * -2 - 1 * 4, 1 * 0.5 - 2 * -2, 0]);
		nearVec("swizzles", vec4(a.zyx, a.xy.yx.x), [3, 2, 1, 2]);
		nearVec("operators", vec4(2 * a - 1 + a / 2, 0), [1.5, 4, 6.5, 0]);
		near("length", length(normalize(b)), 1);
		near("mix", mix(a, b, 0.25).y, 2 + (0.5 - 2) * 0.25);
		near("smoothstep", smoothstep(0, 2, 0.5), 0.15625);
		near("clamp", clamp(a, 1.5, 2.5).x, 1.5);
		near("fract", fract(-1.25), 0.75);
		near("step", step(vec2(1, 3), vec2(2)).y, 0);
		// columns: (m * v) = c0 * v.x + c1 * v.y + ...; mat4(s) is s on the diagonal
		var m = mat4(vec4(1, 0, 0, 0), vec4(0, 2, 0, 0), vec4(0, 0, 3, 0), vec4(4, 5, 6, 1));
		nearVec("mat4 * vec4", m * vec4(1, 1, 1, 1), [5, 7, 9, 1]);
		nearVec("mat4 * mat4", (m * mat4(2)) * vec4(1, 0, 0, 1), [2 + 4 * 2, 5 * 2, 6 * 2, 2]);
		// the clip space: z from 0 at the near plane to w at the far one
		var proj = Mat4.perspective(Math.PI / 2, 2, 1, 10), n = proj * vec4(0, 0, -1, 1), f = proj * vec4(0, 0, -10, 1);
		near("perspective near", n.z / n.w, 0);
		near("perspective far", f.z / f.w, 1);
		nearVec("perspective, a corner", proj * vec4(2, 1, -1, 1), [1, 1, 0, 1]);
		var o = Mat4.orthographic(0, 4, 0, 2, 1, 3) * vec4(4, 0, -3, 1);
		nearVec("orthographic", o, [1, -1, 1, 1]);
		nearVec("rotations", Mat4.translation(1, 0, 0) * Mat4.rotationZ(Math.PI / 2) * Mat4.rotationY(Math.PI / 2) * vec4(0, 0, 1, 1), [1, 1, 0, 1]);
	}

	// the shaders' functions on the CPU
	static function shaders() {
		var o = @:privateAccess TriangleShader.vs({pos: vec2(0.6, -0.5), color: vec3(0, 0, 1)});
		nearVec("TriangleShader.vs pos", o.pos, [0.6, -0.5, 0, 1]);
		nearVec("TriangleShader.fs", @:privateAccess TriangleShader.fs(o), [0, 0, 1, 1]);
		var cam:Camera = {viewProj: mat4(2), eye: vec3(1, 0, 5), time: 0};
		var v = @:privateAccess LitShader.vs({pos: vec3(1, 0, 0), normal: vec3(0, 0, 1), uv: vec2(0.25, 0.75)}, cam);
		nearVec("LitShader.vs clip", v.clip, [2 + Math.sin(3) * 0.05, 0, 0, 2]);
		near("LitShader.vs uv", v.uv.x, 0.75);
		near("LitShader.vs shade", v.shade, 1);
		near("Lighting.lambert", Lighting.lambert(vec3(0, 3, 0), vec3(1, 1, 0)), Math.sqrt(0.5));
		near("Lighting.posterize", Lighting.posterize(0.5, 4), 2 / 3);
		var i:LitVaryings = {normal: vec3(0, 0, 1), clip: vec4(0), uv: vec2(0.25, 0.75), shade: 0.5};
		var glow = 1 / 2 + 1 / 3 + 1 / 4 + 1 / 5, k = 0.1 + 2 / 3;
		nearVec("LitShader.fs", @:privateAccess LitShader.fs(i, {tint: vec4(1, 0.5, 0.25, 1), steps: 4}),
			[k + glow * 0.01, 0.5 * k + glow * 0.01, 0.25 * k + glow * 0.01, 1]);
		// (the uv in the right half: the colour reversed; the checker's dark squares)
		var j:LitVaryings = {normal: vec3(0, 0, 1), clip: vec4(0), uv: vec2(0.7, 0.75), shade: 0.5};
		nearVec("LitShader.fs, right half", @:privateAccess LitShader.fs(j, {tint: vec4(1, 0.5, 0.25, 1), steps: 0}),
			[0.25 * 0.6 * 0.5, 0.5 * 0.6 * 0.5, 0.6 * 0.5, 1]);
		// (a translation by pos.xyz, then halved)
		var b = @:privateAccess BuiltinShader.vs({pos: vec4(1, 2, 3, 1)});
		nearVec("BuiltinShader.vs", b.pos, [1, 2, 3, 0.5]);
		var c = @:privateAccess BuiltinShader.fs(b);
		check("BuiltinShader.fs", [c.x, c.y, c.z, c.w].filter(Math.isFinite).length == 4, Std.string([c.x, c.y, c.z, c.w]));
		// (textures on the CPU: the nearest texel, repeating; rows top to bottom)
		var texels = Bytes.alloc(2 * 2 * 4);
		for (i in 0...4) {
			texels.set(4 * i, 255);
			texels.set(4 * i + 1, [0, 64, 128, 255][i]);
			texels.set(4 * i + 3, 255);
		}
		var tex = new Texture2D(2, 2, texels);
		near("sample", sample(tex, vec2(0.75, 0.25)).y, 64 / 255);
		near("sample, repeating", sample(tex, vec2(-0.25, 1.75)).y, 255 / 255);
		var tv = @:privateAccess TexturedShader.vs({pos: vec2(0, 0), uv: vec2(0.25, 0.75)}, tex);
		near("TexturedShader.vs lift", tv.lift, 1);
		nearVec("TexturedShader.fs", @:privateAccess TexturedShader.fs(tv, {amount: 0.5}, tex, tex), [1, (0.5 + 128 / 255) / 2, 0, 1]);
	}

	// the generated layouts and writers
	static function layouts() {
		var l = TriangleShader.layout[0];
		check("TriangleShader.layout", l.stride == 20 && l.attributes.length == 2 && l.attributes[1].offset == 8 && l.attributes[1].format == Float3);
		var b = TriangleShader.vertexBytes([{pos: vec2(0, 0.6), color: vec3(1, 0, 0)}, {pos: vec2(-0.6, -0.5), color: vec3(0, 1, 0)}]);
		var want = [0.0, 0.6, 1, 0, 0, -0.6, -0.5, 0, 1, 0];
		check("TriangleShader.vertexBytes", b.length == 40 && [for (i in 0...10) b.getFloat(4 * i)].join(",") == [
			for (f in want) {
				var x = Bytes.alloc(4);
				x.setFloat(0, f);
				x.getFloat(0);
			}
		].join(","));
		var u = LitShader.uniforms;
		check("LitShader.uniforms", u.length == 2 && u[0].name == "Camera" && u[0].binding == 0 && u[0].size == 80 && u[1].name == "Material"
			&& u[1].size == 32, Std.string(u));
		var bytes = Bytes.alloc(96);
		LitShader.writeCamera({viewProj: mat4(vec4(1, 2, 3, 4), vec4(5, 6, 7, 8), vec4(9, 10, 11, 12), vec4(13, 14, 15, 16)), eye: vec3(-1, -2, -3), time: 7}, bytes,
			16);
		check("LitShader.writeCamera", [for (i in 0...20) bytes.getFloat(16 + 4 * i)].join(",") == "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,-1,-2,-3,7");
		LitShader.writeMaterial({tint: vec4(0.5), steps: 3}, bytes);
		check("LitShader.writeMaterial", bytes.getFloat(12) == 0.5 && bytes.getInt32(16) == 3);
		var t = TexturedShader.textures, tu = TexturedShader.uniforms;
		check("TexturedShader.textures", t.length == 2 && t[0].name == "height" && t[0].binding == 0 && t[1].name == "albedo" && t[1].binding == 2
			&& tu.length == 1 && tu[0].binding == 1, Std.string(t) + " " + Std.string(tu));
		var bs = TexturedShader.fragmentCode.bindings;
		check("TexturedShader.fragmentCode.bindings", bs.length == 3 && bs[0].name == "Fade_block" && bs[0].slot == 1 && bs[1].name == "tex_2" && bs[2].name == "tex_0", Std.string(bs));
	}

	// the emitted source against the golden files
	static function golden(dir:String, bless:Bool) {
		var codes:Array<{name:String, code:hxmc.gfx.ShaderCode}> = [
			{name: "TriangleShader.vert", code: TriangleShader.vertexCode},
			{name: "TriangleShader.frag", code: TriangleShader.fragmentCode},
			{name: "LitShader.vert", code: LitShader.vertexCode},
			{name: "LitShader.frag", code: LitShader.fragmentCode},
			{name: "BuiltinShader.vert", code: BuiltinShader.vertexCode},
			{name: "BuiltinShader.frag", code: BuiltinShader.fragmentCode},
			{name: "TexturedShader.vert", code: TexturedShader.vertexCode},
			{name: "TexturedShader.frag", code: TexturedShader.fragmentCode},
			{name: "InstancesShader.vert", code: InstancesShader.vertexCode},
			{name: "InstancesShader.frag", code: InstancesShader.fragmentCode}
		];
		for (c in codes)
			for (l in ["glsl", "wgsl", "msl", "hlsl"]) {
				var src:String = Reflect.field(c.code, l);
				var file = '$dir/${c.name}.$l';
				if (bless) {
					sys.io.File.saveContent(file, src);
					continue;
				}
				var want = sys.FileSystem.exists(file) ? sys.io.File.getContent(file) : null;
				check('$file', src == want, want == null ? "missing (--bless writes it)" : "differs:\n" + src);
			}
		if (bless) Sys.println('ShaderTest: blessed $dir');
	}

	// the programs the compiler must reject
	static function rejects(tool:String, here:String) {
		var dir = here + "/reject";
		var src = haxe.io.Path.normalize(here + "/../src");
		var files = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".hx")) f];
		files.sort(Reflect.compare);
		for (f in files) {
			var expect = [
				for (l in sys.io.File.getContent('$dir/$f').split("\n"))
					if (StringTools.startsWith(l, "// expect: ")) StringTools.trim(l.substr(11))
			];
			var p = new sys.io.Process(tool, ["-cp", src, "-cp", dir, "-main", f.substr(0, f.length - 3), "--interp", "--no-output"]);
			var out = p.stdout.readAll().toString() + p.stderr.readAll().toString();
			var code = p.exitCode();
			p.close();
			var missing = [for (e in expect) if (out.indexOf(e) < 0) e];
			check('reject/$f', code != 0 && expect.length > 0 && missing.length == 0,
				code == 0 ? "compiled, but must be rejected" : "missing: " + missing.join("; ") + "\n" + out);
		}
	}
}
