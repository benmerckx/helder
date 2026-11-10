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

// lines of its own and parts; left and right widen (or narrow) its spacing
typedef Glyph = {lines:Array<Line>, parts:Array<Part>, ?left:Float, ?right:Float};

// the nib: its width, how much thinner it draws across than along its
// edge (0: a round marker, 1: a flat calligraphy nib), its edge's angle
// in degrees, the line's ends
typedef Pen = {width:Float, contrast:Float, angle:Float, cap:Cap};

typedef Metrics = {xHeight:Float, capHeight:Float, ascender:Float, descender:Float, spacing:Float};

// a glyph missing from glyphs takes Charset's suggestion (borrowed, or empty)
typedef Face = {name:String, pen:Pen, metrics:Metrics, glyphs:DynamicAccess<Glyph>};

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
		return {name: face.name, pen: face.pen, metrics: face.metrics, glyphs: glyphs};
	}

	public static function withPen(face:Face, pen:Pen):Face
		return {name: face.name, pen: pen, metrics: face.metrics, glyphs: face.glyphs};

	public static function withMetrics(face:Face, metrics:Metrics):Face
		return {name: face.name, pen: face.pen, metrics: metrics, glyphs: face.glyphs};

	public static function named(face:Face, name:String):Face
		return {name: name, pen: face.pen, metrics: face.metrics, glyphs: face.glyphs};

	// whether char has lines of its own
	public static function drawn(face:Face, char:String):Bool {
		var g = face.glyphs.get(char);
		return g != null && g.lines.length > 0;
	}

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
			glyphs: glyphs
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
		return {lines: lines, parts: parts, left: num(g.left, 0), right: num(g.right, 0)};
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
