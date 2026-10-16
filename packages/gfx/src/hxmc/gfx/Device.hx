package hxmc.gfx;

import hxmc.os.Surface;

// A GPU device rendering to one Surface (a window, or headless), with a
// depth buffer of the colour target's size. Resources are created up front;
// a frame is beginFrame, passes recorded through the Encoder, endFrame
// (present). Main thread only.
final class Device {
	public final backend:Backend;
	public final surface:Surface;

	final impl:Impl;
	final encoder:Encoder;

	function new(surface:Surface) {
		this.surface = surface;
		impl = new Impl(surface);
		backend = impl.backend;
		encoder = new Encoder(impl);
	}

	public static function create(surface:Surface):Device
		return new Device(surface);

	public function createBuffer(d:BufferDesc):Buffer
		return new Buffer(impl.createBuffer(d));

	// size bytes of data from dataOffset (default: the rest) into the buffer
	// at offset, before the next commands: a frame's draws read what the
	// buffer holds when the frame is submitted (endFrame), so data that
	// changes within a frame goes to other offsets
	public function writeBuffer(b:Buffer, offset:Int, data:haxe.io.Bytes, dataOffset = 0, size = -1) {
		if (size < 0) size = data.length - dataOffset;
		if (dataOffset < 0 || offset < 0 || dataOffset + size > data.length) throw "hxmc.gfx: writeBuffer: outside the data";
		impl.writeBuffer(b.id(), offset, data, dataOffset, size);
	}

	public function createTexture(d:TextureDesc):Texture {
		if (d.width <= 0 || d.height <= 0) throw "hxmc.gfx: createTexture: a size of " + d.width + "x" + d.height;
		if (d.data != null && d.data.length < d.width * d.height * 4) throw "hxmc.gfx: createTexture: data has fewer than width * height * 4 bytes";
		return new Texture(impl.createTexture(d));
	}

	// all of the texture's texels (width * height * 4 bytes, rows top to bottom)
	public function writeTexture(t:Texture, data:haxe.io.Bytes)
		impl.writeTexture(t.id(), data);

	public function createSampler(d:SamplerDesc):Sampler
		return new Sampler(impl.createSampler(d));

	// throws the compiler's log when the source does not compile
	public function createShader(d:ShaderDesc):Shader
		return new Shader(impl.createShader(d));

	// (d.program: its shaders created first)
	public function createPipeline(d:PipelineDesc):Pipeline {
		if (d.program != null)
			d = {
				vertex: createShader({stage: Vertex, code: d.program.vertex}),
				fragment: createShader({stage: Fragment, code: d.program.fragment}),
				layout: d.layout,
				topology: d.topology,
				cull: d.cull,
				blend: d.blend,
				depthCompare: d.depthCompare,
				depthWrite: d.depthWrite
			};
		return new Pipeline(impl.createPipeline(d));
	}

	// the frame's encoder (the same object each frame); null: no frame now
	// (a hidden window: Metal has no drawable for it), skip it
	public function beginFrame():Null<Encoder>
		return impl.beginFrame() ? encoder : null;

	// submits the frame and presents it
	public function endFrame()
		impl.endFrame();

	// the frame's colour target as RGBA8, rows top to bottom (width * height
	// * 4 bytes into dst), after the passes and before endFrame; waits for
	// the GPU (tests and screenshots)
	public function readPixels(dst:haxe.io.Bytes)
		impl.readPixels(dst);

	// the size of the colour target in pixels
	public var width(get, never):Int;
	public var height(get, never):Int;

	inline function get_width()
		return impl.width;

	inline function get_height()
		return impl.height;

	public function dispose()
		impl.dispose();
}
