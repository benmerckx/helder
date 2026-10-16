// The JavaScript side of hxmc.gfx's WebGPU back end: the imports of the
// module "hxmc_gfx" (src/hxmc/gfx/webgpu/WebGPU.hx), loaded by
// packages/os/browser.mjs with packages/os/imports.mjs. The adapter and the
// device are requested before the module starts; without them (no
// navigator.gpu, no adapter) ready() is 0 and Device.create throws. GPU
// objects live in the loader's handle table; the enums are hxmc.gfx's.
//
// Reading a frame back waits for the GPU, which a browser does
// asynchronously only: host.gfx.readPixels() resolves to {width, height,
// data} (RGBA8, rows top to bottom) of a headless target as it is now, or of
// a canvas's next frame (copied before it is presented).

const FORMATS = ['float32', 'float32x2', 'float32x3', 'float32x4', 'unorm8x4']; // VertexFormat
const TOPOLOGIES = ['triangle-list', 'triangle-strip', 'line-list', 'point-list']; // Topology
const CULLS = ['none', 'front', 'back']; // Cull
const LOADS = ['clear', 'load', 'clear']; // LoadOp (DontCare: clear)

export default async function (host) {
	let adapter = null, device = null;
	try {
		adapter = navigator.gpu && (await navigator.gpu.requestAdapter());
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
		readPixels() {
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
			const context = handles.get(canvas).getContext('webgpu');
			const format = navigator.gpu.getPreferredCanvasFormat();
			// (COPY_SRC: readPixels)
			context.configure({ device, format, usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC, alphaMode: 'opaque' });
			return handles.add({ context, format });
		},
		target_texture(width, height) {
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
	return { hxmc_gfx };
}
