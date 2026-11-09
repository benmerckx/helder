package helder.os.headless;

// A window of a headless run (a build with -D helder.headless,
// helder.headless.Headless): no system's window, a headless Surface of its
// size in points times the run's scale (helder.gfx renders offscreen into
// it: Mesa's llvmpipe on Linux, Metal or WARP elsewhere), its events the
// run's script's (Headless.poll). The run's --size, when given, is its
// size whatever the program asks for; resize (the program's, or a
// script's) changes it and sends a Resize.
class HeadlessWindow {
	public final window:Window;
	public final surface:Surface;
	public final scale:Float;
	// its size in points
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var fullscreen = false;
	public var x = 0;
	public var y = 0;
	// an inset title bar's system buttons (a macOS build's), in points: where macOS puts them
	public var controlsX = 7.0;
	public var controlsY = 6.0;

	public function new(window:Window, width:Int, height:Int) {
		this.window = window;
		var run = helder.headless.Headless.run;
		scale = run.scale;
		if (run.width > 0) {
			width = run.width;
			height = run.height;
		}
		this.width = width;
		this.height = height;
		surface = Surface.headless(Math.round(width * scale), Math.round(height * scale));
		run.opened(this);
	}

	// (the program's, or a script's resize): a Resize event follows
	public function resize(w:Int, h:Int) {
		if (w < 1) w = 1;
		if (h < 1) h = 1;
		if (w == width && h == height) return;
		width = w;
		height = h;
		surface.resized(Math.round(w * scale), Math.round(h * scale));
		var e = new Event();
		e.kind = Resize;
		e.window = window;
		e.x = surface.width;
		e.y = surface.height;
		helder.headless.Headless.run.post(e);
	}
}
