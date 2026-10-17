package hxmc.ui.native;

import hxmc.ui.*;

// hxmc.ui's TextEngine for a NativeHost: text measured as the platform's
// labels lay it out (the backend's measureText). The paragraphs carry their
// size only: the platform draws the text and edits it.
class NativeText implements TextEngine {
	final backend:NativeBackend;

	public function new(backend:NativeBackend)
		this.backend = backend;

	// (justify: not done, the platform's labels align their own text)
	public function layout(text:String, font:Font, maxWidth:Float, ?spans:Array<TextSpan>, maxLines:Int = 0, justify:Bool = false):Paragraph {
		var s = backend.measureText(text, font, maxWidth);
		var one = backend.measureText(text, font, Math.NaN);
		var widest = 0.0;
		// (the widest word: the min-content width)
		var start = 0;
		for (i in 0...text.length + 1) {
			var c = i < text.length ? StringTools.fastCodeAt(text, i) : 32;
			if (c == 32 || c == 10 || c == 9) {
				if (i > start) widest = Math.max(widest, backend.measureText(text.substring(start, i), font, Math.NaN).width);
				start = i + 1;
			}
		}
		return new NativeParagraph(s.width, s.height, Math.round(s.height / Math.max(1, one.height)), widest);
	}
}

class NativeParagraph implements Paragraph {
	public var width(get, never):Float;
	public var height(get, never):Float;
	public var lineCount(get, never):Int;
	public var minWidth(get, never):Float;

	final w:Float;
	final h:Float;
	final lines:Int;
	final min:Float;

	public function new(w:Float, h:Float, lines:Int, min:Float) {
		this.w = w;
		this.h = h;
		this.lines = lines < 1 ? 1 : lines;
		this.min = min;
	}

	inline function get_width()
		return w;

	inline function get_height()
		return h;

	inline function get_lineCount()
		return lines;

	inline function get_minWidth()
		return min;

	// (no carets: the platform's labels are not edited)
	public function caret(i:Int):{x:Float, y:Float, height:Float}
		return {x: 0, y: 0, height: h / lines};

	public function hit(x:Float, y:Float):Int
		return 0;

	public function selection(start:Int, end:Int):Array<{x:Float, y:Float, width:Float}>
		return [];

	// (none: the platform's labels draw their own text)
	public function decoration(start:Int, end:Int, kind:TextDecoration, scale:Float):Array<{x:Float, y:Float, width:Float, height:Float, lineWidth:Float}>
		return [];
}
