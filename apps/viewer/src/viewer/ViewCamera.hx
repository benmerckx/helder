package viewer;

// Where an image is in the view: its scale (device pixels per image pixel:
// 1 is 100%, one image pixel a screen pixel) and the image point at the
// view's centre. Fitted (the default) it follows the view's size: the
// whole image, never above 100% (a small image at its own size), centred.
// Zooms keep the image point under the cursor where it is, and stop at
// 100% and at the fit on their way past them (a wheel's or a pinch's
// steps snap there); a side smaller than the view is centred, a larger one
// kept within it; a pan let go glides to a stop (fling, step).
class ViewCamera {
	public static inline var MIN_SCALE = 0.01;
	public static inline var MAX_SCALE = 64.0;
	// (the zoom keys' steps)
	public static final STEPS = [0.05, 0.1, 1 / 6, 0.25, 1 / 3, 0.5, 2 / 3, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64];

	public var viewWidth(default, null) = 1.0;
	public var viewHeight(default, null) = 1.0;
	public var imageWidth(default, null) = 0.0;
	public var imageHeight(default, null) = 0.0;
	public var scale(default, null) = 1.0;
	public var centerX(default, null) = 0.0;
	public var centerY(default, null) = 0.0;
	// following the view's size (fit)
	public var fitted(default, null) = true;
	// the glide's speed (device pixels a second)
	public var velocityX(default, null) = 0.0;
	public var velocityY(default, null) = 0.0;

	public function new() {}

	// a new image: fitted
	public function setImage(w:Float, h:Float) {
		imageWidth = w;
		imageHeight = h;
		stop();
		fit();
	}

	public function setView(w:Float, h:Float) {
		viewWidth = Math.max(1, w);
		viewHeight = Math.max(1, h);
		if (fitted) fit() else clamp();
	}

	// the scale that shows it whole, at most 100%
	public function fitScale():Float
		return imageWidth <= 0 || imageHeight <= 0 ? 1 : Math.min(1, Math.min(viewWidth / imageWidth, viewHeight / imageHeight));

	public function fit() {
		fitted = true;
		scale = fitScale();
		centerX = imageWidth / 2;
		centerY = imageHeight / 2;
		stop();
	}

	// 100% about a point of the view (its centre by default)
	public function actual(?x:Float, ?y:Float)
		zoomTo(1, x ?? viewWidth / 2, y ?? viewHeight / 2);

	// a double click: the fit and 100% (at the point) in turn; an image
	// already at 100% when fitted: 200% and back
	public function toggle(x:Float, y:Float)
		if (fitted) zoomTo(fitScale() < 1 ? 1 : 2, x, y) else fit();

	// the scale made s, the image point under (x, y) kept there
	public function zoomTo(s:Float, x:Float, y:Float) {
		s = Math.max(Math.min(MIN_SCALE, fitScale()), Math.min(MAX_SCALE, s));
		var ix = centerX + (x - viewWidth / 2) / scale, iy = centerY + (y - viewHeight / 2) / scale;
		scale = s;
		centerX = ix - (x - viewWidth / 2) / scale;
		centerY = iy - (y - viewHeight / 2) / scale;
		if (Math.abs(scale - fitScale()) < 1e-9) fit() else {
			fitted = false;
			clamp();
		}
	}

	// by a factor about (x, y), stopping at 100% and at the fit when it
	// passes them (a wheel's notch, a pinch's step)
	public function zoomBy(factor:Float, x:Float, y:Float) {
		var s = scale * factor;
		for (stop in [1.0, fitScale()])
			if ((scale < stop - 1e-9 && s > stop + 1e-9) || (scale > stop + 1e-9 && s < stop - 1e-9)) s = stop;
		if (Math.abs(s - fitScale()) < 1e-9) {
			fit();
			return;
		}
		zoomTo(s, x, y);
	}

	// the next step in or out (the + and - keys), about the view's centre
	public function step(dir:Int) {
		var s = scale, next = s;
		var fs = fitScale();
		var steps = STEPS.concat([fs]);
		steps.sort(Reflect.compare);
		if (dir > 0) {
			for (v in steps)
				if (v > s * 1.0001) {
					next = v;
					break;
				}
		} else {
			var i = steps.length;
			while (--i >= 0)
				if (steps[i] < s / 1.0001) {
					next = steps[i];
					break;
				}
		}
		if (Math.abs(next - fs) < 1e-9) fit() else zoomTo(next, viewWidth / 2, viewHeight / 2);
	}

	// moved by (dx, dy) device pixels: the image follows the pointer
	public function pan(dx:Float, dy:Float) {
		if (imageWidth <= 0) return;
		centerX -= dx / scale;
		centerY -= dy / scale;
		if (dx != 0 || dy != 0) fitted = false;
		clamp();
	}

	// let go at a speed (device pixels a second): it glides
	public function fling(vx:Float, vy:Float) {
		velocityX = vx;
		velocityY = vy;
	}

	public function stop()
		velocityX = velocityY = 0;

	public var gliding(get, never):Bool;

	function get_gliding():Bool
		return velocityX != 0 || velocityY != 0;

	// dt seconds of the glide (friction: a tenth of its speed left after
	// half a second); false once still
	public function glide(dt:Float):Bool {
		if (!gliding) return false;
		var keep = Math.pow(0.01, dt);
		var x0 = centerX, y0 = centerY;
		pan(velocityX * dt, velocityY * dt);
		velocityX *= keep;
		velocityY *= keep;
		// (at an edge, or slow: still)
		if (Math.abs(velocityX) < 5 && Math.abs(velocityY) < 5 || (centerX == x0 && centerY == y0)) stop();
		return gliding;
	}

	// (a side within the view: centred; else its edges no further in than the view's)
	function clamp() {
		var hw = viewWidth / 2 / scale, hh = viewHeight / 2 / scale;
		centerX = imageWidth <= 2 * hw ? imageWidth / 2 : Math.max(hw, Math.min(imageWidth - hw, centerX));
		centerY = imageHeight <= 2 * hh ? imageHeight / 2 : Math.max(hh, Math.min(imageHeight - hh, centerY));
	}

	// the image on the view: its left, top, width and height (device pixels)
	public function rect():{x:Float, y:Float, width:Float, height:Float}
		return {
			x: viewWidth / 2 - centerX * scale,
			y: viewHeight / 2 - centerY * scale,
			width: imageWidth * scale,
			height: imageHeight * scale
		};

	// the zoom as the status line says it
	public function percent():Int
		return Math.round(scale * 100);
}
