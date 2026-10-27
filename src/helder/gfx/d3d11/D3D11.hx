package helder.gfx.d3d11;

import hxmc.unsafe.*;
import helder.os.win32.Com.IUnknown;

// Direct3D 11, DXGI and the HLSL compiler: the system's C functions, then
// the COM interfaces the back end calls (Com: a method is its vtable slot
// in the official headers, the object its first argument). HRESULTs are
// Int (negative: failed), UINT and BOOL Int, SIZE_T Int64; objects and
// GUIDs are Ptr; out-parameters Ptr<Ptr>.
@:hxmc.c @:hxmc.lib("d3d11") extern class D3D11 {
	static function D3D11CreateDevice(adapter:Ptr, driverType:Int, software:Ptr, flags:Int, featureLevels:Ptr<Int32>, levels:Int, sdkVersion:Int,
		device:Ptr<Ptr>, featureLevel:Ptr<Int32>, context:Ptr<Ptr>):Int;
}

// d3dcompiler_47.dll: part of Windows since 8.1
@:hxmc.c @:hxmc.lib("d3dcompiler_47") extern class D3DCompiler {
	static function D3DCompile(src:Ptr, size:Int64, name:Ptr, defines:Ptr, include:Ptr, entry:Ptr, target:Ptr, flags1:Int, flags2:Int, code:Ptr<Ptr>,
		errors:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class ID3D11Device {
	@:slot(3) static function CreateBuffer(self:Ptr, desc:Ptr<D3D11_BUFFER_DESC>, data:Ptr<D3D11_SUBRESOURCE_DATA>, out:Ptr<Ptr>):Int;
	@:slot(5) static function CreateTexture2D(self:Ptr, desc:Ptr<D3D11_TEXTURE2D_DESC>, data:Ptr, out:Ptr<Ptr>):Int;
	@:slot(7) static function CreateShaderResourceView(self:Ptr, resource:Ptr, desc:Ptr, out:Ptr<Ptr>):Int;
	@:slot(9) static function CreateRenderTargetView(self:Ptr, resource:Ptr, desc:Ptr, out:Ptr<Ptr>):Int;
	@:slot(10) static function CreateDepthStencilView(self:Ptr, resource:Ptr, desc:Ptr, out:Ptr<Ptr>):Int;
	@:slot(11) static function CreateInputLayout(self:Ptr, elements:Ptr<D3D11_INPUT_ELEMENT_DESC>, count:Int, code:Ptr, size:Int64, out:Ptr<Ptr>):Int;
	@:slot(12) static function CreateVertexShader(self:Ptr, code:Ptr, size:Int64, linkage:Ptr, out:Ptr<Ptr>):Int;
	@:slot(15) static function CreatePixelShader(self:Ptr, code:Ptr, size:Int64, linkage:Ptr, out:Ptr<Ptr>):Int;
	@:slot(20) static function CreateBlendState(self:Ptr, desc:Ptr<D3D11_BLEND_DESC>, out:Ptr<Ptr>):Int;
	@:slot(21) static function CreateDepthStencilState(self:Ptr, desc:Ptr<D3D11_DEPTH_STENCIL_DESC>, out:Ptr<Ptr>):Int;
	@:slot(22) static function CreateRasterizerState(self:Ptr, desc:Ptr<D3D11_RASTERIZER_DESC>, out:Ptr<Ptr>):Int;
	@:slot(23) static function CreateSamplerState(self:Ptr, desc:Ptr<D3D11_SAMPLER_DESC>, out:Ptr<Ptr>):Int;
	@:slot(33) static function CheckFeatureSupport(self:Ptr, feature:Int, data:Ptr, size:Int):Int;
	@:slot(37) static function GetFeatureLevel(self:Ptr):Int;
	@:slot(39) static function GetDeviceRemovedReason(self:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
class ID3D11DeviceContext {
	@:slot(7) static function VSSetConstantBuffers(self:Ptr, start:Int, count:Int, buffers:Ptr<Ptr>):Void;
	@:slot(8) static function PSSetShaderResources(self:Ptr, start:Int, count:Int, views:Ptr<Ptr>):Void;
	@:slot(9) static function PSSetShader(self:Ptr, shader:Ptr, classes:Ptr, count:Int):Void;
	@:slot(10) static function PSSetSamplers(self:Ptr, start:Int, count:Int, samplers:Ptr<Ptr>):Void;
	@:slot(11) static function VSSetShader(self:Ptr, shader:Ptr, classes:Ptr, count:Int):Void;
	@:slot(12) static function DrawIndexed(self:Ptr, count:Int, first:Int, baseVertex:Int):Void;
	@:slot(13) static function Draw(self:Ptr, vertices:Int, first:Int):Void;
	@:slot(14) static function Map(self:Ptr, resource:Ptr, subresource:Int, type:Int, flags:Int, out:Ptr<D3D11_MAPPED_SUBRESOURCE>):Int;
	@:slot(15) static function Unmap(self:Ptr, resource:Ptr, subresource:Int):Void;
	@:slot(16) static function PSSetConstantBuffers(self:Ptr, start:Int, count:Int, buffers:Ptr<Ptr>):Void;
	@:slot(17) static function IASetInputLayout(self:Ptr, layout:Ptr):Void;
	@:slot(18) static function IASetVertexBuffers(self:Ptr, first:Int, count:Int, buffers:Ptr<Ptr>, strides:Ptr<Int32>, offsets:Ptr<Int32>):Void;
	@:slot(19) static function IASetIndexBuffer(self:Ptr, buffer:Ptr, format:Int, offset:Int):Void;
	@:slot(20) static function DrawIndexedInstanced(self:Ptr, count:Int, instances:Int, first:Int, baseVertex:Int, firstInstance:Int):Void;
	@:slot(21) static function DrawInstanced(self:Ptr, vertices:Int, instances:Int, first:Int, firstInstance:Int):Void;
	@:slot(24) static function IASetPrimitiveTopology(self:Ptr, topology:Int):Void;
	@:slot(25) static function VSSetShaderResources(self:Ptr, start:Int, count:Int, views:Ptr<Ptr>):Void;
	@:slot(26) static function VSSetSamplers(self:Ptr, start:Int, count:Int, samplers:Ptr<Ptr>):Void;
	@:slot(33) static function OMSetRenderTargets(self:Ptr, count:Int, views:Ptr<Ptr>, depth:Ptr):Void;
	@:slot(35) static function OMSetBlendState(self:Ptr, state:Ptr, factor:Ptr<Float32>, mask:Int):Void;
	@:slot(36) static function OMSetDepthStencilState(self:Ptr, state:Ptr, ref:Int):Void;
	@:slot(43) static function RSSetState(self:Ptr, state:Ptr):Void;
	@:slot(44) static function RSSetViewports(self:Ptr, count:Int, viewports:Ptr<D3D11_VIEWPORT>):Void;
	@:slot(47) static function CopyResource(self:Ptr, dst:Ptr, src:Ptr):Void;
	@:slot(48) static function UpdateSubresource(self:Ptr, dst:Ptr, subresource:Int, box:Ptr<D3D11_BOX>, src:Ptr, rowPitch:Int, depthPitch:Int):Void;
	@:slot(50) static function ClearRenderTargetView(self:Ptr, view:Ptr, rgba:Ptr<Float32>):Void;
	@:slot(53) static function ClearDepthStencilView(self:Ptr, view:Ptr, flags:Int, depth:Float32, stencil:Int):Void;
	@:slot(54) static function GenerateMips(self:Ptr, view:Ptr):Void;
	@:slot(110) static function ClearState(self:Ptr):Void;
	@:slot(111) static function Flush(self:Ptr):Void;
}

// (Direct3D 11.1: constant buffers at offsets, in 16-byte constants, 16 of them at a time)
@:build(helder.os.win32.Com.build())
class ID3D11DeviceContext1 {
	@:slot(119) static function VSSetConstantBuffers1(self:Ptr, start:Int, count:Int, buffers:Ptr<Ptr>, first:Ptr<Int32>, num:Ptr<Int32>):Void;
	@:slot(123) static function PSSetConstantBuffers1(self:Ptr, start:Int, count:Int, buffers:Ptr<Ptr>, first:Ptr<Int32>, num:Ptr<Int32>):Void;
}

@:build(helder.os.win32.Com.build())
class ID3DBlob {
	@:slot(3) static function GetBufferPointer(self:Ptr):Ptr;
	@:slot(4) static function GetBufferSize(self:Ptr):Int64;
}

@:build(helder.os.win32.Com.build())
class IDXGIDevice {
	@:slot(7) static function GetAdapter(self:Ptr, out:Ptr<Ptr>):Int;
}

// (IDXGIObject::GetParent: the adapter's factory)
@:build(helder.os.win32.Com.build())
class IDXGIAdapter {
	@:slot(6) static function GetParent(self:Ptr, iid:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class IDXGIFactory2 {
	@:slot(8) static function MakeWindowAssociation(self:Ptr, hwnd:Ptr, flags:Int):Int;
	@:slot(15) static function CreateSwapChainForHwnd(self:Ptr, device:Ptr, hwnd:Ptr, desc:Ptr<DXGI_SWAP_CHAIN_DESC1>, fullscreen:Ptr, output:Ptr,
		out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class IDXGISwapChain1 {
	@:slot(8) static function Present(self:Ptr, interval:Int, flags:Int):Int;
	@:slot(9) static function GetBuffer(self:Ptr, index:Int, iid:Ptr, out:Ptr<Ptr>):Int;
	@:slot(13) static function ResizeBuffers(self:Ptr, count:Int, width:Int, height:Int, format:Int, flags:Int):Int;
}

class D3D {
	public static inline var SDK_VERSION = 7;
	// D3D_DRIVER_TYPE
	public static inline var DRIVER_TYPE_HARDWARE = 1;
	public static inline var DRIVER_TYPE_WARP = 5;
	// D3D_FEATURE_LEVEL
	public static inline var FEATURE_LEVEL_11_0 = 0xB000;
	// DXGI_FORMAT
	public static inline var FORMAT_UNKNOWN = 0;
	public static inline var FORMAT_R32G32B32A32_FLOAT = 2;
	public static inline var FORMAT_R16G16B16A16_FLOAT = 10;
	public static inline var FORMAT_R8G8B8A8_UNORM_SRGB = 29;
	public static inline var FORMAT_R32_TYPELESS = 39;
	public static inline var FORMAT_R8G8_UNORM = 49;
	public static inline var FORMAT_R16_TYPELESS = 53;
	public static inline var FORMAT_D16_UNORM = 55;
	public static inline var FORMAT_R16_UNORM = 56;
	public static inline var FORMAT_R8_UNORM = 61;
	public static inline var FORMAT_R32G32B32_FLOAT = 6;
	public static inline var FORMAT_R8G8B8A8_UNORM = 28;
	public static inline var FORMAT_R32G32_FLOAT = 16;
	public static inline var FORMAT_R32_FLOAT = 41;
	public static inline var FORMAT_D32_FLOAT = 40;
	public static inline var FORMAT_R32_UINT = 42;
	public static inline var FORMAT_R16_UINT = 57;
	// D3D11_USAGE, D3D11_BIND_FLAG, D3D11_CPU_ACCESS_FLAG, D3D11_MAP
	public static inline var USAGE_DEFAULT = 0;
	public static inline var USAGE_DYNAMIC = 2;
	public static inline var USAGE_STAGING = 3;
	public static inline var BIND_VERTEX_BUFFER = 0x1;
	public static inline var BIND_INDEX_BUFFER = 0x2;
	public static inline var BIND_CONSTANT_BUFFER = 0x4;
	public static inline var BIND_SHADER_RESOURCE = 0x8;
	public static inline var BIND_RENDER_TARGET = 0x20;
	public static inline var BIND_DEPTH_STENCIL = 0x40;
	public static inline var RESOURCE_MISC_GENERATE_MIPS = 0x1;
	// D3D11_DSV_DIMENSION, D3D11_SRV_DIMENSION
	public static inline var DSV_DIMENSION_TEXTURE2D = 3;
	public static inline var SRV_DIMENSION_TEXTURE2D = 4;
	public static inline var CPU_ACCESS_WRITE = 0x10000;
	public static inline var CPU_ACCESS_READ = 0x20000;
	public static inline var MAP_READ = 1;
	public static inline var MAP_WRITE_DISCARD = 4;
	public static inline var MAP_WRITE_NO_OVERWRITE = 5;
	// D3D11_FEATURE: D3D11_OPTIONS (14 BOOLs: ConstantBufferOffsetting the 8th,
	// MapNoOverwriteOnDynamicConstantBuffer the 9th)
	public static inline var FEATURE_D3D11_OPTIONS = 7;
	// D3D11_INPUT_CLASSIFICATION
	public static inline var INPUT_PER_VERTEX_DATA = 0;
	public static inline var INPUT_PER_INSTANCE_DATA = 1;
	// D3D11_FILL_MODE, D3D11_CULL_MODE
	public static inline var FILL_SOLID = 3;
	public static inline var CULL_NONE = 1;
	public static inline var CULL_FRONT = 2;
	public static inline var CULL_BACK = 3;
	// D3D11_COMPARISON_FUNC (NEVER: 1 .. ALWAYS: 8), D3D11_STENCIL_OP, D3D11_CLEAR_FLAG
	public static inline var COMPARISON_NEVER = 1;
	public static inline var COMPARISON_ALWAYS = 8;
	public static inline var STENCIL_OP_KEEP = 1;
	public static inline var CLEAR_DEPTH = 1;
	// D3D11_FILTER, D3D11_TEXTURE_ADDRESS_MODE
	public static inline var FILTER_MIN_MAG_MIP_POINT = 0;
	public static inline var FILTER_MIN_MAG_MIP_LINEAR = 0x15; // MIN_MAG_LINEAR_MIP_POINT: 0x14, MIN_MAG_POINT_MIP_LINEAR: 0x1
	public static inline var TEXTURE_ADDRESS_WRAP = 1;
	public static inline var TEXTURE_ADDRESS_MIRROR = 2;
	public static inline var TEXTURE_ADDRESS_CLAMP = 3;
	// D3D11_BLEND, D3D11_BLEND_OP
	public static inline var BLEND_ZERO = 1;
	public static inline var BLEND_ONE = 2;
	public static inline var BLEND_SRC_ALPHA = 5;
	public static inline var BLEND_INV_SRC_ALPHA = 6;
	public static inline var BLEND_OP_ADD = 1;
	// D3D_PRIMITIVE_TOPOLOGY
	public static inline var TOPOLOGY_POINTLIST = 1;
	public static inline var TOPOLOGY_LINELIST = 2;
	public static inline var TOPOLOGY_TRIANGLELIST = 4;
	public static inline var TOPOLOGY_TRIANGLESTRIP = 5;
	// DXGI_USAGE, DXGI_SWAP_EFFECT, DXGI_SCALING, DXGI_MWA
	public static inline var USAGE_RENDER_TARGET_OUTPUT = 0x20;
	public static inline var SWAP_EFFECT_FLIP_DISCARD = 4;
	public static inline var SCALING_STRETCH = 0;
	public static inline var MWA_NO_ALT_ENTER = 2;
	// HRESULTs
	public static inline var DXGI_ERROR_DEVICE_REMOVED = 0x887A0005;
	public static inline var DXGI_ERROR_DEVICE_RESET = 0x887A0007;
}

// the interface ids the back end asks for, as the headers write them
class IID {
	public static final ID3D11Texture2D = guid(0x6f15aaf2, 0xd208, 0x4e89, [0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c]);
	public static final IDXGIDevice = guid(0x54ec77fa, 0x1377, 0x44e6, [0x8c, 0x32, 0x88, 0xfd, 0x5f, 0x44, 0xc8, 0x4c]);
	public static final IDXGIFactory2 = guid(0x50c83a1c, 0xe072, 0x4c48, [0x87, 0xb0, 0x36, 0x30, 0xfa, 0x36, 0xa6, 0xd0]);
	public static final ID3D11DeviceContext1 = guid(0xbb2c6faa, 0xb5fb, 0x4082, [0x8e, 0x6b, 0x38, 0x8b, 0x8c, 0xfa, 0x90, 0xe1]);

	// a GUID in native memory, kept for the process
	static function guid(d1:Int, d2:Int, d3:Int, d4:Array<Int>):Ptr {
		var p:Ptr<UInt8> = LibC.malloc(16), d:Ptr<Int32> = p.raw(), w:Ptr<UInt16> = p.raw();
		d.value = d1;
		w[2] = d2;
		w[3] = d3;
		for (i in 0...8)
			p[8 + i] = d4[i];
		return p;
	}
}

@:hxmc.struct @:publicFields class D3D11_BUFFER_DESC {
	var ByteWidth:UInt32;
	var Usage:Int32;
	var BindFlags:UInt32;
	var CPUAccessFlags:UInt32;
	var MiscFlags:UInt32;
	var StructureByteStride:UInt32;
}

@:hxmc.struct @:publicFields class D3D11_SUBRESOURCE_DATA {
	var pSysMem:Ptr;
	var SysMemPitch:UInt32;
	var SysMemSlicePitch:UInt32;
}

@:hxmc.struct @:publicFields class D3D11_TEXTURE2D_DESC {
	var Width:UInt32;
	var Height:UInt32;
	var MipLevels:UInt32;
	var ArraySize:UInt32;
	var Format:Int32;
	var SampleCount:UInt32; // DXGI_SAMPLE_DESC
	var SampleQuality:UInt32;
	var Usage:Int32;
	var BindFlags:UInt32;
	var CPUAccessFlags:UInt32;
	var MiscFlags:UInt32;
}

@:hxmc.struct @:publicFields class D3D11_INPUT_ELEMENT_DESC {
	var SemanticName:Ptr;
	var SemanticIndex:UInt32;
	var Format:Int32;
	var InputSlot:UInt32;
	var AlignedByteOffset:UInt32;
	var InputSlotClass:Int32;
	var InstanceDataStepRate:UInt32;
}

@:hxmc.struct @:publicFields class D3D11_RASTERIZER_DESC {
	var FillMode:Int32;
	var CullMode:Int32;
	var FrontCounterClockwise:Int32;
	var DepthBias:Int32;
	var DepthBiasClamp:Float32;
	var SlopeScaledDepthBias:Float32;
	var DepthClipEnable:Int32;
	var ScissorEnable:Int32;
	var MultisampleEnable:Int32;
	var AntialiasedLineEnable:Int32;
}

@:hxmc.struct @:publicFields class D3D11_DEPTH_STENCIL_DESC {
	var DepthEnable:Int32;
	var DepthWriteMask:Int32;
	var DepthFunc:Int32;
	var StencilEnable:Int32;
	var StencilReadMask:UInt8;
	var StencilWriteMask:UInt8;
	var FrontStencilFailOp:Int32; // D3D11_DEPTH_STENCILOP_DESC FrontFace
	var FrontStencilDepthFailOp:Int32;
	var FrontStencilPassOp:Int32;
	var FrontStencilFunc:Int32;
	var BackStencilFailOp:Int32; // BackFace
	var BackStencilDepthFailOp:Int32;
	var BackStencilPassOp:Int32;
	var BackStencilFunc:Int32;
}

// with the first of its 8 D3D11_RENDER_TARGET_BLEND_DESCs (allocate 264 bytes)
@:hxmc.struct @:publicFields class D3D11_BLEND_DESC {
	var AlphaToCoverageEnable:Int32;
	var IndependentBlendEnable:Int32;
	var BlendEnable:Int32;
	var SrcBlend:Int32;
	var DestBlend:Int32;
	var BlendOp:Int32;
	var SrcBlendAlpha:Int32;
	var DestBlendAlpha:Int32;
	var BlendOpAlpha:Int32;
	var RenderTargetWriteMask:UInt8;
}

@:hxmc.struct @:publicFields class D3D11_SAMPLER_DESC {
	var Filter:Int32;
	var AddressU:Int32;
	var AddressV:Int32;
	var AddressW:Int32;
	var MipLODBias:Float32;
	var MaxAnisotropy:UInt32;
	var ComparisonFunc:Int32;
	var BorderColor0:Float32; // BorderColor[4]
	var BorderColor1:Float32;
	var BorderColor2:Float32;
	var BorderColor3:Float32;
	var MinLOD:Float32;
	var MaxLOD:Float32;
}

@:hxmc.struct @:publicFields class D3D11_BOX {
	var left:UInt32;
	var top:UInt32;
	var front:UInt32;
	var right:UInt32;
	var bottom:UInt32;
	var back:UInt32;
}

@:hxmc.struct @:publicFields class D3D11_VIEWPORT {
	var TopLeftX:Float32;
	var TopLeftY:Float32;
	var Width:Float32;
	var Height:Float32;
	var MinDepth:Float32;
	var MaxDepth:Float32;
}

@:hxmc.struct @:publicFields class D3D11_MAPPED_SUBRESOURCE {
	var pData:Ptr;
	var RowPitch:UInt32;
	var DepthPitch:UInt32;
}

@:hxmc.struct @:publicFields class DXGI_SWAP_CHAIN_DESC1 {
	var Width:UInt32;
	var Height:UInt32;
	var Format:Int32;
	var Stereo:Int32;
	var SampleCount:UInt32; // DXGI_SAMPLE_DESC
	var SampleQuality:UInt32;
	var BufferUsage:UInt32;
	var BufferCount:UInt32;
	var Scaling:Int32;
	var SwapEffect:Int32;
	var AlphaMode:Int32;
	var Flags:UInt32;
}
