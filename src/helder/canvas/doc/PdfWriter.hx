package helder.canvas.doc;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.canvas.Gradient;
import helder.canvas.doc.Recorder;

// A Document as a PDF (1.7): a page a recording, its calls as vectors.
// Paths as PDF's (m, l, c, h; f, f*, S; W n for clips, q and Q for saves),
// colours with their opacity and blend mode in an ExtGState, linear and
// radial gradients as axial and radial shadings (their stops a stitching
// function, their alpha a luminosity soft mask), images as image
// XObjects with their alpha as a soft mask, layers as transparency groups.
// What PDF cannot say (conic gradients, patterns, a gradient's reflect or
// repeat, erasing) is drawn on the CPU into an image of its own (the page's
// size, at `fallbackScale`). Streams Flate-compressed (helder.image's
// zlib); text arrives as the glyphs' outlines.
class PdfWriter {
	public var fallbackScale = 2.0;

	final objects:Array<Null<Bytes>> = [null];
	var resources:Resources;
	// (the page's resources' object: its forms' too)
	var resourcesId = 0;

	public function new() {}

	public static function write(doc:Document):Bytes
		return new PdfWriter().document(doc);

	function reserve():Int {
		objects.push(null);
		return objects.length - 1;
	}

	function set(id:Int, s:String)
		objects[id] = Bytes.ofString(s);

	function stream(id:Int, dict:String, data:Bytes, compress = true) {
		var body = compress ? helder.image.PngEncoder.zlib(data) : data;
		var b = new BytesBuffer();
		b.addString('<< $dict${compress ? " /Filter /FlateDecode" : ""} /Length ${body.length} >>\nstream\n');
		b.addBytes(body, 0, body.length);
		b.addString("\nendstream");
		objects[id] = b.getBytes();
	}

	function add(s:String):Int {
		var id = reserve();
		set(id, s);
		return id;
	}

	public function document(doc:Document):Bytes {
		var pagesId = reserve();
		var kids = [];
		for (page in doc.pages)
			kids.push(this.page(page, pagesId));
		set(pagesId, '<< /Type /Pages /Kids [${[for (k in kids) '$k 0 R'].join(" ")}] /Count ${kids.length} >>');
		var catalog = add('<< /Type /Catalog /Pages $pagesId 0 R >>');
		var info = add('<< /Producer (helder.canvas) >>');
		var out = new BytesBuffer();
		// (the header, then a comment of bytes past ASCII: a binary file)
		var head = Bytes.ofHex("255044462d312e370a25e2e3cfd30a");
		out.addBytes(head, 0, head.length);
		var offsets = [0];
		var pos = head.length;
		for (i in 1...objects.length) {
			offsets.push(pos);
			var s = Bytes.ofString('$i 0 obj\n');
			out.addBytes(s, 0, s.length);
			var o = objects[i];
			out.addBytes(o, 0, o.length);
			var e = Bytes.ofString("\nendobj\n");
			out.addBytes(e, 0, e.length);
			pos += s.length + o.length + e.length;
		}
		var xref = new StringBuf();
		xref.add('xref\n0 ${objects.length}\n0000000000 65535 f \n');
		for (i in 1...objects.length)
			xref.add(StringTools.lpad(Std.string(offsets[i]), "0", 10) + " 00000 n \n");
		xref.add('trailer\n<< /Size ${objects.length} /Root $catalog 0 R /Info $info 0 R >>\nstartxref\n$pos\n%%EOF\n');
		out.addString(xref.toString());
		return out.getBytes();
	}

	function page(r:Recorder, parent:Int):Int {
		resources = new Resources();
		resourcesId = reserve();
		var content = new StringBuf();
		// (canvas units: y down from the top left)
		content.add('1 0 0 -1 0 ${r.height} cm\n');
		body(r, 0, r.ops.length, content);
		var cid = reserve();
		stream(cid, "", Bytes.ofString(content.toString()));
		set(resourcesId, resources.dict());
		return add('<< /Type /Page /Parent $parent 0 R /MediaBox [0 0 ${r.width} ${r.height}] /Resources $resourcesId 0 R /Contents $cid 0 R /Group << /S /Transparency /CS /DeviceRGB >> >>');
	}

	// ops from..to into content; a layer's ops into a group of their own
	function body(r:Recorder, from:Int, to:Int, out:StringBuf) {
		var i = from;
		while (i < to) {
			var o = r.ops[i];
			switch o.kind {
				case Save:
					out.add("q\n");
				case Restore:
					out.add("Q\n");
				case Layer:
					// (its ops up to its restore: a transparency group drawn with its alpha and blend)
					var depth = 0, j = i + 1;
					while (j < to) {
						var k = r.ops[j].kind;
						if (k == Save || k == Layer) depth++;
						if (k == Restore) {
							if (depth == 0) break;
							depth--;
						}
						j++;
					}
					var inner = new StringBuf();
					body(r, i + 1, j, inner);
					var fid = reserve();
					stream(fid, '/Type /XObject /Subtype /Form /BBox [0 0 ${r.width} ${r.height}] /Group << /S /Transparency /CS /DeviceRGB >> /Resources $resourcesId 0 R', Bytes.ofString(inner.toString()));
					resources.forms.push(fid);
					var gs = resources.state(o.alpha, o.alpha, o.blend);
					// (the group in the canvas's units, as the page's content around it)
					out.add('q /$gs gs /Fm$fid Do Q\n');
					i = j;
				case Clip:
					path(o.path, o.matrix, out);
					out.add(o.evenOdd ? "W* n\n" : "W n\n");
				case Fill:
					paintOp(r, i, o, out);
				case StrokePath:
					paintOp(r, i, o, out);
				case Clear:
					if (((o.color >>> 24) & 255) > 0) {
						out.add('q ${rgb(o.color)} rg /${resources.state(((o.color >>> 24) & 255) / 255, 1, null)} gs 0 0 ${r.width} ${r.height} re f Q\n');
					}
				case ClearRect | Pixels:
					fallback(r, i, out);
				case Image:
					image(o, out);
			}
			i++;
		}
	}

	static function num(v:Float):String {
		if (Math.abs(v) < 1e-9) return "0";
		var s = Std.string(Math.round(v * 10000) / 10000);
		return s;
	}

	static function rgb(c:Int):String
		return '${num(((c >> 16) & 255) / 255)} ${num(((c >> 8) & 255) / 255)} ${num((c & 255) / 255)}';

	// a path through m into canvas units
	static function path(p:Path, m:Matrix, out:StringBuf) {
		var pts = p.points, pi = 0;
		inline function pt(k:Int)
			out.add(num(m.mapX(pts[k], pts[k + 1])) + " " + num(m.mapY(pts[k], pts[k + 1])) + " ");
		var lx = 0.0, ly = 0.0;
		for (i in 0...p.verbCount)
			switch p.verbs[i] {
				case Path.MOVE:
					pt(pi);
					out.add("m\n");
					lx = pts[pi];
					ly = pts[pi + 1];
					pi += 2;
				case Path.LINE:
					pt(pi);
					out.add("l\n");
					lx = pts[pi];
					ly = pts[pi + 1];
					pi += 2;
				case Path.QUAD:
					// (as a cubic: its control points two thirds of the way to the quadratic's)
					var cx = pts[pi], cy = pts[pi + 1], x = pts[pi + 2], y = pts[pi + 3];
					var c1x = lx + 2 / 3 * (cx - lx), c1y = ly + 2 / 3 * (cy - ly), c2x = x + 2 / 3 * (cx - x), c2y = y + 2 / 3 * (cy - y);
					out.add('${num(m.mapX(c1x, c1y))} ${num(m.mapY(c1x, c1y))} ${num(m.mapX(c2x, c2y))} ${num(m.mapY(c2x, c2y))} ');
					pt(pi + 2);
					out.add("c\n");
					lx = x;
					ly = y;
					pi += 4;
				case Path.CUBIC:
					pt(pi);
					pt(pi + 2);
					pt(pi + 4);
					out.add("c\n");
					lx = pts[pi + 4];
					ly = pts[pi + 5];
					pi += 6;
				case _:
					out.add("h\n");
			}
	}

	function paintOp(r:Recorder, i:Int, o:Op, out:StringBuf) {
		var p = o.paint, s = p.shader, stroke = o.kind == StrokePath;
		var unbounded = p.blend != null && p.blend.unbounded;
		var plain = s == null || ((Std.isOfType(s, LinearGradient) || Std.isOfType(s, RadialGradient)) && (cast s : Gradient).spread == Gradient.PAD);
		if (!plain || unbounded) {
			fallback(r, i, out);
			return;
		}
		out.add("q\n");
		var alpha = p.alpha * (s == null ? ((p.color >>> 24) & 255) / 255 : 1);
		var smask = s != null ? gradientMask(r, cast s, o.matrix) : -1;
		var gs = resources.state(alpha, alpha, p.blend, smask);
		out.add('/$gs gs\n');
		if (s == null) out.add('${rgb(p.color)} ${stroke ? "RG" : "rg"}\n') else {
			var pat = shadingPattern(r, cast s, o.matrix);
			out.add('/Pattern ${stroke ? "CS" : "cs"} /P$pat ${stroke ? "SCN" : "scn"}\n');
		}
		if (stroke) {
			var st = o.stroke, m = o.matrix;
			// (a stroke in its own units: the transform made the PDF's, the pen with it)
			out.add('${num(m.a)} ${num(m.b)} ${num(m.c)} ${num(m.d)} ${num(m.e)} ${num(m.f)} cm\n');
			out.add('${num(st.width)} w ${st.cap.kind} J ${st.join.kind} j ${num(st.miterLimit)} M\n');
			if (st.dash != null && st.dash.valid()) out.add('[${[for (d in st.dash.intervals) num(d)].join(" ")}] ${num(st.dash.offset)} d\n');
			path(o.path, Matrix.IDENTITY, out);
			out.add("S\nQ\n");
		} else {
			path(o.path, o.matrix, out);
			out.add(o.evenOdd ? "f*\nQ\n" : "f\nQ\n");
		}
	}

	// a gradient's shading: an axial or radial one over its stops (a stitching function of linear ones)
	function shading(g:Gradient, alpha:Bool):Int {
		var n = g.stopCount;
		var fns = [], bounds = [], encode = [];
		inline function c(i:Int):String {
			var col = g.stopColor(i);
			return alpha ? num(((col >>> 24) & 255) / 255) : rgb(col);
		}
		if (n == 1) fns.push(add('<< /FunctionType 2 /Domain [0 1] /C0 [${c(0)}] /C1 [${c(0)}] /N 1 >>'));
		for (i in 0...n - 1) {
			fns.push(add('<< /FunctionType 2 /Domain [0 1] /C0 [${c(i)}] /C1 [${c(i + 1)}] /N 1 >>'));
			if (i > 0) bounds.push(num(g.stopOffset(i)));
			encode.push("0 1");
		}
		var fn = fns.length == 1 ? fns[0] : add('<< /FunctionType 3 /Domain [${num(g.stopOffset(0))} ${num(g.stopOffset(n - 1))}] /Functions [${[for (f in fns) '$f 0 R'].join(" ")}] /Bounds [${bounds.join(" ")}] /Encode [${encode.join(" ")}] >>');
		var cs = alpha ? "/DeviceGray" : "/DeviceRGB";
		if (Std.isOfType(g, LinearGradient)) {
			var l:LinearGradient = cast g;
			return add('<< /ShadingType 2 /ColorSpace $cs /Coords [${num(l.x0)} ${num(l.y0)} ${num(l.x1)} ${num(l.y1)}] /Domain [${num(g.stopOffset(0))} ${num(g.stopOffset(n - 1))}] /Function $fn 0 R /Extend [true true] >>');
		}
		var rg:RadialGradient = cast g;
		return add('<< /ShadingType 3 /ColorSpace $cs /Coords [${num(rg.x0)} ${num(rg.y0)} ${num(rg.r0)} ${num(rg.x1)} ${num(rg.y1)} ${num(rg.r1)}] /Domain [${num(g.stopOffset(0))} ${num(g.stopOffset(n - 1))}] /Function $fn 0 R /Extend [true true] >>');
	}

	// (the gradient's space in the page's: the flip, the transform, its own matrix)
	static function patternMatrix(r:Recorder, g:Gradient, m:Matrix, flip = true):String {
		var t = (flip ? new Matrix(1, 0, 0, -1, 0, r.height) : new Matrix()).multiply(m).multiply(g.matrix);
		return '[${num(t.a)} ${num(t.b)} ${num(t.c)} ${num(t.d)} ${num(t.e)} ${num(t.f)}]';
	}

	function shadingPattern(r:Recorder, g:Gradient, m:Matrix):Int {
		var sh = shading(g, false);
		var id = add('<< /Type /Pattern /PatternType 2 /Shading $sh 0 R /Matrix ${patternMatrix(r, g, m)} >>');
		resources.patterns.push(id);
		return id;
	}

	// a gradient whose stops are not all opaque: its alpha as a luminosity soft mask (-1: none needed)
	function gradientMask(r:Recorder, g:Gradient, m:Matrix):Int {
		var opaque = true;
		for (i in 0...g.stopCount)
			if (((g.stopColor(i) >>> 24) & 255) < 255) opaque = false;
		if (opaque) return -1;
		var sh = shading(g, true);
		// (inside the mask's group the page's flip is already the space: its default)
		var pat = add('<< /Type /Pattern /PatternType 2 /Shading $sh 0 R /Matrix ${patternMatrix(r, g, m, false)} >>');
		var form = reserve();
		stream(form, '/Type /XObject /Subtype /Form /BBox [0 0 ${r.width} ${r.height}] /Group << /S /Transparency /CS /DeviceGray >> /Resources << /Pattern << /P$pat $pat 0 R >> >>',
			Bytes.ofString('/Pattern cs /P$pat scn 0 0 ${r.width} ${r.height} re f'));
		return add('<< /Type /Mask /S /Luminosity /G $form 0 R >>');
	}

	// a bitmap as an image XObject (premultiplied undone: RGB, its alpha a soft mask)
	function imageObject(b:Bitmap, smooth:Bool):Int {
		var n = b.width * b.height, rgbBytes = Bytes.alloc(n * 3), a = Bytes.alloc(n), straight = b.straight(), hasAlpha = false;
		for (i in 0...n) {
			rgbBytes.set(i * 3, straight.get(i * 4));
			rgbBytes.set(i * 3 + 1, straight.get(i * 4 + 1));
			rgbBytes.set(i * 3 + 2, straight.get(i * 4 + 2));
			a.set(i, straight.get(i * 4 + 3));
			if (straight.get(i * 4 + 3) < 255) hasAlpha = true;
		}
		var smask = -1;
		if (hasAlpha) {
			smask = reserve();
			stream(smask, '/Type /XObject /Subtype /Image /Width ${b.width} /Height ${b.height} /ColorSpace /DeviceGray /BitsPerComponent 8', a);
		}
		var id = reserve();
		stream(id, '/Type /XObject /Subtype /Image /Width ${b.width} /Height ${b.height} /ColorSpace /DeviceRGB /BitsPerComponent 8${smooth ? " /Interpolate true" : ""}${smask >= 0 ? ' /SMask $smask 0 R' : ""}', rgbBytes);
		resources.images.push(id);
		return id;
	}

	function image(o:Op, out:StringBuf) {
		var r = o.rect, img = o.image;
		// (the source rectangle cut out of the bitmap, whole pixels)
		var sx = Std.int(Math.max(0, Math.floor(r[0]))), sy = Std.int(Math.max(0, Math.floor(r[1])));
		var sw = Std.int(Math.min(img.width - sx, Math.ceil(r[0] + r[2]) - sx)), sh = Std.int(Math.min(img.height - sy, Math.ceil(r[1] + r[3]) - sy));
		if (sw <= 0 || sh <= 0) return;
		var cut = img;
		if (sx != 0 || sy != 0 || sw != img.width || sh != img.height) {
			cut = new Bitmap(sw, sh);
			for (j in 0...sh)
				cut.pixels.blit(j * sw * 4, img.pixels, ((sy + j) * img.width + sx) * 4, sw * 4);
		}
		var id = imageObject(cut, o.smooth);
		var kx = r[6] / r[2], ky = r[7] / r[3];
		var dx = r[4] + (sx - r[0]) * kx, dy = r[5] + (sy - r[1]) * ky, dw = sw * kx, dh = sh * ky;
		var m = o.matrix.clone().multiply(new Matrix(dw, 0, 0, -dh, dx, dy + dh));
		var gs = resources.state(o.paint.alpha, o.paint.alpha, o.paint.blend);
		out.add('q /$gs gs ${num(m.a)} ${num(m.b)} ${num(m.c)} ${num(m.d)} ${num(m.e)} ${num(m.f)} cm /Im$id Do Q\n');
	}

	// one call PDF cannot say drawn on the CPU (its state: the saves and clips around it replayed), placed as an image
	function fallback(r:Recorder, i:Int, out:StringBuf) {
		var k = fallbackScale, w = Std.int(Math.ceil(r.width * k)), h = Std.int(Math.ceil(r.height * k));
		var c = new Canvas(w, h);
		var o = r.ops[i];
		c.scale(k, k);
		var m = o.matrix;
		c.transform(m.a, m.b, m.c, m.d, m.e, m.f);
		switch o.kind {
			case Fill:
				var p = new Paint().copyFrom(o.paint);
				p.blend = null;
				c.fill(o.path, p, o.evenOdd);
			case StrokePath:
				var p = new Paint().copyFrom(o.paint);
				p.blend = null;
				c.stroke(o.path, o.stroke, p);
			case ClearRect:
				// (erasing: the page's white over it)
				c.fillRect(o.rect[0], o.rect[1], o.rect[2], o.rect[3], Paint.solid(0xFFFFFFFF));
			case Pixels:
				c.resetTransform();
				c.scale(k, k);
				c.drawImage(o.image, 0, 0, o.image.width, o.image.height, o.rect[0], o.rect[1], o.image.width, o.image.height, new Paint(), false);
			case _:
		}
		var id = imageObject(c.bitmap, true);
		var gs = resources.state(1, 1, o.paint == null ? null : o.paint.blend);
		out.add('q /$gs gs ${r.width} 0 0 -${r.height} 0 ${r.height} cm /Im$id Do Q\n');
	}
}

// A page's resources as they are used
private class Resources {
	public final states:Array<String> = [];
	public final patterns:Array<Int> = [];
	public final images:Array<Int> = [];
	public final forms:Array<Int> = [];

	public function new() {}

	// an ExtGState of these opacities and blend mode: its name
	public function state(fill:Float, stroke:Float, blend:Null<Blend.Blender>, smask = -1):String {
		var bm = blend == null ? "Normal" : switch blend.code {
			case 0: "Multiply";
			case 1: "Screen";
			case 2: "Overlay";
			case 3: "Darken";
			case 4: "Lighten";
			case 5: "ColorDodge";
			case 6: "ColorBurn";
			case 7: "HardLight";
			case 8: "SoftLight";
			case 9: "Difference";
			case 10: "Exclusion";
			case 11: "Hue";
			case 12: "Saturation";
			case 13: "Color";
			case 14: "Luminosity";
			case _: "Normal";
		}
		var s = '<< /Type /ExtGState /ca ${fill > 1 ? 1 : fill} /CA ${stroke > 1 ? 1 : stroke} /BM /$bm${smask >= 0 ? ' /SMask $smask 0 R' : ""} >>';
		var i = states.indexOf(s);
		if (i < 0) {
			states.push(s);
			i = states.length - 1;
		}
		return "GS" + i;
	}

	public function dict():String {
		var b = new StringBuf();
		b.add("<< /ExtGState << ");
		for (i in 0...states.length)
			b.add('/GS$i ${states[i]} ');
		b.add(">> /Pattern << ");
		for (p in patterns)
			b.add('/P$p $p 0 R ');
		b.add(">> /XObject << ");
		for (p in images)
			b.add('/Im$p $p 0 R ');
		for (p in forms)
			b.add('/Fm$p $p 0 R ');
		b.add(">> >>");
		return b.toString();
	}
}
