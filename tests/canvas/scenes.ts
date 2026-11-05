// The canvas lane's reference scenes: each drawn by helder.canvas's DOM
// facade (render.ts, natively) and by Chromium's canvas (chrome.mjs, this
// same file bundled with "helder/canvas" as the browser's own classes),
// the two compared (compare.mjs). Code as written for the browser.
import { Canvas, CanvasRenderingContext2D, Path2D, FontLibrary, DOMMatrix, ImageData, loadImage } from "helder/canvas";

export type Scene = { name: string; width: number; height: number; draw: (ctx: CanvasRenderingContext2D) => void };

const W = 160, H = 120;

export function fonts(dir: string): void {
	FontLibrary.use("DejaVu Sans", [dir + "/DejaVuSans-canvas.ttf"]);
	FontLibrary.use("DejaVu Sans Bold", [dir + "/DejaVuSans-Bold-canvas.ttf"]);
	FontLibrary.use("IPAGothic", [dir + "/IPAGothic-canvas.ttf"]);
}

function white(ctx: CanvasRenderingContext2D, w: number, h: number): void {
	ctx.fillStyle = "#ffffff";
	ctx.fillRect(0, 0, w, h);
}

function star(ctx: CanvasRenderingContext2D, cx: number, cy: number, r: number): void {
	ctx.beginPath();
	for (let i = 0; i < 5; i++) {
		const a = -Math.PI / 2 + i * 4 * Math.PI / 5;
		if (i === 0) ctx.moveTo(cx + r * Math.cos(a), cy + r * Math.sin(a));
		else ctx.lineTo(cx + r * Math.cos(a), cy + r * Math.sin(a));
	}
	ctx.closePath();
}

// two rectangles, one wound each way, and a ring of two circles
function nested(ctx: CanvasRenderingContext2D, x: number, y: number): void {
	ctx.moveTo(x, y);
	ctx.lineTo(x + 50, y);
	ctx.lineTo(x + 50, y + 45);
	ctx.lineTo(x, y + 45);
	ctx.closePath();
	ctx.moveTo(x + 10, y + 10);
	ctx.lineTo(x + 40, y + 10);
	ctx.lineTo(x + 40, y + 35);
	ctx.lineTo(x + 10, y + 35);
	ctx.closePath();
	ctx.arc(x + 25, y + 70, 22, 0, Math.PI * 2);
	ctx.arc(x + 25, y + 70, 12, 0, Math.PI * 2, true);
}

function fillRule(rule: string): (ctx: CanvasRenderingContext2D) => void {
	return ctx => {
		white(ctx, W, H);
		ctx.fillStyle = "#2a6fdb";
		star(ctx, 45, 60, 42);
		if (rule === "evenodd") ctx.fill("evenodd"); else ctx.fill("nonzero");
		ctx.fillStyle = "rgba(220, 40, 60, 0.8)";
		ctx.beginPath();
		nested(ctx, 100, 8);
		if (rule === "evenodd") ctx.fill("evenodd"); else ctx.fill();
	};
}

function zigzag(ctx: CanvasRenderingContext2D, x: number, y: number): void {
	ctx.beginPath();
	ctx.moveTo(x, y + 24);
	ctx.lineTo(x + 18, y);
	ctx.lineTo(x + 30, y + 24);
	ctx.lineTo(x + 60, y + 6);
	ctx.lineTo(x + 66, y + 26);
	ctx.lineTo(x + 100, y + 22);
	ctx.lineTo(x + 104, y + 4);
}

export const scenes: Scene[] = [
	{ name: "fill-nonzero", width: W, height: H, draw: fillRule("nonzero") },
	{ name: "fill-evenodd", width: W, height: H, draw: fillRule("evenodd") },
	{
		name: "joins", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			const joins = ["miter", "round", "bevel"];
			ctx.lineWidth = 9;
			ctx.strokeStyle = "#1f2937";
			for (let i = 0; i < 3; i++) {
				ctx.lineJoin = joins[i];
				zigzag(ctx, 10, 6 + i * 38);
				ctx.stroke();
			}
			// (the miter limit: a sharp turn beveled, a wide one kept)
			ctx.lineJoin = "miter";
			ctx.miterLimit = 2;
			ctx.lineWidth = 5;
			ctx.strokeStyle = "#c2410c";
			ctx.beginPath();
			ctx.moveTo(126, 20);
			ctx.lineTo(150, 30);
			ctx.lineTo(126, 40);
			ctx.moveTo(126, 70);
			ctx.lineTo(146, 85);
			ctx.lineTo(126, 100);
			ctx.stroke();
		}
	},
	{
		name: "caps", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			const caps = ["butt", "round", "square"];
			ctx.strokeStyle = "#0f766e";
			for (let i = 0; i < 3; i++) {
				ctx.lineCap = caps[i];
				ctx.lineWidth = 14;
				ctx.beginPath();
				ctx.moveTo(20, 20 + i * 36);
				ctx.lineTo(100, 28 + i * 36);
				ctx.stroke();
				// a zero length subpath: a dot for round and square caps
				ctx.beginPath();
				ctx.moveTo(130, 22 + i * 36);
				ctx.lineTo(130, 22 + i * 36);
				ctx.stroke();
			}
			ctx.strokeStyle = "#ef4444";
			ctx.lineWidth = 1;
			ctx.beginPath();
			ctx.moveTo(20.5, 5);
			ctx.lineTo(20.5, 115);
			ctx.moveTo(100.5, 5);
			ctx.lineTo(100.5, 115);
			ctx.stroke();
		}
	},
	{
		name: "dashes", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			ctx.strokeStyle = "#7c3aed";
			ctx.lineWidth = 4;
			ctx.setLineDash([12, 6]);
			ctx.beginPath();
			ctx.moveTo(10, 14);
			ctx.lineTo(150, 14);
			ctx.stroke();
			ctx.setLineDash([2, 6, 10]);
			ctx.lineDashOffset = 5;
			ctx.beginPath();
			ctx.moveTo(10, 30);
			ctx.lineTo(150, 30);
			ctx.stroke();
			ctx.lineCap = "round";
			ctx.setLineDash([0, 10]);
			ctx.lineDashOffset = 0;
			ctx.lineWidth = 6;
			ctx.beginPath();
			ctx.moveTo(10, 46);
			ctx.lineTo(150, 46);
			ctx.stroke();
			ctx.lineCap = "butt";
			ctx.lineWidth = 3;
			ctx.setLineDash([9, 4]);
			ctx.strokeStyle = "#0369a1";
			ctx.beginPath();
			ctx.moveTo(10, 100);
			ctx.bezierCurveTo(40, 50, 80, 130, 150, 64);
			ctx.stroke();
			ctx.setLineDash([16, 5, 3, 5]);
			ctx.lineJoin = "round";
			ctx.strokeStyle = "#b45309";
			ctx.strokeRect(20, 62, 50, 40);
		}
	},
	{
		name: "curves", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			ctx.fillStyle = "#fde68a";
			ctx.strokeStyle = "#92400e";
			ctx.lineWidth = 3;
			ctx.beginPath();
			ctx.moveTo(10, 100);
			ctx.quadraticCurveTo(40, 0, 75, 100);
			ctx.closePath();
			ctx.fill();
			ctx.stroke();
			ctx.beginPath();
			ctx.moveTo(85, 20);
			ctx.bezierCurveTo(160, 0, 70, 110, 150, 110);
			ctx.lineWidth = 6;
			ctx.strokeStyle = "#1d4ed8";
			ctx.stroke();
			// a loop and a cusp
			ctx.beginPath();
			ctx.moveTo(90, 60);
			ctx.bezierCurveTo(150, 100, 150, 30, 95, 80);
			ctx.lineWidth = 2;
			ctx.strokeStyle = "#be123c";
			ctx.stroke();
			ctx.beginPath();
			ctx.moveTo(10, 112);
			ctx.bezierCurveTo(60, 112, 20, 112, 70, 112);
			ctx.stroke();
		}
	},
	{
		name: "arcs", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			ctx.strokeStyle = "#111827";
			ctx.lineWidth = 3;
			ctx.beginPath();
			ctx.arc(30, 30, 20, 0, Math.PI * 1.25);
			ctx.stroke();
			ctx.beginPath();
			ctx.arc(80, 30, 20, Math.PI * 0.25, Math.PI * 1.5, true);
			ctx.stroke();
			ctx.fillStyle = "#34d399";
			ctx.beginPath();
			ctx.moveTo(130, 30);
			ctx.arc(130, 30, 22, -Math.PI / 3, Math.PI / 2);
			ctx.closePath();
			ctx.fill();
			ctx.beginPath();
			ctx.moveTo(10, 110);
			ctx.arcTo(10, 60, 60, 60, 20);
			ctx.arcTo(60, 110, 10, 110, 12);
			ctx.stroke();
			ctx.fillStyle = "rgba(59, 130, 246, 0.7)";
			ctx.beginPath();
			ctx.ellipse(105, 85, 35, 14, Math.PI / 6, 0, Math.PI * 2);
			ctx.fill();
			ctx.strokeStyle = "#f59e0b";
			ctx.beginPath();
			ctx.roundRect(72, 62, 80, 50, [4, 16, 24, 8]);
			ctx.stroke();
		}
	},
	{
		name: "roundrect", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			ctx.fillStyle = "#6366f1";
			ctx.beginPath();
			ctx.roundRect(8, 8, 60, 40, 12);
			ctx.roundRect(150, 8, -70, 40, [20, 4]);
			ctx.roundRect(8, 60, 60, 50, [30]);
			ctx.fill();
			ctx.strokeStyle = "#ec4899";
			ctx.lineWidth = 4;
			ctx.beginPath();
			ctx.roundRect(84, 62, 66, 48, [{ x: 20, y: 10 }, 6, 0, 14]);
			ctx.stroke();
		}
	},
	{
		name: "gradient-linear", width: W, height: H, draw: ctx => {
			const g = ctx.createLinearGradient(0, 0, W, 0);
			g.addColorStop(0, "#ff0000");
			g.addColorStop(0.5, "#00ff00");
			g.addColorStop(1, "#0000ff");
			ctx.fillStyle = g;
			ctx.fillRect(0, 0, W, 40);
			const d = ctx.createLinearGradient(10, 50, 70, 110);
			d.addColorStop(0, "rgba(0, 0, 0, 0)");
			d.addColorStop(0.3, "#f97316");
			d.addColorStop(0.3, "#0ea5e9");
			d.addColorStop(1, "rgba(14, 165, 233, 0.2)");
			ctx.fillStyle = d;
			ctx.fillRect(0, 44, 80, 76);
			const s = ctx.createLinearGradient(90, 0, 150, 0);
			s.addColorStop(0, "#111827");
			s.addColorStop(1, "#facc15");
			ctx.strokeStyle = s;
			ctx.lineWidth = 10;
			ctx.beginPath();
			ctx.moveTo(95, 55);
			ctx.lineTo(150, 110);
			ctx.lineTo(95, 110);
			ctx.stroke();
		}
	},
	{
		name: "gradient-radial", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			const g = ctx.createRadialGradient(40, 40, 4, 40, 40, 36);
			g.addColorStop(0, "#ffffff");
			g.addColorStop(0.4, "#ef4444");
			g.addColorStop(1, "rgba(127, 29, 29, 0)");
			ctx.fillStyle = g;
			ctx.fillRect(0, 0, 80, 80);
			// two circles apart: a cone
			const c = ctx.createRadialGradient(100, 30, 6, 135, 60, 24);
			c.addColorStop(0, "#22c55e");
			c.addColorStop(1, "#1e3a8a");
			ctx.fillStyle = c;
			ctx.fillRect(80, 0, 80, 80);
			// the focus inside the circle
			const f = ctx.createRadialGradient(50, 100, 0, 60, 95, 40);
			f.addColorStop(0, "#fef08a");
			f.addColorStop(1, "#7c2d12");
			ctx.fillStyle = f;
			ctx.fillRect(0, 80, 160, 40);
		}
	},
	{
		name: "gradient-conic", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			const g = ctx.createConicGradient(0, 50, 60);
			g.addColorStop(0, "#ef4444");
			g.addColorStop(0.25, "#eab308");
			g.addColorStop(0.5, "#22c55e");
			g.addColorStop(0.75, "#3b82f6");
			g.addColorStop(1, "#ef4444");
			ctx.fillStyle = g;
			ctx.beginPath();
			ctx.arc(50, 60, 45, 0, Math.PI * 2);
			ctx.fill();
			const h = ctx.createConicGradient(Math.PI / 4, 120, 60);
			h.addColorStop(0, "#000000");
			h.addColorStop(0.5, "#ffffff");
			h.addColorStop(0.5, "#be185d");
			h.addColorStop(1, "rgba(190, 24, 93, 0)");
			ctx.fillStyle = h;
			ctx.fillRect(100, 20, 50, 80);
		}
	},
	{
		name: "patterns", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			const tile = new Canvas(12, 12);
			const t = tile.getContext("2d")!;
			t.fillStyle = "#0ea5e9";
			t.fillRect(0, 0, 6, 6);
			t.fillRect(6, 6, 6, 6);
			t.fillStyle = "rgba(244, 63, 94, 0.6)";
			t.beginPath();
			t.arc(6, 6, 3, 0, Math.PI * 2);
			t.fill();
			ctx.fillStyle = ctx.createPattern(tile, "repeat")!;
			ctx.fillRect(4, 4, 72, 52);
			ctx.fillStyle = ctx.createPattern(tile, "repeat-x")!;
			ctx.fillRect(84, 4, 72, 52);
			ctx.fillStyle = ctx.createPattern(tile, "repeat-y")!;
			ctx.fillRect(4, 64, 72, 52);
			const p = ctx.createPattern(tile, "no-repeat")!;
			p.setTransform(new DOMMatrix().translateSelf(100, 70).rotateSelf(30).scaleSelf(2, 2));
			ctx.fillStyle = p;
			ctx.fillRect(84, 64, 72, 52);
		}
	},
	{
		name: "clips", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			ctx.save();
			ctx.beginPath();
			ctx.arc(50, 60, 40, 0, Math.PI * 2);
			ctx.clip();
			ctx.beginPath();
			ctx.rect(30, 10, 80, 60);
			ctx.clip();
			ctx.fillStyle = "#16a34a";
			ctx.fillRect(0, 0, W, H);
			ctx.restore();
			ctx.save();
			star(ctx, 120, 60, 38);
			ctx.clip("evenodd");
			const g = ctx.createLinearGradient(80, 0, 160, 0);
			g.addColorStop(0, "#9333ea");
			g.addColorStop(1, "#f97316");
			ctx.fillStyle = g;
			ctx.fillRect(80, 0, 80, H);
			ctx.restore();
			// after the restore: no clip
			ctx.fillStyle = "rgba(0, 0, 0, 0.5)";
			ctx.fillRect(0, 108, W, 8);
		}
	},
	...compositeScenes(),
	{
		name: "transforms", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			ctx.save();
			ctx.translate(40, 40);
			ctx.rotate(Math.PI / 7);
			ctx.fillStyle = "#0284c7";
			ctx.fillRect(-20, -15, 40, 30);
			ctx.restore();
			ctx.save();
			ctx.transform(1, 0.3, -0.5, 1, 110, 20);
			ctx.fillStyle = "#e11d48";
			ctx.fillRect(0, 0, 40, 30);
			ctx.restore();
			// a stroke under a non-uniform scale: wider one way
			ctx.save();
			ctx.translate(40, 90);
			ctx.scale(3, 1);
			ctx.lineWidth = 3;
			ctx.strokeStyle = "#65a30d";
			ctx.beginPath();
			ctx.arc(0, 0, 10, 0, Math.PI * 2);
			ctx.stroke();
			ctx.restore();
			// the path kept where it was drawn when the transform changes
			ctx.beginPath();
			ctx.translate(100, 70);
			ctx.moveTo(0, 0);
			ctx.lineTo(40, 0);
			ctx.setTransform(1, 0, 0, 1, 0, 0);
			ctx.lineTo(140, 110);
			ctx.lineTo(100, 110);
			ctx.closePath();
			ctx.fillStyle = "#a855f7";
			ctx.fill();
			ctx.setTransform(2, 0, 0, 2, 0, 0);
			ctx.fillStyle = "rgba(0, 0, 0, 0.6)";
			ctx.fillRect(70, 4, 6, 6);
		}
	},
	{
		name: "alpha", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			const colors = ["#ef4444", "#22c55e", "#3b82f6"];
			for (let i = 0; i < 3; i++) {
				ctx.globalAlpha = 0.3 + i * 0.3;
				ctx.fillStyle = colors[i];
				ctx.beginPath();
				ctx.arc(45 + i * 35, 50, 32, 0, Math.PI * 2);
				ctx.fill();
			}
			ctx.globalAlpha = 0.5;
			ctx.strokeStyle = "rgba(0, 0, 0, 0.5)";
			ctx.lineWidth = 8;
			ctx.beginPath();
			ctx.moveTo(10, 105);
			ctx.lineTo(150, 95);
			ctx.stroke();
		}
	},
	{
		name: "lines-thin", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			ctx.strokeStyle = "#000000";
			const widths = [0.25, 0.5, 1, 1.5, 2, 3];
			for (let i = 0; i < widths.length; i++) {
				ctx.lineWidth = widths[i];
				ctx.beginPath();
				ctx.moveTo(10, 10 + i * 12);
				ctx.lineTo(150, 14 + i * 12);
				ctx.stroke();
				ctx.beginPath();
				ctx.moveTo(10.5 + i * 8, 84);
				ctx.lineTo(10.5 + i * 8, 114);
				ctx.stroke();
			}
			ctx.lineWidth = 1;
			ctx.strokeRect(80.5, 84.5, 30, 25);
			ctx.strokeRect(120, 84, 30, 25);
		}
	},
	{
		name: "path2d", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			const heart = new Path2D("M 40 30 C 40 20 25 15 20 25 C 15 15 0 20 0 30 C 0 45 20 50 20 60 C 20 50 40 45 40 30 Z");
			ctx.save();
			ctx.translate(10, 10);
			ctx.scale(1.5, 1.5);
			ctx.fillStyle = "#e11d48";
			ctx.fill(heart);
			ctx.restore();
			const arcs = new Path2D("M90 20 a 25 15 30 1 1 40 30 l 10 20 q 10 -40 -30 -40 T 80 80 z");
			ctx.strokeStyle = "#0f172a";
			ctx.lineWidth = 2;
			ctx.stroke(arcs);
			const both = new Path2D();
			both.rect(60, 90, 90, 25);
			both.addPath(new Path2D("M 70 95 h 20 v 15 h -20 z"));
			ctx.fillStyle = "#0891b2";
			ctx.fill(both, "evenodd");
		}
	},
	{
		name: "images", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			const src = new Canvas(16, 12);
			const s = src.getContext("2d")!;
			const g = s.createLinearGradient(0, 0, 16, 12);
			g.addColorStop(0, "#f43f5e");
			g.addColorStop(1, "#3b82f6");
			s.fillStyle = g;
			s.fillRect(0, 0, 16, 12);
			s.fillStyle = "#facc15";
			s.fillRect(4, 3, 4, 4);
			s.clearRect(10, 6, 4, 4);
			ctx.drawImage(src, 4, 4);
			ctx.drawImage(src, 24, 4, 48, 36);
			ctx.imageSmoothingEnabled = false;
			ctx.drawImage(src, 80, 4, 48, 36);
			ctx.imageSmoothingEnabled = true;
			ctx.drawImage(src, 2, 2, 8, 6, 132, 4, 24, 18);
			ctx.save();
			ctx.translate(40, 80);
			ctx.rotate(-Math.PI / 9);
			ctx.globalAlpha = 0.7;
			ctx.drawImage(src, -24, -18, 48, 36);
			ctx.restore();
			const photo = loadImage(imageDir + "/sample.png");
			ctx.drawImage(photo, 84, 60, 64, 48);
		}
	},
	{
		name: "pixels", width: W, height: H, draw: ctx => {
			white(ctx, W, H);
			ctx.fillStyle = "rgba(37, 99, 235, 0.5)";
			ctx.fillRect(10, 10, 60, 40);
			ctx.fillStyle = "#dc2626";
			ctx.beginPath();
			ctx.arc(40, 30, 12, 0, Math.PI * 2);
			ctx.fill();
			const d = ctx.getImageData(10, 10, 60, 40);
			ctx.putImageData(d, 90, 10);
			ctx.putImageData(d, 20, 60, 10, 10, 30, 20);
			const px: number[] = [];
			for (let i = 0; i < 20 * 10; i++) px.push(i % 255, 255 - (i % 255), 128, 160 + (i % 90));
			ctx.putImageData(new ImageData(px, 20, 10), 100, 80);
		}
	},
	...textScenes(),
];

let imageDir = "tests/canvas/images";
export function images(dir: string): void {
	imageDir = dir;
}

function compositeScenes(): Scene[] {
	const ops = [
		["source-over", "source-in", "source-out", "source-atop", "destination-over", "destination-in", "destination-out", "destination-atop",
			"lighter", "copy", "xor"],
		["multiply", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "hard-light", "soft-light", "difference", "exclusion",
			"hue", "saturation", "color", "luminosity"],
	];
	const names = ["composite", "blend-modes"];
	const out: Scene[] = [];
	for (let k = 0; k < 2; k++) {
		const list = ops[k], cols = 4, cw = 50, ch = 40;
		const rows = Math.ceil(list.length / cols);
		out.push({
			name: names[k], width: cols * cw, height: rows * ch, draw: ctx => {
				for (let i = 0; i < list.length; i++) {
					const x = (i % cols) * cw, y = Math.floor(i / cols) * ch;
					ctx.save();
					ctx.beginPath();
					ctx.rect(x, y, cw, ch);
					ctx.clip();
					ctx.fillStyle = "#f1f5f9";
					ctx.fillRect(x, y, cw, ch);
					const d = ctx.createLinearGradient(x, y, x + cw, y + ch);
					d.addColorStop(0, "rgba(14, 165, 233, 0.9)");
					d.addColorStop(1, "rgba(234, 179, 8, 0.6)");
					ctx.fillStyle = d;
					ctx.beginPath();
					ctx.arc(x + 19, y + 18, 14, 0, Math.PI * 2);
					ctx.fill();
					ctx.globalCompositeOperation = list[i];
					ctx.fillStyle = "rgba(225, 29, 72, 0.75)";
					ctx.fillRect(x + 20, y + 12, 24, 22);
					ctx.restore();
				}
			}
		});
	}
	return out;
}

function textScenes(): Scene[] {
	return [
		{
			name: "text-latin", width: W, height: H, draw: ctx => {
				white(ctx, W, H);
				ctx.fillStyle = "#111827";
				ctx.font = "16px 'DejaVu Sans'";
				ctx.fillText("Canvas 2D, ffi!", 6, 20);
				ctx.font = "14px 'DejaVu Sans Bold'";
				ctx.fillText("Bold text", 6, 40);
				ctx.strokeStyle = "#2563eb";
				ctx.lineWidth = 1;
				ctx.font = "26px 'DejaVu Sans'";
				ctx.strokeText("Outline", 6, 70);
				ctx.font = "12px 'DejaVu Sans'";
				ctx.letterSpacing = "3px";
				ctx.fillText("spaced out", 6, 90);
				ctx.letterSpacing = "0px";
				ctx.fillText("squeezed into fifty", 6, 110, 50);
				const m = ctx.measureText("Canvas 2D, ffi!");
				ctx.strokeStyle = "rgba(220, 38, 38, 0.7)";
				ctx.font = "16px 'DejaVu Sans'";
				const mm = ctx.measureText("Canvas 2D, ffi!");
				ctx.strokeRect(6 - mm.actualBoundingBoxLeft + 0.5, 20 - mm.actualBoundingBoxAscent + 0.5, Math.round(mm.actualBoundingBoxLeft + mm.actualBoundingBoxRight), Math.round(mm.actualBoundingBoxAscent + mm.actualBoundingBoxDescent));
				if (m.width <= 0) throw new Error("no width");
			}
		},
		{
			name: "text-align", width: W, height: H, draw: ctx => {
				white(ctx, W, H);
				ctx.strokeStyle = "#ef4444";
				ctx.lineWidth = 1;
				ctx.beginPath();
				ctx.moveTo(80.5, 0);
				ctx.lineTo(80.5, H);
				ctx.stroke();
				ctx.fillStyle = "#1f2937";
				ctx.font = "13px 'DejaVu Sans'";
				const aligns = ["left", "center", "right", "start", "end"];
				for (let i = 0; i < aligns.length; i++) {
					ctx.textAlign = aligns[i];
					ctx.fillText(aligns[i] + " Ag", 80, 14 + i * 14);
				}
				ctx.textAlign = "left";
				const baselines = ["top", "hanging", "middle", "alphabetic", "ideographic", "bottom"];
				ctx.font = "10px 'DejaVu Sans'";
				ctx.beginPath();
				ctx.moveTo(0, 100.5);
				ctx.lineTo(W, 100.5);
				ctx.stroke();
				for (let i = 0; i < baselines.length; i++) {
					ctx.textBaseline = baselines[i];
					ctx.fillText("Ag", 4 + i * 26, 100);
				}
			}
		},
		{
			name: "text-scripts", width: W, height: H, draw: ctx => {
				white(ctx, W, H);
				ctx.fillStyle = "#0f172a";
				ctx.font = "15px 'DejaVu Sans'";
				ctx.fillText("Ελληνικά Кириллица", 4, 20);
				ctx.direction = "rtl";
				ctx.textAlign = "right";
				ctx.fillText("שלום עולם", 156, 44);
				ctx.fillText("مرحبا بالعالم", 156, 70);
				ctx.direction = "ltr";
				ctx.textAlign = "left";
				ctx.font = "18px IPAGothic";
				ctx.fillText("日本語のテキスト", 4, 100);
			}
		},
		{
			name: "text-transformed", width: W, height: H, draw: ctx => {
				white(ctx, W, H);
				const g = ctx.createLinearGradient(0, 0, W, 0);
				g.addColorStop(0, "#7c3aed");
				g.addColorStop(1, "#db2777");
				ctx.fillStyle = g;
				ctx.font = "32px 'DejaVu Sans Bold'";
				ctx.fillText("Big", 10, 45);
				ctx.save();
				ctx.translate(100, 80);
				ctx.rotate(-Math.PI / 8);
				ctx.scale(1.5, 1);
				ctx.font = "16px 'DejaVu Sans'";
				ctx.fillStyle = "#059669";
				ctx.fillText("turned", -30, 0);
				ctx.restore();
				ctx.font = "italic 14px 'DejaVu Sans'";
				ctx.fillStyle = "#111827";
				ctx.fillText("oblique", 10, 105);
			}
		},
	];
}
