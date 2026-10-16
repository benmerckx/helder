// The JavaScript side of hxmc.gfx in the browser, loaded by
// packages/os/browser.mjs with packages/os/imports.mjs: the imports of the
// module "hxmc_gfx" for the WebGPU back end (src/hxmc/gfx/webgpu/WebGPU.hx)
// and of the module "hxmc_gl" for the GL back end on WebGL2
// (src/hxmc/gfx/gl/GL.hx, WebGL.hx). The adapter and the device are
// requested before the module starts; without them (no navigator.gpu, no
// adapter, or run's option gfx: 'webgl2') ready() is 0 and Device.create
// takes WebGL2, or throws without it. GPU objects, and GL's object names,
// live in the loader's handle table; the enums are hxmc.gfx's, GL's are
// GL's own.
//
// host.gfx.backend is the API a device was created on ('webgpu', 'webgl2';
// null: none yet). Reading a frame back on WebGPU waits for the GPU, which a
// browser does asynchronously only: host.gfx.readPixels() resolves to
// {width, height, data} (RGBA8, rows top to bottom) of a headless target as
// it is now, or of a canvas's next frame (copied before it is presented);
// on WebGL2 the same, read synchronously (Device.readPixels works there too).

const FORMATS = ['float32', 'float32x2', 'float32x3', 'float32x4', 'unorm8x4']; // VertexFormat
const TOPOLOGIES = ['triangle-list', 'triangle-strip', 'line-list', 'point-list']; // Topology
const CULLS = ['none', 'front', 'back']; // Cull
const LOADS = ['clear', 'load', 'clear']; // LoadOp (DontCare: clear)
const INFO_LOG_LENGTH = 0x8b84; // (GL's, not WebGL's)

export default async function (host) {
	let adapter = null, device = null;
	try {
		adapter = host.options.gfx !== 'webgl2' && navigator.gpu && (await navigator.gpu.requestAdapter());
		device = adapter ? await adapter.requestDevice() : null;
	} catch (e) {
		console.error('hxmc.gfx: no WebGPU device:', e);
	}
	if (device) device.addEventListener('uncapturederror', (e) => console.error('hxmc.gfx: WebGPU:', e.error.message));
	const { handles } = host;
	// a pipeline's vertex buffers, as pipeline_buffer and pipeline_attribute give them
	let layout = [];
	// the frame
	let encoder = null, texture = null, frameTarget = null, pass = null;
	const attachment = { view: null, loadOp: 'clear', storeOp: 'store', clearValue: { r: 0, g: 0, b: 0, a: 1 } };
	const passDesc = { colorAttachments: [attachment] };
	let captures = [];

	// records a copy of a texture into a buffer; then, once the encoder is
	// submitted, the result resolves to its pixels as RGBA8, rows top to bottom
	function copy(enc, tex, format) {
		const w = tex.width, h = tex.height, row = Math.ceil(w * 4 / 256) * 256;
		const buf = device.createBuffer({ size: row * h, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
		enc.copyTextureToBuffer({ texture: tex }, { buffer: buf, bytesPerRow: row }, [w, h]);
		return async () => {
			await buf.mapAsync(GPUMapMode.READ);
			const src = new Uint8Array(buf.getMappedRange()), data = new Uint8Array(w * h * 4);
			const bgra = format.startsWith('bgra');
			for (let y = 0; y < h; y++)
				for (let x = 0; x < w; x++) {
					const s = y * row + 4 * x, d = 4 * (y * w + x);
					data[d] = src[s + (bgra ? 2 : 0)];
					data[d + 1] = src[s + 1];
					data[d + 2] = src[s + (bgra ? 0 : 2)];
					data[d + 3] = src[s + 3];
				}
			buf.destroy();
			return { width: w, height: h, data };
		};
	}

	host.gfx = {
		adapter,
		device,
		backend: null,
		readPixels() {
			if (current) {
				if (current.offscreen) return Promise.resolve(read(current));
				return new Promise((resolve, reject) => current.captures.push({ resolve, reject }));
			}
			if (frameTarget && frameTarget.texture) {
				const enc = device.createCommandEncoder();
				const pixels = copy(enc, frameTarget.texture, frameTarget.format);
				device.queue.submit([enc.finish()]);
				return pixels();
			}
			return new Promise((resolve, reject) => captures.push({ resolve, reject }));
		},
	};

	const hxmc_gfx = {
		ready: () => (device ? 1 : 0),
		target_canvas(canvas) {
			host.gfx.backend = 'webgpu';
			const context = handles.get(canvas).getContext('webgpu');
			const format = navigator.gpu.getPreferredCanvasFormat();
			// (COPY_SRC: readPixels)
			context.configure({ device, format, usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC, alphaMode: 'opaque' });
			return handles.add({ context, format });
		},
		target_texture(width, height) {
			host.gfx.backend = 'webgpu';
			const format = 'rgba8unorm';
			const texture = device.createTexture({ size: [width, height], format, usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC });
			return handles.add({ texture, format });
		},
		buffer(size, usage, data, length) {
			const u = [GPUBufferUsage.VERTEX, GPUBufferUsage.INDEX, GPUBufferUsage.UNIFORM][usage];
			const b = device.createBuffer({ size: Math.ceil(size / 4) * 4, usage: u | GPUBufferUsage.COPY_DST });
			if (length > 0) {
				// (writeBuffer: a multiple of 4 bytes)
				const bytes = new Uint8Array(Math.ceil(length / 4) * 4);
				bytes.set(host.bytes(data, length));
				device.queue.writeBuffer(b, 0, bytes);
			}
			return handles.add(b);
		},
		shader(code) {
			const module = device.createShaderModule({ code: host.string(code) });
			module.getCompilationInfo().then((info) => {
				for (const m of info.messages) if (m.type === 'error') console.error(`hxmc.gfx: WGSL ${m.lineNum}:${m.linePos}: ${m.message}`);
			});
			return handles.add(module);
		},
		pipeline_begin() {
			layout = [];
		},
		pipeline_buffer(stride) {
			layout.push({ arrayStride: stride, attributes: [] });
		},
		pipeline_attribute(location, format, offset) {
			layout[layout.length - 1].attributes.push({ shaderLocation: location, format: FORMATS[format], offset });
		},
		pipeline_end(vertex, fragment, target, topology, cull) {
			const p = device.createRenderPipeline({
				layout: 'auto',
				vertex: { module: handles.get(vertex), entryPoint: 'main', buffers: layout },
				fragment: { module: handles.get(fragment), entryPoint: 'main', targets: [{ format: handles.get(target).format }] },
				// (GL's front faces)
				primitive: { topology: TOPOLOGIES[topology], cullMode: CULLS[cull], frontFace: 'ccw' },
			});
			return handles.add(p);
		},
		frame_begin(target) {
			const t = handles.get(target);
			texture = t.texture ?? t.context.getCurrentTexture();
			if (texture.width === 0 || texture.height === 0) return 0;
			frameTarget = t;
			attachment.view = texture.createView();
			encoder = device.createCommandEncoder();
			return 1;
		},
		pass_begin(load, r, g, b, a) {
			attachment.loadOp = LOADS[load];
			const c = attachment.clearValue;
			c.r = r;
			c.g = g;
			c.b = b;
			c.a = a;
			pass = encoder.beginRenderPass(passDesc);
			pass.setViewport(0, 0, texture.width, texture.height, 0, 1);
		},
		set_pipeline: (p) => pass.setPipeline(handles.get(p)),
		set_vertex_buffer: (slot, b, offset) => pass.setVertexBuffer(slot, handles.get(b), offset),
		draw: (vertices, instances, first) => pass.draw(vertices, instances, first, 0),
		pass_end() {
			pass.end();
			pass = null;
		},
		frame_end() {
			// (a readPixels waiting for a canvas's frame)
			const waiting = captures;
			captures = [];
			const pixels = waiting.length ? copy(encoder, texture, frameTarget.format) : null;
			device.queue.submit([encoder.finish()]);
			pixels?.().then((px) => waiting.forEach((w) => w.resolve(px)), (e) => waiting.forEach((w) => w.reject(e)));
			encoder = null;
			attachment.view = null;
			texture = null;
		},
		release(h) {
			const o = handles.get(h);
			o?.destroy?.();
			o?.texture?.destroy();
			o?.context?.unconfigure();
			handles.remove(h);
		},
	};

	// WebGL2: the current context ({gl, canvas, offscreen, captures}: the
	// readPixels waiting for its next frame)
	let current = null, gl = null;
	const view = () => new DataView(host.memory().buffer);
	const get = (h) => handles.get(h);

	// the drawing buffer as RGBA8, rows top to bottom
	function read(c) {
		const g = c.gl, w = g.drawingBufferWidth, h = g.drawingBufferHeight;
		const src = new Uint8Array(w * h * 4), data = new Uint8Array(w * h * 4);
		g.pixelStorei(g.PACK_ALIGNMENT, 1);
		g.readPixels(0, 0, w, h, g.RGBA, g.UNSIGNED_BYTE, src);
		for (let y = 0; y < h; y++) data.set(src.subarray((h - 1 - y) * w * 4, (h - y) * w * 4), y * w * 4);
		return { width: w, height: h, data };
	}
	// GL's glGen*: n new objects, their handles into p
	function gen(n, p, make) {
		const v = view();
		for (let i = 0; i < n; i++) v.setInt32(p + 4 * i, handles.add(make()), true);
	}
	function del(n, p, f) {
		const v = view();
		for (let i = 0; i < n; i++) {
			const h = v.getInt32(p + 4 * i, true);
			if (h) {
				f(get(h));
				handles.remove(h);
			}
		}
	}
	// glGet*iv: INFO_LOG_LENGTH, which WebGL lacks, from the log itself
	function iv(o, pname, p, param, log) {
		const x = pname === INFO_LOG_LENGTH ? new TextEncoder().encode(log(o)).length + 1 : param(o, pname);
		view().setInt32(p, typeof x === 'boolean' ? (x ? 1 : 0) : x, true);
	}
	// glGet*InfoLog: at most size - 1 bytes and a NUL
	function infoLog(text, size, length, p) {
		const b = new TextEncoder().encode(text).subarray(0, Math.max(0, size - 1));
		host.bytes(p, b.length + 1).set([...b, 0]);
		if (length) view().setInt32(length, b.length, true);
	}

	const hxmc_gl = {
		context(canvas, width, height) {
			const offscreen = canvas === 0;
			const c = offscreen ? (typeof OffscreenCanvas === 'function' ? new OffscreenCanvas(width, height) : Object.assign(document.createElement('canvas'), { width, height })) : handles.get(canvas);
			// (a canvas: presented after each frame's task, read back at swap;
			// offscreen: nothing presents it, read back at any time)
			const g = c.getContext('webgl2', { antialias: false, alpha: false, depth: false, preserveDrawingBuffer: offscreen });
			if (!g) return 0;
			host.gfx.backend = 'webgl2';
			return handles.add({ gl: g, canvas: c, offscreen, captures: [] });
		},
		make_current(h) {
			current = get(h);
			gl = current.gl;
		},
		swap(h) {
			const c = get(h), waiting = c.captures;
			if (!waiting.length) return;
			c.captures = [];
			try {
				const px = read(c);
				waiting.forEach((w) => w.resolve(px));
			} catch (e) {
				waiting.forEach((w) => w.reject(e));
			}
		},
		release(h) {
			const c = get(h);
			c.gl.getExtension('WEBGL_lose_context')?.loseContext();
			if (current === c) current = gl = null;
			handles.remove(h);
		},
		glGetError: () => gl.getError(),
		glEnable: (cap) => gl.enable(cap),
		glDisable: (cap) => gl.disable(cap),
		glCullFace: (mode) => gl.cullFace(mode),
		glFrontFace: (mode) => gl.frontFace(mode),
		glViewport: (x, y, w, h) => gl.viewport(x, y, w, h),
		glClearColor: (r, g, b, a) => gl.clearColor(r, g, b, a),
		glClear: (mask) => gl.clear(mask),
		glGenBuffers: (n, p) => gen(n, p, () => gl.createBuffer()),
		glDeleteBuffers: (n, p) => del(n, p, (b) => gl.deleteBuffer(b)),
		glBindBuffer: (target, b) => gl.bindBuffer(target, get(b)),
		// (GLsizeiptr, GLintptr: Int64, a BigInt)
		glBufferData(target, size, data, usage) {
			if (data) gl.bufferData(target, host.bytes(data, Number(size)), usage);
			else gl.bufferData(target, Number(size), usage);
		},
		glBufferSubData: (target, offset, size, data) => gl.bufferSubData(target, Number(offset), host.bytes(data, Number(size))),
		glCreateShader: (type) => handles.add(gl.createShader(type)),
		// (strings: hxmc's Ptr, 8 bytes each; lengths: none, or one each, < 0 for a C string)
		glShaderSource(s, count, strings, lengths) {
			const v = view();
			let src = '';
			for (let i = 0; i < count; i++) {
				const p = v.getUint32(strings + 8 * i, true), n = lengths ? v.getInt32(lengths + 4 * i, true) : -1;
				src += n < 0 ? host.string(p) : new TextDecoder().decode(host.bytes(p, n));
			}
			gl.shaderSource(get(s), src);
		},
		glCompileShader: (s) => gl.compileShader(get(s)),
		glGetShaderiv: (s, pname, p) => iv(get(s), pname, p, (o, k) => gl.getShaderParameter(o, k), (o) => gl.getShaderInfoLog(o)),
		glGetShaderInfoLog: (s, size, length, p) => infoLog(gl.getShaderInfoLog(get(s)), size, length, p),
		glDeleteShader(s) {
			gl.deleteShader(get(s));
			handles.remove(s);
		},
		glCreateProgram: () => handles.add(gl.createProgram()),
		glAttachShader: (p, s) => gl.attachShader(get(p), get(s)),
		glLinkProgram: (p) => gl.linkProgram(get(p)),
		glGetProgramiv: (o, pname, p) => iv(get(o), pname, p, (x, k) => gl.getProgramParameter(x, k), (x) => gl.getProgramInfoLog(x)),
		glGetProgramInfoLog: (o, size, length, p) => infoLog(gl.getProgramInfoLog(get(o)), size, length, p),
		glUseProgram: (p) => gl.useProgram(get(p)),
		glDeleteProgram(p) {
			gl.deleteProgram(get(p));
			handles.remove(p);
		},
		glGenVertexArrays: (n, p) => gen(n, p, () => gl.createVertexArray()),
		glBindVertexArray: (a) => gl.bindVertexArray(get(a)),
		glEnableVertexAttribArray: (i) => gl.enableVertexAttribArray(i),
		glDisableVertexAttribArray: (i) => gl.disableVertexAttribArray(i),
		glVertexAttribPointer: (i, size, type, normalized, stride, offset) => gl.vertexAttribPointer(i, size, type, !!normalized, stride, offset),
		glDrawArrays: (mode, first, count) => gl.drawArrays(mode, first, count),
		glDrawArraysInstanced: (mode, first, count, instances) => gl.drawArraysInstanced(mode, first, count, instances),
		glPixelStorei: (pname, param) => gl.pixelStorei(pname, param),
		// (pixels: the memory from p on, which WebGL fills as far as it needs)
		glReadPixels: (x, y, w, h, format, type, p) => gl.readPixels(x, y, w, h, format, type, new Uint8Array(host.memory().buffer, p)),
		glFinish: () => gl.finish(),
	};
	return { hxmc_gfx, hxmc_gl };
}
