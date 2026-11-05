package helder.canvas.dom;

import haxe.io.Bytes;

// A canvas as skia-canvas's and @napi-rs/canvas's (and the browser's
// OffscreenCanvas): `new Canvas(width, height)`, its 2D context
// (getContext("2d"): CanvasRenderingContext2D, drawn by helder.canvas on
// the CPU), its pixels as a file (toBuffer("png"), saveAs("out.jpg"),
// toDataURL()). Code written for the browser's Canvas 2D runs on it.
// Setting width or height clears it and resets its context, as the
// browser's.
class Canvas {
	public var width(get, set):Int;
	public var height(get, set):Int;

	@:noCompletion public var core(default, null):helder.canvas.Painter;

	// what each canvas draws with: helder.canvas's CPU back end unless a
	// back end set another (gpu.GpuCanvas.use(), web.WebCanvas.use())
	@:noCompletion public static var backend:(width:Int, height:Int) -> helder.canvas.Painter = (w, h) -> new helder.canvas.Canvas(w, h);
	var context:Null<CanvasRenderingContext2D> = null;
	// (every page drawn, recorded beside its pixels: toBuffer("pdf"), "svg")
	@:noCompletion public final document = new helder.canvas.doc.Document();

	public function new(width = 300, height = 150) {
		core = make(width, height);
	}

	function make(w:Int, h:Int):helder.canvas.Painter
		return new helder.canvas.doc.Tee(backend(w, h), document.newPage(w, h));

	// a page after the others (a PDF's next; this canvas's pixels the new page's), its context
	public function newPage(?width:Int, ?height:Int):CanvasRenderingContext2D {
		core = make(width ?? core.width, height ?? core.height);
		var ctx = getContext("2d");
		ctx.attach(core);
		return ctx;
	}

	public var pageCount(get, never):Int;

	inline function get_pageCount()
		return document.pages.length;

	inline function get_width()
		return core.width;

	inline function get_height()
		return core.height;

	function set_width(v:Int):Int {
		resize(v, core.height);
		return v;
	}

	function set_height(v:Int):Int {
		resize(core.width, v);
		return v;
	}

	function resize(w:Int, h:Int) {
		// (a canvas resized starts its page again)
		document.pages.pop();
		core = make(w, h);
		if (context != null) context.attach(core);
	}

	// "2d" (any other: null, as the browser's for a kind it lacks)
	public function getContext(kind:String, ?options:Dynamic):Null<CanvasRenderingContext2D> {
		if (kind != "2d") return null;
		if (context == null) context = new CanvasRenderingContext2D(this);
		return context;
	}

	// the pixels as a file: "png", "jpg" or "jpeg" (also their MIME
	// types; quality 0 to 1 for JPEG, 0.92), or the drawing as vectors:
	// "pdf" (every page), "svg" (the last)
	public function toBuffer(format = "png", ?quality:Float):Bytes {
		var f = format.toLowerCase();
		if (StringTools.startsWith(f, "image/")) f = f.substr(6);
		if (StringTools.startsWith(f, ".")) f = f.substr(1);
		return switch f {
			case "png": helder.image.PngEncoder.encode(core.snapshot().straight(), width, height);
			case "jpg" | "jpeg": helder.image.JpegEncoder.encode(core.snapshot().straight(), width, height, Std.int(Math.round((quality ?? 0.92) * 100)));
			case "raw": core.snapshot().straight();
			case "pdf": helder.canvas.doc.PdfWriter.write(document);
			case "svg": haxe.io.Bytes.ofString(helder.canvas.doc.SvgWriter.write(document.pages[document.pages.length - 1]));
			case _: throw new Path2D.DOMException("NotSupportedError", 'Canvas.toBuffer: "$format" is not a format helder writes (png, jpg, pdf, svg)');
		}
	}

	// the pixels written to a file, its format by its extension unless given
	public function saveAs(path:String, ?format:String, ?quality:Float) {
		var f = format ?? haxe.io.Path.extension(path);
		sys.io.File.saveBytes(path, toBuffer(f == "" ? "png" : f, quality));
	}

	public function toDataURL(type = "image/png", ?quality:Float):String {
		var f = type.toLowerCase();
		if (f != "image/jpeg" && f != "image/jpg") f = "image/png";
		return "data:" + f + ";base64," + haxe.crypto.Base64.encode(toBuffer(f, quality));
	}
}
