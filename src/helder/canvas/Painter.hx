package helder.canvas;

import haxe.io.Bytes;
import helder.canvas.Blend.Blender;

// What draws: helder.canvas's API over a back end. Canvas draws on the
// CPU (the reference), gpu.GpuCanvas on helder.gfx, web.WebCanvas
// through the browser's own Canvas 2D; the DOM facade and Glyphs draw on
// any. A paint's shader and blend mode are the core's classes everywhere.
interface Painter {
	var width(default, null):Int;
	var height(default, null):Int;
	// the current transform: changed in place
	var matrix(get, never):Matrix;
	function save():Void;
	function saveLayer(alpha:Float = 1.0, ?blend:Blender, ?mask:Mask, ?filter:Filter):Void;
	function restore():Void;
	function restoreToCount(count:Int):Void;
	function translate(x:Float, y:Float):Void;
	function scale(x:Float, y:Float):Void;
	function rotate(angle:Float):Void;
	function transform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float):Void;
	function setTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float):Void;
	function resetTransform():Void;
	function clip(path:Path, evenOdd:Bool = false):Void;
	function fill(path:Path, paint:Paint, evenOdd:Bool = false):Void;
	function stroke(path:Path, style:Stroke, paint:Paint):Void;
	function clearRect(x:Float, y:Float, w:Float, h:Float):Void;
	function clear(color:Int = 0):Void;
	function drawImage(img:Bitmap, sx:Float, sy:Float, sw:Float, sh:Float, dx:Float, dy:Float, dw:Float, dh:Float, paint:Paint, smooth:Bool = true):Void;
	// straight RGBA in and out (getImageData's, putImageData's)
	function readPixels(out:Bytes, x:Int, y:Int, w:Int, h:Int):Void;
	function writePixels(rgba:Bytes, x:Int, y:Int, w:Int, h:Int, srcStride:Int = -1):Void;
	// the pixels now, premultiplied (the CPU canvas's own bitmap; a copy read back elsewhere)
	function snapshot():Bitmap;
	// a painter of the same kind, of its own pixels (a PDF tiling pattern's cell, read by snapshot):
	// no back end brings in another's
	function offscreen(width:Int, height:Int):Painter;
}
