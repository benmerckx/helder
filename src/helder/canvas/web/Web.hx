package helder.canvas.web;

// The DOM facade's canvases drawn by the browser's own Canvas 2D from now
// on (WebCanvas): `useWeb()` in helder/canvas, for a web build
// (wasm32 with src/helder/canvas/imports.mjs). A class apart: a program
// that never calls it keeps none of it.
class Web {
	public static function use() {
		helder.canvas.dom.Canvas.backend = (w, h) -> new WebCanvas(w, h);
	}
}
