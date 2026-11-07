// The JavaScript side of helder.story.web.Preview (the module
// "helder_preview"), in the preview's worker (worker.mjs): its
// OffscreenCanvas, each frame transferred to the page as an ImageBitmap
// (run's option onFrame), the protocol's lines both ways (onLine; the
// worker's queue, options.preview.queue), the loop on the worker's
// animation frames (requestAnimationFrame where the worker has it, else a
// timer at 60 Hz).
const enc = new TextEncoder();

export default function (host) {
	const queue = host.options.preview?.queue ?? [];
	const schedule = typeof requestAnimationFrame === 'function' ? (f) => requestAnimationFrame(f) : (f) => setTimeout(f, 16);
	let stopped = false;
	host.preview = { stop: () => (stopped = true) };
	return {
		helder_preview: {
			canvas: () => host.handles.add(new OffscreenCanvas(1, 1)),
			resize(h, w, hh) {
				const c = host.handles.get(h);
				if (c.width !== w) c.width = w;
				if (c.height !== hh) c.height = hh;
			},
			present(h, screen, version, width, height) {
				const bitmap = host.handles.get(h).transferToImageBitmap();
				host.options.onFrame?.({ screen, version, width, height, bitmap });
			},
			send: (p) => host.options.onLine?.(host.string(p)),
			next: () => (queue.length ? host.handles.add(queue.shift()) : 0),
			text_length: (h) => enc.encode(host.handles.get(h)).length,
			text_take(h, p) {
				const b = enc.encode(host.handles.get(h));
				host.bytes(p, b.length + 1).set(b);
				host.bytes(p + b.length, 1)[0] = 0;
				host.handles.remove(h);
			},
			start(f) {
				const tick = () => {
					if (stopped || host.disposed) return;
					if (host.call(f) !== 0) schedule(tick);
				};
				schedule(tick);
			},
		},
	};
}
