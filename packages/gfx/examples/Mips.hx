// title: Mip maps
// summary: A checkered floor to the horizon, filtered trilinearly through generated mip levels, and swatches of a texture's levels uploaded one by one
// tags: gfx, shaders, 3d, textures
// demo: canvas 512x384
import MipsShader;
import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;
import hxmc.os.*;

// Mip maps, in a window (Escape closes):
//
//   haxe -cp packages/os/src -cp packages/gfx/src -cp packages/gfx/examples -main Mips
//     --custom-target hxmc=mips -D hxmc.libc=glibc
//
// (as Triangle.hx for macOS, Windows and the browser; `--time t` draws it
// still, at t seconds: the tests' frames). The floor's checks are a texture
// of every mip level (TextureDesc.mipLevels 0), the first written, the
// others generated (Device.generateMips), read through a trilinear sampler
// (filter and mipFilter Linear): far away the checks blend into grey
// rather than shimmer. Above it, swatches of a texture whose five levels
// are each written in a colour of their own (Device.writeTexture's level),
// read at levels 0, 1.5, 3 and 4 (sampleLevel: 1.5 is halfway between the
// second and the third). The shaders are MipsShader.hx.
class Mips {
	public static inline var DEPTH = 40.0;
	static inline var CHECKS = 256;

	final device:Device;
	final floor:Buffer;
	final swatches:Buffer;
	final quad:Buffer;
	final floorPipeline:Pipeline;
	final swatchPipeline:Pipeline;
	final checks:Texture;
	final levels:Texture;
	final trilinear:Sampler;
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0.1, 0.1, 0.12)}], depth: {load: Clear}};
	final camera = Bytes.alloc(64);
	final swatch = [for (_ in 0...4) Bytes.alloc(16)];

	public function new(device:Device) {
		this.device = device;
		// the checks: 4 by 4 of 64 texels, their edges soft (so that GPUs
		// filter them alike), every level, the first written
		var b = Bytes.alloc(CHECKS * CHECKS * 4);
		var wave = [for (i in 0...CHECKS) clamp(3 * Math.cos(Math.PI * (i + 0.5) / 64), -1, 1)];
		for (y in 0...CHECKS)
			for (x in 0...CHECKS) {
				var c = mix(vec3(0.34, 0.37, 0.42), vec3(0.78, 0.76, 0.7), 0.5 + 0.5 * wave[x] * wave[y]), p = 4 * (y * CHECKS + x);
				b.set(p, Math.round(c.x * 255));
				b.set(p + 1, Math.round(c.y * 255));
				b.set(p + 2, Math.round(c.z * 255));
				b.set(p + 3, 255);
			}
		checks = device.createTexture({width: CHECKS, height: CHECKS, mipLevels: 0, data: b});
		device.generateMips(checks);
		// five levels of 16x16 to 1x1, each its own colour
		levels = device.createTexture({width: 16, height: 16, mipLevels: 5});
		var colors = [0xff3050e0, 0xff30b0f0, 0xff40d080, 0xff40e0f0, 0xffd060e0];
		for (l in 0...5) {
			var n = 16 >> l;
			var c = Bytes.alloc(n * n * 4);
			for (i in 0...n * n)
				c.setInt32(4 * i, colors[l]);
			device.writeTexture(levels, c, 0, 0, -1, -1, 0, l);
		}
		trilinear = device.createSampler({filter: Linear, mipFilter: Linear, wrap: Repeat});
		// the floor: DEPTH long, its sides out of sight, a check a unit square
		var bytes = FloorShader.vertexBytes([
			for (c in [[-48.0, 0.0], [48.0, 0.0], [48.0, -DEPTH], [-48.0, -DEPTH]]) {pos: vec3(c[0], -1, c[1]), uv: vec2(c[0] / 4, c[1] / 4)}
		]);
		floor = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
		// four swatches in a row at the top
		var vs:Array<SwatchVertex> = [];
		for (k in 0...4) {
			var x = -0.78 + k * 0.4;
			for (c in [[0, 0], [1, 0], [1, 1], [0, 1]])
				vs.push({pos: vec2(x + c[0] * 0.36, 0.5 + c[1] * 0.4), uv: vec2(c[0], 1 - c[1])});
			SwatchShader.writeSwatch({level: [0, 1.5, 3, 4][k]}, swatch[k]);
		}
		bytes = SwatchShader.vertexBytes(vs);
		swatches = device.createBuffer({size: bytes.length, usage: Vertex, data: bytes});
		var qi = Bytes.alloc(12);
		for (k in 0...6)
			qi.setUInt16(2 * k, [0, 1, 2, 0, 2, 3][k]);
		quad = device.createBuffer({size: qi.length, usage: Index, data: qi});
		floorPipeline = device.createPipeline(FloorShader.pipeline());
		swatchPipeline = device.createPipeline(SwatchShader.pipeline());
	}

	// records the frame's pass at time t (the floor slides towards the
	// viewer); the caller ends the frame
	public function draw(enc:Encoder, t:Float) {
		var w = device.width, h = device.height;
		var view = Mat4.perspective(Math.PI / 3, w / h, 0.1, 100) * Mat4.rotationX(0.3) * Mat4.translation(0, 0, t % 4);
		FloorShader.writeFloorCamera({mvp: view}, camera);
		enc.beginPass(pass);
		enc.setIndexBuffer(quad, UInt16);
		enc.setPipeline(floorPipeline);
		enc.setUniforms(0, camera);
		enc.setTexture(1, checks, trilinear);
		enc.setVertexBuffer(0, floor);
		enc.drawIndexed(6);
		enc.setPipeline(swatchPipeline);
		enc.setVertexBuffer(0, swatches);
		for (k in 0...4) {
			enc.setUniforms(0, swatch[k]);
			enc.setTexture(1, levels, trilinear);
			enc.drawIndexed(6, 1, 0, 4 * k);
		}
		enc.endPass();
	}

	public function frame(t:Float) {
		var enc = device.beginFrame();
		if (enc == null) return;
		draw(enc, t);
		device.endFrame();
	}

	static function main() {
		var args = Sys.args(), still = args.indexOf("--time");
		var window = new Window("Mip maps", 640, 480);
		var mips = new Mips(Device.create(window.surface));
		var start = Sys.time();
		App.run(() -> mips.frame(still >= 0 ? Std.parseFloat(args[still + 1]) : Sys.time() - start), e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case _:
		});
	}
}
