import hxmc.ui.*;

// A TextEngine for tests (spans laid out in the paragraph's font): every character is half the font size wide, a
// line is size * lineHeight high, lines break at spaces (or anywhere in a
// word wider than the line, unless the width is 0: the min-content layout)
// and at "\n".
class MonoText implements TextEngine {
	public function new() {}

	public function layout(text:String, font:Font, maxWidth:Float, ?spans:Array<TextSpan>, maxLines:Int = 0):Paragraph
		return new MonoParagraph(text, font, maxWidth, maxLines);
}

class MonoParagraph implements Paragraph {
	public var width(get, never):Float;
	public var height(get, never):Float;
	public var lineCount(get, never):Int;
	public var minWidth(get, never):Float;

	// each line: its first character and its length
	public final lines:Array<{start:Int, length:Int}> = [];
	final char:Float;
	final line:Float;
	final text:String;

	// (maxLines: the last line kept cut to leave room for an ellipsis, one character, counted in its width)
	public var ellipsis(default, null) = false;

	public function new(text:String, font:Font, maxWidth:Float, maxLines = 0) {
		this.text = text;
		// (letter spacing after each character)
		char = font.size / 2 + font.letterSpacing;
		line = font.size * font.lineHeight;
		var perLine = Math.isNaN(maxWidth) ? 1 << 30 : Std.int(Math.max(1, Math.floor(maxWidth / char + 1e-9)));
		var start = 0;
		for (hard in text.split("\n")) {
			var pos = 0;
			while (true) {
				if (hard.length - pos <= perLine) {
					lines.push({start: start + pos, length: hard.length - pos});
					break;
				}
				// the last space that fits, else a cut
				var cut = hard.lastIndexOf(" ", pos + perLine);
				if (cut <= pos && maxWidth == 0) {
					cut = hard.indexOf(" ", pos);
					if (cut < 0) cut = hard.length;
				}
				if (cut <= pos) cut = pos + perLine;
				lines.push({start: start + pos, length: cut - pos});
				pos = cut;
				while (pos < hard.length && hard.charAt(pos) == " ")
					pos++;
			}
			start += hard.length + 1;
		}
		if (maxLines > 0 && lines.length > maxLines) {
			lines.resize(maxLines);
			ellipsis = true;
			var l = lines[maxLines - 1];
			var keep = Math.isNaN(maxWidth) ? l.length : Std.int(Math.min(l.length, Math.max(0, perLine - 1)));
			lines[maxLines - 1] = {start: l.start, length: keep + 1};
		}
	}

	// (the longest word)
	function get_minWidth():Float {
		var w = 0;
		for (hard in text.split("\n"))
			for (word in hard.split(" "))
				if (word.length > w) w = word.length;
		return w * char;
	}

	function get_width():Float {
		var w = 0;
		for (l in lines)
			if (l.length > w) w = l.length;
		return w * char;
	}

	function get_height():Float
		return lines.length * line;

	function get_lineCount():Int
		return lines.length;

	public function caret(i:Int):{x:Float, y:Float, height:Float} {
		for (k in 0...lines.length) {
			var l = lines[k];
			if (i <= l.start + l.length || k == lines.length - 1) return {x: (Math.min(i, l.start + l.length) - l.start) * char, y: k * line, height: line};
		}
		return {x: 0, y: 0, height: line};
	}

	public function selection(start:Int, end:Int):Array<{x:Float, y:Float, width:Float}> {
		var out = [];
		for (k in 0...lines.length) {
			var l = lines[k];
			var a = Std.int(Math.max(start, l.start)), b = Std.int(Math.min(end, l.start + l.length));
			if (b > a) out.push({x: (a - l.start) * char, y: k * line, width: (b - a) * char});
		}
		return out;
	}

	// (a line a tenth of the size thick: an underline at 0.9 of the line, a line-through at the half, an overline at the top)
	public function decoration(start:Int, end:Int, kind:TextDecoration, scale:Float):Array<{x:Float, y:Float, width:Float, height:Float, lineWidth:Float}>
		return [
			for (r in selection(start, end)) {
				var k = Std.int(r.y / line);
				{x: r.x, y: r.y + line * (kind == Underline ? 0.9 : kind == LineThrough ? 0.5 : 0), width: r.width, height: char / 5, lineWidth: lines[k].length * char};
			}
		];

	public function hit(x:Float, y:Float):Int {
		var k = Std.int(Math.max(0, Math.min(lines.length - 1, Math.floor(y / line))));
		var l = lines[k];
		return l.start + Std.int(Math.max(0, Math.min(l.length, Math.round(x / char))));
	}
}
