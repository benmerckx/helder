package helder.gfx;

import helder.os.Surface;
#if hxmc.dev
import helder.dev.Hot;
#end

// A GPU device rendering to one Surface (a window, or headless), with a
// depth buffer of the colour target's size. Resources are created up front;
// a frame is beginFrame, passes recorded through the Encoder, endFrame
// (present). Main thread only. Under hxmc dev a device is disposed with the
// build (helder.dev.Hot.onDispose) when the next one is swapped in.
final class Device {
	public final backend:Backend;
	public final surface:Surface;

	final impl:Impl;
	final encoder:Encoder;

	function new(surface:Surface, antialias:Bool) {
		this.surface = surface;
		impl = new Impl(surface, antialias);
		backend = impl.backend;
		encoder = new Encoder(impl);
		#if hxmc.dev
		// (hxmc dev: a build swapped out releases its buffers, textures, samplers,
		// shaders and pipelines; the surface and the GPU device stay the host's)
		Hot.onDispose(dispose);
		#end
	}

	// antialias: a window's frames multisampled, 4 samples a pixel (in the
	// browser the page's run option antialias decides when it is set);
	// headless surfaces stay single-sampled, readPixels reads the frame
	// resolved; render targets are multisampled by their own samples
	// (TextureDesc.samples, resolved through ColorTarget.resolve)
	public static function create(surface:Surface, ?options:{?antialias:Bool}):Device
		return new Device(surface, options != null && options.antialias == true);

	public function createBuffer(d:BufferDesc):Buffer
		return new Buffer(impl.createBuffer(d));

	// size bytes of data from dataOffset (default: the rest) into the buffer
	// at offset, before the next commands: a frame's draws read what the
	// buffer holds when the frame is submitted (endFrame), so data that
	// changes within a frame goes to other offsets
	public function writeBuffer(b:Buffer, offset:Int, data:haxe.io.Bytes, dataOffset = 0, size = -1) {
		if (size < 0) size = data.length - dataOffset;
		if (dataOffset < 0 || offset < 0 || dataOffset + size > data.length) throw "helder.gfx: writeBuffer: outside the data";
		impl.writeBuffer(b.id(), offset, data, dataOffset, size);
	}

	// (checked by the back end: TextureInfo.of)
	public function createTexture(d:TextureDesc):Texture
		return new Texture(impl.createTexture(d));

	// texels into the texture's mip level (default 0), rows top to bottom:
	// all of them (its width * height * texelSize bytes), or the region w x h
	// at x, y (w * h * texelSize bytes from dataOffset), as a glyph atlas
	// updates the part that changed; not into a render target
	public function writeTexture(t:Texture, data:haxe.io.Bytes, x = 0, y = 0, w = -1, h = -1, dataOffset = 0, level = 0) {
		impl.writeTexture(t.id(), data, x, y, w, h, dataOffset, level);
	}

	// the texture's mip levels after the first, each filtered down from the
	// one before (GL's glGenerateMipmap, D3D11's GenerateMips, Metal's blit,
	// a pass on WebGPU); outside a pass, after the first level was written or
	// rendered (not R32F or a depth format)
	public function generateMips(t:Texture)
		impl.generateMips(t.id());

	// frees a buffer or a texture (its handle is not used again)
	public function destroyBuffer(b:Buffer)
		impl.destroyBuffer(b.id());

	public function destroyTexture(t:Texture)
		impl.destroyTexture(t.id());

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
				depthWrite: d.depthWrite,
				colorFormat: d.colorFormat,
				depthFormat: d.depthFormat,
				samples: d.samples
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
