// The JavaScript side of helder.canvas's web back end (WebCanvas), loaded
// by src/helder/os/browser.mjs: the imports of the module "hxmc_canvas".
// Each canvas a canvas element (in a worker an OffscreenCanvas; a handle); run() reads a buffer of
// commands (float64s: an opcode, its operands) and draws them with its 2D
// context; layers are canvases of their own, composited at their restore.
// host.options.onCanvas(handle, canvas), when given, sees each canvas made.
const OPS = ["clear", "copy", "destination", "source-over", "destination-over", "source-in", "destination-in", "source-out", "destination-out",
	"source-atop", "destination-atop", "xor", "lighter"];
const PD = { "0,0": "clear", "1,0": "copy", "0,1": "destination", "1,3": "source-over", "3,1": "destination-over", "2,0": "source-in",
	"0,2": "destination-in", "3,0": "source-out", "0,3": "destination-out", "2,3": "source-atop", "3,2": "destination-atop", "3,3": "xor", "1,1": "lighter" };
const MODES = ["multiply", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "hard-light", "soft-light", "difference", "exclusion",
	"hue", "saturation", "color", "luminosity"];

function operation(code) {
	if (code >= 1000) return "source-over";
	if (code >= 0) return MODES[code];
	const k = -1 - code;
	return PD[`${k >> 2},${k & 3}`];
}

function rgba(c, a = 1) {
	const al = ((c >>> 24) & 255) / 255 * a;
	return `rgba(${(c >> 16) & 255}, ${(c >> 8) & 255}, ${c & 255}, ${al})`;
}

export default function (host) {
	// (a page's canvas element where there is a document: Chromium's OffscreenCanvas clips without antialiasing; a worker's OffscreenCanvas)
	const make = (w, h) => typeof document !== "undefined" ? Object.assign(document.createElement("canvas"), { width: w, height: h }) : new OffscreenCanvas(w, h);
	const images = new Map();
	let nextImage = 1;
	const canvases = new Map();

	function argb(c) {
		return c < 0 ? c + 4294967296 : c;
	}

	const hxmc_canvas = {
		canvas_create(w, h) {
			const canvas = make(w, h);
			const ctx = canvas.getContext("2d");
			const h_ = host.handles.add({ canvas, ctx, stack: [], w, h });
			canvases.set(h_, true);
			host.options.onCanvas?.(h_, canvas);
			return h_;
		},
		canvas_image(w, h, p) {
			const src = host.bytes(p, w * h * 4), data = new Uint8ClampedArray(w * h * 4);
			for (let i = 0; i < w * h * 4; i += 4) {
				const a = src[i + 3];
				data[i + 3] = a;
				if (a === 0) continue;
				for (let k = 0; k < 3; k++) data[i + k] = Math.min(255, Math.round(src[i + k] * 255 / a));
			}
			const c = make(w, h);
			c.getContext("2d").putImageData(new ImageData(data, w, h), 0, 0);
			const id = nextImage++;
			images.set(id, c);
			return id;
		},
		canvas_read(handle, x, y, w, h, p) {
			const o = host.handles.get(handle);
			host.bytes(p, w * h * 4).set(o.ctx.getImageData(x, y, w, h).data);
		},
		canvas_write(handle, x, y, w, h, p) {
			const o = host.handles.get(handle);
			o.ctx.putImageData(new ImageData(new Uint8ClampedArray(host.bytes(p, w * h * 4).slice()), w, h), x, y);
		},
		canvas_filter(handle, p, n) {
			host.handles.get(handle).filter = new TextDecoder().decode(host.bytes(p, n).slice());
		},
		canvas_run(handle, p, n) {
			const o = host.handles.get(handle);
			const f = new Float64Array(host.memory().buffer.slice(p, p + n));
			let i = 0, path = null, paint = null, line = null, dash = [], dashOffset = 0;
			const m = [1, 0, 0, 1, 0, 0];
			const ctx = () => (o.stack.length > 0 && o.stack[o.stack.length - 1].layer) ? o.stack[o.stack.length - 1].layer.ctx : o.ctx;
			const top = () => {
				for (let k = o.stack.length - 1; k >= 0; k--) if (o.stack[k].layer) return o.stack[k].layer.ctx;
				return o.ctx;
			};
			function style(c) {
				c.globalAlpha = Math.min(1, paint.alpha);
				c.globalCompositeOperation = operation(paint.blend);
				if (paint.kind === 0) return rgba(paint.color);
				const g = paint.g, gm = paint.m;
				let s;
				if (paint.kind === 1) s = c.createLinearGradient(g[0], g[1], g[2], g[3]);
				else if (paint.kind === 2) s = c.createRadialGradient(g[0], g[1], g[2], g[3], g[4], g[5]);
				else if (paint.kind === 3) s = c.createConicGradient(g[0], g[1], g[2]);
				else {
					const img = images.get(g[0]);
					s = c.createPattern(img, g[1] && g[2] ? "repeat" : g[1] ? "repeat-x" : g[2] ? "repeat-y" : "no-repeat");
					s.setTransform(new DOMMatrix(gm));
					c.imageSmoothingEnabled = !!g[3];
					return s;
				}
				for (const [off, col] of paint.stops) s.addColorStop(off, rgba(col));
				return s;
			}
			// (a gradient placed by its own matrix: the path taken into its space, the transform through it)
			function place(c, p) {
				if (paint.kind < 1 || paint.kind > 3) return p;
				const gm = paint.m;
				if (gm[0] === 1 && gm[1] === 0 && gm[2] === 0 && gm[3] === 1 && gm[4] === 0 && gm[5] === 0) return p;
				c.transform(...gm);
				const q = new Path2D();
				q.addPath(p, new DOMMatrix(gm).inverse());
				return q;
			}
			while (i < f.length) {
				const code = f[i++];
				const c = top();
				switch (code) {
					case 1: c.save(); o.stack.push({}); break;
					case 2: {
						const s = o.stack.pop();
						if (s && s.layer) {
							const under = top();
							under.save();
							under.setTransform(1, 0, 0, 1, 0, 0);
							under.globalAlpha = s.layer.alpha;
							under.globalCompositeOperation = operation(s.layer.blend);
							if (s.layer.filter) under.filter = s.layer.filter;
							let src = s.layer.canvas;
							if (s.layer.mask) {
								const t = make(o.w, o.h), tc = t.getContext("2d");
								tc.drawImage(src, 0, 0);
								tc.globalCompositeOperation = "destination-in";
								tc.drawImage(images.get(s.layer.mask), 0, 0);
								src = t;
							}
							under.drawImage(src, 0, 0);
							under.restore();
						} else c.restore();
						break;
					}
					case 3: for (let k = 0; k < 6; k++) m[k] = f[i++]; break;
					case 4: c.setTransform(...m); c.clip(path, f[i++] ? "evenodd" : "nonzero"); break;
					case 5: {
						const rule = f[i++] ? "evenodd" : "nonzero";
						if (paint.blend === -2) break; // (Porter-Duff's destination: nothing drawn)
						c.save();
						c.setTransform(...m);
						const p2 = place(c, path);
						c.fillStyle = style(c);
						c.fill(p2, rule);
						c.restore();
						break;
					}
					case 6: {
						c.save();
						c.setTransform(...m);
						c.lineWidth = line[0];
						c.lineJoin = ["miter", "round", "bevel"][line[1]];
						c.lineCap = ["butt", "round", "square"][line[2]];
						c.miterLimit = line[3];
						c.setLineDash(dash);
						c.lineDashOffset = dashOffset;
						const p2 = place(c, path);
						c.strokeStyle = style(c);
						c.stroke(p2);
						c.restore();
						break;
					}
					case 7: c.save(); c.setTransform(...m); c.clearRect(f[i], f[i + 1], f[i + 2], f[i + 3]); c.restore(); i += 4; break;
					case 8: {
						const col = argb(f[i++]);
						c.save();
						c.setTransform(1, 0, 0, 1, 0, 0);
						c.globalCompositeOperation = "copy";
						c.fillStyle = rgba(col);
						c.fillRect(0, 0, o.w, o.h);
						c.restore();
						break;
					}
					case 9: {
						const img = images.get(f[i]), a = f.slice(i + 1, i + 9);
						c.save();
						c.setTransform(...m);
						c.globalAlpha = Math.min(1, f[i + 9]);
						c.globalCompositeOperation = operation(f[i + 10]);
						c.imageSmoothingEnabled = !!f[i + 11];
						c.drawImage(img, a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]);
						c.restore();
						i += 12;
						break;
					}
					case 10: {
						const canvas = make(o.w, o.h);
						c.save();
						o.stack.push({ layer: { canvas, ctx: canvas.getContext("2d"), alpha: f[i], blend: f[i + 1], mask: f[i + 2], filter: o.filter } });
						o.filter = null;
						i += 3;
						break;
					}
					case 11: {
						path = new Path2D();
						const verbs = f[i++];
						for (let v = 0; v < verbs; v++) {
							const k = f[i++];
							if (k === 0) path.moveTo(f[i++], f[i++]);
							else if (k === 1) path.lineTo(f[i++], f[i++]);
							else if (k === 2) { path.quadraticCurveTo(f[i], f[i + 1], f[i + 2], f[i + 3]); i += 4; }
							else if (k === 3) { path.bezierCurveTo(f[i], f[i + 1], f[i + 2], f[i + 3], f[i + 4], f[i + 5]); i += 6; }
							else path.closePath();
						}
						break;
					}
					case 12: {
						paint = { kind: f[i], color: argb(f[i + 1]), alpha: f[i + 2], blend: f[i + 3], m: Array.from(f.slice(i + 4, i + 10)), g: Array.from(f.slice(i + 10, i + 16)), spread: f[i + 16], stops: [] };
						i += 17;
						break;
					}
					case 13: paint.stops.push([f[i], argb(f[i + 1])]); i += 2; break;
					case 14: line = Array.from(f.slice(i, i + 4)); i += 4; break;
					case 15: {
						const count = f[i++];
						dashOffset = f[i++];
						dash = Array.from(f.slice(i, i + count));
						i += count;
						break;
					}
					default: throw new Error("hxmc_canvas: an unknown command " + code);
				}
			}
		},
	};
	return { hxmc_canvas };
}
