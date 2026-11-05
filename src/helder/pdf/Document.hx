package helder.pdf;

import haxe.io.Bytes;
import helder.pdf.PdfValue;

// A PDF file read (after leanpdf's core: its xref, reader and recovery):
// the cross-reference table or stream at startxref and those it chains to
// (/Prev, a hybrid file's /XRefStm; each offset once: no loops), objects
// read where it says, those in object streams through their stream; a
// file whose xref is missing or wrong rebuilt from its "n g obj" headers.
// Encrypted files open with the standard handler (Crypto: the empty user
// password unless another is given) and their strings and streams are
// decrypted as objects are read. The page tree is walked once, each page
// with what it inherits; every bound is PdfLimits'.
class Document {
	public final data:Bytes;
	public final limits:PdfLimits;
	public var trailer(default, null):PdfDict;
	public var pages(default, null):Array<Page> = [];
	public var repaired(default, null) = false;
	// (why the xref was not taken: a repaired file's)
	public var repairReason(default, null) = "";

	// object number: its offset (type 1) or its object stream's number and index (type 2: -(stream+1), index)
	final offsets = new Map<Int, Int>();
	final inStream = new Map<Int, Int>();
	final cache = new Map<Int, PdfValue>();
	final loading = new Map<Int, Bool>();
	var cached = 0;
	var crypto:Null<Crypto> = null;
	var encryptRef = -1;
	// (what the document's streams have decoded so far: maxDecoded's budget)
	public var decoded = 0;

	public function new(data:Bytes, password = "", ?limits:PdfLimits) {
		this.data = data;
		this.limits = limits ?? PdfLimits.DEFAULT;
		if (data.length < 8) throw PdfError.corrupt("not a PDF: too short");
		try {
			readXref();
		} catch (e:PdfError) {
			if (e.kind == TooLarge) throw e;
			repairReason = e.message;
			recover();
		}
		if (trailer == null || !trailer.has("Root")) recover();
		var enc = trailer.get("Encrypt");
		if (enc != PNull) {
			switch enc {
				case PRef(n, _): encryptRef = n;
				case _:
			}
			var d = Values.dict(resolve(enc));
			if (d != null) {
				var ids = Values.arr(resolve(trailer.get("ID")));
				var id = ids != null && ids.length > 0 ? Values.str(resolve(ids[0])) : null;
				crypto = Crypto.open(d, id ?? Bytes.alloc(0), password);
				if (crypto == null) throw new PdfError(Encrypted, "the password does not open it");
				// (what was read before the key was known: read again)
				for (k in cache.keys())
					if (k != encryptRef) cache.remove(k);
			}
		}
		readPages();
	}

	// ---- the cross-reference

	function readXref() {
		// (the last startxref, by its bytes: the tail is binary)
		var at = -1, key = Bytes.ofString("startxref"), i = data.length - key.length;
		var stop = Std.int(Math.max(0, data.length - 4096));
		while (i >= stop && at < 0) {
			var ok = true;
			for (k in 0...key.length)
				if (data.get(i + k) != key.get(k)) {
					ok = false;
					break;
				}
			if (ok) at = i;
			i--;
		}
		if (at < 0) throw PdfError.corrupt("no startxref");
		var p = new Parser(data, at + 9);
		p.skip();
		var off = Std.int(p.number());
		var seen = new Map<Int, Bool>();
		var first = true;
		var queue = [off];
		while (queue.length > 0) {
			var o = queue.shift();
			if (seen.exists(o) || o < 0 || o >= data.length) {
				if (first) throw PdfError.corrupt("startxref past the file");
				continue;
			}
			seen.set(o, true);
			var t = xrefAt(o);
			if (first) trailer = t;
			first = false;
			var stm = Values.int(t.get("XRefStm"), -1);
			if (stm >= 0) queue.unshift(stm);
			var prev = Values.int(t.get("Prev"), -1);
			if (prev >= 0) queue.push(prev);
		}
	}

	// a table or an xref stream at o: its trailer; its entries added where none is yet (the newest first)
	function xrefAt(o:Int):PdfDict {
		var p = new Parser(data, o, null, limits.maxNesting);
		p.skip();
		if (data.getString(p.pos, 4) == "xref") {
			p.pos += 4;
			while (true) {
				p.skip();
				if (p.pos + 7 <= data.length && data.getString(p.pos, 7) == "trailer") {
					p.pos += 7;
					var t = Values.dict(p.next());
					if (t == null) throw PdfError.corrupt("a trailer that is no dictionary");
					return t;
				}
				var before = p.pos;
				var start = Std.int(p.number());
				p.skip();
				var count = Std.int(p.number());
				if (p.pos == before) throw PdfError.corrupt("an xref table that does not parse");
				if (count < 0 || count > limits.maxObjects) throw PdfError.tooLarge("an xref section of " + count + " entries");
				for (i in 0...count) {
					p.skip();
					if (p.pos >= data.length) break;
					var off = Std.int(p.number());
					p.skip();
					p.number();
					p.skip();
					var kind = p.at(p.pos);
					p.pos++;
					var n = start + i;
					if (kind == "n".code && !offsets.exists(n) && !inStream.exists(n)) offsets.set(n, off);
					if (kind == "f".code && !offsets.exists(n) && !inStream.exists(n)) offsets.set(n, -1);
				}
				if (p.pos >= data.length) throw PdfError.corrupt("an xref table without a trailer");
			}
		}
		// an xref stream
		var v = objectAt(o, -1);
		var d:PdfDict, raw:Bytes;
		switch v {
			case PStream(dd, r):
				d = dd;
				raw = r;
			case _:
				throw PdfError.corrupt("startxref at no xref");
		}
		if (Values.name(d.get("Type")) != "XRef") throw PdfError.corrupt("startxref at no xref");
		var bytes = Filters.decode(raw, d, limits.maxStream, null).data;
		var w = Values.nums(d.get("W"));
		if (w == null || w.length < 3) throw PdfError.corrupt("an xref stream without /W");
		var w0 = Std.int(w[0]), w1 = Std.int(w[1]), w2 = Std.int(w[2]), row = w0 + w1 + w2;
		if (w0 < 0 || w1 < 0 || w2 < 0 || row <= 0 || row > 32) throw PdfError.corrupt("an xref stream's /W");
		var size = Values.int(d.get("Size"));
		var index = Values.nums(d.get("Index")) ?? [0, size];
		var at = 0;
		inline function field(width:Int, def:Int):Int {
			if (width == 0) return def;
			var v = 0;
			for (k in 0...width)
				v = v * 256 + (at + k < bytes.length ? bytes.get(at + k) : 0);
			at += width;
			return v;
		}
		var k = 0;
		while (k + 1 < index.length) {
			var start = Std.int(index[k]), count = Std.int(index[k + 1]);
			if (count < 0 || count > limits.maxObjects) throw PdfError.tooLarge("an xref stream of " + count + " entries");
			for (i in 0...count) {
				if (at + row > bytes.length) break;
				var t = field(w0, 1), a = field(w1, 0), b = field(w2, 0), n = start + i;
				if (offsets.exists(n) || inStream.exists(n)) continue;
				if (t == 1) offsets.set(n, a) else if (t == 2) inStream.set(n, a * 65536 + b) else if (t == 0) offsets.set(n, -1);
			}
			k += 2;
		}
		return d;
	}

	// every "n g obj" in the file: a damaged file's objects, the last of each number kept
	function recover() {
		repaired = true;
		offsets.clear();
		inStream.clear();
		cache.clear();
		var s = data, n = s.length, i = 0;
		trailer = null;
		var root:Null<PdfValue> = null;
		while (i < n - 4) {
			var c = s.get(i);
			if (c == "o".code && s.get(i + 1) == "b".code && s.get(i + 2) == "j".code) {
				// (back over the generation and the number)
				var j = i - 1;
				while (j > 0 && Parser.isWhite(s.get(j)))
					j--;
				var ge = j;
				while (j > 0 && s.get(j) >= "0".code && s.get(j) <= "9".code)
					j--;
				if (j < ge) {
					while (j > 0 && Parser.isWhite(s.get(j)))
						j--;
					var ne = j;
					while (j >= 0 && s.get(j) >= "0".code && s.get(j) <= "9".code)
						j--;
					if (j < ne) {
						var num = Std.parseInt(s.getString(j + 1, ne - j));
						if (num != null && num > 0 && num <= limits.maxObjects) offsets.set(num, j + 1);
					}
				}
			} else if (c == "t".code && i + 7 < n && s.getString(i, 7) == "trailer") {
				var p = new Parser(s, i + 7, null, limits.maxNesting);
				try {
					var t = Values.dict(p.next());
					if (t != null && t.has("Root")) trailer = t;
				} catch (_:PdfError) {}
			}
			i++;
		}
		if (trailer == null) {
			// (no trailer: an xref stream's dictionary, or the catalog itself)
			for (num => off in offsets) {
				var v = try objectAt(off, num) catch (_:PdfError) PNull;
				var d = Values.dict(v);
				if (d == null) continue;
				if (d.has("Root")) {
					trailer = d;
					break;
				}
				if (Values.name(d.get("Type")) == "Catalog") root = PRef(num, 0);
			}
			if (trailer == null && root != null) {
				trailer = new PdfDict();
				trailer.set("Root", root);
			}
		}
		if (trailer == null) throw PdfError.corrupt("no trailer and no catalog");
	}

	// ---- objects

	// v itself, or the object it refers to
	public function resolve(v:PdfValue):PdfValue {
		if (v == null) return PNull;
		var depth = 0;
		while (true)
			switch v {
				case PRef(n, _):
					if (++depth > 32) return PNull;
					v = object(n);
				case _:
					return v;
			}
	}

	public function object(n:Int):PdfValue {
		var c = cache.get(n);
		if (c != null) return c;
		if (loading.exists(n)) return PNull;
		loading.set(n, true);
		var v = PNull;
		try {
			if (inStream.exists(n)) {
				var e = inStream.get(n);
				v = fromObjectStream(Std.int(e / 65536), e % 65536, n);
			} else if (offsets.exists(n) && offsets.get(n) >= 0) {
				v = objectAt(offsets.get(n), n);
				if (crypto != null && n != encryptRef) v = decryptAll(v, n, 0);
			}
		} catch (e:PdfError) {
			loading.remove(n);
			if (e.kind == TooLarge) throw e;
			v = PNull;
		}
		loading.remove(n);
		if (++cached > limits.maxObjects) throw PdfError.tooLarge("past " + limits.maxObjects + " objects");
		cache.set(n, v);
		return v;
	}

	// "n g obj value [stream ... endstream]" at o (want: the number it must be, -1 any)
	function objectAt(o:Int, want:Int):PdfValue {
		var p = new Parser(data, o, null, limits.maxNesting);
		var num = p.next();
		p.next();
		p.next();
		if (p.keyword != "obj") throw PdfError.corrupt("no object at " + o);
		var v = p.next();
		if (v == null) return PNull;
		switch v {
			case PDict(d):
				p.skip();
				if (p.pos + 6 <= data.length && data.getString(p.pos, 6) == "stream") {
					var s = p.pos + 6;
					if (s < data.length && data.get(s) == 13) s++;
					if (s < data.length && data.get(s) == 10) s++;
					var len = -1;
					switch d.get("Length") {
						case PNum(x): len = Std.int(x);
						case PRef(rn, _): if (rn != want) len = Values.int(object(rn), -1);
						case _:
					}
					// (a length that does not end at endstream: the stream to its endstream)
					if (len < 0 || s + len > data.length || !endsAt(s + len)) {
						var e = find("endstream", s);
						if (e < 0) e = data.length;
						len = e - s;
						while (len > 0 && Parser.isWhite(data.get(s + len - 1)))
							len--;
					}
					if (len > limits.maxStream) throw PdfError.tooLarge("a stream of " + len + " bytes");
					return PStream(d, data.sub(s, len));
				}
			case _:
		}
		return v;
	}

	function endsAt(p:Int):Bool {
		var q = p;
		while (q < data.length && Parser.isWhite(data.get(q)))
			q++;
		return q + 9 <= data.length && data.getString(q, 9) == "endstream";
	}

	function find(what:String, from:Int):Int {
		var w = Bytes.ofString(what), n = w.length;
		var i = from;
		while (i + n <= data.length) {
			if (data.get(i) == w.get(0)) {
				var ok = true;
				for (k in 1...n)
					if (data.get(i + k) != w.get(k)) {
						ok = false;
						break;
					}
				if (ok) return i;
			}
			i++;
		}
		return -1;
	}

	final objectStreams = new Map<Int, {data:Bytes, first:Int, offsets:Map<Int, Int>}>();

	function fromObjectStream(stream:Int, index:Int, n:Int):PdfValue {
		var os = objectStreams.get(stream);
		if (os == null) {
			var v = object(stream);
			switch v {
				case PStream(d, _):
					var bytes = this.stream(v);
					var count = Values.int(d.get("N")), first = Values.int(d.get("First"));
					if (count < 0 || count > limits.maxObjects || first < 0) throw PdfError.corrupt("an object stream's /N or /First");
					var p = new Parser(bytes, 0, Std.int(Math.min(first, bytes.length)));
					var map = new Map<Int, Int>();
					for (_ in 0...count) {
						var on = Values.int(p.next() ?? PNull, -1), off = Values.int(p.next() ?? PNull, -1);
						if (on < 0) break;
						if (!map.exists(on)) map.set(on, off);
					}
					os = {data: bytes, first: first, offsets: map};
					objectStreams.set(stream, os);
				case _:
					return PNull;
			}
		}
		var off = os.offsets.get(n);
		if (off == null) return PNull;
		var p = new Parser(os.data, os.first + off, null, limits.maxNesting);
		return p.next() ?? PNull;
	}

	function decryptAll(v:PdfValue, n:Int, depth:Int):PdfValue {
		if (depth > limits.maxNesting) return v;
		return switch v {
			case PStr(b): PStr(crypto.decrypt(b, n, 0, false));
			case PArray(a): PArray([for (x in a) decryptAll(x, n, depth + 1)]);
			case PDict(d):
				for (k => x in d.map)
					d.map.set(k, decryptAll(x, n, depth + 1));
				PDict(d);
			case PStream(d, data):
				for (k => x in d.map)
					d.map.set(k, decryptAll(x, n, depth + 1));
				var t = Values.name(d.get("Type"));
				PStream(d, t == "XRef" ? data : crypto.decrypt(data, n, 0, true));
			case _: v;
		}
	}

	// a stream's bytes decoded by its filters (stopAt: one left for the caller); within the budgets
	public function stream(v:PdfValue, ?stopAt:Array<String>):Bytes
		return streamWith(v, stopAt).data;

	public function streamWith(v:PdfValue, ?stopAt:Array<String>):{data:Bytes, rest:Null<String>, parms:Null<PdfDict>} {
		v = resolve(v);
		switch v {
			case PStream(d, raw):
				var left = limits.maxDecoded - decoded;
				if (left <= 0) throw PdfError.tooLarge("the document's streams past " + limits.maxDecoded + " bytes decoded");
				var r = Filters.decode(raw, d, Std.int(Math.min(limits.maxStream, left)), this, stopAt);
				decoded += r.data.length;
				return r;
			case _:
				return {data: Bytes.alloc(0), rest: null, parms: null};
		}
	}

	// ---- pages

	function readPages() {
		var root = Values.dict(resolve(trailer.get("Root")));
		if (root == null) throw PdfError.corrupt("no catalog");
		var seen = new Map<Int, Bool>();
		function walk(v:PdfValue, inherited:{resources:PdfValue, media:PdfValue, crop:PdfValue, rotate:PdfValue}, depth:Int) {
			if (depth > 64) throw PdfError.corrupt("a page tree past 64 levels");
			switch v {
				case PRef(n, _):
					if (seen.exists(n)) return;
					seen.set(n, true);
				case _:
			}
			var d = Values.dict(resolve(v));
			if (d == null) return;
			var inh = {
				resources: d.has("Resources") ? d.get("Resources") : inherited.resources,
				media: d.has("MediaBox") ? d.get("MediaBox") : inherited.media,
				crop: d.has("CropBox") ? d.get("CropBox") : inherited.crop,
				rotate: d.has("Rotate") ? d.get("Rotate") : inherited.rotate
			};
			var kids = Values.arr(resolve(d.get("Kids")));
			var type = Values.name(d.get("Type"));
			if (kids != null && type != "Page") {
				for (k in kids)
					walk(k, inh, depth + 1);
			} else {
				if (pages.length >= limits.maxPages) throw PdfError.tooLarge("past " + limits.maxPages + " pages");
				pages.push(new Page(this, d, inh.resources, inh.media, inh.crop, Values.int(resolve(inh.rotate))));
			}
		}
		walk(root.get("Pages"), {resources: PNull, media: PNull, crop: PNull, rotate: PNull}, 0);
	}
}

// A page: its dictionary and what it inherits; its box in points
class Page {
	public final doc:Document;
	public final dict:PdfDict;
	public final resources:Null<PdfDict>;
	public final box:Array<Float>;
	public final rotate:Int;

	public function new(doc:Document, dict:PdfDict, resources:PdfValue, media:PdfValue, crop:PdfValue, rotate:Int) {
		this.doc = doc;
		this.dict = dict;
		this.resources = Values.dict(doc.resolve(resources));
		var m = Values.nums(doc.resolve(media)), c = Values.nums(doc.resolve(crop));
		var b = c != null && c.length == 4 ? c : m != null && m.length == 4 ? m : [0.0, 0, 612, 792];
		box = [Math.min(b[0], b[2]), Math.min(b[1], b[3]), Math.max(b[0], b[2]), Math.max(b[1], b[3])];
		var r = rotate % 360;
		if (r < 0) r += 360;
		this.rotate = Std.int(r / 90) * 90;
	}

	// its size in points, rotated as shown
	public var width(get, never):Float;
	public var height(get, never):Float;

	function get_width()
		return rotate % 180 == 0 ? box[2] - box[0] : box[3] - box[1];

	function get_height()
		return rotate % 180 == 0 ? box[3] - box[1] : box[2] - box[0];

	// the page's content streams, one after another
	public function contents():Bytes {
		var v = doc.resolve(dict.get("Contents"));
		var parts = switch v {
			case PArray(a): a;
			case PNull: [];
			case _: [v];
		}
		var b = new haxe.io.BytesBuffer();
		for (part in parts) {
			b.add(doc.stream(part));
			b.addByte(10);
		}
		return b.getBytes();
	}
}
