import helder.canvas.Canvas;
import helder.canvas.Paint;
import helder.canvas.Path;

// The canvas lane's DCE check, the small side: a path filled, the pixels
// as a PNG; built with -dce full, its executable must hold none of the
// JPEG encoder, the gradients, patterns, blend modes, strokes' round
// joins or text (tests/canvas/dce.mjs)
class Tiny {
	static function main() {
		var c = new Canvas(64, 64);
		var p = new Path();
		p.moveTo(8, 8);
		p.lineTo(56, 20);
		p.lineTo(20, 56);
		p.close();
		c.fill(p, Paint.solid(0xFF2563EB));
		var png = c.toPng();
		Sys.println('tiny: ${png.length} bytes of PNG');
	}
}
