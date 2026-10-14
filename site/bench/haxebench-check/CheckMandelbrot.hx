// BMMandelbrotCode's image (both variants: -D anon_objects), summed
@:access(BMMandelbrotCode)
class CheckMandelbrot {
	static function main() {
		var m:BMMandelbrotCode = Type.createEmptyInstance(BMMandelbrotCode);
		var SIZE = 25, MaxIterations = 1000, MaxRad = 1 << 16;
		var width = 35 * SIZE, height = 20 * SIZE;
		var palette = [];
		for (i in 0...MaxIterations + 1)
			palette.push(m.createPalette(i / MaxIterations));
		var image = [];
		image[width * height - 1] = null;
		var outPixel = 0;
		var scale = 0.1 / SIZE;
		var iters = 0, r = 0, g = 0, b = 0;
		for (y in 0...height) {
			for (x in 0...width) {
				var iteration = 0;
				var offset = m.createComplex(x * scale - 2.5, y * scale - 1);
				var val = m.createComplex(0.0, 0.0);
				while (m.complexLength2(val) < MaxRad && iteration < MaxIterations) {
					val = m.complexAdd(m.complexSquare(val), offset);
					iteration++;
				}
				iters += iteration;
				image[outPixel++] = palette[iteration];
			}
		}
		for (p in image) {
			r += p.r;
			g += p.g;
			b += p.b;
		}
		Sys.println('pixels ${image.length}, iterations $iters, rgb sums $r $g $b');
	}
}
