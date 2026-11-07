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
	@:typescript public static function create(surface:Surface, ?options:{?antialias:Bool}):Device
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

	// the bytes of the textures alive: their levels' and samples', as their
	// formats store them (the GPU's own padding and alignment aside)
	public var textureBytes(default, null) = 0.0;

	final textureSizes = new Map<Int, Float>();

	// (checked by the back end: TextureInfo.of)
	public function createTexture(d:TextureDesc):Texture {
		var t = new Texture(impl.createTexture(d));
		var format:TextureFormat = d.format == null ? RGBA8 : d.format;
		var levels = d.mipLevels == null ? 1 : d.mipLevels, bytes = 0.0, l = 0;
		while (levels == 0 ? (d.width | d.height) >> l != 0 : l < levels) {
			bytes += format.levelBytes(d.width >> l > 0 ? d.width >> l : 1, d.height >> l > 0 ? d.height >> l : 1);
			l++;
		}
		bytes *= d.samples == null ? 1 : d.samples;
		textureSizes.set(t.id(), bytes);
		textureBytes += bytes;
		return t;
	}

	// texels into the texture's mip level (default 0), rows top to bottom:
	// all of them (its width * height * texelSize bytes), or the region w x h
	// at x, y (w * h * texelSize bytes from dataOffset), as a glyph atlas
	// updates the part that changed; not into a render target
	public function writeTexture(t:Texture, data:haxe.io.Bytes, x = 0, y = 0, w = -1, h = -1, dataOffset = 0, level = 0) {
		impl.writeTexture(t.id(), data, x, y, w, h, dataOffset, level);
	}

	// whether its GPU samples textures of a format: the compressed ones (BC1,
	// BC3, ASTC4x4) where it has them (GL's extensions, WebGL2's, WebGPU's
	// features), the others everywhere
	public function supports(format:TextureFormat):Bool
		return impl.supports(format);

	// whether textures are filled from images the browser decoded
	// (writeTextureImage; helder.gfx.ImageTexture): in a browser
	public var decodesImages(get, never):Bool;

	inline function get_decodesImages()
		return hxmc.unsafe.Mem.os() == 3;

	// the texture (RGBA8 or RGBA8Srgb, not a render target, the image's
	// size) filled from a browser image (helder.image.WebImages' handle): at
	// once when the browser decoded it, else when it has (the texture blank
	// until then); its mip levels after the first generated then; release:
	// the image freed after. Only where decodesImages
	@:noCompletion public function writeTextureImage(t:Texture, image:Int, release = false)
		impl.writeTextureImage(t.id(), image, release);

	// the texture's mip levels after the first, each filtered down from the
	// one before (GL's glGenerateMipmap, D3D11's GenerateMips, Metal's blit,
	// a pass on WebGPU); outside a pass, after the first level was written or
	// rendered (not R32F or a depth format)
	public function generateMips(t:Texture)
		impl.generateMips(t.id());

	// ---- shared textures (helder.story's native preview host: its frames
	// drawn into textures another process samples, without copies)
	//
	// sharing: how this device shares a texture with another process:
	// "iosurface" (Metal: an IOSurface, found by its id), "dxgi" (Direct3D 11:
	// a texture with a keyed mutex, by its DXGI shared handle), "dmabuf" (GL:
	// a dma-buf exported through EGL_MESA_image_dma_buf_export, the other
	// process taking its file descriptor with pidfd_getfd, imported with
	// EGL_EXT_image_dma_buf_import); null: none (WebGPU, WebGL2, Android, an
	// EGL without those extensions: llvmpipe without udmabuf), a copy then.
	public var sharing(get, never):Null<String>;

	inline function get_sharing()
		return impl.sharing();

	// a render target of width x height another process opens (openShared):
	// the frame drawn into with frameInto, its handle a string to give that
	// process (null: this device cannot share). The texture's format is the
	// frame's (Metal: BGRA8, sampled as RGBA); destroyed by destroyTexture.
	public function createShared(width:Int, height:Int):Null<{texture:Texture, handle:String}> {
		var r = impl.createShared(width, height);
		if (r == null) return null;
		textureSizes.set(r.id, width * height * 4.0);
		textureBytes += width * height * 4.0;
		return {texture: new Texture(r.id), handle: r.handle};
	}

	// another process's shared texture (its createShared's handle, its
	// size), sampled like any texture (null: it cannot be opened here: its
	// process gone, another kind of handle); destroyed by destroyTexture
	// (the memory is the other process's too: freed when both let go).
	// Synchronised: a Direct3D 11 frame holds its keyed mutex from the
	// first draw that samples it to endFrame; Metal and GL rely on the
	// producer's frame being complete before it hands the handle over (its
	// endFrame waits for the GPU) and on the producer not drawing into a
	// texture this one samples (helder.story's buffers)
	public function openShared(handle:String, width:Int, height:Int):Null<Texture> {
		var id = impl.openShared(handle, width, height);
		return id == 0 ? null : new Texture(id);
	}

	// the next frames drawn into t (a shared texture, or a render target of
	// the frame's format) instead of the surface: beginFrame to endFrame at
	// its size, its passes without a colour texture into it, readPixels
	// reading it; null: the surface again. A frame into a shared texture
	// waits for the GPU at endFrame (its pixels complete for the other process)
	public function frameInto(t:Null<Texture>)
		impl.frameInto(t == null ? 0 : t.id());

	// frees a buffer or a texture (its handle is not used again)
	public function destroyBuffer(b:Buffer)
		impl.destroyBuffer(b.id());

	public function destroyTexture(t:Texture) {
		var bytes = textureSizes.get(t.id());
		if (bytes != null) {
			textureBytes -= bytes;
			textureSizes.remove(t.id());
		}
		impl.destroyTexture(t.id());
	}

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
	@:typescript public function beginFrame():Null<Encoder>
		return impl.beginFrame() ? encoder : null;

	// submits the frame and presents it
	@:typescript public function endFrame() {
		#if helder.headless
		// (a headless run's window: its frame read before it is presented, for the run's outputs)
		if (surface.kind == Headless) helder.headless.Headless.run.present(surface, impl.width, impl.height, readPixels);
		#end
		impl.endFrame();
	}

	// the frame's colour target as RGBA8, rows top to bottom (width * height
	// * 4 bytes into dst), after the passes and before endFrame; waits for
	// the GPU (tests and screenshots)
	@:typescript public function readPixels(dst:haxe.io.Bytes)
		impl.readPixels(dst);

	// the size of the colour target in pixels
	@:typescript public var width(get, never):Int;
	@:typescript public var height(get, never):Int;

	inline function get_width()
		return impl.width;

	inline function get_height()
		return impl.height;

	@:typescript public function dispose()
		impl.dispose();
}
