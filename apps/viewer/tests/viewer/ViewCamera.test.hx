package viewer;

import helder.test.Test;

// ViewCamera: the fit (never above 100%), zooms about a point, their stops
// at 100% and at the fit, the keys' steps, the double click, pans kept
// within the image, the glide
@:test.interp function tests() {
	describe("ViewCamera", () -> {
		function near(a:Float, b:Float, ?what:String)
			assert(Math.abs(a - b) < 1e-6, '${what ?? ""} $a != $b');
		test("fit: whole and centred, at most 100%", () -> {
			var c = new ViewCamera();
			c.setView(1000, 500);
			c.setImage(4000, 1000);
			near(c.scale, 0.25);
			var r = c.rect();
			near(r.x, 0);
			near(r.y, 125);
			c.setImage(200, 100);
			near(c.scale, 1, "a small image at its own size");
			near(c.rect().x, 400);
			// (the view resized while fitted: fitted again)
			c.setImage(4000, 1000);
			c.setView(2000, 500);
			near(c.scale, 0.5);
		});
		test("a zoom keeps the point under the cursor; it stops at 100% and at the fit", () -> {
			var c = new ViewCamera();
			c.setView(1000, 1000);
			c.setImage(4000, 4000);
			// (the image point under (250, 250) at 0.25: (1000, 1000))
			c.zoomBy(3, 250, 250);
			near(c.scale, 0.75);
			var r = c.rect();
			near((250 - r.x) / c.scale, 1000, "x kept");
			near((250 - r.y) / c.scale, 1000, "y kept");
			c.zoomBy(2, 250, 250);
			near(c.scale, 1, "stopped at 100%");
			c.zoomBy(2, 250, 250);
			near(c.scale, 2);
			c.zoomBy(0.01, 250, 250);
			near(c.scale, 1, "stopped at 100% going out");
			c.zoomBy(0.01, 250, 250);
			near(c.scale, 0.25, "stopped at the fit");
			equals(c.fitted, true);
		});
		test("the keys' steps, 100%, fit; the double click", () -> {
			var c = new ViewCamera();
			c.setView(800, 600);
			c.setImage(1600, 1200);
			near(c.scale, 0.5);
			c.step(1);
			near(c.scale, 2 / 3);
			c.step(1);
			near(c.scale, 1);
			c.step(-1);
			c.step(-1);
			near(c.scale, 0.5);
			equals(c.fitted, true);
			c.actual();
			near(c.scale, 1);
			equals(c.percent(), 100);
			c.fit();
			c.toggle(100, 100);
			near(c.scale, 1, "double click: 100%");
			c.toggle(100, 100);
			near(c.scale, 0.5, "and the fit");
		});
		test("a pan stays within the image; a smaller side stays centred", () -> {
			var c = new ViewCamera();
			c.setView(1000, 1000);
			c.setImage(3000, 500);
			c.actual();
			c.pan(-100000, 300);
			var r = c.rect();
			near(r.x, 1000 - 3000, "its right edge at the view's");
			near(r.y, 250, "centred vertically");
			c.pan(100000, 0);
			near(c.rect().x, 0);
		});
		test("the glide slows to a stop", () -> {
			var c = new ViewCamera();
			c.setView(1000, 1000);
			c.setImage(100000, 100000);
			c.actual();
			var x0 = c.centerX;
			c.fling(-2000, 0);
			var steps = 0;
			while (c.glide(1 / 60))
				steps++;
			assert(c.centerX > x0 + 100, "it moved");
			assert(steps > 10 && steps < 200, '$steps frames');
		});
	});
}
