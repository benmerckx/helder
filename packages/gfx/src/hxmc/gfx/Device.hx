package hxmc.gfx;

import hxmc.os.Surface;

// A GPU device rendering to one Surface (a window, or headless). Resources
// are created up front; a frame is beginFrame, passes recorded through the
// Encoder, endFrame (present). Main thread only.
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

	// replaces size bytes of a buffer from offset with data's from dataOffset
	// (size -1: the rest of data). A write takes effect for the whole frame
	// (WebGPU queues it before the frame's commands): write what a frame
	// draws before its passes, and never a range an earlier draw of the same
	// frame read.
	public function writeBuffer(b:Buffer, offset:Int, data:haxe.io.Bytes, dataOffset = 0, size = -1) {
		if (size < 0) size = data.length - dataOffset;
		if (dataOffset < 0 || dataOffset + size > data.length) throw "hxmc.gfx: writeBuffer: out of data's bounds";
		if (size > 0) impl.writeBuffer(b.id(), offset, data, dataOffset, size);
	}

	// frees a buffer (after the frames that use it are submitted: the GPU
	// keeps what a submitted frame needs)
	public function destroyBuffer(b:Buffer)
		if (b.id() != 0) impl.destroyBuffer(b.id());

	public function createTexture(d:TextureDesc):Texture {
		if (d.data != null && d.data.length < d.width * d.height * d.format.bytesPerPixel)
			throw "hxmc.gfx: createTexture: data has fewer than width * height * " + d.format.bytesPerPixel + " bytes";
		return new Texture(impl.createTexture(d));
	}

	// replaces a w x h region of a texture at (x, y) with data's pixels from
	// dataOffset, rows of w pixels top to bottom (writeBuffer's rules on
	// frames apply)
	public function writeTexture(t:Texture, x:Int, y:Int, w:Int, h:Int, data:haxe.io.Bytes, dataOffset = 0) {
		if (w <= 0 || h <= 0) return;
		impl.writeTexture(t.id(), x, y, w, h, data, dataOffset);
	}

	// frees a texture (destroyBuffer's rule)
	public function destroyTexture(t:Texture)
		if (t.id() != 0) impl.destroyTexture(t.id());

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
				textures: d.textures
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
