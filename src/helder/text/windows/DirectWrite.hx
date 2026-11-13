package helder.text.windows;

import hxmc.unsafe.*;
import helder.text.Shaping;
import helder.os.win32.Com;

// Windows' text stack behind helder.text, DirectWrite through COM: the
// shared IDWriteFactory; the system font collection for a family's face
// (FindFamilyName, GetFirstMatchingFont); IDWriteFontFallback for a
// character the app's fonts lack (MapCharacters over a text analysis
// source of ours); IDWriteTextAnalyzer's AnalyzeScript, GetGlyphs and
// GetGlyphPlacements for shaping (at the face's units per em: advances and
// offsets in font units); IDWriteGlyphRunAnalysis for a glyph's grayscale
// coverage (DWRITE_TEXTURE_ALIASED_1x1 under grayscale anti-aliasing,
// natural symmetric, fitted to the grid vertically), blended as Direct2D
// blends it (blend: the user's gamma and grayscale enhanced contrast).
// Each face opened once from its file (FontFile.path) or its bytes (an
// app's embedded fonts: Windows 10 1703's in-memory loader, the bytes
// copied; before it, helder's own). A file is named by its local loader's
// path (IDWriteLocalFontFileLoader).
@:hxmc.unsafe(gc)
class DirectWrite implements TextBackend {
	public static function create():Null<TextBackend> {
		var out:Ptr<Ptr> = LibC.malloc(8);
		out.value = Ptr.nil();
		DWrite.DWriteCreateFactory(0, IID_IDWriteFactory2, out); // (DWRITE_FACTORY_TYPE_SHARED)
		var f = out.value;
		LibC.free(cast out);
		return f.isNull() ? null : new DirectWrite(f);
	}

	static final IID_IDWriteFactory2 = Com.guid(0x0439fc60, 0xca44, 0x4994, [0x8d, 0xee, 0x3a, 0x9a, 0xf7, 0xb7, 0x32, 0xec]);
	static final IID_IDWriteLocalFontFileLoader = Com.guid(0xb2d9f3ec, 0xc9fe, 0x4a11, [0xa2, 0xec, 0xd8, 0x62, 0x08, 0xf7, 0xc0, 0xa2]);

	final factory:Ptr;
	var analyzer = Ptr.nil();
	var fallbackObj = Ptr.nil();
	var collection = Ptr.nil();
	final faces = new Map<Int, Ptr>();
	// (one text analysis source and sink of ours, kept: their state in native memory)
	final source:Ptr;
	final sink:Ptr;
	// (one word of scratch per out-parameter, a buffer for texts and results)
	final scratch:Ptr<Ptr>;
	var buf:Ptr<UInt8> = Ptr.nil();
	var bufSize = 0;
	final locale:Ptr<UInt16>;

	function new(factory:Ptr) {
		this.factory = factory;
		scratch = LibC.malloc(64);
		locale = LibC.malloc(16);
		var l = "en-us";
		for (i in 0...l.length)
			locale[i] = StringTools.fastCodeAt(l, i);
		locale[l.length] = 0;
		source = Analysis.source(locale);
		sink = Analysis.sink();
	}

	public function name():String
		return "DirectWrite";

	static final IID_IDWriteRenderingParams1 = Com.guid(0x94413cf4, 0xa6fc, 0x4248, [0x8b, 0x50, 0x66, 0x74, 0x34, 0x8f, 0xca, 0xd3]);
	var blended:Null<GlyphBlend> = null;

	// the user's text rendering (their ClearType tuning): the default
	// rendering params' gamma and grayscale enhanced contrast (Windows'
	// defaults, 1.8 and 1, without them)
	public function blend():Null<GlyphBlend> {
		if (blended != null) return blended;
		var gamma = 1.8, contrast = 1.0;
		var o = out(0);
		if (IDWriteFactory.CreateRenderingParams(factory, o) >= 0 && !o.value.isNull()) {
			var params = o.value;
			var g:Float = IDWriteRenderingParams.GetGamma(params);
			if (g > 0) gamma = g;
			var o1 = out(1);
			if (IUnknown.QueryInterface(params, IID_IDWriteRenderingParams1, o1) >= 0 && !o1.value.isNull()) {
				var c:Float = IDWriteRenderingParams.GetGrayscaleEnhancedContrast(o1.value);
				if (c >= 0) contrast = c;
				Com.release(o1.value);
			}
			Com.release(params);
		}
		return blended = new GlyphBlend(gamma, contrast);
	}

	inline function out(k:Int):Ptr<Ptr> {
		var p:Ptr<Ptr> = cast scratch.add(8 * k);
		p.value = Ptr.nil();
		return p;
	}

	function room(n:Int):Ptr<UInt8> {
		if (n > bufSize) {
			if (!buf.isNull()) LibC.free(cast buf);
			bufSize = n * 2;
			buf = LibC.malloc((bufSize : hxmc.I64));
		}
		return buf;
	}

	static final IID_IDWriteFactory5 = Com.guid(0x958db99a, 0xbe2a, 0x4f09, [0xaf, 0x7d, 0x65, 0x18, 0x98, 0x03, 0xd1, 0xd3]);
	// (the in-memory font file loader, registered once; nil: none, before Windows 10 1703)
	var memory = Ptr.nil();
	var memoryTried = false;

	function memoryLoader():Ptr {
		if (memoryTried) return memory;
		memoryTried = true;
		var f5 = out(6);
		if (IUnknown.QueryInterface(factory, IID_IDWriteFactory5, f5) < 0 || f5.value.isNull()) return memory;
		var factory5 = f5.value, l = out(7);
		if (IDWriteFactory.CreateInMemoryFontFileLoader(factory5, l) >= 0 && !l.value.isNull()) {
			var loader = l.value;
			if (IDWriteFactory.RegisterFontFileLoader(factory, loader) >= 0) memory = loader else Com.release(loader);
		}
		Com.release(factory5);
		return memory;
	}

	// (a font file of bytes: copied into native memory, then DirectWrite's own copy of them, no owner)
	static function fromMemory(loader:Ptr, factory:Ptr, data:haxe.io.Bytes, file:Ptr<Ptr>) {
		var n = data.length, p:Ptr<UInt8> = LibC.malloc((n : hxmc.I64));
		copyOut(data, cast p, n);
		IDWriteInMemoryFontFileLoader.CreateInMemoryFontFileReference(loader, factory, cast p, n, Ptr.nil(), file);
		LibC.free(cast p);
	}

	@:hxmc.unsafe static inline function copyOut(b:haxe.io.Bytes, p:Ptr, n:Int)
		LibC.memcpy(p, Mem.addr(b.getData()), (n : hxmc.I64));

	// (the face of a font's file or bytes, opened once; nil: none)
	function faceOf(f:FontFile):Ptr {
		var h = faces.get(f.id);
		if (h != null) return h;
		var face = Ptr.nil();
		var bytes = f.path == null && f.data != null && f.data.length > 0 && !memoryLoader().isNull();
		var file = out(0);
		if (f.path != null) Arena.scoped(a -> IDWriteFactory.CreateFontFileReference(factory, a.wstring(f.path), Ptr.nil(), file));
		else if (bytes) fromMemory(memory, factory, f.data, file);
		if (!file.value.isNull()) {
			var ff = file.value;
			if (!ff.isNull()) {
				var info:Ptr<Int32> = cast scratch.add(16);
				// (isSupported, fileType, faceType, numberOfFaces)
				if (IDWriteFontFile.Analyze(ff, cast info, cast info.add(4), cast info.add(8), cast info.add(12)) >= 0 && info[0] != 0) {
					var arr = out(4);
					arr.value = ff;
					var fo = out(5);
					IDWriteFactory.CreateFontFace(factory, info[2], 1, cast arr, f.faceIndex, 0, fo);
					face = fo.value;
				}
				Com.release(ff);
			}
		}
		faces.set(f.id, face);
		return face;
	}

	public function shape(font:FontFile, text:String, start:Int, end:Int, rtl:Bool, res:ShapedGlyphs):Bool {
		var face = faceOf(font);
		if (face.isNull()) return false;
		if (analyzer.isNull()) {
			var a = out(0);
			IDWriteFactory.CreateTextAnalyzer(factory, a);
			analyzer = a.value;
			if (analyzer.isNull()) return false;
		}
		var n = end - start, max = 3 * n + 16;
		// (the text, its cluster map and properties, the glyphs and theirs, advances, offsets: each 8-aligned)
		inline function up(x:Int):Int
			return (x + 7) & ~7;
		var oMap = up(2 * n + 2), oTprops = oMap + up(2 * n), oIds = oTprops + up(2 * n), oGprops = oIds + up(2 * max), oAdv = oGprops + up(2 * max),
			oOffs = oAdv + up(4 * max);
		var p = room(oOffs + 8 * max);
		var units:Ptr<UInt16> = cast p, cmap:Ptr<UInt16> = cast p.add(oMap), tprops:Ptr<UInt16> = cast p.add(oTprops);
		var ids:Ptr<UInt16> = cast p.add(oIds), gprops:Ptr<UInt16> = cast p.add(oGprops);
		var adv:Ptr<Float32> = cast p.add(oAdv), offs:Ptr<Float32> = cast p.add(oOffs);
		for (i in 0...n)
			units[i] = StringTools.fastCodeAt(text, start + i);
		units[n] = 0;
		Analysis.reset(source, cast units, n, rtl);
		Analysis.resetSink(sink);
		if (IDWriteTextAnalyzer.AnalyzeScript(analyzer, source, 0, n, sink) < 0) return false;
		var script = Analysis.script(sink), count:Ptr<Int32> = cast scratch.add(48);
		var hr = IDWriteTextAnalyzer.GetGlyphs(analyzer, cast units, n, face, 0, rtl ? 1 : 0, script, cast locale, Ptr.nil(), Ptr.nil(), Ptr.nil(), 0, max, cast cmap,
			cast tprops, cast ids, cast gprops, cast count);
		if (hr < 0) return false;
		var g = count[0];
		hr = IDWriteTextAnalyzer.GetGlyphPlacements(analyzer, cast units, cast cmap, cast tprops, n, cast ids, cast gprops, g, face, (font.unitsPerEm : Float), 0, rtl ? 1 : 0,
			script, cast locale, Ptr.nil(), Ptr.nil(), 0, cast adv, cast offs);
		if (hr < 0) return false;
		// (each glyph's cluster: the first unit whose cluster map names its first glyph)
		res.reset(g);
		var clusterOf = new haxe.ds.Vector<Int>(g);
		var i = 0;
		while (i < n) {
			var j = i + 1;
			while (j < n && cmap[j] == cmap[i])
				j++;
			var g0:Int = cmap[i], g1:Int = j < n ? cmap[j] : g;
			for (k in g0...g1)
				if (k >= 0 && k < g) clusterOf[k] = start + i;
			i = j;
		}
		// (logical order from DirectWrite: visual order for a right-to-left run reversed)
		for (q in 0...g) {
			var k = rtl ? g - 1 - q : q;
			res.push(ids[k], clusterOf[k], (adv[k] : Float), (offs[2 * k] : Float), (offs[2 * k + 1] : Float));
		}
		return true;
	}

	public function rasterize(font:FontFile, glyph:Int, size:Float, dx:Float, res:GlyphBitmap):Bool {
		var face = faceOf(font);
		if (face.isNull()) return false;
		// (DWRITE_GLYPH_RUN: fontFace, fontEmSize, glyphCount, glyphIndices, glyphAdvances, glyphOffsets, isSideways, bidiLevel)
		var run:Ptr<UInt8> = cast scratch;
		var id:Ptr<UInt16> = cast scratch.add(56), advance:Ptr<Float32> = cast scratch.add(60);
		id[0] = glyph;
		advance[0] = 0;
		(cast run : Ptr<Ptr>).value = face;
		(cast run.add(8) : Ptr<Float32>).value = size;
		(cast run.add(12) : Ptr<Int32>).value = 1;
		(cast run.add(16) : Ptr<Ptr>).value = cast id;
		(cast run.add(24) : Ptr<Ptr>).value = cast advance;
		(cast run.add(32) : Ptr<Ptr>).value = Ptr.nil();
		(cast run.add(40) : Ptr<Int32>).value = 0;
		(cast run.add(44) : Ptr<Int32>).value = 0;
		var analysis:Ptr<Ptr> = LibC.malloc(8);
		analysis.value = Ptr.nil();
		// (DWRITE_RENDERING_MODE_NATURAL_SYMMETRIC, DWRITE_MEASURING_MODE_NATURAL, DWRITE_GRID_FIT_MODE_ENABLED: the outline
		// fitted to the pixels vertically, as Windows draws its text, DWRITE_TEXT_ANTIALIAS_MODE_GRAYSCALE)
		var hr = IDWriteFactory.CreateGlyphRunAnalysis2(factory, cast run, Ptr.nil(), 5, 0, 2, 1, dx, 0, analysis);
		var an = analysis.value;
		LibC.free(cast analysis);
		if (hr < 0 || an.isNull()) return false;
		// (DWRITE_TEXTURE_ALIASED_1x1, grayscale coverage; where the analysis gives it as DWRITE_TEXTURE_CLEARTYPE_3x1
		// instead, as Wine's does for any but the aliased mode, its three equal samples a pixel's one)
		var rect:Ptr<Int32> = LibC.malloc(16), type = 0;
		var ok = IDWriteGlyphRunAnalysis.GetAlphaTextureBounds(an, 0, cast rect) >= 0;
		if (ok && (rect[2] <= rect[0] || rect[3] <= rect[1])) {
			type = 1;
			ok = IDWriteGlyphRunAnalysis.GetAlphaTextureBounds(an, 1, cast rect) >= 0;
		}
		var l = rect[0], t = rect[1], w = rect[2] - rect[0], h = rect[3] - rect[1];
		if (ok && (w <= 0 || h <= 0)) {
			LibC.free(cast rect);
			res.size(0, 0);
			res.left = res.top = 0;
			Com.release(an);
			return true;
		}
		if (ok) {
			res.size(w, h);
			res.left = l;
			res.top = t;
			var bpp = type == 0 ? 1 : 3, px = room(w * h * bpp);
			ok = IDWriteGlyphRunAnalysis.CreateAlphaTexture(an, type, cast rect, cast px, w * h * bpp) >= 0;
			if (ok && bpp == 1) BytesPtr.copyIn(res.pixels, 0, cast px, w * h) else if (ok) for (i in 0...w * h)
				res.pixels.set(i, Std.int((px[3 * i] + px[3 * i + 1] + px[3 * i + 2]) / 3));
		}
		LibC.free(cast rect);
		Com.release(an);
		return ok;
	}

	// (a font's file and face index: its face's first file through the local loader)
	function fileOf(font:Ptr):Null<{path:String, index:Int}> {
		var fo = out(0);
		if (IDWriteFont.CreateFontFace(font, fo) < 0 || fo.value.isNull()) return null;
		var face = fo.value;
		var n:Ptr<Int32> = cast scratch.add(8);
		n[0] = 1;
		var file = out(2);
		var result:Null<{path:String, index:Int}> = null;
		if (IDWriteFontFace.GetFiles(face, cast n, file) >= 0 && !file.value.isNull()) {
			var ff = file.value, key = out(3), size:Ptr<Int32> = cast scratch.add(32), loader = out(5);
			if (IDWriteFontFile.GetReferenceKey(ff, key, cast size) >= 0 && IDWriteFontFile.GetLoader(ff, loader) >= 0 && !loader.value.isNull()) {
				var ld = loader.value, local = out(6);
				if (IUnknown.QueryInterface(ld, IID_IDWriteLocalFontFileLoader, local) >= 0 && !local.value.isNull()) {
					var lo = local.value, len:Ptr<Int32> = cast scratch.add(56);
					var k = key.value, ks = size[0];
					if (IDWriteLocalFontFileLoader.GetFilePathLengthFromKey(lo, k, ks, cast len) >= 0) {
						var m = len[0] + 1, p:Ptr<UInt16> = cast room(2 * m);
						if (IDWriteLocalFontFileLoader.GetFilePathFromKey(lo, k, ks, cast p, m) >= 0) {
							var sb = new StringBuf();
							for (i in 0...m - 1)
								sb.addChar(p[i]);
							result = {path: sb.toString(), index: IDWriteFontFace.GetIndex(face)};
						}
					}
					Com.release(lo);
				}
				Com.release(ld);
			}
			Com.release(ff);
		}
		Com.release(face);
		return result;
	}

	public function fallback(cp:Int, ?lang:String):Null<{path:String, index:Int}> {
		if (fallbackObj.isNull()) {
			var o = out(0);
			IDWriteFactory.GetSystemFontFallback(factory, o);
			fallbackObj = o.value;
			if (fallbackObj.isNull()) return null;
		}
		var units:Ptr<UInt16> = cast room(8), n = 1;
		if (cp >= 0x10000) {
			units[0] = 0xD800 + ((cp - 0x10000) >> 10);
			units[1] = 0xDC00 + ((cp - 0x10000) & 0x3FF);
			n = 2;
		} else units[0] = cp;
		units[n] = 0;
		Analysis.reset(source, cast units, n, false);
		var mapped:Ptr<Int32> = cast scratch.add(8), font = out(2), scale:Ptr<Float32> = cast scratch.add(24);
		// (no base collection: the system's; DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL)
		var hr = IDWriteFontFallback.MapCharacters(fallbackObj, source, 0, n, Ptr.nil(), Ptr.nil(), 400, 0, 5, cast mapped, font, cast scale);
		if (hr < 0 || font.value.isNull()) return null;
		var f = font.value;
		var r = fileOf(f);
		Com.release(f);
		return r;
	}

	public function find(family:String, weight:Int, italic:Bool):Null<{path:String, index:Int}> {
		if (collection.isNull()) {
			var c = out(0);
			IDWriteFactory.GetSystemFontCollection(factory, c, 0);
			collection = c.value;
			if (collection.isNull()) return null;
		}
		var index:Ptr<Int32> = cast scratch.add(8), exists:Ptr<Int32> = cast scratch.add(12);
		exists[0] = 0;
		Arena.scoped(a -> IDWriteFontCollection.FindFamilyName(collection, a.wstring(family), cast index, cast exists));
		if (exists[0] == 0) return null;
		var fam = out(2);
		if (IDWriteFontCollection.GetFontFamily(collection, index[0], fam) < 0 || fam.value.isNull()) return null;
		var fm = fam.value, font = out(3);
		// (DWRITE_FONT_STRETCH_NORMAL; DWRITE_FONT_STYLE_ITALIC 2, NORMAL 0)
		var ok = IDWriteFontFamily.GetFirstMatchingFont(fm, weight, 5, italic ? 2 : 0, font) >= 0;
		// (taken before fileOf, whose out-parameters reuse the scratch)
		var fo = font.value;
		var r = ok && !fo.isNull() ? fileOf(fo) : null;
		Com.release(fo);
		Com.release(fm);
		return r;
	}
}

// IDWriteTextAnalysisSource and IDWriteTextAnalysisSink, of ours: an
// object of native memory each, its vtable built here (source: vtable,
// text, length, locale, direction; sink: vtable, the first script
// analysis, whether there was one).
class Analysis {
	@:hxmc.unsafe static var sourceTable = Ptr.nil();
	@:hxmc.unsafe static var sinkTable = Ptr.nil();

	@:hxmc.unsafe(gc) public static function source(locale:Ptr):Ptr {
		if (sourceTable.isNull()) {
			var t:Ptr<Ptr> = LibC.malloc(8 * 8);
			t[0] = Callback.addr(Analysis.qi);
			t[1] = Callback.addr(Analysis.addRef);
			t[2] = Callback.addr(Analysis.addRef);
			t[3] = Callback.addr(Analysis.textAt);
			t[4] = Callback.addr(Analysis.textBefore);
			t[5] = Callback.addr(Analysis.direction);
			t[6] = Callback.addr(Analysis.localeName);
			t[7] = Callback.addr(Analysis.numberSubstitution);
			sourceTable = cast t;
		}
		var o:Ptr<Ptr> = LibC.malloc(48);
		o[0] = sourceTable;
		o[1] = Ptr.nil();
		(cast o.add(16) : Ptr<Int32>).value = 0;
		o[3] = locale;
		(cast o.add(32) : Ptr<Int32>).value = 0;
		return cast o;
	}

	@:hxmc.unsafe(gc) public static function reset(source:Ptr, text:Ptr, n:Int, rtl:Bool) {
		var o:Ptr<Ptr> = cast source;
		o[1] = text;
		(cast source.add(16) : Ptr<Int32>).value = n;
		(cast source.add(32) : Ptr<Int32>).value = rtl ? 1 : 0;
	}

	@:hxmc.unsafe(gc) public static function sink():Ptr {
		if (sinkTable.isNull()) {
			var t:Ptr<Ptr> = LibC.malloc(8 * 7);
			t[0] = Callback.addr(Analysis.qi);
			t[1] = Callback.addr(Analysis.addRef);
			t[2] = Callback.addr(Analysis.addRef);
			t[3] = Callback.addr(Analysis.setScript);
			t[4] = Callback.addr(Analysis.setOther);
			t[5] = Callback.addr(Analysis.setBidi);
			t[6] = Callback.addr(Analysis.setOther);
			sinkTable = cast t;
		}
		var o:Ptr<Ptr> = LibC.malloc(24);
		o[0] = sinkTable;
		return cast o;
	}

	@:hxmc.unsafe(gc) public static function resetSink(sink:Ptr)
		(cast sink.add(16) : Ptr<Int32>).value = 0;

	// (the DWRITE_SCRIPT_ANALYSIS the sink was given)
	@:hxmc.unsafe public static inline function script(sink:Ptr):Ptr
		return sink.add(8);

	// The methods: checked kernels over the objects' own memory, a span of
	// Ints (source: 0-1 vtable, 2-3 text, 4 length, 6-7 locale, 8 direction;
	// sink: 0-1 vtable, 2-3 the script analysis, 4 whether there was one),
	// C's out-parameters spans of one (hxmc's typed callbacks). What stays
	// the declarations': the objects' sizes, and the addresses written for
	// DirectWrite to read (the text's, the locale's).

	@:hxmc.callback @:hxmc.kernel @:hxmc.len(out, 1)
	static function qi(self:hxmc.I64, iid:hxmc.I64, out:hxmc.Span<hxmc.I64>):Int {
		out[0] = 0;
		return 0x80004002; // (E_NOINTERFACE)
	}

	@:hxmc.callback @:hxmc.kernel static function addRef(self:hxmc.I64):Int
		return 1;

	@:hxmc.callback @:hxmc.kernel @:hxmc.len(self, 12) @:hxmc.len(text, 1) @:hxmc.len(len, 1)
	static function textAt(self:hxmc.Span<Int>, pos:Int, text:hxmc.Span<hxmc.I64>, len:hxmc.Span<Int>):Int {
		var n = self[4], ok = pos >= 0 && pos < n;
		text[0] = ok ? self.getI64(2) + 2 * pos : 0;
		len[0] = ok ? n - pos : 0;
		return 0;
	}

	@:hxmc.callback @:hxmc.kernel @:hxmc.len(self, 12) @:hxmc.len(text, 1) @:hxmc.len(len, 1)
	static function textBefore(self:hxmc.Span<Int>, pos:Int, text:hxmc.Span<hxmc.I64>, len:hxmc.Span<Int>):Int {
		var n = self[4], ok = pos > 0 && pos <= n;
		text[0] = ok ? self.getI64(2) : 0;
		len[0] = ok ? pos : 0;
		return 0;
	}

	// (DWRITE_READING_DIRECTION_LEFT_TO_RIGHT 0, RIGHT_TO_LEFT 1)
	@:hxmc.callback @:hxmc.kernel @:hxmc.len(self, 12)
	static function direction(self:hxmc.Span<Int>):Int
		return self[8];

	@:hxmc.callback @:hxmc.kernel @:hxmc.len(self, 12) @:hxmc.len(len, 1) @:hxmc.len(name, 1)
	static function localeName(self:hxmc.Span<Int>, pos:Int, len:hxmc.Span<Int>, name:hxmc.Span<hxmc.I64>):Int {
		var n = self[4];
		len[0] = pos < n ? n - pos : 0;
		name[0] = self.getI64(6);
		return 0;
	}

	@:hxmc.callback @:hxmc.kernel @:hxmc.len(self, 12) @:hxmc.len(len, 1) @:hxmc.len(sub, 1)
	static function numberSubstitution(self:hxmc.Span<Int>, pos:Int, len:hxmc.Span<Int>, sub:hxmc.Span<hxmc.I64>):Int {
		var n = self[4];
		len[0] = pos < n ? n - pos : 0;
		sub[0] = 0;
		return 0;
	}

	// (the first script analysis kept: DWRITE_SCRIPT_ANALYSIS's 8 bytes)
	@:hxmc.callback @:hxmc.kernel @:hxmc.len(self, 6) @:hxmc.len(analysis, 2)
	static function setScript(self:hxmc.Span<Int>, pos:Int, len:Int, analysis:hxmc.ReadOnlySpan<Int>):Int {
		if (self[4] == 0) {
			self[2] = analysis[0];
			self[3] = analysis[1];
			self[4] = 1;
		}
		return 0;
	}

	@:hxmc.callback @:hxmc.kernel static function setOther(self:hxmc.I64, pos:Int, len:Int, x:hxmc.I64):Int
		return 0;

	@:hxmc.callback @:hxmc.kernel static function setBidi(self:hxmc.I64, pos:Int, len:Int, explicit:Int, resolved:Int):Int
		return 0;
}

@:hxmc.c @:hxmc.lib("dwrite") extern class DWrite {
	static function DWriteCreateFactory(type:Int, iid:Ptr, out:Ptr<Ptr>):Int;
}

// (the interfaces' vtables: IUnknown 0-2, then each base's methods, in the headers' order)
@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IDWriteFactory {
	@:slot(3) static function GetSystemFontCollection(self:Ptr, out:Ptr<Ptr>, check:Int):Int;
	@:slot(7) static function CreateFontFileReference(self:Ptr, path:Ptr, time:Ptr, out:Ptr<Ptr>):Int;
	@:slot(9) static function CreateFontFace(self:Ptr, type:Int, files:Int, list:Ptr, index:Int, simulations:Int, out:Ptr<Ptr>):Int;
	@:slot(10) static function CreateRenderingParams(self:Ptr, out:Ptr<Ptr>):Int;
	@:slot(13) static function RegisterFontFileLoader(self:Ptr, loader:Ptr):Int;
	@:slot(21) static function CreateTextAnalyzer(self:Ptr, out:Ptr<Ptr>):Int;
	// (IDWriteFactory2's)
	@:slot(26) static function GetSystemFontFallback(self:Ptr, out:Ptr<Ptr>):Int;
	@:slot(30) static function CreateGlyphRunAnalysis2(self:Ptr, run:Ptr, transform:Ptr, rendering:Int, measuring:Int, gridFit:Int, antialias:Int, x:Float32, y:Float32,
		out:Ptr<Ptr>):Int;
	// (IDWriteFactory5's)
	@:slot(44) static function CreateInMemoryFontFileLoader(self:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IDWriteInMemoryFontFileLoader {
	@:slot(4) static function CreateInMemoryFontFileReference(self:Ptr, factory:Ptr, data:Ptr, size:Int, owner:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IDWriteFontFile {
	@:slot(3) static function GetReferenceKey(self:Ptr, key:Ptr<Ptr>, size:Ptr):Int;
	@:slot(4) static function GetLoader(self:Ptr, out:Ptr<Ptr>):Int;
	@:slot(5) static function Analyze(self:Ptr, supported:Ptr, fileType:Ptr, faceType:Ptr, faces:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IDWriteLocalFontFileLoader {
	@:slot(4) static function GetFilePathLengthFromKey(self:Ptr, key:Ptr, size:Int, len:Ptr):Int;
	@:slot(5) static function GetFilePathFromKey(self:Ptr, key:Ptr, size:Int, path:Ptr, len:Int):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IDWriteFontFace {
	@:slot(4) static function GetFiles(self:Ptr, n:Ptr, files:Ptr<Ptr>):Int;
	@:slot(5) static function GetIndex(self:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IDWriteFont {
	@:slot(13) static function CreateFontFace(self:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IDWriteFontCollection {
	@:slot(4) static function GetFontFamily(self:Ptr, index:Int, out:Ptr<Ptr>):Int;
	@:slot(5) static function FindFamilyName(self:Ptr, name:Ptr, index:Ptr, exists:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IDWriteFontFamily {
	@:slot(7) static function GetFirstMatchingFont(self:Ptr, weight:Int, stretch:Int, style:Int, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IDWriteFontFallback {
	@:slot(3) static function MapCharacters(self:Ptr, source:Ptr, pos:Int, len:Int, collection:Ptr, family:Ptr, weight:Int, style:Int, stretch:Int, mapped:Ptr,
		font:Ptr<Ptr>, scale:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IDWriteTextAnalyzer {
	@:slot(3) static function AnalyzeScript(self:Ptr, source:Ptr, pos:Int, len:Int, sink:Ptr):Int;
	@:slot(7) static function GetGlyphs(self:Ptr, text:Ptr, len:Int, face:Ptr, sideways:Int, rtl:Int, script:Ptr, locale:Ptr, numbers:Ptr, features:Ptr,
		featureLengths:Ptr, featureRanges:Int, max:Int, clusterMap:Ptr, textProps:Ptr, glyphs:Ptr, glyphProps:Ptr, count:Ptr):Int;
	@:slot(8) static function GetGlyphPlacements(self:Ptr, text:Ptr, clusterMap:Ptr, textProps:Ptr, len:Int, glyphs:Ptr, glyphProps:Ptr, count:Int, face:Ptr,
		em:Float32, sideways:Int, rtl:Int, script:Ptr, locale:Ptr, features:Ptr, featureLengths:Ptr, featureRanges:Int, advances:Ptr, offsets:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IDWriteRenderingParams {
	@:slot(3) static function GetGamma(self:Ptr):Float32;
	// (IDWriteRenderingParams1's)
	@:slot(8) static function GetGrayscaleEnhancedContrast(self:Ptr):Float32;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IDWriteGlyphRunAnalysis {
	@:slot(3) static function GetAlphaTextureBounds(self:Ptr, type:Int, rect:Ptr):Int;
	@:slot(4) static function CreateAlphaTexture(self:Ptr, type:Int, rect:Ptr, buffer:Ptr, size:Int):Int;
}
