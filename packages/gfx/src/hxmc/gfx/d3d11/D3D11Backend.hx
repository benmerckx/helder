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
// SPIRV-Cross names them); a 32-bit float depth buffer of the target's
// size; a pipeline's state objects (rasterizer, depth, blend) made with it.
// A texture at slot n is a shader resource view at tn and its sampler at
// sn, in both stages.
// readPixels copies the target into a staging texture
// and maps it. Uniform blocks: with Direct3D 11.1's constant buffer offsets
// (VSSetConstantBuffers1; WARP has them), a dynamic ring buffer written
// without overwriting (discarded at the frame's first block), else a
// dynamic constant buffer per slot, discarded at each setUniforms
// (HXMC_GFX_D3D11_NO_OFFSETS=1 forces that).
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
	var depth = Ptr.nil(); // the depth buffer (ID3D11Texture2D) and its ID3D11DepthStencilView
	var depthView = Ptr.nil();
	var upload = Ptr.nil(); // writeBuffer's copy of the data, of uploadSize bytes
	var uploadSize = 0;
	var staging = Ptr.nil(); // readPixels' texture, of stagingWidth x stagingHeight
	var stagingWidth = 0;
	var stagingHeight = 0;
	// native memory: out-parameters, the clear colour, the viewport, the
	// vertex buffers bound at the next draw
	final scratch:Ptr<Ptr>;
	final clear:Ptr<Float32>;
	final viewport:Ptr<D3D11_VIEWPORT>;
	final mapped:Ptr<D3D11_MAPPED_SUBRESOURCE>;
	final box:Ptr<D3D11_BOX>;
	final vbufs:Ptr<Ptr>;
	final strides:Ptr<Int32>;
	final offsets:Ptr<Int32>;
	final cbuf:Ptr<Ptr>; // setUniforms' arguments
	final cfirst:Ptr<Int32>;
	final cnum:Ptr<Int32>;

	// tables (handle = index + 1)
	final buffers:Array<Ptr> = []; // ID3D11Buffer
	final textures:Array<D3DTexture> = [];
	final samplers:Array<Ptr> = []; // ID3D11SamplerState
	final shaders:Array<D3DShader> = [];
	final pipelines:Array<D3DPipeline> = [];

	// draw state
	var pipeline:D3DPipeline = null;
	var dirty = true;
	// uniform blocks: the ID3D11DeviceContext1 (nil: no constant buffer
	// offsets), its ring and the next offset into it; else a buffer per slot
	var context1 = Ptr.nil();
	var ring = Ptr.nil();
	var cursor = 0;
	final slotBuffers:Array<Ptr> = [];
	final slotSizes:Array<Int> = [];

	static inline var MAX_SLOTS = 8;

	public function new(surface:Surface) {
		this.surface = surface;
		scratch = LibC.malloc(64);
		clear = LibC.malloc(16);
		viewport = LibC.malloc(24);
		mapped = LibC.malloc(16);
		box = LibC.malloc(24);
		vbufs = LibC.malloc(8 * MAX_SLOTS);
		strides = LibC.malloc(4 * MAX_SLOTS);
		offsets = LibC.malloc(4 * MAX_SLOTS);
		LibC.memset(vbufs, 0, 8 * MAX_SLOTS);
		cbuf = LibC.malloc(8);
		cfirst = LibC.malloc(4);
		cnum = LibC.malloc(4);
		var level:Ptr<Int32> = scratch.offset(2).raw();
		var hr = Sys.getEnv("HXMC_GFX_SOFTWARE") == "1" ? -1 : createDevice(D3D.DRIVER_TYPE_HARDWARE, level);
		if (hr < 0) hr = createDevice(D3D.DRIVER_TYPE_WARP, level);
		check(hr, "D3D11CreateDevice");
		device = scratch.value;
		context = scratch.offset(1).value;
		shaderModel = level.value >= D3D.FEATURE_LEVEL_11_0 ? "_5_0" : "_4_0";
		if (Sys.getEnv("HXMC_GFX_D3D11_NO_OFFSETS") != "1") offsetting();
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
			createDepth();
		}
	}

	// the context's 11.1 interface, if constant buffers take offsets there
	function offsetting() {
		if (IUnknown.QueryInterface(context, IID.ID3D11DeviceContext1, scratch) < 0) return;
		var c1 = scratch.value;
		var ok = Arena.scopedValue(a -> {
			var o:Ptr<Int32> = a.alloc(56);
			LibC.memset(o, 0, 56);
			ID3D11Device.CheckFeatureSupport(device, D3D.FEATURE_D3D11_OPTIONS, o, 56) >= 0 && o[7] != 0 && o[8] != 0;
		});
		if (ok) context1 = c1 else Com.release(c1);
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
		createDepth();
	}

	function createView() {
		check(ID3D11Device.CreateRenderTargetView(device, target, Ptr.nil(), scratch), "CreateRenderTargetView");
		view = scratch.value;
	}

	// the depth buffer, of the target's size
	function createDepth() {
		Com.release(depthView);
		Com.release(depth);
		Arena.scoped(a -> {
			var d = a.make(D3D11_TEXTURE2D_DESC);
			d.value.Width = width;
			d.value.Height = height;
			d.value.MipLevels = 1;
			d.value.ArraySize = 1;
			d.value.Format = D3D.FORMAT_D32_FLOAT;
			d.value.SampleCount = 1;
			d.value.Usage = D3D.USAGE_DEFAULT;
			d.value.BindFlags = D3D.BIND_DEPTH_STENCIL;
			check(ID3D11Device.CreateTexture2D(device, d, Ptr.nil(), scratch), "CreateTexture2D (depth)");
		});
		depth = scratch.value;
		check(ID3D11Device.CreateDepthStencilView(device, depth, Ptr.nil(), scratch), "CreateDepthStencilView");
		depthView = scratch.value;
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
		return buffers.length;
	}

	public function writeBuffer(id:Int, offset:Int, data:haxe.io.Bytes, dataOffset:Int, size:Int) {
		// (a copy first: the Bytes may move during the call)
		if (uploadSize < size) {
			LibC.free(upload);
			upload = LibC.malloc((size : Int64));
			uploadSize = size;
		}
		LibC.memcpy(upload, Mem.addr(data).add(8 + dataOffset), (size : Int64));
		box.value.left = offset;
		box.value.right = offset + size;
		box.value.top = 0;
		box.value.bottom = 1;
		box.value.front = 0;
		box.value.back = 1;
		ID3D11DeviceContext.UpdateSubresource(context, buffers[id - 1], 0, box, upload, 0, 0);
	}

	public function createTexture(d:TextureDesc):Int {
		var hr = Arena.scopedValue(a -> {
			var t = a.make(D3D11_TEXTURE2D_DESC);
			t.value.Width = d.width;
			t.value.Height = d.height;
			t.value.MipLevels = 1;
			t.value.ArraySize = 1;
			t.value.Format = D3D.FORMAT_R8G8B8A8_UNORM;
			t.value.SampleCount = 1;
			t.value.Usage = D3D.USAGE_DEFAULT;
			t.value.BindFlags = D3D.BIND_SHADER_RESOURCE;
			var init:Ptr<D3D11_SUBRESOURCE_DATA> = Ptr.nil();
			if (d.data != null) {
				init = a.make(D3D11_SUBRESOURCE_DATA);
				init.value.pSysMem = a.copyBytes(d.data, 0, d.width * d.height * 4);
				init.value.SysMemPitch = d.width * 4;
			}
			ID3D11Device.CreateTexture2D(device, t, init, scratch);
		});
		check(hr, "CreateTexture2D (" + d.width + "x" + d.height + ")");
		var tex = scratch.value;
		hr = ID3D11Device.CreateShaderResourceView(device, tex, Ptr.nil(), scratch);
		if (hr < 0) Com.release(tex);
		check(hr, "CreateShaderResourceView");
		textures.push(new D3DTexture(tex, scratch.value, d.width, d.height));
		return textures.length;
	}

	public function writeTexture(id:Int, data:haxe.io.Bytes) {
		var t = textures[id - 1];
		if (data.length < t.width * t.height * 4) throw "hxmc.gfx: writeTexture: data has fewer than width * height * 4 bytes";
		Arena.scoped(a -> ID3D11DeviceContext.UpdateSubresource(context, t.texture, 0, Ptr.nil(), a.copyBytes(data, 0, t.width * t.height * 4), t.width * 4, 0));
	}

	public function createSampler(d:SamplerDesc):Int {
		var hr = Arena.scopedValue(a -> {
			var s = a.make(D3D11_SAMPLER_DESC);
			s.value.Filter = d.filter == Nearest ? D3D.FILTER_MIN_MAG_MIP_POINT : D3D.FILTER_MIN_MAG_MIP_LINEAR;
			var w = switch d.wrap {
				case null | Repeat: D3D.TEXTURE_ADDRESS_WRAP;
				case Clamp: D3D.TEXTURE_ADDRESS_CLAMP;
				case Mirror: D3D.TEXTURE_ADDRESS_MIRROR;
			}
			s.value.AddressU = w;
			s.value.AddressV = w;
			s.value.AddressW = w;
			s.value.MipLODBias = 0;
			s.value.MaxAnisotropy = 1;
			s.value.ComparisonFunc = D3D.COMPARISON_NEVER;
			s.value.BorderColor0 = 0;
			s.value.BorderColor1 = 0;
			s.value.BorderColor2 = 0;
			s.value.BorderColor3 = 0;
			s.value.MinLOD = 0;
			s.value.MaxLOD = 3.402823466e38;
			ID3D11Device.CreateSamplerState(device, s, scratch);
		});
		check(hr, "CreateSamplerState");
		samplers.push(scratch.value);
		return samplers.length;
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
			ID3D11Device.CreateRasterizerState(device, r, scratch);
		});
		if (hr < 0) Com.release(layout);
		check(hr, "CreateRasterizerState");
		var rasterizer = scratch.value;
		hr = Arena.scopedValue(a -> {
			var s = a.make(D3D11_DEPTH_STENCIL_DESC);
			var c:Compare = d.depthCompare == null ? Always : d.depthCompare, write = d.depthWrite == true;
			// (no test: nothing written either)
			s.value.DepthEnable = c == Always && !write ? 0 : 1;
			s.value.DepthWriteMask = write ? 1 : 0;
			s.value.DepthFunc = D3D.COMPARISON_NEVER + (cast c : Int);
			s.value.StencilEnable = 0;
			s.value.StencilReadMask = 0xFF;
			s.value.StencilWriteMask = 0xFF;
			s.value.FrontStencilFailOp = s.value.FrontStencilDepthFailOp = s.value.FrontStencilPassOp = D3D.STENCIL_OP_KEEP;
			s.value.BackStencilFailOp = s.value.BackStencilDepthFailOp = s.value.BackStencilPassOp = D3D.STENCIL_OP_KEEP;
			s.value.FrontStencilFunc = s.value.BackStencilFunc = D3D.COMPARISON_ALWAYS;
			ID3D11Device.CreateDepthStencilState(device, s, scratch);
		});
		check(hr, "CreateDepthStencilState");
		var depthState = scratch.value;
		hr = Arena.scopedValue(a -> {
			var b:Ptr<D3D11_BLEND_DESC> = a.alloc(264);
			LibC.memset(b, 0, 264);
			var blend:Blend = d.blend == null ? Opaque : d.blend;
			b.value.BlendEnable = blend == Opaque ? 0 : 1;
			b.value.SrcBlend = blend == Premultiplied ? D3D.BLEND_ONE : D3D.BLEND_SRC_ALPHA;
			b.value.DestBlend = blend == Additive ? D3D.BLEND_ONE : D3D.BLEND_INV_SRC_ALPHA;
			b.value.BlendOp = D3D.BLEND_OP_ADD;
			b.value.SrcBlendAlpha = D3D.BLEND_ONE;
			b.value.DestBlendAlpha = blend == Additive ? D3D.BLEND_ONE : D3D.BLEND_INV_SRC_ALPHA;
			b.value.BlendOpAlpha = D3D.BLEND_OP_ADD;
			b.value.RenderTargetWriteMask = 0xF;
			ID3D11Device.CreateBlendState(device, b, scratch);
		});
		check(hr, "CreateBlendState");
		pipelines.push(new D3DPipeline(vs.shader, ps.shader, layout, rasterizer, depthState, scratch.value, d));
		return pipelines.length;
	}

	public function beginFrame():Bool {
		cursor = 0;
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
		ID3D11DeviceContext.OMSetRenderTargets(context, 1, scratch, depthView);
		viewport.value.TopLeftX = 0;
		viewport.value.TopLeftY = 0;
		viewport.value.Width = width;
		viewport.value.Height = height;
		viewport.value.MinDepth = 0;
		viewport.value.MaxDepth = 1;
		ID3D11DeviceContext.RSSetViewports(context, 1, viewport);
		var c = p.colors[0];
		if (c.load != Load) {
			var k = c.clear;
			clear[0] = k == null ? 0 : k.r;
			clear[1] = k == null ? 0 : k.g;
			clear[2] = k == null ? 0 : k.b;
			clear[3] = k == null ? 1 : k.a;
			ID3D11DeviceContext.ClearRenderTargetView(context, view, clear);
		}
		var d = p.depth;
		if (d != null && d.load != Load) ID3D11DeviceContext.ClearDepthStencilView(context, depthView, D3D.CLEAR_DEPTH, d.clear == null ? 1 : d.clear, 0);
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
		ID3D11DeviceContext.OMSetDepthStencilState(context, p.depth, 0);
		ID3D11DeviceContext.OMSetBlendState(context, p.blend, Ptr.nil(), -1);
		dirty = true;
	}

	public function setVertexBuffer(slot:Int, id:Int, offset:Int) {
		vbufs[slot] = buffers[id - 1];
		offsets[slot] = offset;
		dirty = true;
	}

	public function setUniforms(slot:Int, data:haxe.io.Bytes, offset:Int, size:Int) {
		if (offset < 0 || size < 0 || offset + size > data.length) throw "hxmc.gfx: setUniforms: outside the data";
		// (constant buffers: whole 256-byte blocks of 16 constants)
		var n = (size + 255) & ~255;
		if (!context1.isNull()) {
			if (cursor + n > Encoder.UNIFORM_RING) throw "hxmc.gfx: setUniforms: more than " + Encoder.UNIFORM_RING + " bytes of uniforms in a frame";
			if (ring.isNull()) ring = dynamicBuffer(Encoder.UNIFORM_RING);
			check(ID3D11DeviceContext.Map(context, ring, 0, cursor == 0 ? D3D.MAP_WRITE_DISCARD : D3D.MAP_WRITE_NO_OVERWRITE, 0, mapped), "Map");
			LibC.memcpy((mapped.value.pData : Ptr<UInt8>).add(cursor), Mem.addr(data).add(8 + offset), (size : Int64));
			ID3D11DeviceContext.Unmap(context, ring, 0);
			cbuf.value = ring;
			cfirst.value = cursor >> 4;
			cnum.value = n >> 4;
			ID3D11DeviceContext1.VSSetConstantBuffers1(context1, slot, 1, cbuf, cfirst, cnum);
			ID3D11DeviceContext1.PSSetConstantBuffers1(context1, slot, 1, cbuf, cfirst, cnum);
			cursor += n;
			return;
		}
		while (slotBuffers.length <= slot) {
			slotBuffers.push(Ptr.nil());
			slotSizes.push(0);
		}
		if (slotSizes[slot] < n) {
			Com.release(slotBuffers[slot]);
			slotBuffers[slot] = dynamicBuffer(n);
			slotSizes[slot] = n;
		}
		var b = slotBuffers[slot];
		check(ID3D11DeviceContext.Map(context, b, 0, D3D.MAP_WRITE_DISCARD, 0, mapped), "Map");
		LibC.memcpy(mapped.value.pData, Mem.addr(data).add(8 + offset), (size : Int64));
		ID3D11DeviceContext.Unmap(context, b, 0);
		cbuf.value = b;
		ID3D11DeviceContext.VSSetConstantBuffers(context, slot, 1, cbuf);
		ID3D11DeviceContext.PSSetConstantBuffers(context, slot, 1, cbuf);
	}

	// a constant buffer the CPU writes (Map)
	function dynamicBuffer(size:Int):Ptr {
		var hr = Arena.scopedValue(a -> {
			var desc = a.make(D3D11_BUFFER_DESC);
			desc.value.ByteWidth = size;
			desc.value.Usage = D3D.USAGE_DYNAMIC;
			desc.value.BindFlags = D3D.BIND_CONSTANT_BUFFER;
			desc.value.CPUAccessFlags = D3D.CPU_ACCESS_WRITE;
			ID3D11Device.CreateBuffer(device, desc, Ptr.nil(), scratch);
		});
		check(hr, "CreateBuffer (uniforms, " + size + " bytes)");
		return scratch.value;
	}

	public function draw(vertices:Int, instances:Int, first:Int) {
		vertexBuffers();
		if (instances == 1) ID3D11DeviceContext.Draw(context, vertices, first) else
			ID3D11DeviceContext.DrawInstanced(context, vertices, instances, first, 0);
	}

	public function setTexture(slot:Int, texture:Int, sampler:Int) {
		cbuf.value = textures[texture - 1].view;
		ID3D11DeviceContext.VSSetShaderResources(context, slot, 1, cbuf);
		ID3D11DeviceContext.PSSetShaderResources(context, slot, 1, cbuf);
		cbuf.value = samplers[sampler - 1];
		ID3D11DeviceContext.VSSetSamplers(context, slot, 1, cbuf);
		ID3D11DeviceContext.PSSetSamplers(context, slot, 1, cbuf);
	}

	public function setIndexBuffer(id:Int, format:IndexFormat, offset:Int)
		ID3D11DeviceContext.IASetIndexBuffer(context, buffers[id - 1], format == UInt16 ? D3D.FORMAT_R16_UINT : D3D.FORMAT_R32_UINT, offset);

	public function drawIndexed(count:Int, instances:Int, first:Int, baseVertex:Int) {
		vertexBuffers();
		if (instances == 1) ID3D11DeviceContext.DrawIndexed(context, count, first, baseVertex) else
			ID3D11DeviceContext.DrawIndexedInstanced(context, count, instances, first, baseVertex, 0);
	}

	// the vertex buffers, after a pipeline or vertex buffer change
	function vertexBuffers() {
		if (!dirty) return;
		// (the strides are the pipeline's: bound with its buffers at the first draw)
		var p = pipeline;
		for (i in 0...p.strides.length)
			strides[i] = p.strides[i];
		if (p.strides.length > 0) ID3D11DeviceContext.IASetVertexBuffers(context, 0, p.strides.length, vbufs, strides, offsets);
		dirty = false;
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
		Com.release(depthView);
		Com.release(depth);
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

	public function dispose() {
		ID3D11DeviceContext.ClearState(context);
		ID3D11DeviceContext.Flush(context);
		for (p in pipelines) {
			Com.release(p.layout);
			Com.release(p.rasterizer);
			Com.release(p.depth);
			Com.release(p.blend);
		}
		for (s in shaders) {
			Com.release(s.shader);
			Com.release(s.code);
		}
		for (b in buffers)
			Com.release(b);
		for (b in slotBuffers)
			Com.release(b);
		for (t in textures) {
			Com.release(t.view);
			Com.release(t.texture);
		}
		for (s in samplers)
			Com.release(s);
		Com.release(ring);
		Com.release(context1);
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
		LibC.free(box);
		LibC.free(upload);
		LibC.free(vbufs);
		LibC.free(strides);
		LibC.free(offsets);
		LibC.free(cbuf);
		LibC.free(cfirst);
		LibC.free(cnum);
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

// a texture and its shader resource view
private class D3DTexture {
	public final texture:Ptr;
	public final view:Ptr;
	public final width:Int;
	public final height:Int;

	public function new(texture:Ptr, view:Ptr, width:Int, height:Int) {
		this.texture = texture;
		this.view = view;
		this.width = width;
		this.height = height;
	}
}

// the state objects a pipeline sets, and its vertex buffers' strides
private class D3DPipeline {
	public final vs:Ptr;
	public final ps:Ptr;
	public final layout:Ptr; // ID3D11InputLayout
	public final rasterizer:Ptr; // ID3D11RasterizerState
	public final depth:Ptr; // ID3D11DepthStencilState
	public final blend:Ptr; // ID3D11BlendState
	public final topology:Int;
	public final strides:Array<Int> = [];

	public function new(vs:Ptr, ps:Ptr, layout:Ptr, rasterizer:Ptr, depth:Ptr, blend:Ptr, d:PipelineDesc) {
		this.vs = vs;
		this.ps = ps;
		this.layout = layout;
		this.rasterizer = rasterizer;
		this.depth = depth;
		this.blend = blend;
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
