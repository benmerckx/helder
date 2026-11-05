package helder.canvas.doc;

import helder.canvas.Gradient;
import helder.canvas.doc.Recorder;

// A page as SVG: paths (their data in canvas units, through each call's
// transform), fills and strokes with their opacity and mix-blend-mode,
// linear and radial gradients (userSpaceOnUse, their transform; a radial's
// start circle as SVG 2's fx, fy, fr), clips as clipPaths of the saves'
// groups, layers as groups of their opacity, images as PNG data URLs.
// Conic gradients, patterns and erasing are drawn on the CPU into an image
// of their own, as PdfWriter does; text arrives as the glyphs' outlines.
class SvgWriter {
	public var fallbackScale = 2.0;

	final defs = new StringBuf();
	var ids = 0;

	public function new() {}

	public static function write(page:Recorder):String
		return new SvgWriter().svg(page);

	public function svg(r:Recorder):String {
		var body = new StringBuf();
		var open = [];
		var i = 0;
		while (i < r.ops.length) {
			var o = r.ops[i];
			switch o.kind {
				case Save:
					body.add("<g>");
					open.push(1);
				case Layer:
					body.add('<g opacity="${num(o.alpha)}"${blendStyle(o.blend)}>');
					open.push(1);
				case Restore:
					// (a save's group and the clips' groups inside it)
					while (open.length > 0) {
						var k = open.pop();
						body.add("</g>");
						if (k == 1) break;
					}
				case Clip:
					var id = "c" + ids++;
					defs.add('<clipPath id="$id"><path d="${data(o.path, o.matrix)}" clip-rule="${o.evenOdd ? "evenodd" : "nonzero"}"/></clipPath>');
					body.add('<g clip-path="url(#$id)">');
					open.push(0);
				case Fill | StrokePath:
					shape(r, o, body);
				case Clear:
					if (((o.color >>> 24) & 255) > 0) body.add('<rect width="${r.width}" height="${r.height}" fill="${color(o.color)}" fill-opacity="${num(((o.color >>> 24) & 255) / 255)}"/>');
				case ClearRect | Pixels:
					fallback(r, o, body);
				case Image:
					image(o, body);
			}
			i++;
		}
		while (open.length > 0) {
			open.pop();
			body.add("</g>");
		}
		return '<svg xmlns="http://www.w3.org/2000/svg" width="${r.width}" height="${r.height}" viewBox="0 0 ${r.width} ${r.height}"><defs>${defs.toString()}</defs>${body.toString()}</svg>';
	}

	static function num(v:Float):String
		return Math.abs(v) < 1e-9 ? "0" : Std.string(Math.round(v * 1000) / 1000);

	static function color(c:Int):String
		return "#" + StringTools.hex(c & 0xFFFFFF, 6).toLowerCase();

	static function blendStyle(b:Null<Blend.Blender>):String {
		if (b == null || b.code < 0) return "";
		var names = ["multiply", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "hard-light", "soft-light", "difference", "exclusion",
			"hue", "saturation", "color", "luminosity"];
		return ' style="mix-blend-mode:${names[b.code]}"';
	}

	static function matrix(m:Matrix):String
		return 'matrix(${num(m.a)} ${num(m.b)} ${num(m.c)} ${num(m.d)} ${num(m.e)} ${num(m.f)})';

	// path data through m
	static function data(p:Path, m:Matrix):String {
		var b = new StringBuf(), pts = p.points, pi = 0;
		inline function pt(k:Int)
			b.add(num(m.mapX(pts[k], pts[k + 1])) + " " + num(m.mapY(pts[k], pts[k + 1])) + " ");
		for (i in 0...p.verbCount)
			switch p.verbs[i] {
				case Path.MOVE:
					b.add("M");
					pt(pi);
					pi += 2;
				case Path.LINE:
					b.add("L");
					pt(pi);
					pi += 2;
				case Path.QUAD:
					b.add("Q");
					pt(pi);
					pt(pi + 2);
					pi += 4;
				case Path.CUBIC:
					b.add("C");
					pt(pi);
					pt(pi + 2);
					pt(pi + 4);
					pi += 6;
				case _:
					b.add("Z");
			}
		return StringTools.trim(b.toString());
	}

	function shape(r:Recorder, o:Op, out:StringBuf) {
		var p = o.paint, s = p.shader, stroke = o.kind == StrokePath;
		var plain = s == null || Std.isOfType(s, LinearGradient) || Std.isOfType(s, RadialGradient);
		if (!plain || (p.blend != null && p.blend.code < 0 && p.blend.unbounded)) {
			fallback(r, o, out);
			return;
		}
		var fill = s == null ? color(p.color) : 'url(#${gradient(cast s, o.matrix)})';
		var alpha = p.alpha * (s == null ? ((p.color >>> 24) & 255) / 255 : 1);
		var blend = blendStyle(p.blend);
		if (stroke) {
			var st = o.stroke;
			var dash = st.dash != null && st.dash.valid() ? ' stroke-dasharray="${[for (d in st.dash.intervals) num(d)].join(" ")}" stroke-dashoffset="${num(st.dash.offset)}"' : "";
			out.add('<path transform="${matrix(o.matrix)}" d="${data(o.path, Matrix.IDENTITY)}" fill="none" stroke="$fill" stroke-opacity="${num(alpha)}" stroke-width="${num(st.width)}" stroke-linecap="${["butt", "round", "square"][st.cap.kind]}" stroke-linejoin="${["miter", "round", "bevel"][st.join.kind]}" stroke-miterlimit="${num(st.miterLimit)}"$dash$blend/>');
		} else
			out.add('<path d="${data(o.path, o.matrix)}" fill="$fill" fill-opacity="${num(alpha)}" fill-rule="${o.evenOdd ? "evenodd" : "nonzero"}"$blend/>');
	}

	function gradient(g:Gradient, m:Matrix):String {
		var id = "g" + ids++;
		var t = m.clone().multiply(g.matrix);
		var spread = g.spread == Gradient.REFLECT ? ' spreadMethod="reflect"' : g.spread == Gradient.REPEAT ? ' spreadMethod="repeat"' : "";
		var stops = new StringBuf();
		for (i in 0...g.stopCount) {
			var c = g.stopColor(i);
			stops.add('<stop offset="${num(g.stopOffset(i))}" stop-color="${color(c)}" stop-opacity="${num(((c >>> 24) & 255) / 255)}"/>');
		}
		if (Std.isOfType(g, LinearGradient)) {
			var l:LinearGradient = cast g;
			defs.add('<linearGradient id="$id" gradientUnits="userSpaceOnUse" gradientTransform="${matrix(t)}" x1="${num(l.x0)}" y1="${num(l.y0)}" x2="${num(l.x1)}" y2="${num(l.y1)}"$spread>${stops.toString()}</linearGradient>');
		} else {
			var rg:RadialGradient = cast g;
			defs.add('<radialGradient id="$id" gradientUnits="userSpaceOnUse" gradientTransform="${matrix(t)}" cx="${num(rg.x1)}" cy="${num(rg.y1)}" r="${num(rg.r1)}" fx="${num(rg.x0)}" fy="${num(rg.y0)}" fr="${num(rg.r0)}"$spread>${stops.toString()}</radialGradient>');
		}
		return id;
	}

	static function png(b:Bitmap):String
		return "data:image/png;base64," + haxe.crypto.Base64.encode(helder.image.PngEncoder.encode(b.straight(), b.width, b.height));

	function image(o:Op, out:StringBuf) {
		var r = o.rect, img = o.image;
		var kx = r[6] / r[2], ky = r[7] / r[3];
		// (the whole image placed so the source rectangle lands on the destination, clipped to it)
		var id = "c" + ids++;
		defs.add('<clipPath id="$id"><rect x="${num(r[4])}" y="${num(r[5])}" width="${num(r[6])}" height="${num(r[7])}"/></clipPath>');
		out.add('<g transform="${matrix(o.matrix)}" opacity="${num(o.paint.alpha)}"${blendStyle(o.paint.blend)}><image clip-path="url(#$id)" x="${num(r[4] - r[0] * kx)}" y="${num(r[5] - r[1] * ky)}" width="${num(img.width * kx)}" height="${num(img.height * ky)}" preserveAspectRatio="none"${o.smooth ? "" : ' image-rendering="pixelated"'} href="${png(img)}"/></g>');
	}

	function fallback(r:Recorder, o:Op, out:StringBuf) {
		var k = fallbackScale, c = new Canvas(Std.int(Math.ceil(r.width * k)), Std.int(Math.ceil(r.height * k)));
		c.scale(k, k);
		var m = o.matrix;
		c.transform(m.a, m.b, m.c, m.d, m.e, m.f);
		switch o.kind {
			case Fill:
				c.fill(o.path, o.paint, o.evenOdd);
			case StrokePath:
				c.stroke(o.path, o.stroke, o.paint);
			case ClearRect:
				c.fillRect(o.rect[0], o.rect[1], o.rect[2], o.rect[3], Paint.solid(0xFFFFFFFF));
			case Pixels:
				c.resetTransform();
				c.scale(k, k);
				c.drawImage(o.image, 0, 0, o.image.width, o.image.height, o.rect[0], o.rect[1], o.image.width, o.image.height, new Paint(), false);
			case _:
		}
		out.add('<image width="${r.width}" height="${r.height}" href="${png(c.bitmap)}"/>');
	}
}
