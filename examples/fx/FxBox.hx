import Effects;
import haxe.io.Bytes;
import helder.gfx.Device;
import helder.gfx.Encoder;
import helder.gfx.Pipeline;
import helder.gfx.Texture;
import helder.gfx.shader.Shader;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec4;

typedef FxShader = Shader<FxVertex, {fx:helder.gfx.shader.Shader.UniformWriter<FxParams>}>;

// A box in ui's layout drawing an effect (one of Effects' shaders): each
// frame it is painted, its fragment stage runs over a texture of the box's
// size in pixels, before ui's pass (as a <Scene>'s box:
// helder.ui.draw.Renderer.beforePass), and ui draws that texture as the
// box's content, its corners rounded with the box's. The knobs, the two
// colours and the time are the stage's uniform block. A box shares its
// effect's pipeline with every other box of it.
class FxBox extends helder.ui.Node {
	public var shader(default, set):FxShader;
	public var knobs = new Vec4(0.5, 0.5, 0.5, 0.5);
	public var a = new Vec4(1, 1, 1, 1);
	public var b = new Vec4(1, 1, 1, 1);
	public var time = 0.0;
	// at most so many pixels a point (the gallery's small boxes: 1)
	public var density = 0.0;

	static final pipelines = new Map<String, Pipeline>();
	static var triangle:Null<helder.gfx.Buffer> = null;

	var device:Null<Device>;
	var color:Null<Texture>;
	final retired:Array<Texture> = [];
	final retiredAt:Array<Int> = [];
	final bytes = Bytes.alloc(64);
	var pipeline:Null<Pipeline>;
	var records = 0;
	var tw = 0;
	var th = 0;
	var queued = -1;
	final id = -(++ids) - 2000000;

	static var ids = 0;

	public function new(shader:FxShader) {
		super("fx");
		this.shader = shader;
	}

	function set_shader(s:FxShader):FxShader {
		if (s != shader) pipeline = null;
		return shader = s;
	}

	// the knobs from a slider's values
	public function setKnobs(v:Array<Float>) {
		knobs = new Vec4(v[0], v[1], v[2], v[3]);
		if (ui != null) ui.requestFrame();
	}

	override public function hasContent():Bool
		return true;

	function ready(d:Device) {
		device = d;
		if (triangle == null) {
			var v = shader.vertexBytes([{pos: new Vec2(-1, -1)}, {pos: new Vec2(3, -1)}, {pos: new Vec2(-1, 3)}]);
			triangle = d.createBuffer({size: v.length, usage: Vertex, data: v});
		}
		var key = Type.getClassName(Type.getClass(shader));
		pipeline = pipelines.get(key);
		if (pipeline == null) {
			var desc = shader.pipeline({});
			desc.colorFormat = RGBA8;
			pipeline = d.createPipeline(desc);
			pipelines.set(key, pipeline);
		}
	}

	override public function paintContent(canvas:helder.ui.Canvas, x:Float, y:Float, width:Float, height:Float) {
		var r = Std.downcast(canvas, helder.ui.draw.Renderer);
		if (r == null) return;
		if (pipeline == null) ready(r.device);
		var k = density > 0 ? Math.min(1, density / r.scale) : 1;
		var pw = Std.int(Math.max(1, Math.round(width * r.scale * k))), ph = Std.int(Math.max(1, Math.round(height * r.scale * k)));
		if (pw != tw || ph != th) {
			if (color != null) {
				retired.push(color);
				retiredAt.push(records);
			}
			color = device.createTexture({width: pw, height: ph, renderTarget: true});
			tw = pw;
			th = ph;
		}
		while (retired.length > 0 && records >= retiredAt[0] + 2) {
			device.destroyTexture(retired.shift());
			retiredAt.shift();
		}
		shader.params.fx.write({frame: new Vec4(pw, ph, time, 0), knobs: knobs, a: a, b: b}, bytes);
		if (queued != r.frames) {
			queued = r.frames;
			r.beforePass(record);
		}
		var radius = style.radius;
		r.gpuTexture(color, id, x, y, width, height, radius);
	}

	function record(enc:Encoder) {
		records++;
		var c = color;
		if (c == null || pipeline == null) return;
		enc.beginPass({colors: [{load: Clear, clear: new helder.gfx.Color(0, 0, 0, 1), texture: c}]});
		enc.setPipeline(pipeline);
		enc.setVertexBuffer(0, triangle);
		enc.setUniforms(shader.uniforms[0].binding, bytes);
		enc.draw(3);
		enc.endPass();
	}

	public function dispose() {
		if (device != null) {
			if (color != null) device.destroyTexture(color);
			for (t in retired)
				device.destroyTexture(t);
			retired.resize(0);
			retiredAt.resize(0);
		}
		color = null;
	}
}
