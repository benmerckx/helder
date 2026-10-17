// title: Instances
// summary: Sixty-three shapes in three instanced draws: a vertex buffer for the shapes, an instance buffer for where, how big, how turned and what colour
// tags: gfx, shaders, instancing
// demo: canvas 512x384
import InstancesShader;
import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.gfx.shader.ShaderMath.*;
import hxmc.os.*;

// A field of shapes, turning, in a window (Escape closes):
//
//   haxe -cp packages/os/src -cp packages/gfx/src -cp packages/gfx/examples -main Instances
//     --custom-target hxmc=instances -D hxmc.libc=glibc
//
// (as Triangle.hx for macOS, Windows and the browser; `--time t` draws it
// still, at t seconds: the tests' frames). The pipeline's layout has two
// vertex buffers: slot 0 steps per vertex (the shapes' corners), slot 1 per
// instance (VertexStep.Instance: each instance's centre, size, angle and
// colour). Three draws share them: the squares (drawIndexed), the arrows
// (drawIndexed with a base vertex, which moves the shapes' vertices, not the
// instances') and the triangles (draw from a first vertex); each sets the
// instance buffer at its own instances' offset. The shaders are
// InstancesShader.hx.
class Instances {
	static inline var COLUMNS = 9;
	static inline var ROWS = 7;
	static inline var CELL = 0.25;
	// the instance buffer's element: at (2 floats), size, angle, color (3)
	static inline var STRIDE = 28;

	// the shader's attributes (locations in InstanceVertex's order) over the two buffers
	public static final layout:Array<VertexBufferLayout> = [
		{stride: 8, attributes: [{location: 0, format: Float2, offset: 0}]},
		{
			stride: STRIDE,
			step: Instance,
			attributes: [
				{location: 1, format: Float2, offset: 0},
				{location: 2, format: Float1, offset: 8},
				{location: 3, format: Float1, offset: 12},
				{location: 4, format: Float3, offset: 16}
			]
		}
	];

	final device:Device;
	final shapes:Buffer;
	final indices:Buffer;
	final instances:Buffer;
	final pipeline:Pipeline;
	final pass:PassDesc = {colors: [{load: Clear, clear: new Color(0.1, 0.1, 0.12)}]};
	final field = Bytes.alloc(16);

	public function new(device:Device) {
		this.device = device;
		// the square (0-3), the arrow (4-7) and the triangle (8-10)
		var corners = [
			-0.7, -0.7, 0.7, -0.7, 0.7, 0.7, -0.7, 0.7,
			0, 1, -0.75, -0.8, 0, -0.35, 0.75, -0.8,
			0, 0.95, -0.85, -0.55, 0.85, -0.55
		];
		var b = Bytes.alloc(4 * corners.length);
		for (i in 0...corners.length)
			b.setFloat(4 * i, corners[i]);
		shapes = device.createBuffer({size: b.length, usage: Vertex, data: b});
		// (both quads' indices, from their own first vertex: the base vertex)
		var is = Bytes.alloc(6 * 2);
		for (k in 0...6)
			is.setUInt16(2 * k, [0, 1, 2, 0, 2, 3][k]);
		indices = device.createBuffer({size: is.length, usage: Index, data: is});
		// row by row from the top: the hue along the row, lighter down the field
		b = Bytes.alloc(COLUMNS * ROWS * STRIDE);
		for (r in 0...ROWS)
			for (c in 0...COLUMNS) {
				var i = r * COLUMNS + c, o = i * STRIDE;
				b.setFloat(o, (c - (COLUMNS - 1) / 2) * CELL);
				b.setFloat(o + 4, ((ROWS - 1) / 2 - r) * CELL);
				b.setFloat(o + 8, CELL * (0.32 + 0.1 * ((c + r) % 3)));
				b.setFloat(o + 12, 0.37 * i);
				var h = c / COLUMNS * 6, l = 0.55 + 0.4 * r / (ROWS - 1);
				b.setFloat(o + 16, l * (0.5 + 0.5 * Math.cos(h)));
				b.setFloat(o + 20, l * (0.5 + 0.5 * Math.cos(h - 2.1)));
				b.setFloat(o + 24, l * (0.5 + 0.5 * Math.cos(h + 2.1)));
			}
		instances = device.createBuffer({size: b.length, usage: Vertex, data: b});
		var d = InstancesShader.pipeline();
		d.layout = layout;
		pipeline = device.createPipeline(d);
	}

	// records the frame's pass at time t; the caller ends the frame
	public function draw(enc:Encoder, t:Float) {
		var w = device.width, h = device.height;
		// (the field's height fills the target's: square units)
		var unit = 2 / (ROWS * CELL + 0.2);
		InstancesShader.writeInstanceField({scale: vec2(unit * h / w, unit), time: t}, field);
		enc.beginPass(pass);
		enc.setPipeline(pipeline);
		enc.setUniforms(0, field);
		enc.setVertexBuffer(0, shapes);
		enc.setIndexBuffer(indices, UInt16);
		// the first three rows squares, the next two arrows, the last two triangles
		enc.setVertexBuffer(1, instances);
		enc.drawIndexed(6, 3 * COLUMNS);
		enc.setVertexBuffer(1, instances, 3 * COLUMNS * STRIDE);
		enc.drawIndexed(6, 2 * COLUMNS, 0, 4);
		enc.setVertexBuffer(1, instances, 5 * COLUMNS * STRIDE);
		enc.draw(3, 2 * COLUMNS, 8);
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
		var window = new Window("Instances", 640, 480);
		var instances = new Instances(Device.create(window.surface));
		var start = Sys.time();
		App.run(() -> instances.frame(still >= 0 ? Std.parseFloat(args[still + 1]) : Sys.time() - start), e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case _:
		});
	}
}
