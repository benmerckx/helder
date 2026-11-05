package helder.pdf;

import haxe.io.Bytes;
import helder.pdf.PdfValue;
import helder.pdf.Document;

// PDF's functions (types 0: sampled, 2: exponential, 3: stitching, 4:
// PostScript calculator), each input and output clipped to its domain and
// range
class PdfFunction {
	public final inputs:Int;
	public final outputs:Int;
	final kind:Int;
	final domain:Array<Float>;
	final range:Null<Array<Float>>;
	// 0
	var size:Array<Int>;
	var bps = 8;
	var encode:Array<Float>;
	var decode:Array<Float>;
	var samples:Bytes;
	// 2
	var c0:Array<Float>;
	var c1:Array<Float>;
	var n = 1.0;
	// 3
	var functions:Array<PdfFunction>;
	var bounds:Array<Float>;
	// 4
	var program:Array<Dynamic>;

	function new(kind:Int, inputs:Int, outputs:Int, domain:Array<Float>, range:Null<Array<Float>>) {
		this.kind = kind;
		this.inputs = inputs;
		this.outputs = outputs;
		this.domain = domain;
		this.range = range;
	}

	// a function (or an array of one-output ones: their outputs together)
	public static function load(doc:Document, v:PdfValue, depth = 0):PdfFunction {
		v = doc.resolve(v);
		if (depth > 8) throw PdfError.corrupt("functions nested past 8");
		var list = Values.arr(v);
		if (list != null) {
			var fs = [for (x in list) load(doc, x, depth + 1)];
			var f = new PdfFunction(-1, fs[0].inputs, fs.length, [0, 1], null);
			f.functions = fs;
			return f;
		}
		var d = Values.dict(v);
		if (d == null) throw PdfError.corrupt("a function that is no dictionary");
		var t = Values.int(d.get("FunctionType"), -1);
		var domain = Values.nums(doc.resolve(d.get("Domain"))) ?? [0.0, 1];
		var range = Values.nums(doc.resolve(d.get("Range")));
		var inputs = Std.int(domain.length / 2);
		switch t {
			case 0:
				var f = new PdfFunction(0, inputs, range == null ? 1 : Std.int(range.length / 2), domain, range);
				f.size = [for (x in Values.nums(doc.resolve(d.get("Size"))) ?? [2.0]) Std.int(x)];
				f.bps = Values.int(d.get("BitsPerSample"), 8);
				f.encode = Values.nums(doc.resolve(d.get("Encode"))) ?? [for (s in f.size) for (k in [0.0, s - 1]) k];
				f.decode = Values.nums(doc.resolve(d.get("Decode"))) ?? range ?? [0.0, 1];
				f.samples = doc.stream(v);
				var total = 1.0;
				for (s in f.size)
					total *= s;
				if (total * f.outputs > 1e7) throw PdfError.tooLarge("a sampled function of " + total + " samples");
				return f;
			case 2:
				var c0 = Values.nums(doc.resolve(d.get("C0"))) ?? [0.0], c1 = Values.nums(doc.resolve(d.get("C1"))) ?? [1.0];
				var f = new PdfFunction(2, 1, c0.length, domain, range);
				f.c0 = c0;
				f.c1 = c1;
				f.n = Values.num(d.get("N"), 1);
				return f;
			case 3:
				var fs = [for (x in Values.arr(doc.resolve(d.get("Functions"))) ?? []) load(doc, x, depth + 1)];
				if (fs.length == 0) throw PdfError.corrupt("a stitching function of none");
				var f = new PdfFunction(3, 1, fs[0].outputs, domain, range);
				f.functions = fs;
				f.bounds = Values.nums(doc.resolve(d.get("Bounds"))) ?? [];
				f.encode = Values.nums(doc.resolve(d.get("Encode"))) ?? [for (_ in fs) for (k in [0.0, 1]) k];
				return f;
			case 4:
				var f = new PdfFunction(4, inputs, range == null ? 1 : Std.int(range.length / 2), domain, range);
				f.program = PostScript.parse(doc.stream(v));
				return f;
			case _:
				throw PdfError.unsupported("function type " + t);
		}
	}

	public function eval(x:Array<Float>):Array<Float> {
		var input = [for (i in 0...inputs) clip(i < x.length ? x[i] : 0, domain[i * 2], domain[i * 2 + 1])];
		var out = switch kind {
			case -1: [for (f in functions) f.eval(input)[0]];
			case 0: sampled(input);
			case 2:
				var t = input[0];
				[for (i in 0...c0.length) c0[i] + Math.pow(t, n) * (c1[i] - c0[i])];
			case 3:
				var t = input[0], k = 0;
				while (k < bounds.length && t >= bounds[k])
					k++;
				var a = k == 0 ? domain[0] : bounds[k - 1], b = k == bounds.length ? domain[1] : bounds[k];
				var e0 = encode[k * 2], e1 = encode[k * 2 + 1];
				functions[k].eval([b == a ? e0 : e0 + (t - a) * (e1 - e0) / (b - a)]);
			case _: PostScript.run(program, input, outputs);
		}
		if (range != null)
			for (i in 0...out.length)
				if (i * 2 + 1 < range.length) out[i] = clip(out[i], range[i * 2], range[i * 2 + 1]);
		return out;
	}

	static inline function clip(v:Float, a:Float, b:Float):Float
		return v < a ? a : v > b ? b : v;

	function sampled(x:Array<Float>):Array<Float> {
		// (multilinear in one input, nearest in the others: most sampled functions have one)
		var idx = 0, stride = 1, frac = 0.0, step = 0;
		for (i in 0...inputs) {
			var e = encode[i * 2] + (x[i] - domain[i * 2]) * (encode[i * 2 + 1] - encode[i * 2]) / (domain[i * 2 + 1] - domain[i * 2]);
			e = clip(e, 0, size[i] - 1);
			var f = Math.floor(e);
			if (i == 0) {
				frac = e - f;
				step = f < size[0] - 1 ? 1 : 0;
			}
			idx += Std.int(i == 0 ? f : Math.round(e)) * stride;
			stride *= size[i];
		}
		var max = Math.pow(2, bps) - 1;
		return [for (o in 0...outputs) {
			var a = sample(idx * outputs + o), b = sample((idx + step) * outputs + o);
			var v = (a + (b - a) * frac) / max;
			decode[o * 2] + v * (decode[o * 2 + 1] - decode[o * 2]);
		}];
	}

	function sample(i:Int):Float {
		var bit = i * bps;
		if (bps == 8) return i < samples.length ? samples.get(i) : 0;
		if (bps == 16) return i * 2 + 1 < samples.length ? (samples.get(i * 2) << 8) | samples.get(i * 2 + 1) : 0;
		var v = 0;
		for (k in 0...bps) {
			var p = bit + k, byte = p >> 3;
			v = (v << 1) | (byte < samples.length ? (samples.get(byte) >> (7 - (p & 7))) & 1 : 0);
		}
		return v;
	}
}

// Type 4 functions: a PostScript subset (arithmetic, comparisons, if, ifelse, stack operators)
class PostScript {
	public static function parse(b:Bytes):Array<Dynamic> {
		var p = new Parser(b);
		p.skip();
		if (p.at(p.pos) == "{".code) p.pos++;
		return block(p, 0);
	}

	static function block(p:Parser, depth:Int):Array<Dynamic> {
		if (depth > 32) throw PdfError.corrupt("a PostScript function nested past 32");
		var out:Array<Dynamic> = [];
		while (true) {
			p.skip();
			if (p.pos >= p.end) break;
			var c = p.at(p.pos);
			if (c == "{".code) {
				p.pos++;
				out.push(block(p, depth + 1));
				continue;
			}
			if (c == "}".code) {
				p.pos++;
				break;
			}
			var v = p.next();
			if (v != null) out.push(Values.num(v)) else if (p.keyword != "") out.push(p.keyword);
		}
		return out;
	}

	public static function run(prog:Array<Dynamic>, input:Array<Float>, outputs:Int):Array<Float> {
		var s = input.copy();
		exec(prog, s, 0);
		while (s.length < outputs)
			s.unshift(0);
		return s.slice(s.length - outputs);
	}

	static function exec(prog:Array<Dynamic>, s:Array<Float>, depth:Int) {
		if (depth > 32) return;
		var i = 0;
		inline function pop():Float
			return s.length > 0 ? s.pop() : 0;
		while (i < prog.length) {
			var t:Dynamic = prog[i++];
			if (Std.isOfType(t, Float) || Std.isOfType(t, Int)) {
				s.push(t);
				continue;
			}
			if (Std.isOfType(t, Array)) {
				// (a block before if or ifelse)
				var next:Dynamic = prog[i];
				if (next == "if") {
					i++;
					if (pop() != 0) exec(t, s, depth + 1);
				} else if (next == "ifelse") {
					continue;
				} else if (Std.isOfType(next, Array) && prog[i + 1] == "ifelse") {
					i += 2;
					if (pop() != 0) exec(t, s, depth + 1) else exec(next, s, depth + 1);
				}
				continue;
			}
			if (s.length > 1000) return;
			switch (t : String) {
				case "add": var b = pop(), a = pop(); s.push(a + b);
				case "sub": var b = pop(), a = pop(); s.push(a - b);
				case "mul": var b = pop(), a = pop(); s.push(a * b);
				case "div": var b = pop(), a = pop(); s.push(b == 0 ? 0 : a / b);
				case "idiv": var b = pop(), a = pop(); s.push(b == 0 ? 0 : Std.int(a / b));
				case "mod": var b = pop(), a = pop(); s.push(b == 0 ? 0 : a % b);
				case "neg": s.push(-pop());
				case "abs": s.push(Math.abs(pop()));
				case "ceiling": s.push(Math.fceil(pop()));
				case "floor": s.push(Math.ffloor(pop()));
				case "round": s.push(Math.fround(pop()));
				case "truncate": var a = pop(); s.push(a < 0 ? Math.fceil(a) : Math.ffloor(a));
				case "sqrt": s.push(Math.sqrt(Math.max(0, pop())));
				case "sin": s.push(Math.sin(pop() * Math.PI / 180));
				case "cos": s.push(Math.cos(pop() * Math.PI / 180));
				case "atan": var b = pop(), a = pop(); var d = Math.atan2(a, b) * 180 / Math.PI; s.push(d < 0 ? d + 360 : d);
				case "exp": var b = pop(), a = pop(); s.push(Math.pow(a, b));
				case "ln": s.push(Math.log(Math.max(1e-30, pop())));
				case "log": s.push(Math.log(Math.max(1e-30, pop())) / Math.log(10));
				case "cvi": s.push(Std.int(pop()));
				case "cvr":
				case "eq": s.push(pop() == pop() ? 1 : 0);
				case "ne": s.push(pop() != pop() ? 1 : 0);
				case "gt": var b = pop(), a = pop(); s.push(a > b ? 1 : 0);
				case "ge": var b = pop(), a = pop(); s.push(a >= b ? 1 : 0);
				case "lt": var b = pop(), a = pop(); s.push(a < b ? 1 : 0);
				case "le": var b = pop(), a = pop(); s.push(a <= b ? 1 : 0);
				case "and": var b = Std.int(pop()), a = Std.int(pop()); s.push(a & b);
				case "or": var b = Std.int(pop()), a = Std.int(pop()); s.push(a | b);
				case "xor": var b = Std.int(pop()), a = Std.int(pop()); s.push(a ^ b);
				case "not": var a = pop(); s.push(a == 0 ? 1 : a == 1 ? 0 : ~Std.int(a));
				case "bitshift": var b = Std.int(pop()), a = Std.int(pop()); s.push(b >= 0 ? a << b : a >> -b);
				case "true": s.push(1);
				case "false": s.push(0);
				case "pop": pop();
				case "exch": var b = pop(), a = pop(); s.push(b); s.push(a);
				case "dup": var a = pop(); s.push(a); s.push(a);
				case "copy":
					var n = Std.int(pop());
					if (n > 0 && n <= s.length) for (v in s.slice(s.length - n)) s.push(v);
				case "index":
					var n = Std.int(pop());
					s.push(n >= 0 && n < s.length ? s[s.length - 1 - n] : 0);
				case "roll":
					var j = Std.int(pop()), n = Std.int(pop());
					if (n > 0 && n <= s.length) {
						var part = s.splice(s.length - n, n);
						j = ((j % n) + n) % n;
						for (k in 0...n) s.push(part[(k - j + n) % n]);
					}
				case _:
			}
		}
	}
}

// A colour space: its components into RGB (0 to 1): DeviceGray, DeviceRGB,
// DeviceCMYK (the naive conversion), CalGray and CalRGB as their device
// ones, Lab (to sRGB under D65), ICCBased by its N (its alternate's
// components), Indexed, Separation and DeviceN through their tint
// transform into the alternate, Pattern (its paint set apart)
class ColorSpace {
	public final kind:String;
	public final components:Int;
	var base:Null<ColorSpace>;
	var lookup:Null<Bytes>;
	var hival = 0;
	var tint:Null<PdfFunction>;
	var white = [0.9505, 1.0, 1.089];
	var labRange = [-100.0, 100, -100, 100];

	function new(kind:String, components:Int) {
		this.kind = kind;
		this.components = components;
	}

	public static final GRAY = new ColorSpace("DeviceGray", 1);
	public static final RGB = new ColorSpace("DeviceRGB", 3);
	public static final CMYK = new ColorSpace("DeviceCMYK", 4);

	public static function load(doc:Document, v:PdfValue, resources:Null<PdfDict>, depth = 0):ColorSpace {
		v = doc.resolve(v);
		if (depth > 8) throw PdfError.corrupt("colour spaces nested past 8");
		switch v {
			case PName(n):
				switch n {
					case "DeviceGray" | "G" | "CalGray": return GRAY;
					case "DeviceRGB" | "RGB" | "CalRGB": return RGB;
					case "DeviceCMYK" | "CMYK": return CMYK;
					case "Pattern": return new ColorSpace("Pattern", 0);
					case _:
						var cs = resources == null ? null : Values.dict(doc.resolve(resources.get("ColorSpace")));
						if (cs != null && cs.has(n)) return load(doc, cs.get(n), resources, depth + 1);
						return n == "I" ? GRAY : RGB;
				}
			case PArray(a) if (a.length > 0):
				var n = Values.name(doc.resolve(a[0]), "");
				switch n {
					case "DeviceGray" | "CalGray" | "G": return GRAY;
					case "DeviceRGB" | "CalRGB" | "RGB": return RGB;
					case "DeviceCMYK" | "CMYK": return CMYK;
					case "Lab":
						var c = new ColorSpace("Lab", 3);
						var d = a.length > 1 ? Values.dict(doc.resolve(a[1])) : null;
						if (d != null) {
							c.white = Values.nums(doc.resolve(d.get("WhitePoint"))) ?? c.white;
							c.labRange = Values.nums(doc.resolve(d.get("Range"))) ?? c.labRange;
						}
						return c;
					case "ICCBased":
						var d = a.length > 1 ? Values.dict(doc.resolve(a[1])) : null;
						var k = d == null ? 3 : Values.int(d.get("N"), 3);
						if (d != null && d.has("Alternate")) return load(doc, d.get("Alternate"), resources, depth + 1);
						return k == 1 ? GRAY : k == 4 ? CMYK : RGB;
					case "Indexed" | "I":
						var c = new ColorSpace("Indexed", 1);
						c.base = load(doc, a[1], resources, depth + 1);
						c.hival = Values.int(doc.resolve(a[2]));
						var l = doc.resolve(a[3]);
						c.lookup = switch l {
							case PStr(b): b;
							case PStream(_, _): doc.stream(l);
							case _: Bytes.alloc(0);
						}
						return c;
					case "Separation" | "DeviceN":
						var names = n == "Separation" ? 1 : (Values.arr(doc.resolve(a[1])) ?? []).length;
						var c = new ColorSpace(n, names);
						c.base = load(doc, a[2], resources, depth + 1);
						c.tint = try PdfFunction.load(doc, a[3]) catch (_:PdfError) null;
						return c;
					case "Pattern":
						var c = new ColorSpace("Pattern", 0);
						if (a.length > 1) c.base = load(doc, a[1], resources, depth + 1);
						return c;
					case _:
						return RGB;
				}
			case _:
				return GRAY;
		}
	}

	// the components' initial value (black, or the first index; a tint of 1)
	public function initial():Array<Float>
		return switch kind {
			case "DeviceCMYK": [0, 0, 0, 1];
			case "DeviceRGB" | "Lab": [0, 0, 0];
			case "Separation" | "DeviceN": [for (_ in 0...components) 1];
			case _: [0];
		}

	// 0xFF000000 | RGB of the components
	public function rgb(c:Array<Float>):Int {
		inline function at(i:Int):Float
			return i < c.length ? c[i] : 0;
		inline function pack(r:Float, g:Float, b:Float):Int
			return 0xFF000000 | (byte(r) << 16) | (byte(g) << 8) | byte(b);
		return switch kind {
			case "DeviceGray": pack(at(0), at(0), at(0));
			case "DeviceRGB": pack(at(0), at(1), at(2));
			case "DeviceCMYK":
				var k = at(3);
				pack((1 - at(0)) * (1 - k), (1 - at(1)) * (1 - k), (1 - at(2)) * (1 - k));
			case "Lab": lab(at(0), at(1), at(2));
			case "Indexed":
				var i = Std.int(Math.max(0, Math.min(hival, Math.round(at(0))))), n = base.components;
				base.rgb([for (k in 0...n) (i * n + k < lookup.length ? lookup.get(i * n + k) : 0) / 255]);
			case "Separation" | "DeviceN":
				if (tint == null) pack(1 - at(0), 1 - at(0), 1 - at(0)) else base.rgb(tint.eval(c));
			case _: 0xFF000000;
		}
	}

	static inline function byte(v:Float):Int
		return v <= 0 ? 0 : v >= 1 ? 255 : Std.int(v * 255 + 0.5);

	function lab(l:Float, a:Float, b:Float):Int {
		var fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - b / 200;
		inline function g(t:Float):Float
			return t > 6 / 29 ? t * t * t : 3 * (6 / 29) * (6 / 29) * (t - 4 / 29);
		var x = white[0] * g(fx), y = white[1] * g(fy), z = white[2] * g(fz);
		var r = 3.2406 * x - 1.5372 * y - 0.4986 * z, gg = -0.9689 * x + 1.8758 * y + 0.0415 * z, bb = 0.0557 * x - 0.2040 * y + 1.0570 * z;
		inline function enc(c:Float):Float
			return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
		return 0xFF000000 | (byte(enc(r)) << 16) | (byte(enc(gg)) << 8) | byte(enc(bb));
	}

	// an image's default Decode for the components (bits per component bpc)
	public function defaultDecode(bpc:Int):Array<Float> {
		if (kind == "Indexed") return [0, Math.pow(2, bpc) - 1];
		if (kind == "Lab") return [0, 100, labRange[0], labRange[1], labRange[2], labRange[3]];
		return [for (_ in 0...components) for (k in [0.0, 1]) k];
	}
}
