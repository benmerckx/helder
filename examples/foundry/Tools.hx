import Model;
import haxe.Json;
import haxe.crypto.Base64;

// What an agent can do in Foundry (Mcp serves it): read the font and a
// glyph, draw a glyph as pen lines, borrow, space, set the pen and the
// proportions, and look at the result (a glyph on its guides, a line of
// text) as pictures, so that it can judge and correct its own strokes as
// a person does at the board. Every edit goes through the Workshop's
// history (undoable in the window) and opens the glyph on the board.
class Tools {
	public static final INSTRUCTIONS = "Foundry makes a font by drawing letters with a pen. A glyph is a few pen LINES, not outlines: each line is the path of the pen's centre, a list of knots [x, y] that a smooth curve passes through, in font units (1000 to the em, y up, baseline 0); [x, y, 1] marks a corner (a sharp turn, as at the bottom of v); {\"knots\": [...], \"closed\": true} is a loop (o, the bowl of a, b, d, p, q). One pen (pen.set) draws every line: its width, contrast and angle make the weight and style of the whole font, so draw skeletons only. Ink reaches half the pen (font.read's penHalf) beyond the knots, so knots of a letter resting on the baseline sit at y = penHalf, and those touching the x-height at xHeight - penHalf (likewise capital and ascender heights, descender + penHalf). A loop of 8 knots on an ellipse makes a clean bowl; 2 knots a straight stem; arches 5 to 6 knots. Where strokes meet, end one line on a knot of another (an arch starting on its stem). Spacing is automatic (metrics.spacing either side of the ink); fine-tune with glyph.space. Work like a type designer: font.read first, glyph.read a drawn letter to match its stems, bowls and widths; after each glyph.draw look at the picture it returns and at text.snap of the letter among others (\"nanbnonc\", \"HAHBHOHC\"), then correct. Letters borrow until drawn (b, p, q from d; u from n; capitals like O, S, V grown from small ones; accented letters from base and accent): draw the source to change them all, or glyph.draw the borrower to give it a shape of its own. A letter can also be an OUTLINE: contours of points [x, y] on the curve ([x, y, \"smooth\"] where the curve runs straight through), with each cubic curve's two handles between its points ([x, y, \"off\"]); a font started from another (font.start) keeps the font's exact outlines, so a proper font stays one: change it with metrics.set (outline points move with the guides), glyph.transform (scale, slant, move letters), glyph.draw with an outline (its points moved, never redrawn from scratch: glyph.read first). Pen lines can sit over an outline (a swash). Other fonts are material: sources.list names them (the open fonts Foundry carries, every font installed here), font.start begins from one traced into pen lines, font.blend makes a whole font between two (\"something between Inter and Geist Mono\": t 0.5; nearer one: t 0.25), glyph.blend one letter between two, fitted to this font. To restyle a single letter (a swirly x, a looped g), glyph.read it, then glyph.draw its lines changed: a swirl is a line of knots on a spiral, a loop a line that crosses itself; keep the knots where the letter meets the guides.";

	public static final list:Array<Dynamic> = [
		{
			name: "font.read",
			description: "The font: its name, pen, proportions (metrics), penHalf (how far ink reaches beyond a knot vertically), and every character's state (drawn, borrowed, empty).",
			inputSchema: {type: "object", properties: {}}
		},
		{
			name: "glyph.read",
			description: "A glyph: its own lines (knots [x, y] or [x, y, 1] for corners), what it borrows (parts), its spacing, the ink's box and advance, and a picture of it on its guides (blue: the pen's path and knots).",
			inputSchema: {type: "object", properties: {char: {type: "string"}}, required: ["char"]}
		},
		{
			name: "glyph.draw",
			description: "Draw a glyph: its lines replace its own (mode \"add\": added to them), its outline (if given) its own. Each line: {knots: [[x, y], [x, y, 1], ...], closed?: true} or just the array of knots; each outline contour an array of points [x, y], [x, y, \"smooth\"], [x, y, \"off\"] (a cubic's handles, two between points on the curve). Answers with a picture of the result.",
			inputSchema: {
				type: "object",
				properties: {
					char: {type: "string"},
					lines: {type: "array", items: {}},
					outline: {type: "array", items: {type: "array"}},
					mode: {type: "string", "enum": ["replace", "add"]},
					keepParts: {type: "boolean", description: "keep what it borrows besides its own lines (default false)"}
				},
				required: ["char"]
			}
		},
		{
			name: "glyph.transform",
			description: "Scale, slant or move letters' own ink (outline points and pen knots): chars is the letters (\"abc\", or \"lowercase\", \"uppercase\", \"figures\"); scaleX and scaleY about the ink's middle and the baseline (1: as is), slant in degrees (positive leans right, about the baseline), dx and dy in font units. Answers with a picture of text in them.",
			inputSchema: {
				type: "object",
				properties: {
					chars: {type: "string"},
					scaleX: {type: "number"},
					scaleY: {type: "number"},
					slant: {type: "number"},
					dx: {type: "number"},
					dy: {type: "number"}
				},
				required: ["chars"]
			}
		},
		{
			name: "glyph.borrow",
			description: "Make a glyph from others: parts [{of: \"d\", how: \"flip\"}] (how: same, flip (mirrored), turn (half round), flop (upside down), grow (small letter to capital), mark (an accent over the part before), dotless, top, beside; dx, dy to move it). Its own lines stay.",
			inputSchema: {type: "object", properties: {char: {type: "string"}, parts: {type: "array", items: {type: "object"}}}, required: ["char", "parts"]}
		},
		{
			name: "glyph.clear",
			description: "A glyph back to empty, or to what it borrows by default.",
			inputSchema: {type: "object", properties: {char: {type: "string"}}, required: ["char"]}
		},
		{
			name: "glyph.space",
			description: "A glyph's spacing: left and right add to (or take from) the font's spacing either side of its ink, in font units.",
			inputSchema: {type: "object", properties: {char: {type: "string"}, left: {type: "number"}, right: {type: "number"}}, required: ["char"]}
		},
		{
			name: "pen.set",
			description: "The pen for the whole font: width (font units: 40 light, 84 regular, 150 bold), contrast (0 round marker to 1 flat nib), angle (the nib's edge in degrees), cap (\"round\" or \"flat\"). Knots on the guides follow so ink still rests on them.",
			inputSchema: {
				type: "object",
				properties: {width: {type: "number"}, contrast: {type: "number"}, angle: {type: "number"}, cap: {type: "string", "enum": ["round", "flat"]}}
			}
		},
		{
			name: "metrics.set",
			description: "The proportions: xHeight, capHeight, ascender, descender (negative), spacing. Knots move with the guides around them, so every letter follows.",
			inputSchema: {
				type: "object",
				properties: {
					xHeight: {type: "number"},
					capHeight: {type: "number"},
					ascender: {type: "number"},
					descender: {type: "number"},
					spacing: {type: "number"}
				}
			}
		},
		{
			name: "sources.list",
			description: "The fonts other tools can take from: current (the one being drawn), Pebble, Inter, Hanken Grotesk, Geist Mono (SIL Open Font License), and every font installed on this machine (keep to a font's license when sharing what is made from it).",
			inputSchema: {type: "object", properties: {}}
		},
		{
			name: "font.start",
			description: "Start the font again from a source (undoable): its outlines kept exactly, or with pen: true traced into pen lines (a drawn look, the pen's to restyle). Answers with a picture of text in it.",
			inputSchema: {type: "object", properties: {from: {type: "string"}, name: {type: "string"}, pen: {type: "boolean"}}, required: ["from"]}
		},
		{
			name: "font.blend",
			description: "Make the whole font between two sources (each traced into pen lines): t 0 is a, 1 is b, 0.5 halfway; pen, proportions, spacing and every letter's lines in between. Answers with a picture of text in it.",
			inputSchema: {
				type: "object",
				properties: {a: {type: "string"}, b: {type: "string"}, t: {type: "number"}, name: {type: "string"}},
				required: ["a", "b"]
			}
		},
		{
			name: "glyph.blend",
			description: "One letter between two sources (b left out: a's letter alone), fitted to this font's guides; a may be \"current\". Answers with a picture.",
			inputSchema: {
				type: "object",
				properties: {char: {type: "string"}, a: {type: "string"}, b: {type: "string"}, t: {type: "number"}},
				required: ["char", "a"]
			}
		},
		{
			name: "font.rename",
			description: "The font's name (its family when exported).",
			inputSchema: {type: "object", properties: {name: {type: "string"}}, required: ["name"]}
		},
		{
			name: "text.snap",
			description: "A picture of text set in the font as it is now (missing letters left as gaps), to judge shapes, weight and spacing together.",
			inputSchema: {type: "object", properties: {text: {type: "string"}, size: {type: "number", description: "pixels per em, default 96"}}, required: ["text"]}
		},
		{
			name: "font.export",
			description: "The font as a .ttf where downloads go; answers the path.",
			inputSchema: {type: "object", properties: {}}
		},
		{
			name: "board.open",
			description: "Show a glyph on the board (where the person is looking).",
			inputSchema: {type: "object", properties: {char: {type: "string"}}, required: ["char"]}
		}
	];

	final ws:Workshop;

	public function new(ws:Workshop)
		this.ws = ws;

	public function call(name:Null<String>, args:Dynamic):Dynamic {
		if (args == null) args = {};
		return try {content: switch name {
			case "font.read": [text(Json.stringify(font(), "  "))];
			case "glyph.read":
				var char = character(args);
				[text(Json.stringify(glyph(char), "  ")), image(Picture.glyph(ws.value(), char))];
			case "glyph.draw":
				var char = character(args);
				if (args.lines == null && args.outline == null) throw "lines or outline: what to draw";
				var raw:Array<Dynamic> = Std.isOfType(args.lines, Array) ? args.lines : [];
				var lines = [for (l in raw) Model.lineOf(l)].filter(l -> l != null);
				var g = ws.glyph(char);
				var own = args.mode == "add" ? g.lines.concat(lines) : args.lines == null ? g.lines : lines;
				var outline = Std.isOfType(args.outline, Array) ? Model.outlineOf(args.outline) : args.mode == "add" || args.lines == null ? g.outline : null;
				ws.setGlyph(char, {lines: own, parts: args.keepParts == true ? g.parts : [], outline: outline, left: g.left, right: g.right});
				shown(char, 'drew $char');
				[text('$char: ${own.length} lines, ${outline == null ? 0 : outline.length} contours'), image(Picture.glyph(ws.value(), char))];
			case "glyph.transform":
				var spec:String = args.chars ?? "", f = ws.value();
				var chars = switch spec {
					case "lowercase": Charset.groups[0].chars;
					case "uppercase": Charset.groups[1].chars;
					case "figures": Charset.groups[2].chars;
					case _: [for (c in new haxe.iterators.StringIteratorUnicode(spec)) String.fromCharCode(c)];
				};
				var sx:Float = args.scaleX ?? 1, sy:Float = args.scaleY ?? 1, k = Math.tan((args.slant ?? 0) * Math.PI / 180), dx:Float = args.dx ?? 0,
					dy:Float = args.dy ?? 0, done = [];
				for (char in chars) {
					var g = Model.glyph(f, char);
					if (g == null || !Model.drawn(f, char)) continue;
					var b = Ink.bounds(f, char), mid = (b.x0 + b.x1) / 2;
					inline function tx(x:Float, y:Float):Float
						return mid + (x - mid) * sx + y * sy * k + dx;
					var lines = [for (l in g.lines) {knots: [for (q in l.knots) {x: tx(q.x, q.y), y: q.y * sy + dy, corner: q.corner}], closed: l.closed}];
					var outline = g.outline == null ? null : [for (c in g.outline) [for (q in c) {x: tx(q.x, q.y), y: q.y * sy + dy, off: q.off, smooth: q.smooth}]];
					ws.setGlyph(char, {lines: lines, parts: g.parts, outline: outline, left: g.left, right: g.right}, "transform");
					ws.byAgent(char);
					done.push(char);
				}
				if (done.length == 0) throw 'None of "$spec" has ink of its own to transform';
				ws.agent('Agent transformed ${done.length} letters');
				[text('transformed ${done.join("")}'), image(Picture.text(ws.value(), done.slice(0, 24).join(""), 72))];
			case "glyph.borrow":
				var char = character(args), g = ws.glyph(char);
				var parsed = Model.glyphOf({lines: [], parts: args.parts});
				ws.setGlyph(char, {lines: g.lines, parts: parsed == null ? [] : parsed.parts, outline: g.outline, left: g.left, right: g.right});
				shown(char, 'made $char from others');
				[text(Charset.describe(Charset.parts(ws.value(), char))), image(Picture.glyph(ws.value(), char))];
			case "glyph.clear":
				var char = character(args);
				ws.clear(char);
				shown(char, 'cleared $char');
				[text('$char: ${Workshop.state(ws.value(), char)}')];
			case "glyph.space":
				var char = character(args), g = ws.glyph(char);
				ws.setSpacing(char, args.left ?? g.left ?? 0, args.right ?? g.right ?? 0);
				shown(char, 'spaced $char');
				[text('$char: left ${args.left ?? g.left ?? 0}, right ${args.right ?? g.right ?? 0}'), image(Picture.glyph(ws.value(), char))];
			case "pen.set":
				var p = ws.value().pen;
				ws.setPen({
					width: args.width ?? p.width,
					contrast: args.contrast ?? p.contrast,
					angle: args.angle ?? p.angle,
					cap: args.cap == "flat" ? Flat : args.cap == "round" ? Round : p.cap
				});
				ws.agent("Changed the pen");
				[text(Json.stringify(ws.value().pen))];
			case "metrics.set":
				var m = ws.value().metrics;
				ws.setMetrics({
					xHeight: args.xHeight ?? m.xHeight,
					capHeight: args.capHeight ?? m.capHeight,
					ascender: args.ascender ?? m.ascender,
					descender: args.descender ?? m.descender,
					spacing: args.spacing ?? m.spacing
				});
				ws.agent("Changed the proportions");
				[text(Json.stringify(ws.value().metrics))];
			case "sources.list":
				[text(Sources.names().join("\n"))];
			case "font.start":
				var from = Std.string(args.from), pen = args.pen == true;
				var f = Model.named(Sources.face(from, ws, pen), args.name ?? "My " + from);
				ws.begin(f);
				everything('started from $from');
				[text('${f.name}: ${[for (k in f.glyphs.keys()) k].length} letters from $from, ${pen ? "traced into pen lines" : "its outlines"}'), image(Picture.text(ws.value(), SAMPLE, 72))];
			case "font.blend":
				var a = Std.string(args.a), b = Std.string(args.b), t:Float = args.t ?? 0.5;
				var f = Blend.faces(Sources.face(a, ws), Sources.face(b, ws), t, args.name ?? '$a $b');
				ws.begin(f);
				everything('blended $a and $b');
				[text('${f.name}: ${Math.round((1 - t) * 100)}% $a, ${Math.round(t * 100)}% $b'), image(Picture.text(ws.value(), SAMPLE, 72))];
			case "glyph.blend":
				var char = character(args), cur = ws.value(), t:Float = args.t ?? 0.5;
				var fa = Sources.face(Std.string(args.a), ws), fb = args.b == null ? fa : Sources.face(Std.string(args.b), ws);
				var ca = Ink.ink(fa, char), cb = Ink.ink(fb, char);
				if (ca.length == 0 && cb.length == 0) throw 'Neither source has "$char"';
				var g = ws.glyph(char), between = Blend.mixed(fa, fb, t, "");
				var lines = [for (l in Workshop.fit(Blend.shapes(ca, cb, args.b == null ? 0 : t), between, cur, char)) Freehand.snap(l, cur, [])];
				ws.setGlyph(char, {lines: lines, parts: [], left: g.left, right: g.right});
				shown(char, 'drew $char');
				[text('$char: ${lines.length} lines'), image(Picture.glyph(ws.value(), char))];
			case "font.rename":
				ws.rename(Std.string(args.name));
				[text(ws.value().name)];
			case "text.snap":
				var size:Float = args.size ?? 96;
				[image(Picture.text(ws.value(), Std.string(args.text), Std.int(Math.max(16, Math.min(256, size)))))];
			case "font.export":
				ws.export();
				[text(ws.status.peek())];
			case "board.open":
				var char = character(args);
				ws.open(char);
				[text('showing $char')];
			case _: throw 'no tool $name';
		}} catch (e:Dynamic) {
			{content: [{type: "text", text: Std.string(e)}], isError: true};
		}
	}

	static inline var SAMPLE = "Hamburgefonstiv HOXA 0123";

	// a whole font changed by an agent: every letter marked, the one on the board written out
	function everything(what:String) {
		ws.agentGlyphs([for (k in ws.value().glyphs.keys()) k]);
		ws.agentStroke({char: ws.current.peek(), at: helder.ui.Clock.now});
		ws.agent("Agent " + what);
		haxe.Timer.delay(() -> if (ws.agent.peek() == "Agent " + what) ws.agent(""), 5000);
	}

	function shown(char:String, what:String) {
		ws.open(char);
		if (what.indexOf("drew") == 0 || what.indexOf("made") == 0) ws.byAgent(char);
		ws.agent("Agent " + what);
		haxe.Timer.delay(() -> if (ws.agent.peek() == "Agent " + what) ws.agent(""), 4000);
	}

	function font():Dynamic {
		var f = ws.value();
		var states:haxe.DynamicAccess<String> = {};
		for (c in Charset.all)
			states.set(c, Workshop.state(f, c));
		return {
			name: f.name,
			unitsPerEm: Model.EM,
			pen: f.pen,
			penHalf: Math.round(Ink.vertical(f.pen) * 10) / 10,
			metrics: f.metrics,
			start: Charset.start,
			glyphs: states
		};
	}

	function glyph(char:String):Dynamic {
		var f = ws.value(), g = ws.glyph(char), s = Ink.shape(f, char), b = Ink.box(Ink.lines(f, char));
		return {
			char: char,
			state: Workshop.state(f, char),
			lines: [for (l in g.lines) {
				knots: [for (k in l.knots) k.corner == true ? [k.x, k.y, 1] : [k.x, k.y]],
				closed: l.closed == true
			}],
			outline: g.outline == null ? null : [for (c in g.outline) [for (q in c) {
				var x:Dynamic = Math.round(q.x * 10) / 10, y:Dynamic = Math.round(q.y * 10) / 10;
				q.off == true ? [x, y, "off"] : q.smooth == true ? [x, y, "smooth"] : [x, y];
			}]],
			parts: g.parts,
			borrowed: Charset.describe(Charset.parts(f, char)),
			left: g.left ?? 0,
			right: g.right ?? 0,
			knotBox: b,
			advance: Math.round(s.advance)
		};
	}

	static function character(args:Dynamic):String {
		var c:Null<String> = args.char;
		if (c == null || c == "") throw "char: the character, as \"a\"";
		var first = String.fromCharCode(Charset.code(c));
		if (Charset.all.indexOf(first) < 0) throw 'Foundry does not make "$first" (font.read lists what it makes)';
		return first;
	}

	static function text(s:String):Dynamic
		return {type: "text", text: s};

	static function image(png:haxe.io.Bytes):Dynamic
		return {type: "image", data: Base64.encode(png), mimeType: "image/png"};
}
