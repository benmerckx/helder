package hxmc.gfx;

import hxmc.os.Surface;

// the back end of this target (D3D11, Metal and WebGL2 come in here)
private typedef Impl = hxmc.gfx.gl.GLBackend;

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

	// throws the compiler's log when the source does not compile
	public function createShader(d:ShaderDesc):Shader
		return new Shader(impl.createShader(d));

	public function createPipeline(d:PipelineDesc):Pipeline
		return new Pipeline(impl.createPipeline(d));

	// the frame's encoder (the same object each frame)
	public function beginFrame():Null<Encoder> {
		impl.beginFrame();
		return encoder;
	}

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
