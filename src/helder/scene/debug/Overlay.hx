package helder.scene.debug;

import helder.gfx.*;
import helder.ui.draw.Renderer as UiRenderer;

// A debug overlay over the 3D frame, drawn with helder.ui's drawn renderer
// (helder.ui.draw.Renderer, so helder.ui and helder.text must be on the class
// path of a program that uses it; a program that does not links none of
// it): a panel in the top left with the last frames' times as bars (green
// under the 60 Hz budget, amber under 30 Hz, red above; the line is
// 16.7 ms), the renderer's draws as a bar, and two lines of figures (the
// average and the longest frame, draws, culled and instanced) in a pixel
// font of its own (whole pixels, no font file: alike everywhere). Its own
// pass, loading what the renderer drew:
//
//   renderer.draw(enc, world, camera);
//   stats.add(seconds); stats.from(renderer);
//   overlay.draw(enc, stats);
class Overlay {
	public final device:Device;
	public var scale = 1.0;
	// three lines more under the figures: frames a second, the frame
	// time's median and 99th percentile, the CPU's (FrameStats.add's cpu);
	// then lines, the program's own (a count, a mode)
	public var detail = false;
	public final lines:Array<String> = [];
	// drawn after the panel in its pass, with text and rect: a program's own controls
	public var extra:Null<Overlay->Void> = null;
	// whether the panel is drawn (false: extra alone, a program's controls without the figures)
	public var panel = true;
	final ui:UiRenderer;
	final pass:PassDesc = {colors: [{load: Load}]};

	public function new(device:Device) {
		this.device = device;
		ui = new UiRenderer(device);
	}

	public function draw(enc:Encoder, stats:FrameStats) {
		var w = device.width, h = device.height;
		ui.scale = scale;
		ui.begin(w, h);
		if (panel) figures(stats);
		if (extra != null) extra(this);
		enc.beginPass(pass);
		ui.end(enc);
		enc.endPass();
	}

	// the panel: the bars and the figures
	function figures(stats:FrameStats) {
		var bars = stats.capacity, bw = 2.0, gh = 48.0, x0 = 8.0, y0 = 8.0;
		var pw = detail ? Math.max(bars * bw + 12, 252) : bars * bw + 12, ph = gh + 26 + 30 + (detail ? 28 + 14 * lines.length : 0);
		ui.rect(x0, y0, pw, ph, 0, 0xB0101418, 0, 0);
		// (the bars: newest on the right; 33 ms fills the graph)
		for (k in 0...stats.count) {
			var t = stats.at(k), v = Math.min(t / 0.0333, 1);
			var color = t <= 1 / 59 ? 0xFF4CC38A : t <= 1 / 29 ? 0xFFE0B040 : 0xFFE05050;
			// (whole pixels: alike on every rasterizer)
			var bh = Math.max(Math.round(v * gh), 1);
			ui.rect(x0 + 6 + (bars - 1 - k) * bw, y0 + 6 + gh - bh, bw - 1, bh, 0, color, 0, 0);
		}
		// (the 60 Hz budget)
		ui.rect(x0 + 6, y0 + 6 + gh - Math.round((1 / 60) / 0.0333 * gh), bars * bw, 1, 0, 0x80FFFFFF, 0, 0);
		// (draws: a bar of up to 100, culled after it)
		var dw = Math.round(Math.min(stats.draws, 100) / 100 * (bars * bw));
		ui.rect(x0 + 6, y0 + 12 + gh, dw, 6, 0, 0xFF5AA0F0, 0, 0);
		ui.rect(x0 + 6 + dw, y0 + 12 + gh, Math.round(Math.min(stats.culled, 100) / 100 * (bars * bw - dw)), 6, 0, 0x605AA0F0, 0, 0);
		// (the figures)
		var ty = y0 + gh + 26;
		write('AVG ${ms(stats.average())} MS  MAX ${ms(stats.max())} MS', x0 + 6, ty);
		write('DRAWS ${stats.draws} CULLED ${stats.culled} INST ${stats.instanced}', x0 + 6, ty + 14);
		if (detail) {
			write('FPS ${Math.round(stats.fps())}  P50 ${ms(stats.percentile(0.5))}  P99 ${ms(stats.percentile(0.99))} MS', x0 + 6, ty + 28);
			write('CPU P50 ${ms(stats.percentile(0.5, true))}  P99 ${ms(stats.percentile(0.99, true))} MS', x0 + 6, ty + 42);
			for (k in 0...lines.length)
				write(lines[k], x0 + 6, ty + 56 + 14 * k);
		}
	}

	// milliseconds with one decimal
	static function ms(seconds:Float):String {
		var tenths = Math.round(seconds * 10000);
		return Std.int(tenths / 10) + "." + (tenths % 10);
	}

	// text in the pixel font (letters upper case), at x, y in points, of
	// cells of size points: inside extra
	public function text(text:String, x:Float, y:Float, color = 0xFFE8ECF0, size = 2.0) {
		for (i in 0...text.length) {
			var c = StringTools.fastCodeAt(text, i);
			var g = c >= 97 && c <= 122 ? CODES[c - 32] : c < 128 ? CODES[c] : null;
			if (g != null)
				for (cell in 0...15)
					if (g.charCodeAt(cell) == "1".code) ui.rect(x + (cell % 3) * size, y + Std.int(cell / 3) * size, size, size, 0, color, 0, 0);
			x += 4 * size;
		}
	}

	// a filled rectangle (ARGB), its corners rounded by radius: inside extra
	public inline function rect(x:Float, y:Float, w:Float, h:Float, color:Int, radius = 0.0)
		ui.rect(x, y, w, h, radius, color, 0, 0);

	// how wide text is in the pixel font at size
	public static inline function measure(text:String, size = 2.0):Float
		return text.length * 4 * size - size;

	// text in the pixel font: 3x5 cells of 2 pixels, a cell between letters
	inline function write(s:String, x:Float, y:Float)
		text(s, x, y);

	// (rows top to bottom, three cells each)
	static final GLYPHS:Map<String, String> = [
		"0" => "111101101101111", "1" => "010110010010111", "2" => "111001111100111", "3" => "111001111001111", "4" => "101101111001001",
		"5" => "111100111001111", "6" => "111100111101111", "7" => "111001001001001", "8" => "111101111101111", "9" => "111101111001111",
		"." => "000000000000010", "A" => "010101111101101", "C" => "011100100100011", "D" => "110101101101110", "E" => "111100110100111",
		"F" => "111100110100100", "G" => "011100101101011", "I" => "111010010010111", "L" => "100100100100111", "M" => "101111111101101",
		"N" => "110101101101101", "P" => "110101110100100", "R" => "110101110101101", "S" => "011100010001110", "T" => "111010010010010",
		"U" => "101101101101111", "V" => "101101101101010", "W" => "101101111111101", "X" => "101101010101101", "B" => "110101110101110", "H" => "101101111101101", "J" => "001001001101010",
		"K" => "101101110101101", "O" => "010101101101010", "Q" => "010101101111011", "Y" => "101101010010010", "Z" => "111001010100111",
		"/" => "001001010100100", ":" => "000010000010000", "-" => "000000111000000", "+" => "000010111010000", "%" => "101001010100101",
		"<" => "001010100010001", ">" => "100010001010100", "(" => "010100100100010", ")" => "010001001001010", "," => "000000000010100",
		"!" => "010010010000010", "=" => "000111000111000", "'" => "010010000000000"
	];

	// (the glyphs by character code)
	static final CODES:Array<Null<String>> = {
		var a:Array<Null<String>> = [for (_ in 0...128) null];
		for (k => v in GLYPHS)
			a[k.charCodeAt(0)] = v;
		a;
	};
}
