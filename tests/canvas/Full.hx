import helder.canvas.*;
import helder.canvas.Gradient;
import helder.canvas.Stroke;

// The canvas lane's DCE check, the large side: every paint, blend mode,
// join, cap, dashes, clips, layers, images, text and both encoders
// (tests/canvas/dce.mjs compares its size with Tiny's)
class Full {
	static function main() {
		var c = new Canvas(128, 128);
		var p = new Path();
		p.roundRect(8, 8, 100, 80, 12);
		var shaders:Array<Paint.Shader> = [new LinearGradient(0, 0, 128, 0).addStop(0, 0xFFFF0000).addStop(1, 0xFF0000FF),
			new RadialGradient(64, 64, 4, 64, 64, 60).addStop(0, 0xFFFFFFFF).addStop(1, 0xFF000000),
			new ConicGradient(0, 64, 64).addStop(0, 0xFF00FF00).addStop(1, 0xFFFF00FF), new Pattern(c.bitmap)];
		var blends = [Blend.clear, Blend.copy, Blend.destination, Blend.sourceOver, Blend.destinationOver, Blend.sourceIn, Blend.destinationIn,
			Blend.sourceOut, Blend.destinationOut, Blend.sourceAtop, Blend.destinationAtop, Blend.xor, Blend.lighter, Blend.multiply, Blend.screen,
			Blend.overlay, Blend.darken, Blend.lighten, Blend.colorDodge, Blend.colorBurn, Blend.hardLight, Blend.softLight, Blend.difference,
			Blend.exclusion, Blend.hue, Blend.saturation, Blend.color, Blend.luminosity];
		for (i in 0...blends.length) {
			var paint = Paint.shaded(shaders[i % shaders.length]);
			paint.blend = blends[i];
			c.fill(p, paint, i % 2 == 0);
		}
		var s = new Stroke(5);
		for (j in [Join.miter, Join.round, Join.bevel])
			for (k in [Cap.butt, Cap.round, Cap.square]) {
				s.join = j;
				s.cap = k;
				s.dash = new Dash([4, 2]);
				c.stroke(p, s, Paint.solid(0x80000000));
			}
		c.save();
		c.clip(p, true);
		c.saveLayer(0.5, Blend.multiply, Mask.ofBitmap(c.bitmap));
		c.drawImage(c.bitmap, 0, 0, 64, 64, 0, 0, 128, 128, new Paint());
		c.restore();
		c.restore();
		var fonts = helder.text.SystemFonts.get();
		var face = fonts.match("sans-serif", 400);
		if (face != null) Glyphs.fill(c, new helder.text.TextLayout("text", new helder.text.FontSet(face, 16), 1.2, Math.POSITIVE_INFINITY), 4, 120, new Paint());
		Sys.println('full: ${c.toPng().length} bytes of PNG, ${c.toJpeg(90).length} of JPEG');
	}
}
