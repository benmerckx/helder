// The sky behind everything: three layers of stars drifting with the pointer
// (or the phone's tilt), a nebula, the orbits of the universe view, and the
// warp: stars stretch into streaks while the compiler works (app.js bumps
// it for every file the compiler opens) and when entering a world.
//
//   const s = sky(canvas);
//   s.orbits = [{cx, cy, rx, ry, color}];   // drawn each frame
//   s.kick(0.4);                            // a burst of warp (decays)
//   s.calm = true;                          // a program runs: fewer frames

export function sky(canvas) {
	const ctx = canvas.getContext('2d');
	const reduced = matchMedia('(prefers-reduced-motion: reduce)');
	let w = 0, h = 0, dpr = 1, nebula = null;
	const stars = [];
	let warp = 0, target = 0, tx = 0, ty = 0, px = 0, py = 0, last = performance.now(), frame = 0;
	const state = { orbits: [], calm: false, kick, hold };

	function resize() {
		dpr = Math.min(devicePixelRatio || 1, 2);
		w = innerWidth;
		h = innerHeight;
		canvas.width = Math.round(w * dpr);
		canvas.height = Math.round(h * dpr);
		const n = Math.round(Math.min(900, (w * h) / 2200));
		stars.length = 0;
		for (let i = 0; i < n; i++) {
			const z = Math.random();
			stars.push({
				x: (Math.random() - 0.5) * 2,
				y: (Math.random() - 0.5) * 2,
				z: 0.15 + z * 0.85,
				hue: Math.random() < 0.15 ? 200 + Math.random() * 140 : 220,
				tw: Math.random() * Math.PI * 2,
			});
		}
		nebula = paintNebula();
	}

	// soft clouds, painted once at a quarter of the size
	function paintNebula() {
		const c = document.createElement('canvas');
		c.width = Math.max(1, Math.round(w / 4));
		c.height = Math.max(1, Math.round(h / 4));
		const g = c.getContext('2d');
		const blobs = [
			[0.18, 0.25, 0.55, 'rgba(124, 58, 237, 0.35)'],
			[0.85, 0.2, 0.45, 'rgba(14, 165, 233, 0.22)'],
			[0.7, 0.85, 0.6, 'rgba(236, 72, 153, 0.18)'],
			[0.3, 0.9, 0.4, 'rgba(20, 184, 166, 0.16)'],
		];
		for (const [x, y, r, col] of blobs) {
			const rad = r * Math.max(c.width, c.height);
			const gr = g.createRadialGradient(x * c.width, y * c.height, 0, x * c.width, y * c.height, rad);
			gr.addColorStop(0, col);
			gr.addColorStop(1, 'rgba(0,0,0,0)');
			g.fillStyle = gr;
			g.fillRect(0, 0, c.width, c.height);
		}
		return c;
	}

	function kick(v) {
		if (reduced.matches) return;
		warp = Math.min(1.6, warp + v);
	}
	// a steady warp while something runs (0: none)
	function hold(v) {
		target = reduced.matches ? 0 : v;
	}

	addEventListener('resize', resize);
	addEventListener('pointermove', (e) => {
		tx = (e.clientX / w - 0.5) * 2;
		ty = (e.clientY / h - 0.5) * 2;
	}, { passive: true });
	addEventListener('deviceorientation', (e) => {
		if (e.gamma == null) return;
		tx = Math.max(-1, Math.min(1, e.gamma / 30));
		ty = Math.max(-1, Math.min(1, (e.beta - 40) / 30));
	}, { passive: true });

	function draw(now) {
		requestAnimationFrame(draw);
		const dt = Math.min(0.05, (now - last) / 1000);
		// (calm: a program has the GPU; 15 frames a second unless warping)
		if (state.calm && warp < 0.02 && target === 0 && frame++ % 4 !== 0) return;
		last = now;
		warp += (target - warp) * Math.min(1, dt * 2.5);
		px += (tx - px) * Math.min(1, dt * 2);
		py += (ty - py) * Math.min(1, dt * 2);
		ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
		ctx.fillStyle = '#04050d';
		ctx.fillRect(0, 0, w, h);
		ctx.globalAlpha = 0.9;
		ctx.drawImage(nebula, -px * 12, -py * 12, w + 24, h + 24);
		ctx.globalAlpha = 1;

		const cx = w / 2, cy = h / 2, span = Math.max(w, h) * 0.6;
		const speed = reduced.matches ? 0 : 0.012 + warp * 1.4;
		for (const s of stars) {
			s.z -= speed * dt * s.z * 2.2;
			if (s.z < 0.05) {
				s.z = 1;
				s.x = (Math.random() - 0.5) * 2;
				s.y = (Math.random() - 0.5) * 2;
			}
			const k = 1 / s.z;
			const x = cx + (s.x * span - px * 30 * (1 - s.z)) * k * 0.35;
			const y = cy + (s.y * span - py * 30 * (1 - s.z)) * k * 0.35;
			if (x < -50 || x > w + 50 || y < -50 || y > h + 50) {
				s.z = 1;
				continue;
			}
			const b = Math.min(1, (1 - s.z) * 1.3) * (0.75 + 0.25 * Math.sin(now / 600 + s.tw));
			const r = Math.max(0.4, (1 - s.z) * 1.8);
			if (warp > 0.05) {
				// (a streak toward the centre, its length the warp)
				const len = warp * 60 * (1 - s.z);
				const dx = x - cx, dy = y - cy, d = Math.hypot(dx, dy) || 1;
				ctx.strokeStyle = `hsla(${s.hue}, 90%, 85%, ${b})`;
				ctx.lineWidth = r;
				ctx.beginPath();
				ctx.moveTo(x, y);
				ctx.lineTo(x - (dx / d) * len, y - (dy / d) * len);
				ctx.stroke();
			} else {
				ctx.fillStyle = `hsla(${s.hue}, 90%, 88%, ${b})`;
				ctx.beginPath();
				ctx.arc(x, y, r, 0, Math.PI * 2);
				ctx.fill();
			}
		}

		for (const o of state.orbits) {
			ctx.strokeStyle = o.color;
			ctx.globalAlpha = 0.28;
			ctx.lineWidth = 1;
			ctx.setLineDash([2, 6]);
			ctx.beginPath();
			ctx.ellipse(o.cx, o.cy, o.rx, o.ry, 0, 0, Math.PI * 2);
			ctx.stroke();
		}
		ctx.setLineDash([]);
		ctx.globalAlpha = 1;
	}

	resize();
	requestAnimationFrame(draw);
	return state;
}
