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
// host.gfx.release() destroys the device and loses the WebGL contexts (a page
// done with the program); a device or context lost otherwise goes to run's
// option onError when given.
//
// Swapped out (hxmc dev, host.dispose(): packages/os/browser.mjs), the
// instance's GPU objects are released (what the program left too, counted:
// host.gfx.left), but the device and the canvases' contexts stay as they
// are, configured, showing the last frame: run's option gpu ({adapter,
// device}) gives the next instance the same device, and a canvas configured
// alike is not configured again (which would clear it). A WebGL2 context
// stays too (the same one for the next instance's getContext), its state
// set back to WebGL's defaults.
//
// host.gfx.backend is the API a device was created on ('webgpu', 'webgl2';
// null: none yet). Reading a frame back on WebGPU waits for the GPU, which a
// browser does asynchronously only: host.gfx.readPixels() resolves to
// {width, height, data} (RGBA8, rows top to bottom) of a headless target as
// it is now, or of a canvas's next frame (copied before it is presented);
// on WebGL2 the same, read synchronously (Device.readPixels works there too).
//
// run's option antialias (true: 4 samples a pixel) multisamples a canvas's
// frames: on WebGPU a multisampled colour and depth texture resolved into
// the canvas's, the frame's pipelines made for them; on WebGL2 the
// context's antialias. Render targets and headless targets stay single-
// sampled, and readPixels reads what is shown (resolved).
//
// WebGPU's textures: their TextureFormat's GPU format; a pipeline is made
// for its bind group layout reading every texture as filterable, and again
// (once, at the first draw binding one) for R32F or depth textures at some
// slots, read unfilterable; generate_mips draws each level from the one
// before (MIPS).

const FORMATS = ['float32', 'float32x2', 'float32x3', 'float32x4', 'unorm8x4']; // VertexFormat
const TOPOLOGIES = ['triangle-list', 'triangle-strip', 'line-list', 'point-list']; // Topology
const CULLS = ['none', 'front', 'back']; // Cull
const LOADS = ['clear', 'load', 'clear']; // LoadOp (DontCare: clear)
const COMPARES = ['never', 'less', 'equal', 'less-equal', 'greater', 'not-equal', 'greater-equal', 'always']; // Compare
const INDEX = ['uint16', 'uint32']; // IndexFormat
const WRAPS = ['repeat', 'clamp-to-edge', 'mirror-repeat']; // Wrap
// Blend: Opaque, Alpha, Additive, Premultiplied
const BLENDS = [
	undefined,
	{ color: { srcFactor: 'src-alpha', dstFactor: 'one-minus-src-alpha' }, alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' } },
	{ color: { srcFactor: 'src-alpha', dstFactor: 'one' }, alpha: { srcFactor: 'one', dstFactor: 'one' } },
	{ color: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' }, alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' } },
];
const INFO_LOG_LENGTH = 0x8b84; // (GL's, not WebGL's)
const RING = 256 * 1024; // the uniform ring (Encoder.UNIFORM_RING)
const UNIFORM = 0, TEXTURE = 1; // BindingKind
// TextureFormat: WebGPU's, bytes a texel; R32F and the depth formats are unfilterable from R32F on
const TEXTURE_FORMATS = ['rgba8unorm', 'rgba8unorm-srgb', 'r8unorm', 'rg8unorm', 'rgba16float', 'r32float', 'depth16unorm', 'depth32float'];
const TEXEL = [4, 4, 1, 2, 8, 4, 2, 4];
const R32F = 5, DEPTH16 = 6;
// generateMips: a level drawn from the one before, sampled at its texels' centres
const MIPS = `@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var smp: sampler;
struct V { @builtin(position) pos: vec4f, @location(0) uv: vec2f }
@vertex fn vs(@builtin(vertex_index) i: u32) -> V {
	let uv = vec2f(f32((i << 1u) & 2u), f32(i & 2u));
	return V(vec4f(uv * vec2f(2, -2) + vec2f(-1, 1), 0, 1), uv);
}
@fragment fn fs(v: V) -> @location(0) vec4f { return textureSampleLevel(src, smp, v.uv, 0.0); }`;

// (a canvas's WebGPU configuration, kept across instances: hxmc dev)
const configured = new WeakMap();

export default async function (host) {
	let adapter = null, device = null;
	try {
		if (host.options.gpu) ({ adapter, device } = host.options.gpu);
		else {
			adapter = host.options.gfx !== 'webgl2' && navigator.gpu && (await navigator.gpu.requestAdapter());
			device = adapter ? await adapter.requestDevice() : null;
		}
	} catch (e) {
		console.error('hxmc.gfx: no WebGPU device:', e);
	}
	if (device) device.addEventListener('uncapturederror', (e) => console.error('hxmc.gfx: WebGPU:', e.error.message));
	// (a device or context lost, but by release: run's option onError)
	let released = false;
	const lost = (what) => !released && !host.disposed && host.options.onError && host.options.onError(new Error(what));
	if (device) device.lost.then((info) => lost('the WebGPU device was lost' + (info.message ? ': ' + info.message : '')));
	const contexts = [];
	const { handles } = host;
	// a pipeline's vertex buffers and resources, as pipeline_buffer,
	// pipeline_attribute and pipeline_binding give them
	let layout = [], resources = [];
	// the frame
	let encoder = null, texture = null, frameTarget = null, frameView = null, pass = null;
	// generateMips: its pipeline per format, its sampler
	const mipPipelines = new Map();
	let mipSampler = null;
	// the uniform ring: the frame's blocks, copied at set_uniforms and written
	// to the GPU buffer before the frame's submit (which the queue orders
	// after the previous frames' reads); each slot's offset, for the bind group
	const ring = device ? { buffer: device.createBuffer({ size: RING, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST }), staging: new Uint8Array(RING), used: 0 } : null;
	const offsets = new Uint32Array(16);
	// each slot's texture and sampler (handles)
	const textures = new Int32Array(16), samplers = new Int32Array(16);
	// the pipeline set (its bind group layout and groups), and whether its bind group needs setting
	let pipe = null, dirty = false;
	const attachment = { view: null, loadOp: 'clear', storeOp: 'store', clearValue: { r: 0, g: 0, b: 0, a: 1 } };
	const depthAttachment = { view: null, depthLoadOp: 'clear', depthStoreOp: 'store', depthClearValue: 1 };
	const passDesc = { colorAttachments: [attachment], depthStencilAttachment: depthAttachment };
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
		// the GPU's memory given back: the device destroyed, the WebGL contexts lost
		release() {
			released = true;
			if (device) device.destroy();
			for (const g of contexts) g.getExtension('WEBGL_lose_context')?.loseContext();
			contexts.length = 0;
		},
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

	// the current pipeline's bind group, with the slots' uniform offsets (a
	// group per set of textures, made once)
	function bind() {
		if (!dirty) return;
		dirty = false;
		// (an unfilterable texture bound: the pipeline made for those slots)
		let mask = 0;
		for (const t of pipe.textures) if (handles.get(textures[t.slot])?.unfilterable) mask |= 1 << t.slot;
		const c = pipe.variants.get(mask) ?? variant(pipe, mask);
		if (c !== pipe.active) {
			pipe.active = c;
			pass.setPipeline(c.pipeline);
		}
		let key = '';
		for (const t of c.textures) key += textures[t.slot] + ':' + samplers[t.slot] + ',';
		let group = c.groups.get(key);
		if (!group) {
			const entries = c.uniforms.map((u) => ({ binding: u.slot, resource: { buffer: ring.buffer, size: u.size } }));
			for (const t of c.textures) {
				entries.push({ binding: t.slot, resource: handles.get(textures[t.slot]).view }, { binding: 16 + t.slot, resource: handles.get(samplers[t.slot]) });
			}
			group = device.createBindGroup({ layout: c.bgl, entries });
			c.groups.set(key, group);
		}
		for (let i = 0; i < c.uniforms.length; i++) c.offsets[i] = offsets[c.uniforms[i].slot];
		pass.setBindGroup(0, group, c.offsets);
	}

	// a pipeline's bind group layout: uniform blocks at dynamic offsets, a
	// texture at its slot and its sampler at 16 + slot (in mask: an
	// unfilterable texture and a non-filtering sampler)
	function bindGroupLayout(resources, mask) {
		const visibility = GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT;
		const entries = [];
		for (const r of resources)
			if (r.kind === UNIFORM) entries.push({ binding: r.slot, visibility, buffer: { type: 'uniform', hasDynamicOffset: true, minBindingSize: r.size } });
			else {
				const plain = (mask & (1 << r.slot)) === 0;
				entries.push({ binding: r.slot, visibility, texture: { sampleType: plain ? 'float' : 'unfilterable-float' } }, { binding: 16 + r.slot, visibility, sampler: { type: plain ? 'filtering' : 'non-filtering' } });
			}
		return entries.length ? device.createBindGroupLayout({ entries }) : null;
	}

	// the pipeline p for unfilterable textures at the slots of mask
	function variant(p, mask) {
		const bgl = bindGroupLayout(p.resources, mask);
		const v = { ...p.base, pipeline: device.createRenderPipeline({ ...p.desc, layout: device.createPipelineLayout({ bindGroupLayouts: [bgl] }) }), bgl, groups: new Map() };
		p.variants.set(mask, v);
		return v;
	}

	const hxmc_gfx = {
		ready: () => (device ? 1 : 0),
		target_canvas(canvas) {
			host.gfx.backend = 'webgpu';
			const context = handles.get(canvas).getContext('webgpu');
			const format = navigator.gpu.getPreferredCanvasFormat();
			// (COPY_SRC: readPixels; configured alike by an earlier instance: as it is, its last frame shown)
			const c = configured.get(context);
			if (!c || c.device !== device || c.format !== format) {
				context.configure({ device, format, usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC, alphaMode: 'opaque' });
				configured.set(context, { device, format });
			}
			return handles.add({ context, format, samples: host.options.antialias ? 4 : 1 });
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
		write_buffer: (b, offset, data, size) => device.queue.writeBuffer(handles.get(b), offset, host.bytes(data, size)),
		texture(width, height, format, levels, target, data) {
			// (a mip chain's levels are drawn by generate_mips)
			const usage = GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST | (target || (levels > 1 && format < R32F) ? GPUTextureUsage.RENDER_ATTACHMENT : 0);
			const texture = device.createTexture({ size: [width, height], format: TEXTURE_FORMATS[format], mipLevelCount: levels, usage });
			const t = { texture, view: texture.createView(), target: target ? texture.createView({ mipLevelCount: 1 }) : null, texel: TEXEL[format], unfilterable: format >= R32F, depth: format >= DEPTH16 };
			if (data) device.queue.writeTexture({ texture }, host.bytes(data, width * height * t.texel), { bytesPerRow: width * t.texel }, [width, height]);
			return handles.add(t);
		},
		write_texture(h, x, y, w, height, level, data) {
			const t = handles.get(h);
			device.queue.writeTexture({ texture: t.texture, mipLevel: level, origin: [x, y] }, host.bytes(data, w * height * t.texel), { bytesPerRow: w * t.texel }, [w, height]);
		},
		generate_mips(h) {
			const t = handles.get(h), { texture } = t;
			let pipeline = mipPipelines.get(texture.format);
			if (!pipeline) {
				const module = device.createShaderModule({ code: MIPS });
				pipeline = device.createRenderPipeline({ layout: 'auto', vertex: { module, entryPoint: 'vs' }, fragment: { module, entryPoint: 'fs', targets: [{ format: texture.format }] } });
				mipPipelines.set(texture.format, pipeline);
				mipSampler ??= device.createSampler({ magFilter: 'linear', minFilter: 'linear' });
			}
			// (each level's view and the bind group reading the one before, made once)
			if (!t.mips) {
				const views = [];
				for (let i = 0; i < texture.mipLevelCount; i++) views.push(texture.createView({ baseMipLevel: i, mipLevelCount: 1 }));
				t.mips = views.slice(1).map((view, i) => ({
					attachments: [{ view, loadOp: 'clear', storeOp: 'store', clearValue: { r: 0, g: 0, b: 0, a: 0 } }],
					group: device.createBindGroup({ layout: pipeline.getBindGroupLayout(0), entries: [{ binding: 0, resource: views[i] }, { binding: 1, resource: mipSampler }] }),
				}));
			}
			const enc = encoder ?? device.createCommandEncoder();
			for (const m of t.mips) {
				const p = enc.beginRenderPass({ colorAttachments: m.attachments });
				p.setPipeline(pipeline);
				p.setBindGroup(0, m.group);
				p.draw(3);
				p.end();
			}
			if (!encoder) device.queue.submit([enc.finish()]);
		},
		sampler(filter, mip, wrap) {
			const f = filter ? 'linear' : 'nearest', w = WRAPS[wrap];
			return handles.add(device.createSampler({ magFilter: f, minFilter: f, mipmapFilter: mip === 2 ? 'linear' : 'nearest', lodMaxClamp: mip ? 32 : 0, addressModeU: w, addressModeV: w }));
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
			resources = [];
		},
		pipeline_buffer(stride, instance) {
			layout.push({ arrayStride: stride, stepMode: instance ? 'instance' : 'vertex', attributes: [] });
		},
		pipeline_attribute(location, format, offset) {
			layout[layout.length - 1].attributes.push({ shaderLocation: location, format: FORMATS[format], offset });
		},
		pipeline_binding(slot, kind, size) {
			resources.push({ slot, kind, size });
		},
		pipeline_end(vertex, fragment, target, topology, cull, blend, depthCompare, depthWrite, colorFormat, depthFormat) {
			const uniforms = resources.filter((r) => r.kind === UNIFORM).sort((a, b) => a.slot - b.slot);
			const bgl = bindGroupLayout(resources, 0);
			const desc = {
				vertex: { module: handles.get(vertex), entryPoint: 'main', buffers: layout },
				fragment: { module: handles.get(fragment), entryPoint: 'main', targets: [{ format: colorFormat < 0 ? handles.get(target).format : TEXTURE_FORMATS[colorFormat], blend: BLENDS[blend] }] },
				depthStencil: depthFormat < 0 ? undefined : { format: TEXTURE_FORMATS[depthFormat], depthWriteEnabled: !!depthWrite, depthCompare: COMPARES[depthCompare] },
				// (GL's front faces)
				primitive: { topology: TOPOLOGIES[topology], cullMode: CULLS[cull], frontFace: 'ccw' },
				// (the frame's: its samples)
				multisample: { count: colorFormat < 0 ? handles.get(target).samples ?? 1 : 1 },
			};
			const pipeline = device.createRenderPipeline({ ...desc, layout: bgl ? device.createPipelineLayout({ bindGroupLayouts: [bgl] }) : 'auto' });
			// (base: what its variants share, variant())
			const base = { uniforms, textures: resources.filter((r) => r.kind === TEXTURE), offsets: new Uint32Array(uniforms.length) };
			const p = { ...base, pipeline, bgl, groups: new Map(), base, desc, resources, variants: new Map(), active: null };
			p.variants.set(0, p);
			return handles.add(p);
		},
		frame_begin(target) {
			const t = handles.get(target);
			texture = t.texture ?? t.context.getCurrentTexture();
			if (texture.width === 0 || texture.height === 0) return 0;
			frameTarget = t;
			frameView = texture.createView();
			// (the depth buffer, of the target's size and samples; multisampled,
			// the colour texture resolved into the target's)
			if (!t.depth || t.depth.width !== texture.width || t.depth.height !== texture.height) {
				const size = [texture.width, texture.height], sampleCount = t.samples ?? 1, usage = GPUTextureUsage.RENDER_ATTACHMENT;
				t.depth?.destroy();
				t.msaa?.destroy();
				t.depth = device.createTexture({ size, format: 'depth32float', sampleCount, usage });
				t.depthView = t.depth.createView();
				t.msaa = sampleCount > 1 ? device.createTexture({ size, format: t.format, sampleCount, usage }) : null;
				t.msaaView = t.msaa?.createView();
			}
			depthAttachment.view = t.depthView;
			encoder = device.createCommandEncoder();
			return 1;
		},
		pass_begin(color, load, r, g, b, a, depthTexture, depthLoad, depth) {
			// (a render target: its first level, and its depth texture or none)
			const t = color ? handles.get(color) : null, d = depthTexture ? handles.get(depthTexture) : null;
			attachment.view = t ? t.target : frameTarget.msaaView ?? frameView;
			attachment.resolveTarget = !t && frameTarget.msaa ? frameView : undefined;
			attachment.loadOp = LOADS[load];
			depthAttachment.view = t ? d?.target : frameTarget.depthView;
			passDesc.depthStencilAttachment = depthAttachment.view ? depthAttachment : undefined;
			depthAttachment.depthLoadOp = LOADS[depthLoad];
			depthAttachment.depthClearValue = depth;
			const c = attachment.clearValue;
			c.r = r;
			c.g = g;
			c.b = b;
			c.a = a;
			pass = encoder.beginRenderPass(passDesc);
			const size = t ? t.texture : texture;
			pass.setViewport(0, 0, size.width, size.height, 0, 1);
		},
		set_pipeline(p) {
			pipe = handles.get(p);
			pipe.active = pipe;
			pass.setPipeline(pipe.pipeline);
			dirty = !!pipe.bgl;
		},
		set_vertex_buffer: (slot, b, offset) => pass.setVertexBuffer(slot, handles.get(b), offset),
		set_texture(slot, t, s) {
			textures[slot] = t;
			samplers[slot] = s;
			dirty = true;
		},
		set_uniforms(slot, offset, data, size) {
			ring.staging.set(host.bytes(data, size), offset);
			ring.used = Math.max(ring.used, offset + size);
			offsets[slot] = offset;
			dirty = true;
		},
		set_index_buffer: (b, format, offset) => pass.setIndexBuffer(handles.get(b), INDEX[format], offset),
		draw(vertices, instances, first) {
			bind();
			pass.draw(vertices, instances, first, 0);
		},
		draw_indexed(count, instances, first, baseVertex) {
			bind();
			pass.drawIndexed(count, instances, first, baseVertex, 0);
		},
		pass_end() {
			pass.end();
			pass = null;
		},
		frame_end() {
			// (a readPixels waiting for a canvas's frame)
			const waiting = captures;
			captures = [];
			const pixels = waiting.length ? copy(encoder, texture, frameTarget.format) : null;
			if (ring.used) device.queue.writeBuffer(ring.buffer, 0, ring.staging, 0, Math.ceil(ring.used / 4) * 4);
			ring.used = 0;
			device.queue.submit([encoder.finish()]);
			pixels?.().then((px) => waiting.forEach((w) => w.resolve(px)), (e) => waiting.forEach((w) => w.reject(e)));
			encoder = null;
			attachment.view = attachment.resolveTarget = frameView = null;
			depthAttachment.view = null;
			texture = null;
		},
		release(h) {
			const o = handles.get(h);
			o?.destroy?.();
			o?.texture?.destroy();
			// (a target's depth and multisampled textures; a texture's depth is whether it is one)
			o?.depth?.destroy?.();
			o?.msaa?.destroy?.();
			// (swapped out: the canvas stays configured, its last frame shown)
			if (o?.context && !host.swapping) {
				o.context.unconfigure();
				configured.delete(o.context);
			}
			handles.remove(h);
		},
	};

	// (hxmc dev: swapped out; what the program did not release, released and counted)
	host.onDispose?.(() => {
		let left = 0;
		const glObject = typeof WebGLObject === 'function' ? WebGLObject : null;
		for (const g of contexts) resetGL(g);
		for (let h = 1; h < handles.size(); h++) {
			const o = handles.get(h);
			if (!o) continue;
			if (typeof GPUBuffer === 'function' && (o instanceof GPUBuffer || o instanceof GPUTexture)) {
				o.destroy();
				left++;
			} else if (o.texture instanceof Object && typeof o.texture.destroy === 'function') {
				o.texture.destroy();
				o.depth?.destroy?.();
				o.msaa?.destroy?.();
				left++;
			} else if (o.context && typeof GPUCanvasContext === 'function' && o.context instanceof GPUCanvasContext) {
				o.depth?.destroy?.();
				o.msaa?.destroy?.();
				left++;
			} else if (glObject && o instanceof glObject && gl) {
				const d = o instanceof WebGLBuffer ? 'deleteBuffer' : o instanceof WebGLTexture ? 'deleteTexture' : o instanceof WebGLProgram ? 'deleteProgram'
					: o instanceof WebGLShader ? 'deleteShader' : o instanceof WebGLFramebuffer ? 'deleteFramebuffer' : o instanceof WebGLVertexArrayObject ? 'deleteVertexArray'
					: o instanceof WebGLSampler ? 'deleteSampler' : o instanceof WebGLRenderbuffer ? 'deleteRenderbuffer' : null;
				if (d) {
					gl[d](o);
					left++;
				}
			}
		}
		ring?.buffer.destroy();
		host.gfx.left = left;
		if (left > 0) console.warn(`hxmc.gfx: ${left} GPU objects left by the build swapped out, released`);
	});

	// a context's state as WebGL's defaults: what the next instance finds
	function resetGL(g) {
		if (g.isContextLost()) return;
		g.bindFramebuffer(g.FRAMEBUFFER, null);
		g.bindBuffer(g.ARRAY_BUFFER, null);
		g.bindBuffer(g.ELEMENT_ARRAY_BUFFER, null);
		g.bindBuffer(g.UNIFORM_BUFFER, null);
		g.bindVertexArray(null);
		g.useProgram(null);
		const units = g.getParameter(g.MAX_COMBINED_TEXTURE_IMAGE_UNITS);
		for (let i = 0; i < Math.min(units, 32); i++) {
			g.activeTexture(g.TEXTURE0 + i);
			g.bindTexture(g.TEXTURE_2D, null);
			g.bindSampler(i, null);
		}
		g.activeTexture(g.TEXTURE0);
		for (const cap of [g.BLEND, g.CULL_FACE, g.DEPTH_TEST, g.SCISSOR_TEST, g.STENCIL_TEST, g.POLYGON_OFFSET_FILL]) g.disable(cap);
		g.blendFunc(g.ONE, g.ZERO);
		g.blendEquation(g.FUNC_ADD);
		g.depthFunc(g.LESS);
		g.depthMask(true);
		g.colorMask(true, true, true, true);
		g.clearColor(0, 0, 0, 0);
		g.clearDepth(1);
		g.cullFace(g.BACK);
		g.frontFace(g.CCW);
		g.pixelStorei(g.UNPACK_ALIGNMENT, 4);
		g.pixelStorei(g.PACK_ALIGNMENT, 4);
		g.viewport(0, 0, g.drawingBufferWidth, g.drawingBufferHeight);
	}

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
			const g = c.getContext('webgl2', { antialias: !offscreen && !!host.options.antialias, alpha: false, depth: true, preserveDrawingBuffer: offscreen });
			if (!g) return 0;
			// (RGBA16F and R32F render targets)
			g.getExtension('EXT_color_buffer_float');
			contexts.push(g);
			if (!offscreen) c.addEventListener('webglcontextlost', () => lost('the WebGL2 context was lost'));
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
			// (swapped out: a canvas's context stays, its last frame shown, for the next instance)
			if (!(host.swapping && !c.offscreen)) c.gl.getExtension('WEBGL_lose_context')?.loseContext();
			else contexts.splice(contexts.indexOf(c.gl), 1), resetGL(c.gl);
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
		glDeleteTextures: (n, p) => del(n, p, (t) => gl.deleteTexture(t)),
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
		glVertexAttribDivisor: (i, divisor) => gl.vertexAttribDivisor(i, divisor),
		glDrawArrays: (mode, first, count) => gl.drawArrays(mode, first, count),
		glDrawArraysInstanced: (mode, first, count, instances) => gl.drawArraysInstanced(mode, first, count, instances),
		// (offset: a byte offset into the index buffer)
		glDrawElements: (mode, count, type, offset) => gl.drawElements(mode, count, type, offset),
		glDrawElementsInstanced: (mode, count, type, offset, instances) => gl.drawElementsInstanced(mode, count, type, offset, instances),
		glGetIntegerv: (pname, p) => view().setInt32(p, gl.getParameter(pname), true),
		glBindBufferRange: (target, index, b, offset, size) => gl.bindBufferRange(target, index, get(b), Number(offset), Number(size)),
		glGetUniformBlockIndex: (p, name) => gl.getUniformBlockIndex(get(p), host.string(name)) | 0,
		glUniformBlockBinding: (p, index, binding) => gl.uniformBlockBinding(get(p), index >>> 0, binding),
		// (a location: a handle, -1 none; each lookup a new one, as a program's are looked up once)
		glGetUniformLocation(p, name) {
			const l = gl.getUniformLocation(get(p), host.string(name));
			return l ? handles.add(l) : -1;
		},
		glUniform1i: (l, x) => gl.uniform1i(get(l), x),
		glUniform1f: (l, x) => gl.uniform1f(get(l), x),
		glUniform2f: (l, x, y) => gl.uniform2f(get(l), x, y),
		glBlendFuncSeparate: (a, b, c, d) => gl.blendFuncSeparate(a, b, c, d),
		glBlendEquation: (mode) => gl.blendEquation(mode),
		glDepthFunc: (f) => gl.depthFunc(f),
		glDepthMask: (flag) => gl.depthMask(!!flag),
		glClearDepthf: (d) => gl.clearDepth(d),
		glGenTextures: (n, p) => gen(n, p, () => gl.createTexture()),
		glBindTexture: (target, t) => gl.bindTexture(target, get(t)),
		glActiveTexture: (unit) => gl.activeTexture(unit),
		glTexStorage2D: (target, levels, internal, w, h) => gl.texStorage2D(target, levels, internal, w, h),
		// (pixels: w * h texels of the memory, in the view WebGL wants for the type, copied for floats: their address may be unaligned)
		glTexSubImage2D(target, level, x, y, w, h, format, type, p) {
			const n = w * h * (format === gl.RED ? 1 : format === gl.RG ? 2 : 4), size = type === gl.FLOAT ? 4 : type === gl.HALF_FLOAT ? 2 : 1;
			const b = host.bytes(p, n * size);
			gl.texSubImage2D(target, level, x, y, w, h, format, type, size === 1 ? b : new (size === 4 ? Float32Array : Uint16Array)(b.slice().buffer));
		},
		glGenerateMipmap: (target) => gl.generateMipmap(target),
		glGenFramebuffers: (n, p) => gen(n, p, () => gl.createFramebuffer()),
		glDeleteFramebuffers: (n, p) => del(n, p, (f) => gl.deleteFramebuffer(f)),
		glBindFramebuffer: (target, f) => gl.bindFramebuffer(target, get(f)),
		glFramebufferTexture2D: (target, attachment, textarget, t, level) => gl.framebufferTexture2D(target, attachment, textarget, get(t), level),
		glCheckFramebufferStatus: (target) => gl.checkFramebufferStatus(target),
		glGenSamplers: (n, p) => gen(n, p, () => gl.createSampler()),
		glDeleteSamplers: (n, p) => del(n, p, (s) => gl.deleteSampler(s)),
		glDeleteVertexArrays: (n, p) => del(n, p, (a) => gl.deleteVertexArray(a)),
		glSamplerParameteri: (s, pname, param) => gl.samplerParameteri(get(s), pname, param),
		glBindSampler: (unit, s) => gl.bindSampler(unit, get(s)),
		glPixelStorei: (pname, param) => gl.pixelStorei(pname, param),
		// (pixels: the memory from p on, which WebGL fills as far as it needs)
		glReadPixels: (x, y, w, h, format, type, p) => gl.readPixels(x, y, w, h, format, type, new Uint8Array(host.memory().buffer, p)),
		glFinish: () => gl.finish(),
	};
	return { hxmc_gfx, hxmc_gl };
}
