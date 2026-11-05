package helder.canvas.gpu;

import haxe.io.Bytes;
import helder.canvas.Blend.Blender;
import helder.canvas.Gradient;
import helder.canvas.Paint.Shader;
import helder.canvas.gpu.CanvasShaders;
import helder.gfx.*;

// helder.canvas on the GPU (helder.gfx): the same Painter as the CPU's
// Canvas, its pixels in a render target (premultiplied RGBA8). A path is
// cut into trapezoids in its own units (Trapezoids: any fill rule, a
// stroke's outline from the same Stroker), the transform applied in the
// vertex shader; their analytic coverage summed into a float target
// (CoverageShader), then the path's bounds painted by the paint times that
// coverage and the clip (CoverShader: a colour, a gradient through a table
// of its colours, a pattern, an image; BlendShader for a blend mode, over a
// copy of the pixels). Consecutive fills of colours that do not overlap
// share their passes and draws: a batch of their trapezoids, then one
// draw of their bounds. Clips are coverage textures (one a save depth),
// layers render targets composited at restore. The CPU back end is the
// reference: the canvas-gpu lane compares the reference scenes drawn by
// both. A headless device of its own size (Surface.headless) by default;
// present() draws it into a device's frame.
class GpuCanvas implements Painter {
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var matrix(get, never):Matrix;

	public final device:Device;
	public var tolerance = 0.1;

	final target:Texture;
	final dstCopy:Texture;
	final coverage:Texture;
	final white:Texture;
	final table:Texture;
	final tableBytes = Bytes.alloc(256 * 4);
	var tableRow = 0;
	static inline var TABLE_ROWS = 64;

	final coveragePipe:Pipeline;
	final coverPipe:Pipeline;
	final blendPipe:Pipeline;
	final clipPipe:Pipeline;
	final copyPipe:Pipeline;
	final presentPipe:Pipeline;
	final nearest:Sampler;
	final linear:Sampler;
	final linearRepeat:Sampler;
	final nearestRepeat:Sampler;

	var vertices:Buffer;
	var vertexCapacity = 1 << 20;
	var vertexUsed = 0;
	var indices:Buffer;
	var indexQuads = 0;
	final uniforms = Bytes.alloc(256);
	var enc:Null<Encoder> = null;

	final traps = new Trapezoids();
	final stroker = new Stroker();
	final scratch = new Path();
	final inverse = new Matrix();
	final full = new Matrix();
	var image:Null<Pattern> = null;
	final textures = new haxe.ds.ObjectMap<Bitmap, {texture:Texture, version:Int}>();

	final states:Array<GpuState> = [];
	var depth = 0;
	var state:GpuState;

	// (a batch of colour fills: its trapezoids, its bounds' quads, their union)
	var batchTraps = 0;
	final batchQuads = Bytes.alloc(4096 * 4 * 24);
	var batchCount = 0;
	final batchBoxes:Array<Float> = [];

	public function new(width:Int, height:Int, ?device:Device) {
		if (width < 1) width = 1;
		if (height < 1) height = 1;
		this.width = width;
		this.height = height;
		this.device = device ?? Device.create(helder.os.Surface.headless(width, height));
		var d = this.device;
		target = d.createTexture({width: width, height: height, renderTarget: true});
		dstCopy = d.createTexture({width: width, height: height, renderTarget: true});
		coverage = d.createTexture({width: width, height: height, format: RGBA16F, renderTarget: true});
		white = d.createTexture({width: 1, height: 1, data: Bytes.ofHex("ffffffff")});
		table = d.createTexture({width: 256, height: TABLE_ROWS});
		var p = CoverageShader.pipeline({blend: Additive});
		p.colorFormat = RGBA16F;
		coveragePipe = d.createPipeline(p);
		var p = CoverShader.pipeline({blend: Premultiplied});
		p.colorFormat = RGBA8;
		coverPipe = d.createPipeline(p);
		var p = BlendShader.pipeline({blend: Opaque});
		p.colorFormat = RGBA8;
		blendPipe = d.createPipeline(p);
		var p = ClipShader.pipeline({blend: Opaque});
		p.colorFormat = RGBA8;
		clipPipe = d.createPipeline(p);
		var p = CopyShader.pipeline({blend: Opaque});
		p.colorFormat = RGBA8;
		copyPipe = d.createPipeline(p);
		presentPipe = d.createPipeline(CopyShader.pipeline({blend: Opaque}));
		nearest = d.createSampler({filter: Nearest, wrap: Clamp});
		linear = d.createSampler({filter: Linear, wrap: Clamp});
		linearRepeat = d.createSampler({filter: Linear, wrap: Repeat});
		nearestRepeat = d.createSampler({filter: Nearest, wrap: Repeat});
		vertices = d.createBuffer({size: vertexCapacity, usage: Vertex});
		indices = d.createBuffer({size: 4, usage: Index, data: Bytes.alloc(4)});
		state = new GpuState();
		state.reset(width, height);
		state.drawTarget = target;
		states.push(state);
		clear(0);
	}

	inline function get_matrix()
		return state.matrix;

	// ---- frames: everything a frame records until the pixels are read

	function begin():Encoder {
		if (enc == null) {
			enc = device.beginFrame();
			vertexUsed = 0;
			tableRow = 0;
		}
		return enc;
	}

	// the frame ended (its draws submitted); the next draw begins another
	function flush() {
		if (enc == null) return;
		device.endFrame();
		enc = null;
	}

	// bytes into the vertex buffer at a place of their own this frame: its offset
	function upload(b:Bytes, n:Int):Int {
		if (vertexUsed + n > vertexCapacity) {
			flush();
			begin();
			if (n > vertexCapacity) {
				device.destroyBuffer(vertices);
				vertexCapacity = n * 2;
				vertices = device.createBuffer({size: vertexCapacity, usage: Vertex});
			}
		}
		var at = vertexUsed;
		device.writeBuffer(vertices, at, b, 0, n);
		vertexUsed += (n + 255) & ~255;
		return at;
	}

	function quadIndices(quads:Int) {
		if (quads <= indexQuads) return;
		var n = Std.int(Math.max(quads, indexQuads * 2));
		var ib = Bytes.alloc(n * 6 * 4);
		for (q in 0...n)
			for (k in 0...6)
				ib.setInt32((q * 6 + k) * 4, q * 4 + [0, 1, 2, 0, 2, 3][k]);
		device.destroyBuffer(indices);
		indices = device.createBuffer({size: ib.length, usage: Index, data: ib});
		indexQuads = n;
	}

	// ---- the state

	public var saveCount(get, never):Int;

	inline function get_saveCount()
		return depth;

	public function save() {
		depth++;
		if (states.length <= depth) states.push(new GpuState());
		states[depth].inherit(state);
		state = states[depth];
	}

	public function saveLayer(alpha = 1.0, ?blend:Blender, ?mask:Mask) {
		finishBatch();
		save();
		var s = state;
		s.layer = true;
		s.layerAlpha = alpha;
		s.layerBlend = blend;
		s.layerMask = mask;
		s.under = s.drawTarget;
		if (s.pixels == null) s.pixels = device.createTexture({width: width, height: height, renderTarget: true});
		s.drawTarget = s.pixels;
		var e = begin();
		e.beginPass({colors: [{load: Clear, clear: new Color(0, 0, 0, 0), texture: s.pixels}]});
		e.endPass();
	}

	public function restore() {
		if (depth == 0) return;
		finishBatch();
		var s = state;
		depth--;
		state = states[depth];
		if (s.layer) {
			s.layer = false;
			var maskTex:Null<Texture> = null;
			if (s.layerMask != null) {
				var m = s.layerMask;
				maskTex = device.createTexture({width: m.width, height: m.height, format: R8, data: m.coverage});
			}
			setPaint(5, 0, 0, null, s.layerAlpha, s.layerBlend);
			if (maskTex != null) uniforms.setFloat(12, 1);
			quad(state.clipX0, state.clipY0, state.clipX1, state.clipY1, 0);
			drawCover(s.layerBlend, maskTex ?? coverage, s.pixels, nearest);
			if (maskTex != null) {
				flush();
				device.destroyTexture(maskTex);
			}
			s.layerMask = null;
		}
	}

	public function restoreToCount(count:Int)
		while (depth > count)
			restore();

	public function translate(x:Float, y:Float)
		state.matrix.translate(x, y);

	public function scale(x:Float, y:Float)
		state.matrix.scale(x, y);

	public function rotate(angle:Float)
		state.matrix.rotate(angle);

	public function transform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float)
		state.matrix.transform(a, b, c, d, e, f);

	public function setTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float)
		state.matrix.set(a, b, c, d, e, f);

	public function resetTransform()
		state.matrix.identity();

	// ---- coverage

	// the path's trapezoids, in its units, for the transform now
	function tessellate(path:Path, evenOdd:Bool) {
		traps.reset();
		var s = state.matrix.maxScale();
		path.flatten(traps, Matrix.IDENTITY, tolerance / (s > 0 ? s : 1));
		traps.build(evenOdd);
	}

	function tessellateStroke(path:Path, style:Stroke) {
		traps.reset();
		stroker.stroke(path, style, Matrix.IDENTITY, traps, tolerance / Math.max(state.matrix.maxScale(), 1e-9));
		traps.build(false);
	}

	// the trapezoids' bounds in pixels, within the clip: x0, y0, x1, y1 (false: none)
	final box = [0.0, 0.0, 0.0, 0.0];

	function bounds():Bool {
		var m = state.matrix, t = traps.traps;
		var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
		for (k in 0...traps.count) {
			var o = k * 6;
			for (c in 0...4) {
				var x = t[o + 2 + (c == 0 ? 0 : c == 1 ? 1 : c == 2 ? 3 : 2)], y = t[o + (c < 2 ? 0 : 1)];
				var px = m.mapX(x, y), py = m.mapY(x, y);
				if (px < x0) x0 = px;
				if (px > x1) x1 = px;
				if (py < y0) y0 = py;
				if (py > y1) y1 = py;
			}
		}
		x0 = Math.max(Math.floor(x0) - 1, state.clipX0);
		y0 = Math.max(Math.floor(y0) - 1, state.clipY0);
		x1 = Math.min(Math.ceil(x1) + 1, state.clipX1);
		y1 = Math.min(Math.ceil(y1) + 1, state.clipY1);
		box[0] = x0;
		box[1] = y0;
		box[2] = x1;
		box[3] = y1;
		return x1 > x0 && y1 > y0;
	}

	// the trapezoids as vertices (10 floats each, 4 a trapezoid) into cpuVerts from at: the next offset
	function trapVertices(into:Bytes, at:Int):Int {
		var t = traps.traps, o = at;
		for (k in 0...traps.count) {
			var b = k * 6;
			for (c in 0...4) {
				into.setFloat(o, c);
				into.setFloat(o + 4, 0);
				into.setFloat(o + 8, t[b + 2]);
				into.setFloat(o + 12, t[b]);
				into.setFloat(o + 16, t[b + 3]);
				into.setFloat(o + 20, t[b]);
				into.setFloat(o + 24, t[b + 5]);
				into.setFloat(o + 28, t[b + 1]);
				into.setFloat(o + 32, t[b + 4]);
				into.setFloat(o + 36, t[b + 1]);
				o += 40;
			}
		}
		return o;
	}

	var trapBytes = Bytes.alloc(40 * 4 * 1024);

	// the trapezoids' coverage into the coverage target (cleared first)
	function coverTraps() {
		var n = traps.count * 160;
		if (n > trapBytes.length) trapBytes = Bytes.alloc(n * 2);
		trapVertices(trapBytes, 0);
		var e = begin();
		var at = n > 0 ? upload(trapBytes, n) : 0;
		var m = state.matrix;
		uniforms.setFloat(0, m.a);
		uniforms.setFloat(4, m.b);
		uniforms.setFloat(8, m.c);
		uniforms.setFloat(12, m.d);
		uniforms.setFloat(16, m.e);
		uniforms.setFloat(20, m.f);
		uniforms.setFloat(24, width);
		uniforms.setFloat(28, height);
		quadIndices(traps.count);
		e.beginPass({colors: [{load: Clear, clear: new Color(0, 0, 0, 0), texture: coverage}]});
		if (traps.count > 0) {
			e.setPipeline(coveragePipe);
			e.setUniforms(CoverageShader.uniforms[0].binding, uniforms, 0, 32);
			e.setVertexBuffer(0, vertices, at);
			e.setIndexBuffer(indices, UInt32);
			e.drawIndexed(traps.count * 6);
		}
		e.endPass();
	}

	// ---- painting

	final quadBytes = Bytes.alloc(4 * 24);

	// a quad over (x0, y0, x1, y1) in pixels, of colour c (premultiplied) into quadBytes
	function quad(x0:Float, y0:Float, x1:Float, y1:Float, c:Int, ?into:Bytes, at = 0) {
		var b = into ?? quadBytes;
		var a = ((c >>> 24) & 255) / 255;
		var r = ((c >> 16) & 255) / 255 * a, g = ((c >> 8) & 255) / 255 * a, bl = (c & 255) / 255 * a;
		for (k in 0...4) {
			var o = at + k * 24;
			b.setFloat(o, k == 0 || k == 3 ? x0 : x1);
			b.setFloat(o + 4, k < 2 ? y0 : y1);
			b.setFloat(o + 8, r);
			b.setFloat(o + 12, g);
			b.setFloat(o + 16, bl);
			b.setFloat(o + 20, a);
		}
	}

	// the CoverPaint uniforms: kind, its spread and table row, the device-to-paint transform, the parameters
	function setPaint(kind:Int, spread:Int, row:Float, inv:Null<Matrix>, alpha:Float, blend:Null<Blender>) {
		var u = uniforms;
		u.fill(0, 112, 0);
		u.setFloat(0, width);
		u.setFloat(4, height);
		u.setFloat(8, alpha > 1 ? 1 : alpha);
		u.setFloat(12, kind == 5 ? 0 : 1);
		u.setFloat(16, kind);
		u.setFloat(20, spread);
		u.setFloat(24, row);
		var code = blend == null ? -1 : blend.code;
		u.setFloat(28, code >= 0 ? code : -1);
		if (inv != null) {
			u.setFloat(32, inv.a);
			u.setFloat(36, inv.b);
			u.setFloat(40, inv.c);
			u.setFloat(44, inv.d);
			u.setFloat(48, inv.e);
			u.setFloat(52, inv.f);
		}
		u.setFloat(56, -1);
		u.setFloat(60, -1);
		if (code < 0) {
			var k = -1 - code;
			u.setFloat(96, k >> 2);
			u.setFloat(100, k & 3);
		}
		u.setFloat(104, blend != null && blend.unbounded ? 1 : 0);
	}

	// the paint's kind into the uniforms (false: it draws nothing); its texture and sampler
	var paintTexture:Texture;
	var paintSampler:Sampler;

	function preparePaint(paint:Paint):Bool {
		var shader = paint.shader;
		paintTexture = white;
		paintSampler = nearest;
		if (shader == null) {
			setPaint(0, 0, 0, null, paint.alpha, paint.blend);
			return true;
		}
		if (Std.isOfType(shader, Pattern)) {
			var p:Pattern = cast shader;
			full.copyFrom(state.matrix).multiply(p.matrix);
			if (!full.invertInto(inverse)) return false;
			setPaint(4, 0, 0, inverse, paint.alpha, paint.blend);
			var u = uniforms;
			u.setFloat(64, p.bitmap.width);
			u.setFloat(68, p.bitmap.height);
			u.setFloat(72, p.repeatX ? 1 : 0);
			u.setFloat(76, p.repeatY ? 1 : 0);
			if (p.clamp) {
				u.setFloat(56, Math.floor(p.sx0));
				u.setFloat(60, Math.floor(p.sy0));
				u.setFloat(80, Math.ceil(p.sx1));
				u.setFloat(84, Math.ceil(p.sy1));
			}
			paintTexture = textureOf(p.bitmap);
			var rep = !p.clamp && (p.repeatX || p.repeatY);
			paintSampler = p.smooth ? (rep ? linearRepeat : linear) : (rep ? nearestRepeat : nearest);
			return true;
		}
		var g:Gradient = cast shader;
		full.copyFrom(state.matrix).multiply(g.matrix);
		if (!full.invertInto(inverse)) return false;
		if (!g.begin(Matrix.IDENTITY)) return false;
		if (tableRow >= TABLE_ROWS) {
			finishBatch();
			flush();
		}
		begin();
		g.table(tableBytes, 0, 256);
		device.writeTexture(table, tableBytes, 0, tableRow, 256, 1);
		var row = (tableRow + 0.5) / TABLE_ROWS;
		tableRow++;
		var u = uniforms;
		if (Std.isOfType(g, LinearGradient)) {
			var l:LinearGradient = cast g;
			setPaint(1, g.spread, row, inverse, paint.alpha, paint.blend);
			u.setFloat(64, l.x0);
			u.setFloat(68, l.y0);
			u.setFloat(72, l.x1);
			u.setFloat(76, l.y1);
		} else if (Std.isOfType(g, RadialGradient)) {
			var r:RadialGradient = cast g;
			setPaint(2, g.spread, row, inverse, paint.alpha, paint.blend);
			u.setFloat(64, r.x0);
			u.setFloat(68, r.y0);
			u.setFloat(72, r.r0);
			u.setFloat(80, r.x1);
			u.setFloat(84, r.y1);
			u.setFloat(88, r.r1);
		} else {
			var c:ConicGradient = cast g;
			setPaint(3, g.spread, row, inverse, paint.alpha, paint.blend);
			u.setFloat(64, c.start);
			u.setFloat(68, c.x);
			u.setFloat(72, c.y);
		}
		paintTexture = table;
		paintSampler = linear;
		return true;
	}

	// the quad(s) in quadBytes (n of them) painted with the uniforms set, into the target
	function drawCover(blend:Null<Blender>, cov:Texture, tex:Texture, smp:Sampler, ?quads:Bytes, n = 1) {
		var e = begin();
		var q = quads ?? quadBytes;
		var at = upload(q, n * 96);
		quadIndices(n);
		var t = state.drawTarget, clip = state.clip ?? white;
		if (blend != null) {
			// (the pixels as they are, for the shader to blend with)
			copy(t, dstCopy);
			e.beginPass({colors: [{load: Load, texture: t}]});
			e.setPipeline(blendPipe);
			e.setUniforms(BlendShader.uniforms[0].binding, uniforms, 0, 112);
			e.setTexture(BlendShader.textures[0].binding, cov, nearest);
			e.setTexture(BlendShader.textures[1].binding, clip, nearest);
			e.setTexture(BlendShader.textures[2].binding, table, linear);
			e.setTexture(BlendShader.textures[3].binding, tex, smp);
			e.setTexture(BlendShader.textures[4].binding, dstCopy, nearest);
		} else {
			e.beginPass({colors: [{load: Load, texture: t}]});
			e.setPipeline(coverPipe);
			e.setUniforms(CoverShader.uniforms[0].binding, uniforms, 0, 112);
			e.setTexture(CoverShader.textures[0].binding, cov, nearest);
			e.setTexture(CoverShader.textures[1].binding, clip, nearest);
			e.setTexture(CoverShader.textures[2].binding, table, linear);
			e.setTexture(CoverShader.textures[3].binding, tex, smp);
		}
		e.setVertexBuffer(0, vertices, at);
		e.setIndexBuffer(indices, UInt32);
		e.drawIndexed(n * 6);
		e.endPass();
	}

	final copyQuad = Bytes.alloc(4 * 16);

	// a texture's pixels into another of the canvas's size
	function copy(from:Texture, to:Texture) {
		for (k in 0...4) {
			var x = k == 0 || k == 3 ? -1.0 : 1.0, y = k < 2 ? 1.0 : -1.0;
			copyQuad.setFloat(k * 16, x);
			copyQuad.setFloat(k * 16 + 4, y);
			copyQuad.setFloat(k * 16 + 8, (x + 1) / 2);
			copyQuad.setFloat(k * 16 + 12, (1 - y) / 2);
		}
		var e = begin();
		var at = upload(copyQuad, 64);
		quadIndices(1);
		e.beginPass({colors: [{load: Load, texture: to}]});
		e.setPipeline(copyPipe);
		e.setTexture(CopyShader.textures[0].binding, from, nearest);
		e.setVertexBuffer(0, vertices, at);
		e.setIndexBuffer(indices, UInt32);
		e.drawIndexed(6);
		e.endPass();
	}

	// a bitmap's texture (premultiplied), made once a bitmap and contents
	function textureOf(b:Bitmap):Texture {
		var t = textures.get(b);
		if (t != null) return t.texture;
		var tex = device.createTexture({width: b.width, height: b.height, data: b.pixels});
		textures.set(b, {texture: tex, version: 0});
		return tex;
	}

	// the trapezoids in traps painted
	function paintTraps(paint:Paint) {
		var unbounded = paint.blend != null && paint.blend.unbounded;
		if (!(paint.alpha > 0) && !unbounded) return;
		var some = bounds();
		if (!some && !unbounded) return;
		// (a colour over: into the batch, unless it overlaps what the batch has)
		if (paint.shader == null && paint.blend == null) {
			batch(paint);
			return;
		}
		finishBatch();
		// (the coverage first: its uniforms are the paint's bytes too)
		coverTraps();
		if (!preparePaint(paint)) {
			if (!unbounded) return;
			setPaint(0, 0, 0, null, 0, paint.blend);
		}
		if (unbounded) quad(state.clipX0, state.clipY0, state.clipX1, state.clipY1, paint.color) else quad(box[0], box[1], box[2], box[3], paint.color);
		drawCover(paint.blend, coverage, paintTexture, paintSampler);
	}

	// ---- batches of colour fills

	var batchTrapBytes = Bytes.alloc(40 * 4 * 4096);
	var batchTrapUsed = 0;

	function batch(paint:Paint) {
		for (k in 0...batchCount)
			if (box[0] < batchBoxes[k * 4 + 2] && box[2] > batchBoxes[k * 4] && box[1] < batchBoxes[k * 4 + 3] && box[3] > batchBoxes[k * 4 + 1]) {
				finishBatch();
				break;
			}
		if (batchCount > 0 && !sameMatrix()) finishBatch();
		if (batchCount >= 4096) finishBatch();
		// (the trapezoids in device pixels: a batch has one transform, so they are taken through it here)
		var n = traps.count * 160;
		if (batchTrapUsed + n > batchTrapBytes.length) {
			var b = Bytes.alloc((batchTrapUsed + n) * 2);
			b.blit(0, batchTrapBytes, 0, batchTrapUsed);
			batchTrapBytes = b;
		}
		batchTrapUsed = trapVertices(batchTrapBytes, batchTrapUsed);
		batchTraps += traps.count;
		batchMatrix.copyFrom(state.matrix);
		var c = paint.color, a = Std.int(((c >>> 24) & 255) * (paint.alpha > 1 ? 1 : paint.alpha) + 0.5);
		quad(box[0], box[1], box[2], box[3], (a << 24) | (c & 0xFFFFFF), batchQuads, batchCount * 96);
		batchBoxes[batchCount * 4] = box[0];
		batchBoxes[batchCount * 4 + 1] = box[1];
		batchBoxes[batchCount * 4 + 2] = box[2];
		batchBoxes[batchCount * 4 + 3] = box[3];
		batchCount++;
	}

	final batchMatrix = new Matrix();

	inline function sameMatrix():Bool {
		var m = state.matrix, b = batchMatrix;
		return m.a == b.a && m.b == b.b && m.c == b.c && m.d == b.d && m.e == b.e && m.f == b.f;
	}

	// the batch drawn: its trapezoids' coverage in one draw, its quads in another
	function finishBatch() {
		if (batchCount == 0) return;
		var e = begin();
		var at = batchTraps > 0 ? upload(batchTrapBytes, batchTrapUsed) : 0;
		var m = batchMatrix;
		uniforms.setFloat(0, m.a);
		uniforms.setFloat(4, m.b);
		uniforms.setFloat(8, m.c);
		uniforms.setFloat(12, m.d);
		uniforms.setFloat(16, m.e);
		uniforms.setFloat(20, m.f);
		uniforms.setFloat(24, width);
		uniforms.setFloat(28, height);
		quadIndices(Std.int(Math.max(batchTraps, batchCount)));
		e.beginPass({colors: [{load: Clear, clear: new Color(0, 0, 0, 0), texture: coverage}]});
		if (batchTraps > 0) {
			e.setPipeline(coveragePipe);
			e.setUniforms(CoverageShader.uniforms[0].binding, uniforms, 0, 32);
			e.setVertexBuffer(0, vertices, at);
			e.setIndexBuffer(indices, UInt32);
			e.drawIndexed(batchTraps * 6);
		}
		e.endPass();
		setPaint(0, 0, 0, null, 1, null);
		paintTexture = white;
		drawCover(null, coverage, white, nearest, batchQuads, batchCount);
		batchCount = 0;
		batchTraps = 0;
		batchTrapUsed = 0;
		draws++;
	}

	// (batches drawn: the lane prints how many draws the scenes took)
	public var draws(default, null) = 0;

	// ---- the API

	public function fill(path:Path, paint:Paint, evenOdd = false) {
		tessellate(path, evenOdd);
		paintTraps(paint);
	}

	public function stroke(path:Path, style:Stroke, paint:Paint) {
		if (!(style.width > 0) || !Math.isFinite(style.width)) return;
		tessellateStroke(path, style);
		paintTraps(paint);
	}

	public function clip(path:Path, evenOdd = false) {
		finishBatch();
		tessellate(path, evenOdd);
		var has = bounds();
		coverTraps();
		var s = state, before = s.clip ?? white;
		var into = s.nextClip(device, width, height);
		for (k in 0...4) {
			var x = k == 0 || k == 3 ? -1.0 : 1.0, y = k < 2 ? 1.0 : -1.0;
			copyQuad.setFloat(k * 16, x);
			copyQuad.setFloat(k * 16 + 4, y);
			copyQuad.setFloat(k * 16 + 8, (x + 1) / 2);
			copyQuad.setFloat(k * 16 + 12, (1 - y) / 2);
		}
		var e = begin();
		var at = upload(copyQuad, 64);
		quadIndices(1);
		e.beginPass({colors: [{load: Load, texture: into}]});
		e.setPipeline(clipPipe);
		e.setTexture(ClipShader.textures[0].binding, coverage, nearest);
		e.setTexture(ClipShader.textures[1].binding, before, nearest);
		e.setVertexBuffer(0, vertices, at);
		e.setIndexBuffer(indices, UInt32);
		e.drawIndexed(6);
		e.endPass();
		s.clip = into;
		if (has) {
			s.clipX0 = Std.int(box[0]);
			s.clipY0 = Std.int(box[1]);
			s.clipX1 = Std.int(box[2]);
			s.clipY1 = Std.int(box[3]);
		} else
			s.clipX1 = s.clipX0;
	}

	final erase = new Paint(0xFF000000);

	public function fillRect(x:Float, y:Float, w:Float, h:Float, paint:Paint) {
		scratch.clear();
		scratch.rect(x, y, w, h);
		fill(scratch, paint);
	}

	public function clearRect(x:Float, y:Float, w:Float, h:Float) {
		scratch.clear();
		scratch.rect(x, y, w, h);
		erase.blend = helder.canvas.Blend.destinationOut;
		fill(scratch, erase);
	}

	public function clear(color = 0) {
		finishBatch();
		var a = ((color >>> 24) & 255) / 255;
		var e = begin();
		e.beginPass({
			colors: [{load: Clear, clear: new Color(((color >> 16) & 255) / 255 * a, ((color >> 8) & 255) / 255 * a, (color & 255) / 255 * a, a),
				texture: state.drawTarget}]
		});
		e.endPass();
	}

	public function drawImage(img:Bitmap, sx:Float, sy:Float, sw:Float, sh:Float, dx:Float, dy:Float, dw:Float, dh:Float, paint:Paint,
			smooth = true) {
		if (sw == 0 || sh == 0 || dw == 0 || dh == 0) return;
		if (sw < 0) {
			sx += sw;
			sw = -sw;
		}
		if (sh < 0) {
			sy += sh;
			sh = -sh;
		}
		if (dw < 0) {
			dx += dw;
			dw = -dw;
		}
		if (dh < 0) {
			dy += dh;
			dh = -dh;
		}
		var kx = dw / sw, ky = dh / sh;
		if (sx < 0) {
			dx -= sx * kx;
			dw += sx * kx;
			sw += sx;
			sx = 0;
		}
		if (sy < 0) {
			dy -= sy * ky;
			dh += sy * ky;
			sh += sy;
			sy = 0;
		}
		if (sx + sw > img.width) {
			dw -= (sx + sw - img.width) * kx;
			sw = img.width - sx;
		}
		if (sy + sh > img.height) {
			dh -= (sy + sh - img.height) * ky;
			sh = img.height - sy;
		}
		if (sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0) return;
		var pat = image;
		if (pat == null) image = pat = new Pattern(img, false, false);
		pat.bitmap = img;
		pat.smooth = smooth;
		pat.clamp = true;
		pat.sx0 = sx;
		pat.sy0 = sy;
		pat.sx1 = sx + sw;
		pat.sy1 = sy + sh;
		pat.matrix.set(kx, 0, 0, ky, dx - sx * kx, dy - sy * ky);
		var saved = paint.shader;
		paint.shader = pat;
		scratch.clear();
		scratch.rect(dx, dy, dw, dh);
		fill(scratch, paint);
		paint.shader = saved;
	}

	// ---- pixels

	// the canvas's pixels read back (premultiplied): drawn into the frame, read, the frame ended
	public function snapshot():Bitmap {
		finishBatch();
		var e = begin();
		for (k in 0...4) {
			var x = k == 0 || k == 3 ? -1.0 : 1.0, y = k < 2 ? 1.0 : -1.0;
			copyQuad.setFloat(k * 16, x);
			copyQuad.setFloat(k * 16 + 4, y);
			copyQuad.setFloat(k * 16 + 8, (x + 1) / 2);
			copyQuad.setFloat(k * 16 + 12, (1 - y) / 2);
		}
		var at = upload(copyQuad, 64);
		quadIndices(1);
		e.beginPass({colors: [{load: Clear, clear: new Color(0, 0, 0, 0)}]});
		e.setPipeline(presentPipe);
		e.setTexture(CopyShader.textures[0].binding, target, nearest);
		e.setVertexBuffer(0, vertices, at);
		e.setIndexBuffer(indices, UInt32);
		e.drawIndexed(6);
		e.endPass();
		var b = new Bitmap(width, height);
		device.readPixels(b.pixels);
		flush();
		// (a bitmap drawn from changes: the textures made of the old one dropped)
		return b;
	}

	public function readPixels(out:Bytes, x:Int, y:Int, w:Int, h:Int)
		snapshot().readStraight(out, x, y, w, h);

	public function writePixels(rgba:Bytes, x:Int, y:Int, w:Int, h:Int, srcStride = -1) {
		// (as they are: the canvas read back, the region replaced, the whole drawn in again)
		var b = snapshot();
		b.writeStraight(rgba, x, y, w, h, srcStride);
		var t = device.createTexture({width: width, height: height, data: b.pixels});
		copy(t, target);
		flush();
		device.destroyTexture(t);
	}

	public function dispose() {
		flush();
		device.dispose();
	}
}

// A save's transform and clip (its texture: the parent's until it clips,
// then one of its own, two kept to narrow it again), a layer
@:allow(helder.canvas.gpu.GpuCanvas)
private class GpuState {
	public final matrix = new Matrix();
	public var clip:Null<Texture> = null;
	var own:Array<Texture> = [];
	var turn = 0;
	public var clipX0 = 0;
	public var clipY0 = 0;
	public var clipX1 = 0;
	public var clipY1 = 0;
	public var drawTarget:Texture;
	public var layer = false;
	public var layerAlpha = 1.0;
	public var layerBlend:Null<Blender> = null;
	public var layerMask:Null<Mask> = null;
	public var pixels:Null<Texture> = null;
	public var under:Null<Texture> = null;

	public function new() {}

	public function reset(w:Int, h:Int) {
		matrix.identity();
		clip = null;
		clipX0 = clipY0 = 0;
		clipX1 = w;
		clipY1 = h;
	}

	public function inherit(p:GpuState) {
		matrix.copyFrom(p.matrix);
		clip = p.clip;
		clipX0 = p.clipX0;
		clipY0 = p.clipY0;
		clipX1 = p.clipX1;
		clipY1 = p.clipY1;
		drawTarget = p.drawTarget;
		layer = false;
	}

	// a texture of its own to narrow the clip into (never the one it reads)
	public function nextClip(d:Device, w:Int, h:Int):Texture {
		if (own.length < 2) {
			own.push(d.createTexture({width: w, height: h, renderTarget: true}));
			own.push(d.createTexture({width: w, height: h, renderTarget: true}));
		}
		var t = own[turn];
		if (t == clip) {
			turn = 1 - turn;
			t = own[turn];
		}
		turn = 1 - turn;
		return t;
	}
}
