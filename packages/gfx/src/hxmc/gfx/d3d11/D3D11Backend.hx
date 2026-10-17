package hxmc.gfx.d3d11;

import hxmc.gfx.*;
import hxmc.gfx.d3d11.D3D11;
import hxmc.os.Surface;
import hxmc.unsafe.*;

// The Direct3D 11 back end (Windows): a device and its immediate context,
// rendering to a window's flip-model swap chain (DXGI_SWAP_EFFECT_FLIP_DISCARD,
// two RGBA8 buffers, resized with the window) or, headless, to an offscreen
// texture. WARP (the system's software rasterizer) when HXMC_GFX_SOFTWARE=1
// or when there is no hardware device. Shaders are HLSL compiled at run
// time (D3DCompile, entry point main, shader model 5.0, or 4.0 below
// feature level 11_0), vertex inputs at semantic TEXCOORD<location> (as
// SPIRV-Cross names them); a pipeline's blending is a blend state, there
// is no depth buffer. Buffer and texture writes are UpdateSubresource (in
// the context's order); textures are shader resource views with one of two
// sampler states (Linear, Nearest). Rasterizer states enable the scissor
// test (the whole target by default). readPixels copies the target into a
// staging texture and maps it.
class D3D11Backend {
	public final backend = Backend.D3D11;
	public var width(default, null) = 0;
	public var height(default, null) = 0;

	final surface:Surface;
	final device:Ptr; // ID3D11Device
	final context:Ptr; // ID3D11DeviceContext
	final shaderModel:String;
	var swapChain = Ptr.nil(); // IDXGISwapChain1 (a window)
	var target = Ptr.nil(); // ID3D11Texture2D: the back buffer, or the headless target
	var view = Ptr.nil(); // its ID3D11RenderTargetView
	var staging = Ptr.nil(); // readPixels' texture, of stagingWidth x stagingHeight
	var stagingWidth = 0;
	var stagingHeight = 0;
	// native memory: out-parameters, the clear colour, the viewport, the
	// vertex buffers bound at the next draw
	final scratch:Ptr<Ptr>;
	final clear:Ptr<Float32>;
	final viewport:Ptr<D3D11_VIEWPORT>;
	final mapped:Ptr<D3D11_MAPPED_SUBRESOURCE>;
	final vbufs:Ptr<Ptr>;
	final strides:Ptr<Int32>;
	final offsets:Ptr<Int32>;

	// tables (handle = index + 1)
	final buffers:Array<Ptr> = []; // ID3D11Buffer
	final usages:Array<BufferUsage> = [];
	final textures:Array<D3DTexture> = [];
	final samplers:Array<Ptr> = [Ptr.nil(), Ptr.nil()]; // ID3D11SamplerState by Filter
	final shaders:Array<D3DShader> = [];
	final pipelines:Array<D3DPipeline> = [];

	// draw state
	var pipeline:D3DPipeline = null;
	var dirty = true;

	static inline var MAX_SLOTS = 8;
	static inline var BLEND_DESC_SIZE = 8 + 8 * 32;

	public function new(surface:Surface) {
		this.surface = surface;
		scratch = LibC.malloc(64);
		clear = LibC.malloc(16);
		viewport = LibC.malloc(24);
		mapped = LibC.malloc(16);
		vbufs = LibC.malloc(8 * MAX_SLOTS);
		strides = LibC.malloc(4 * MAX_SLOTS);
		offsets = LibC.malloc(4 * MAX_SLOTS);
		LibC.memset(vbufs, 0, 8 * MAX_SLOTS);
		var level:Ptr<Int32> = scratch.offset(2).raw();
		var hr = Sys.getEnv("HXMC_GFX_SOFTWARE") == "1" ? -1 : createDevice(D3D.DRIVER_TYPE_HARDWARE, level);
		if (hr < 0) hr = createDevice(D3D.DRIVER_TYPE_WARP, level);
		check(hr, "D3D11CreateDevice");
		device = scratch.value;
		context = scratch.offset(1).value;
		shaderModel = level.value >= D3D.FEATURE_LEVEL_11_0 ? "_5_0" : "_4_0";
		width = surface.width;
		height = surface.height;
		if (surface.kind == Win32) createSwapChain() else {
			Arena.scoped(a -> {
				var d = a.make(D3D11_TEXTURE2D_DESC);
				d.value.Width = width;
				d.value.Height = height;
				d.value.MipLevels = 1;
				d.value.ArraySize = 1;
				d.value.Format = D3D.FORMAT_R8G8B8A8_UNORM;
				d.value.SampleCount = 1;
				d.value.Usage = D3D.USAGE_DEFAULT;
				d.value.BindFlags = D3D.BIND_RENDER_TARGET;
				check(ID3D11Device.CreateTexture2D(device, d, Ptr.nil(), scratch), "CreateTexture2D");
			});
			target = scratch.value;
			createView();
		}
	}

	// the device and its context into scratch[0] and [1]
	function createDevice(driver:Int, level:Ptr<Int32>):Int
		return D3D11.D3D11CreateDevice(Ptr.nil(), driver, Ptr.nil(), 0, Ptr.nil(), 0, D3D.SDK_VERSION, scratch, level, scratch.offset(1));

	function check(hr:Int, what:String)
		if (hr < 0) throw "hxmc.gfx: " + what + " failed (HRESULT 0x" + StringTools.hex(hr, 8) + ")";

	// the window's swap chain, from the factory of the device's adapter
	function createSwapChain() {
		check(IUnknown.QueryInterface(device, IID.IDXGIDevice, scratch), "QueryInterface(IDXGIDevice)");
		var dxgi = scratch.value;
		var hr = IDXGIDevice.GetAdapter(dxgi, scratch);
		Com.release(dxgi);
		check(hr, "IDXGIDevice::GetAdapter");
		var adapter = scratch.value;
		hr = IDXGIAdapter.GetParent(adapter, IID.IDXGIFactory2, scratch);
		Com.release(adapter);
		check(hr, "IDXGIAdapter::GetParent(IDXGIFactory2)");
		var factory = scratch.value;
		hr = Arena.scopedValue(a -> {
			var d = a.make(DXGI_SWAP_CHAIN_DESC1);
			d.value.Width = width;
			d.value.Height = height;
			d.value.Format = D3D.FORMAT_R8G8B8A8_UNORM;
			d.value.SampleCount = 1;
			d.value.BufferUsage = D3D.USAGE_RENDER_TARGET_OUTPUT;
			d.value.BufferCount = 2;
			d.value.Scaling = D3D.SCALING_STRETCH;
			d.value.SwapEffect = D3D.SWAP_EFFECT_FLIP_DISCARD;
			IDXGIFactory2.CreateSwapChainForHwnd(factory, device, surface.handle, d, Ptr.nil(), Ptr.nil(), scratch);
		});
		if (hr >= 0) IDXGIFactory2.MakeWindowAssociation(factory, surface.handle, D3D.MWA_NO_ALT_ENTER);
		Com.release(factory);
		check(hr, "CreateSwapChainForHwnd");
		swapChain = scratch.value;
		backBuffer();
	}

	function backBuffer() {
		check(IDXGISwapChain1.GetBuffer(swapChain, 0, IID.ID3D11Texture2D, scratch), "IDXGISwapChain1::GetBuffer");
		target = scratch.value;
		createView();
	}

	function createView() {
		check(ID3D11Device.CreateRenderTargetView(device, target, Ptr.nil(), scratch), "CreateRenderTargetView");
		view = scratch.value;
	}

	public function createBuffer(d:BufferDesc):Int {
		var data = d.data, size = d.size;
		if (data != null && data.length < size) throw "hxmc.gfx: createBuffer: data has fewer than size bytes";
		var hr = Arena.scopedValue(a -> {
			var desc = a.make(D3D11_BUFFER_DESC);
			// (constant buffers: a multiple of 16 bytes)
			desc.value.ByteWidth = d.usage == Uniform ? (size + 15) & ~15 : size;
			desc.value.Usage = D3D.USAGE_DEFAULT;
			desc.value.BindFlags = switch d.usage {
				case Index: D3D.BIND_INDEX_BUFFER;
				case Uniform: D3D.BIND_CONSTANT_BUFFER;
				case _: D3D.BIND_VERTEX_BUFFER;
			}
			var init:Ptr<D3D11_SUBRESOURCE_DATA> = Ptr.nil();
			if (data != null) {
				init = a.make(D3D11_SUBRESOURCE_DATA);
				init.value.pSysMem = a.copyBytes(data, 0, size);
			}
			ID3D11Device.CreateBuffer(device, desc, init, scratch);
		});
		check(hr, "CreateBuffer (" + size + " bytes)");
		buffers.push(scratch.value);
		usages.push(d.usage);
		return buffers.length;
	}

	public function writeBuffer(id:Int, offset:Int, data:haxe.io.Bytes, dataOffset:Int, size:Int) {
		var uniform = usages[id - 1] == Uniform;
		if (uniform && offset != 0) throw "hxmc.gfx: writeBuffer: D3D11 writes a uniform buffer whole";
		Arena.scoped(a -> {
			// (a constant buffer: no box)
			var box:Ptr<D3D11_BOX> = Ptr.nil();
			if (!uniform) {
				box = a.make(D3D11_BOX);
				box.value.left = offset;
				box.value.right = offset + size;
				box.value.bottom = 1;
				box.value.back = 1;
			}
			ID3D11DeviceContext.UpdateSubresource(context, buffers[id - 1], 0, box, a.copyBytes(data, dataOffset, size), 0, 0);
		});
	}

	public function createTexture(d:TextureDesc):Int {
		var bpp = d.format.bytesPerPixel;
		var hr = Arena.scopedValue(a -> {
			var desc = a.make(D3D11_TEXTURE2D_DESC);
			desc.value.Width = d.width;
			desc.value.Height = d.height;
			desc.value.MipLevels = 1;
			desc.value.ArraySize = 1;
			desc.value.Format = d.format == R8 ? D3D.FORMAT_R8_UNORM : D3D.FORMAT_R8G8B8A8_UNORM;
			desc.value.SampleCount = 1;
			desc.value.Usage = D3D.USAGE_DEFAULT;
			desc.value.BindFlags = D3D.BIND_SHADER_RESOURCE;
			// (zeros unless given)
			var init = a.make(D3D11_SUBRESOURCE_DATA);
			init.value.pSysMem = d.data != null ? a.copyBytes(d.data, 0, d.width * d.height * bpp) : a.alloc(d.width * d.height * bpp);
			init.value.SysMemPitch = d.width * bpp;
			ID3D11Device.CreateTexture2D(device, desc, init.raw(), scratch);
		});
		check(hr, "CreateTexture2D (" + d.width + "x" + d.height + ")");
		var tex = scratch.value;
		hr = ID3D11Device.CreateShaderResourceView(device, tex, Ptr.nil(), scratch);
		if (hr < 0) Com.release(tex);
		check(hr, "CreateShaderResourceView");
		var view = scratch.value;
		var filter = d.filter == Nearest ? 1 : 0;
		if (samplers[filter].isNull()) {
			hr = Arena.scopedValue(a -> {
				var s = a.make(D3D11_SAMPLER_DESC);
				s.value.Filter = filter == 1 ? D3D.FILTER_MIN_MAG_MIP_POINT : D3D.FILTER_MIN_MAG_MIP_LINEAR;
				s.value.AddressU = D3D.TEXTURE_ADDRESS_CLAMP;
				s.value.AddressV = D3D.TEXTURE_ADDRESS_CLAMP;
				s.value.AddressW = D3D.TEXTURE_ADDRESS_CLAMP;
				s.value.MaxAnisotropy = 1;
				s.value.ComparisonFunc = D3D.COMPARISON_NEVER;
				s.value.MaxLOD = 3.402823466e38;
				ID3D11Device.CreateSamplerState(device, s, scratch);
			});
			check(hr, "CreateSamplerState");
			samplers[filter] = scratch.value;
		}
		textures.push(new D3DTexture(tex, view, samplers[filter], d.width, d.height, bpp));
		return textures.length;
	}

	public function writeTexture(id:Int, x:Int, y:Int, w:Int, h:Int, data:haxe.io.Bytes, dataOffset:Int) {
		var t = textures[id - 1];
		if (x < 0 || y < 0 || x + w > t.width || y + h > t.height) throw "hxmc.gfx: writeTexture: outside the texture";
		Arena.scoped(a -> {
			var box = a.make(D3D11_BOX);
			box.value.left = x;
			box.value.top = y;
			box.value.right = x + w;
			box.value.bottom = y + h;
			box.value.back = 1;
			ID3D11DeviceContext.UpdateSubresource(context, t.texture, 0, box, a.copyBytes(data, dataOffset, w * h * t.bpp), w * t.bpp, 0);
		});
	}

	public function setTexture(slot:Int, id:Int) {
		var t = id == 0 ? null : textures[id - 1];
		scratch.value = t == null ? Ptr.nil() : t.view;
		ID3D11DeviceContext.PSSetShaderResources(context, slot, 1, scratch);
		scratch.value = t == null ? Ptr.nil() : t.sampler;
		ID3D11DeviceContext.PSSetSamplers(context, slot, 1, scratch);
	}

	public function setScissor(x:Int, y:Int, w:Int, h:Int) {
		var x0 = x < 0 ? 0 : x > width ? width : x, y0 = y < 0 ? 0 : y > height ? height : y;
		var x1 = x + w > width ? width : x + w, y1 = y + h > height ? height : y + h;
		Arena.scoped(a -> {
			var r = a.make(D3D11_RECT);
			r.value.left = x0;
			r.value.top = y0;
			r.value.right = x1 < x0 ? x0 : x1;
			r.value.bottom = y1 < y0 ? y0 : y1;
			ID3D11DeviceContext.RSSetScissorRects(context, 1, r);
		});
	}

	public function createShader(d:ShaderDesc):Int {
		if (d.code.hlsl == null) throw "hxmc.gfx: createShader: no HLSL source for the D3D11 back end";
		var vertex = d.stage == Vertex;
		scratch.offset(1).value = Ptr.nil();
		var hr = Arena.scopedValue(a -> {
			var src = a.cstring(d.code.hlsl), target = a.cstring((vertex ? "vs" : "ps") + shaderModel);
			D3DCompiler.D3DCompile(src, LibC.strlen(src), Ptr.nil(), Ptr.nil(), Ptr.nil(), Mem.cstr("main"), target, 0, 0, scratch, scratch.offset(1));
		});
		var errors = scratch.offset(1).value;
		var text:Ptr<UInt8> = errors.isNull() ? Ptr.nil() : ID3DBlob.GetBufferPointer(errors);
		var log = errors.isNull() ? "" : (text : CString).toString();
		Com.release(errors);
		if (hr < 0) throw "hxmc.gfx: the shader does not compile (HRESULT 0x" + StringTools.hex(hr, 8) + "):\n" + log;
		var blob = scratch.value;
		var code = ID3DBlob.GetBufferPointer(blob), size = ID3DBlob.GetBufferSize(blob);
		hr = vertex ? ID3D11Device.CreateVertexShader(device, code, size, Ptr.nil(), scratch) : ID3D11Device.CreatePixelShader(device, code, size,
			Ptr.nil(), scratch);
		if (hr < 0) Com.release(blob);
		check(hr, vertex ? "CreateVertexShader" : "CreatePixelShader");
		// (a vertex shader's code: its pipelines' input layouts are checked against it)
		if (!vertex) {
			Com.release(blob);
			blob = Ptr.nil();
		}
		shaders.push(new D3DShader(scratch.value, blob));
		return shaders.length;
	}

	public function createPipeline(d:PipelineDesc):Int {
		if (d.layout.length > MAX_SLOTS) throw "hxmc.gfx: more than " + MAX_SLOTS + " vertex buffers";
		var vs = shaders[d.vertex.id() - 1], ps = shaders[d.fragment.id() - 1];
		var count = 0;
		for (l in d.layout)
			count += l.attributes.length;
		var hr = Arena.scopedValue(a -> {
			var e = a.makeArray(D3D11_INPUT_ELEMENT_DESC, count), i = 0;
			var semantic = Mem.cstr("TEXCOORD");
			for (slot in 0...d.layout.length)
				for (at in d.layout[slot].attributes) {
					var el = e.offset(i++);
					el.value.SemanticName = semantic;
					el.value.SemanticIndex = at.location;
					el.value.Format = switch at.format {
						case Float1: D3D.FORMAT_R32_FLOAT;
						case Float2: D3D.FORMAT_R32G32_FLOAT;
						case Float3: D3D.FORMAT_R32G32B32_FLOAT;
						case Float4: D3D.FORMAT_R32G32B32A32_FLOAT;
						case UByte4Norm: D3D.FORMAT_R8G8B8A8_UNORM;
					}
					el.value.InputSlot = slot;
					el.value.AlignedByteOffset = at.offset;
					el.value.InputSlotClass = D3D.INPUT_PER_VERTEX_DATA;
				}
			ID3D11Device.CreateInputLayout(device, e, count, ID3DBlob.GetBufferPointer(vs.code), ID3DBlob.GetBufferSize(vs.code), scratch);
		});
		check(hr, "CreateInputLayout");
		var layout = scratch.value;
		hr = Arena.scopedValue(a -> {
			var r = a.make(D3D11_RASTERIZER_DESC);
			r.value.FillMode = D3D.FILL_SOLID;
			r.value.CullMode = switch d.cull {
				case null | None: D3D.CULL_NONE;
				case Front: D3D.CULL_FRONT;
				case Back: D3D.CULL_BACK;
			}
			// (GL's front faces)
			r.value.FrontCounterClockwise = 1;
			r.value.DepthClipEnable = 1;
			r.value.ScissorEnable = 1;
			ID3D11Device.CreateRasterizerState(device, r, scratch);
		});
		if (hr < 0) Com.release(layout);
		check(hr, "CreateRasterizerState");
		var rasterizer = scratch.value;
		var blend = Ptr.nil();
		if (d.blend != null && d.blend != Replace) {
			hr = Arena.scopedValue(a -> {
				var b:Ptr<D3D11_BLEND_DESC> = a.alloc(BLEND_DESC_SIZE);
				b.value.BlendEnable = 1;
				b.value.SrcBlend = d.blend == Alpha ? D3D.BLEND_SRC_ALPHA : D3D.BLEND_ONE;
				b.value.DestBlend = d.blend == Add ? D3D.BLEND_ONE : D3D.BLEND_INV_SRC_ALPHA;
				b.value.BlendOp = D3D.BLEND_OP_ADD;
				b.value.SrcBlendAlpha = D3D.BLEND_ONE;
				b.value.DestBlendAlpha = D3D.BLEND_INV_SRC_ALPHA;
				b.value.BlendOpAlpha = D3D.BLEND_OP_ADD;
				b.value.RenderTargetWriteMask = D3D.COLOR_WRITE_ENABLE_ALL;
				ID3D11Device.CreateBlendState(device, b, scratch);
			});
			if (hr < 0) {
				Com.release(layout);
				Com.release(rasterizer);
			}
			check(hr, "CreateBlendState");
			blend = scratch.value;
		}
		pipelines.push(new D3DPipeline(vs.shader, ps.shader, layout, rasterizer, blend, d));
		return pipelines.length;
	}

	public function beginFrame():Bool {
		if (swapChain.isNull() || (surface.width == width && surface.height == height)) return true;
		// the window was resized: the swap chain's buffers follow
		ID3D11DeviceContext.OMSetRenderTargets(context, 0, Ptr.nil(), Ptr.nil());
		Com.release(view);
		Com.release(target);
		var hr = IDXGISwapChain1.ResizeBuffers(swapChain, 0, surface.width, surface.height, D3D.FORMAT_UNKNOWN, 0);
		check(hr, "IDXGISwapChain1::ResizeBuffers");
		width = surface.width;
		height = surface.height;
		backBuffer();
		return true;
	}

	public function beginPass(p:PassDesc) {
		// (a flip-model swap chain unbinds its buffer at each Present)
		scratch.value = view;
		ID3D11DeviceContext.OMSetRenderTargets(context, 1, scratch, Ptr.nil());
		viewport.value.TopLeftX = 0;
		viewport.value.TopLeftY = 0;
		viewport.value.Width = width;
		viewport.value.Height = height;
		viewport.value.MinDepth = 0;
		viewport.value.MaxDepth = 1;
		ID3D11DeviceContext.RSSetViewports(context, 1, viewport);
		setScissor(0, 0, width, height);
		var c = p.colors[0];
		if (c.load == Clear) {
			var k = c.clear;
			clear[0] = k == null ? 0 : k.r;
			clear[1] = k == null ? 0 : k.g;
			clear[2] = k == null ? 0 : k.b;
			clear[3] = k == null ? 1 : k.a;
			ID3D11DeviceContext.ClearRenderTargetView(context, view, clear);
		}
		pipeline = null;
		dirty = true;
	}

	public function setPipeline(id:Int) {
		var p = pipelines[id - 1];
		if (p == pipeline) return;
		pipeline = p;
		ID3D11DeviceContext.VSSetShader(context, p.vs, Ptr.nil(), 0);
		ID3D11DeviceContext.PSSetShader(context, p.ps, Ptr.nil(), 0);
		ID3D11DeviceContext.IASetInputLayout(context, p.layout);
		ID3D11DeviceContext.IASetPrimitiveTopology(context, p.topology);
		ID3D11DeviceContext.RSSetState(context, p.rasterizer);
		ID3D11DeviceContext.OMSetBlendState(context, p.blend, Ptr.nil(), 0xFFFFFFFF);
		dirty = true;
	}

	public function setVertexBuffer(slot:Int, id:Int, offset:Int) {
		vbufs[slot] = buffers[id - 1];
		offsets[slot] = offset;
		dirty = true;
	}

	public function draw(vertices:Int, instances:Int, first:Int) {
		var p = pipeline;
		if (dirty) {
			// (the strides are the pipeline's: bound with its buffers at the first draw)
			for (i in 0...p.strides.length)
				strides[i] = p.strides[i];
			if (p.strides.length > 0) ID3D11DeviceContext.IASetVertexBuffers(context, 0, p.strides.length, vbufs, strides, offsets);
			dirty = false;
		}
		if (instances == 1) ID3D11DeviceContext.Draw(context, vertices, first) else
			ID3D11DeviceContext.DrawInstanced(context, vertices, instances, first, 0);
	}

	public function endPass() {}

	public function endFrame() {
		if (swapChain.isNull()) {
			ID3D11DeviceContext.Flush(context);
			return;
		}
		// (vsync; a lost device is not recovered yet)
		var hr = IDXGISwapChain1.Present(swapChain, 1, 0);
		if (hr == D3D.DXGI_ERROR_DEVICE_REMOVED || hr == D3D.DXGI_ERROR_DEVICE_RESET)
			check(ID3D11Device.GetDeviceRemovedReason(device), "Present: the device was removed");
	}

	public function readPixels(dst:haxe.io.Bytes) {
		var row = width * 4;
		if (dst.length < row * height) throw "hxmc.gfx: readPixels: " + row * height + " bytes needed";
		if (stagingWidth != width || stagingHeight != height) {
			Com.release(staging);
			Arena.scoped(a -> {
				var d = a.make(D3D11_TEXTURE2D_DESC);
				d.value.Width = width;
				d.value.Height = height;
				d.value.MipLevels = 1;
				d.value.ArraySize = 1;
				d.value.Format = D3D.FORMAT_R8G8B8A8_UNORM;
				d.value.SampleCount = 1;
				d.value.Usage = D3D.USAGE_STAGING;
				d.value.CPUAccessFlags = D3D.CPU_ACCESS_READ;
				check(ID3D11Device.CreateTexture2D(device, d, Ptr.nil(), scratch), "CreateTexture2D (staging)");
			});
			staging = scratch.value;
			stagingWidth = width;
			stagingHeight = height;
		}
		ID3D11DeviceContext.CopyResource(context, staging, target);
		// (waits for the GPU)
		check(ID3D11DeviceContext.Map(context, staging, 0, D3D.MAP_READ, 0, mapped), "Map");
		var src:Ptr<UInt8> = mapped.value.pData, pitch:Int = mapped.value.RowPitch;
		for (y in 0...height)
			LibC.memcpy(Mem.addr(dst).add(8 + y * row), src.add(y * pitch), (row : Int64));
		ID3D11DeviceContext.Unmap(context, staging, 0);
	}

	// (the id stays taken: ids are indices; the context keeps what it has bound)
	public function destroyBuffer(id:Int) {
		Com.release(buffers[id - 1]);
		buffers[id - 1] = Ptr.nil();
	}

	public function destroyTexture(id:Int) {
		var t = textures[id - 1];
		if (t == null) return;
		Com.release(t.view);
		Com.release(t.texture);
		textures[id - 1] = null;
	}

	public function dispose() {
		ID3D11DeviceContext.ClearState(context);
		ID3D11DeviceContext.Flush(context);
		for (p in pipelines) {
			Com.release(p.layout);
			Com.release(p.rasterizer);
			Com.release(p.blend);
		}
		for (t in textures)
			if (t != null) {
				Com.release(t.view);
				Com.release(t.texture);
			}
		for (s in samplers)
			Com.release(s);
		for (s in shaders) {
			Com.release(s.shader);
			Com.release(s.code);
		}
		for (b in buffers)
			Com.release(b);
		Com.release(staging);
		Com.release(view);
		Com.release(target);
		Com.release(swapChain);
		Com.release(context);
		Com.release(device);
		LibC.free(scratch);
		LibC.free(clear);
		LibC.free(viewport);
		LibC.free(mapped);
		LibC.free(vbufs);
		LibC.free(strides);
		LibC.free(offsets);
	}
}

// a compiled shader (ID3D11VertexShader or ID3D11PixelShader) and, for a
// vertex shader, its code (an ID3DBlob)
private class D3DShader {
	public final shader:Ptr;
	public final code:Ptr;

	public function new(shader:Ptr, code:Ptr) {
		this.shader = shader;
		this.code = code;
	}
}

// a texture, its shader resource view and its sampler (shared)
private class D3DTexture {
	public final texture:Ptr;
	public final view:Ptr;
	public final sampler:Ptr;
	public final width:Int;
	public final height:Int;
	public final bpp:Int;

	public function new(texture:Ptr, view:Ptr, sampler:Ptr, width:Int, height:Int, bpp:Int) {
		this.texture = texture;
		this.view = view;
		this.sampler = sampler;
		this.width = width;
		this.height = height;
		this.bpp = bpp;
	}
}

// the state objects a pipeline sets, and its vertex buffers' strides
private class D3DPipeline {
	public final vs:Ptr;
	public final ps:Ptr;
	public final layout:Ptr; // ID3D11InputLayout
	public final rasterizer:Ptr; // ID3D11RasterizerState
	public final blend:Ptr; // ID3D11BlendState (nil: Replace)
	public final topology:Int;
	public final strides:Array<Int> = [];

	public function new(vs:Ptr, ps:Ptr, layout:Ptr, rasterizer:Ptr, blend:Ptr, d:PipelineDesc) {
		this.blend = blend;
		this.vs = vs;
		this.ps = ps;
		this.layout = layout;
		this.rasterizer = rasterizer;
		topology = switch d.topology {
			case null | Triangles: D3D.TOPOLOGY_TRIANGLELIST;
			case TriangleStrip: D3D.TOPOLOGY_TRIANGLESTRIP;
			case Lines: D3D.TOPOLOGY_LINELIST;
			case Points: D3D.TOPOLOGY_POINTLIST;
		}
		for (l in d.layout)
			strides.push(l.stride);
	}
}
