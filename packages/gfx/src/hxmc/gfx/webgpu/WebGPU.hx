package hxmc.gfx.webgpu;

import hxmc.unsafe.*;

// WebGPU through JavaScript (WebAssembly): imports of the module
// "hxmc_gfx", which packages/gfx/imports.mjs provides. The adapter and the
// device are requested before the module starts (the import convention of
// packages/os/browser.mjs lets imports.mjs wait), so they are ready here.
// GPU objects are handles into the loader's table of JavaScript objects (0:
// none). Formats, usages and states are hxmc.gfx's own enums' values, mapped
// on the JavaScript side. None calls back (@:hxmc.fast: memory may be passed
// by its address).
@:hxmc.c @:hxmc.fast @:hxmc.lib("hxmc_gfx") extern class WebGPU {
	// 1: there is a device (navigator.gpu and an adapter)
	static function ready():Int;
	// a colour target: a canvas (its handle: hxmc.os.Surface's) configured
	// for WebGPU in the preferred format, or a texture of that size (RGBA8)
	static function target_canvas(canvas:Int):Int;
	static function target_texture(width:Int, height:Int):Int;
	static function buffer(size:Int, usage:Int, data:Ptr, length:Int):Int;
	// WGSL; errors are reported asynchronously, on the console
	static function shader(wgsl:CString):Int;
	// a pipeline: its vertex buffers and their attributes, then the rest
	static function pipeline_begin():Void;
	static function pipeline_buffer(stride:Int):Void;
	static function pipeline_attribute(location:Int, format:Int, offset:Int):Void;
	// a resource of the pipeline (ShaderCode.bindings: kind, slot, a uniform
	// block's size): its bind group layout
	static function pipeline_binding(slot:Int, kind:Int, size:Int):Void;
	static function pipeline_end(vertex:Int, fragment:Int, target:Int, topology:Int, cull:Int):Int;
	// a frame: a command encoder for the target's texture (the canvas's
	// current one); 0: none now
	static function frame_begin(target:Int):Int;
	static function pass_begin(load:Int, r:Float, g:Float, b:Float, a:Float):Void;
	static function set_pipeline(pipeline:Int):Void;
	static function set_vertex_buffer(slot:Int, buffer:Int, offset:Int):Void;
	// size bytes at data into the frame's uniform ring at offset (256-byte
	// aligned), bound at the slot (a dynamic offset); written to the GPU
	// when the frame is submitted
	static function set_uniforms(slot:Int, offset:Int, data:Ptr, size:Int):Void;
	static function draw(vertices:Int, instances:Int, first:Int):Void;
	static function pass_end():Void;
	// submits the frame (the canvas presents it when the task ends)
	static function frame_end():Void;
	static function release(handle:Int):Void;
}
