import haxe.DynamicAccess;

// A typeface as Foundry keeps it: letters drawn as pen lines (knots the
// line passes through, smooth unless a knot is a corner), one pen for all
// of them, so the weight and the nib are the whole font's; a letter may
// borrow another's lines (b from d mirrored, é from e and an acute) and
// follows it when that one changes. Font units, y up, 1000 to the em.
// Values are never changed in place: each edit makes a new Face.
typedef Knot = {x:Float, y:Float, ?corner:Bool};

typedef Line = {knots:Array<Knot>, ?closed:Bool};

// another glyph's lines, moved: how (Turn), and an offset
typedef Part = {of:String, how:Turn, ?dx:Float, ?dy:Float};

// a point of an outline: on the contour (a corner, or smooth: the handles
// either side in line), or a cubic curve's handle (off); a contour is
// closed, from on point to on point a line, or a curve through two handles
typedef OPoint = {x:Float, y:Float, ?off:Bool, ?smooth:Bool};

// pen lines of its own, an outline of its own (a font's letter kept
// exact: its points edited as they are), parts; left and right widen (or
// narrow) its spacing. Its ink is all of them.
// (advance: an empty glyph's own (a space's); also: other characters it is;
// anchors: where marks go on it ("top", "bottom", "ogonek") or where a mark
// goes onto its letter ("_top"...), where they are not where its ink says)
typedef Glyph = {
	lines:Array<Line>,
	parts:Array<Part>,
	?outline:Array<Array<OPoint>>,
	?left:Float,
	?right:Float,
	?advance:Float,
	?also:Array<Int>,
	?anchors:DynamicAccess<{x:Float, y:Float}>
};

// the nib: its width, how much thinner it draws across than along its
// edge (0: a round marker, 1: a flat calligraphy nib), its edge's angle
// in degrees, the line's ends
typedef Pen = {width:Float, contrast:Float, angle:Float, cap:Cap};

typedef Metrics = {xHeight:Float, capHeight:Float, ascender:Float, descender:Float, spacing:Float};

// a glyph missing from glyphs takes Charset's suggestion (borrowed, or
// empty). Keys are characters, or "#" and a name for a glyph without one
// (an alternate, a ligature's). source: the font it was started from, kept
// to write it again as a whole: its units to the em, its glyphs' order (by
// key, from 0), its layout tables (GSUB, GPOS, GDEF: base64), which name
// glyphs by their place in that order
// kerning: the space put between two glyphs, by "left\tright" (their keys)
typedef Face = {name:String, pen:Pen, metrics:Metrics, glyphs:DynamicAccess<Glyph>, ?source:Source, ?kerning:DynamicAccess<Float>};

typedef Source = {units:Int, order:Array<String>, tables:DynamicAccess<String>};

enum abstract Cap(String) from String to String {
	var Round = "round";
	var Flat = "flat";
}

// how a part is moved: as it is, mirrored left to right, turned half
// round, mirrored top to bottom, grown to capitals, an accent over (or a
// cedilla under) the base before it, the dot left out, raised to the
// x-height, set beside itself
enum abstract Turn(String) from String to String {
	var Same = "same";
	var Flip = "flip";
	var Half = "turn";
	var Flop = "flop";
	var Grow = "grow";
	var Mark = "mark";
	var Dotless = "dotless";
	var Top = "top";
	var Beside = "beside";
}

class Model {
	public static inline var EM = 1000;

	public static final PEN:Pen = {width: 84, contrast: 0, angle: 30, cap: Round};
	public static final METRICS:Metrics = {xHeight: 500, capHeight: 700, ascender: 740, descender: -230, spacing: 60};

	public static function empty(name = "Untitled"):Face
		return {name: name, pen: PEN, metrics: METRICS, glyphs: {}};

	public static function glyph(face:Face, char:String):Null<Glyph>
		return face.glyphs.get(char);

	// the face with char's glyph set (null: back to its suggestion)
	public static function with(face:Face, char:String, g:Null<Glyph>):Face {
		var glyphs:DynamicAccess<Glyph> = {};
		for (k => v in face.glyphs)
			if (k != char) glyphs.set(k, v);
		if (g != null) glyphs.set(char, g);
		return {name: face.name, pen: face.pen, metrics: face.metrics, glyphs: glyphs, source: face.source, kerning: face.kerning};
	}

	public static function withPen(face:Face, pen:Pen):Face
		return {name: face.name, pen: pen, metrics: face.metrics, glyphs: face.glyphs, source: face.source, kerning: face.kerning};

	public static function withMetrics(face:Face, metrics:Metrics):Face
		return {name: face.name, pen: face.pen, metrics: metrics, glyphs: face.glyphs, source: face.source, kerning: face.kerning};

	// the face with the kerning between left and right (0: none)
	public static function kerned(face:Face, left:String, right:String, value:Float):Face {
		var k:DynamicAccess<Float> = {};
		if (face.kerning != null)
			for (key => v in face.kerning)
				k.set(key, v);
		if (Math.round(value) == 0) k.remove(left + "\t" + right) else k.set(left + "\t" + right, Math.round(value));
		return {name: face.name, pen: face.pen, metrics: face.metrics, glyphs: face.glyphs, source: face.source, kerning: k};
	}

	public static function kern(face:Face, left:String, right:String):Float
		return face.kerning == null ? 0 : face.kerning.get(left + "\t" + right) ?? 0;

	// whether the face's kerning is its own (a source's GPOS has its own, which a kern table does not change)
	public static function kernable(face:Face):Bool
		return face.source == null || !face.source.tables.exists("GPOS");

	public static function named(face:Face, name:String):Face
		return {name: name, pen: face.pen, metrics: face.metrics, glyphs: face.glyphs, source: face.source, kerning: face.kerning};

	// whether char has ink of its own (pen lines, an outline)
	public static function drawn(face:Face, char:String):Bool {
		var g = face.glyphs.get(char);
		return g != null && (g.lines.length > 0 || outlined(g));
	}

	public static inline function outlined(g:Null<Glyph>):Bool
		return g != null && g.outline != null && g.outline.length > 0;

	public static function save(face:Face):String
		return haxe.Json.stringify(face);

	// a saved face (or an agent's), its fields checked: null when it is not one
	public static function load(json:String):Null<Face> {
		var d:Dynamic = try haxe.Json.parse(json) catch (_:Dynamic) null;
		if (d == null || d.glyphs == null || d.pen == null || d.metrics == null) return null;
		var glyphs:DynamicAccess<Glyph> = {};
		var raw:DynamicAccess<Dynamic> = d.glyphs;
		for (k => g in raw) {
			var parsed = glyphOf(g);
			if (parsed != null) glyphs.set(k, parsed);
		}
		var p:Dynamic = d.pen, m:Dynamic = d.metrics;
		return {
			name: Std.string(d.name ?? "Untitled"),
			pen: {width: num(p.width, PEN.width), contrast: num(p.contrast, 0), angle: num(p.angle, PEN.angle), cap: p.cap == "flat" ? Flat : Round},
			metrics: {
				xHeight: num(m.xHeight, METRICS.xHeight),
				capHeight: num(m.capHeight, METRICS.capHeight),
				ascender: num(m.ascender, METRICS.ascender),
				descender: num(m.descender, METRICS.descender),
				spacing: num(m.spacing, METRICS.spacing)
			},
			glyphs: glyphs,
			kerning: d.kerning,
			source: d.source == null || !Std.isOfType(d.source.order, Array) ? null : {
				units: Std.int(num(d.source.units, EM)),
				order: [for (k in (d.source.order : Array<Dynamic>)) Std.string(k)],
				tables: d.source.tables ?? {}
			}
		};
	}

	// a glyph from JSON (an agent's: lines of knots as {x, y, corner} or [x, y, corner])
	public static function glyphOf(g:Dynamic):Null<Glyph> {
		if (g == null) return null;
		var lines:Array<Line> = [];
		var raw:Array<Dynamic> = Std.isOfType(g.lines, Array) ? g.lines : [];
		for (l in raw) {
			var line = lineOf(l);
			if (line != null) lines.push(line);
		}
		var parts:Array<Part> = [];
		var rawParts:Array<Dynamic> = Std.isOfType(g.parts, Array) ? g.parts : [];
		for (p in rawParts)
			if (p != null && p.of != null) parts.push({of: Std.string(p.of), how: p.how ?? Same, dx: num(p.dx, 0), dy: num(p.dy, 0)});
		var outline = Std.isOfType(g.outline, Array) ? outlineOf(g.outline) : null;
		return {
			lines: lines,
			parts: parts,
			outline: outline,
			left: num(g.left, 0),
			right: num(g.right, 0),
			advance: g.advance == null ? null : num(g.advance, 0),
			also: Std.isOfType(g.also, Array) ? [for (c in (g.also : Array<Dynamic>)) Std.int(num(c, 0))] : null,
			anchors: g.anchors
		};
	}

	// an outline from JSON: contours of points as {x, y, off, smooth} or [x, y] ([x, y, "off"], [x, y, "smooth"])
	public static function outlineOf(raw:Array<Dynamic>):Array<Array<OPoint>> {
		var out = [];
		for (c in raw) {
			if (!Std.isOfType(c, Array)) continue;
			var points:Array<OPoint> = [];
			for (p in (c : Array<Dynamic>)) {
				if (p == null) continue;
				if (Std.isOfType(p, Array)) {
					var a:Array<Dynamic> = p;
					if (a.length >= 2) points.push({x: num(a[0], 0), y: num(a[1], 0), off: a[2] == "off", smooth: a[2] == "smooth"});
				} else points.push({x: num(p.x, 0), y: num(p.y, 0), off: p.off == true, smooth: p.smooth == true});
			}
			if (points.length > 1) out.push(points);
		}
		return out;
	}

	public static function lineOf(l:Dynamic):Null<Line> {
		if (l == null) return null;
		var raw:Array<Dynamic> = Std.isOfType(l, Array) ? l : Std.isOfType(l.knots, Array) ? l.knots : [];
		var knots:Array<Knot> = [];
		for (k in raw) {
			if (k == null) continue;
			if (Std.isOfType(k, Array)) {
				var a:Array<Dynamic> = k;
				if (a.length >= 2) knots.push({x: num(a[0], 0), y: num(a[1], 0), corner: a[2] == true || a[2] == "corner"});
			} else knots.push({x: num(k.x, 0), y: num(k.y, 0), corner: k.corner == true});
		}
		if (knots.length == 0) return null;
		return {knots: knots, closed: !Std.isOfType(l, Array) && l.closed == true};
	}

	static function num(v:Dynamic, d:Float):Float {
		if (v == null) return d;
		var f:Float = Std.isOfType(v, String) ? Std.parseFloat(v) : v;
		return Math.isNaN(f) ? d : f;
	}
}
