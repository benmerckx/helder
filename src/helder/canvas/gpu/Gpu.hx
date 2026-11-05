package helder.canvas.gpu;

// The DOM facade's canvases drawn on the GPU from now on (GpuCanvas, each
// on a headless device of its size): `useGpu()` in helder/canvas. A class
// apart, so that a program that never calls it keeps no GPU code.
class Gpu {
	public static function use() {
		helder.canvas.dom.Canvas.backend = (w, h) -> new GpuCanvas(w, h);
	}
}
