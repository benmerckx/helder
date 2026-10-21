import js.Browser.document;
import js.Browser.window;
import js.html.CanvasElement;
import js.html.CanvasRenderingContext2D;

typedef Orbit = {cx:Float, cy:Float, rx:Float, ry:Float, color:String};

private typedef Star = {x:Float, y:Float, z:Float, hue:Float, tw:Float};

// The sky behind everything: three layers of stars drifting with the
// pointer (or the phone's tilt), a nebula, the orbits of the universe view,
// and the warp: stars stretch into streaks while the compiler works (the
// forge bumps it for every file the compiler opens) and when entering a
// world. calm: a program runs and has the GPU, so the sky draws less often.
class Sky {
	public var orbits:Array<Orbit> = [];
	public var calm = false;

	final canvas:CanvasElement;
	final ctx:CanvasRenderingContext2D;
	final stars:Array<Star> = [];
	final reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
	var w = 0.0;
	var h = 0.0;
	var dpr = 1.0;
	var nebula:CanvasElement;
	var warp = 0.0;
	var target = 0.0;
	var tx = 0.0;
	var ty = 0.0;
	var px = 0.0;
	var py = 0.0;
	var last = 0.0;
	var frame = 0;

	public function new(canvas:CanvasElement) {
		this.canvas = canvas;
		ctx = canvas.getContext2d();
		resize();
		window.addEventListener("resize", resize);
		window.addEventListener("pointermove", (e:js.html.PointerEvent) -> {
			tx = (e.clientX / w - 0.5) * 2;
			ty = (e.clientY / h - 0.5) * 2;
		}, {passive: true});
		window.addEventListener("deviceorientation", (e:js.html.DeviceOrientationEvent) -> {
			if (e.gamma == null) return;
			tx = Math.max(-1, Math.min(1, e.gamma / 30));
			ty = Math.max(-1, Math.min(1, (e.beta - 40) / 30));
		}, {passive: true});
		window.requestAnimationFrame(draw);
	}

	// a burst of warp, which decays
	public function kick(v:Float)
		if (!reduced.matches) warp = Math.min(1.6, warp + v);

	// a steady warp while something runs (0: none)
	public function hold(v:Float)
		target = reduced.matches ? 0 : v;

	function resize() {
		dpr = Math.min(window.devicePixelRatio, 2);
		w = window.innerWidth;
		h = window.innerHeight;
		canvas.width = Math.round(w * dpr);
		canvas.height = Math.round(h * dpr);
		stars.resize(0);
		for (_ in 0...Math.round(Math.min(900, w * h / 2200)))
			stars.push({
				x: (Math.random() - 0.5) * 2,
				y: (Math.random() - 0.5) * 2,
				z: 0.15 + Math.random() * 0.85,
				hue: Math.random() < 0.15 ? 200 + Math.random() * 140 : 220,
				tw: Math.random() * Math.PI * 2,
			});
		nebula = paintNebula();
	}

	// soft clouds, painted once at a quarter of the size
	function paintNebula():CanvasElement {
		var c = document.createCanvasElement();
		c.width = Std.int(Math.max(1, w / 4));
		c.height = Std.int(Math.max(1, h / 4));
		var g = c.getContext2d();
		var blobs:Array<Array<Dynamic>> = [
			[0.18, 0.25, 0.55, "rgba(124, 58, 237, 0.35)"],
			[0.85, 0.2, 0.45, "rgba(14, 165, 233, 0.22)"],
			[0.7, 0.85, 0.6, "rgba(236, 72, 153, 0.18)"],
			[0.3, 0.9, 0.4, "rgba(20, 184, 166, 0.16)"],
		];
		for (b in blobs) {
			var x:Float = b[0], y:Float = b[1], r:Float = b[2];
			var rad = r * Math.max(c.width, c.height);
			var gr = g.createRadialGradient(x * c.width, y * c.height, 0, x * c.width, y * c.height, rad);
			gr.addColorStop(0, b[3]);
			gr.addColorStop(1, "rgba(0,0,0,0)");
			g.fillStyle = gr;
			g.fillRect(0, 0, c.width, c.height);
		}
		return c;
	}

	function draw(now:Float) {
		window.requestAnimationFrame(draw);
		var dt = Math.min(0.05, (now - last) / 1000);
		// (calm: 15 frames a second unless warping)
		if (calm && warp < 0.02 && target == 0 && frame++ % 4 != 0) return;
		last = now;
		warp += (target - warp) * Math.min(1, dt * 2.5);
		px += (tx - px) * Math.min(1, dt * 2);
		py += (ty - py) * Math.min(1, dt * 2);
		ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
		ctx.fillStyle = "#04050d";
		ctx.fillRect(0, 0, w, h);
		ctx.globalAlpha = 0.9;
		ctx.drawImage(nebula, -px * 12, -py * 12, w + 24, h + 24);
		ctx.globalAlpha = 1;

		var cx = w / 2, cy = h / 2, span = Math.max(w, h) * 0.6;
		var speed = reduced.matches ? 0 : 0.012 + warp * 1.4;
		for (s in stars) {
			s.z -= speed * dt * s.z * 2.2;
			if (s.z < 0.05) {
				s.z = 1;
				s.x = (Math.random() - 0.5) * 2;
				s.y = (Math.random() - 0.5) * 2;
			}
			var k = 1 / s.z;
			var x = cx + (s.x * span - px * 30 * (1 - s.z)) * k * 0.35;
			var y = cy + (s.y * span - py * 30 * (1 - s.z)) * k * 0.35;
			if (x < -50 || x > w + 50 || y < -50 || y > h + 50) {
				s.z = 1;
				continue;
			}
			var b = Math.min(1, (1 - s.z) * 1.3) * (0.75 + 0.25 * Math.sin(now / 600 + s.tw));
			var r = Math.max(0.4, (1 - s.z) * 1.8);
			if (warp > 0.05) {
				// (a streak toward the centre, its length the warp)
				var len = warp * 60 * (1 - s.z);
				var dx = x - cx, dy = y - cy, d = Math.max(1, Math.sqrt(dx * dx + dy * dy));
				ctx.strokeStyle = 'hsla(${s.hue}, 90%, 85%, $b)';
				ctx.lineWidth = r;
				ctx.beginPath();
				ctx.moveTo(x, y);
				ctx.lineTo(x - dx / d * len, y - dy / d * len);
				ctx.stroke();
			} else {
				ctx.fillStyle = 'hsla(${s.hue}, 90%, 88%, $b)';
				ctx.beginPath();
				ctx.arc(x, y, r, 0, Math.PI * 2);
				ctx.fill();
			}
		}

		ctx.setLineDash([2, 6]);
		ctx.lineWidth = 1;
		ctx.globalAlpha = 0.28;
		for (o in orbits) {
			ctx.strokeStyle = o.color;
			ctx.beginPath();
			ctx.ellipse(o.cx, o.cy, o.rx, o.ry, 0, 0, Math.PI * 2);
			ctx.stroke();
		}
		ctx.setLineDash([]);
		ctx.globalAlpha = 1;
	}
}
