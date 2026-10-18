package hxmc.scene.debug;

import hxmc.gfx.*;
import hxmc.ui.draw.Renderer as UiRenderer;

// A debug overlay over the 3D frame, drawn with @hxmc/ui's drawn renderer
// (hxmc.ui.draw.Renderer, so @hxmc/ui and @hxmc/text must be on the class
// path of a program that uses it; a program that does not links none of
// it): a panel in the top left with the last frames' times as bars (green
// under the 60 Hz budget, amber under 30 Hz, red above; the line is
// 16.7 ms) and the renderer's draws as a bar. Its own pass, loading what
// the renderer drew:
//
//   renderer.draw(enc, world, camera);
//   stats.add(seconds); stats.from(renderer);
//   overlay.draw(enc, stats);
class Overlay {
	public final device:Device;
	public var scale = 1.0;
	final ui:UiRenderer;
	final pass:PassDesc = {colors: [{load: Load}]};

	public function new(device:Device) {
		this.device = device;
		ui = new UiRenderer(device);
	}

	public function draw(enc:Encoder, stats:FrameStats) {
		var w = device.width, h = device.height;
		ui.scale = scale;
		ui.begin(w, h);
		var bars = stats.capacity, bw = 2.0, gh = 48.0, x0 = 8.0, y0 = 8.0;
		var pw = bars * bw + 12, ph = gh + 26;
		ui.rect(x0, y0, pw, ph, 0, 0xB0101418, 0, 0);
		// (the bars: newest on the right; 33 ms fills the graph)
		for (k in 0...stats.count) {
			var t = stats.at(k), v = Math.min(t / 0.0333, 1);
			var color = t <= 1 / 59 ? 0xFF4CC38A : t <= 1 / 29 ? 0xFFE0B040 : 0xFFE05050;
			// (whole pixels: alike on every rasterizer)
			var bh = Math.max(Math.round(v * gh), 1);
			ui.rect(x0 + 6 + (bars - 1 - k) * bw, y0 + 6 + gh - bh, bw - 1, bh, 0, color, 0, 0);
		}
		// (the 60 Hz budget)
		ui.rect(x0 + 6, y0 + 6 + gh - Math.round((1 / 60) / 0.0333 * gh), bars * bw, 1, 0, 0x80FFFFFF, 0, 0);
		// (draws: a bar of up to 100, culled after it)
		var dw = Math.round(Math.min(stats.draws, 100) / 100 * (bars * bw));
		ui.rect(x0 + 6, y0 + 12 + gh, dw, 6, 0, 0xFF5AA0F0, 0, 0);
		ui.rect(x0 + 6 + dw, y0 + 12 + gh, Math.round(Math.min(stats.culled, 100) / 100 * (bars * bw - dw)), 6, 0, 0x605AA0F0, 0, 0);
		enc.beginPass(pass);
		ui.end(enc);
		enc.endPass();
	}
}
