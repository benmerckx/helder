package helder.canvas;

// A Painter that draws images its host holds by handle (web.WebCanvas:
// images the browser decoded, web.BrowserImages), as drawImage draws a
// Bitmap; a caller checks for it (Std.isOfType) and falls back to Bitmaps.
interface HandleImages {
	function drawHandle(handle:Int, sx:Float, sy:Float, sw:Float, sh:Float, dx:Float, dy:Float, dw:Float, dh:Float, paint:Paint, smooth:Bool = true):Void;
}

// an image a host holds: its handle, its size (web.WebImage's)
class ImageHandle {
	public final handle:Int;
	public final width:Int;
	public final height:Int;

	public function new(handle, width, height) {
		this.handle = handle;
		this.width = width;
		this.height = height;
	}
}
