import helder.canvas.Bitmap;
import helder.canvas.Paint;
import helder.canvas.web.BrowserImages;
import helder.canvas.web.WebCanvas;

// The canvas-web lane's browser decoding check (webdecode.mjs): a PNG
// and a JPEG (tests/canvas/images/sample.png, and it encoded by helder)
// decoded by the browser (BrowserImages), at their size and at half,
// drawn by handle on a WebCanvas, against helder's own decoders' pixels
// drawn the same way; a line each, then "webdecode: done"
class WebDecode {
	static function main() {
		var png = sys.io.File.getBytes("tests/canvas/images/sample.png");
		var img = helder.image.PngDecoder.decode(png);
		var jpg = helder.image.JpegEncoder.encode(img.rgba, img.width, img.height, 90);
		var ours = [
			Bitmap.fromStraight(img.width, img.height, img.rgba),
			{
				var j = helder.image.JpegDecoder.decode(jpg);
				Bitmap.fromStraight(j.width, j.height, j.rgba);
			}
		];
		var w = img.width, h = img.height;
		var requests = [
			{bytes: png, type: "image/png", width: 0, height: 0},
			{bytes: jpg, type: "image/jpeg", width: 0, height: 0},
			{bytes: png, type: "image/png", width: w >> 1, height: h >> 1},
			{bytes: jpg, type: "image/jpeg", width: w >> 1, height: h >> 1}
		];
		var names = ["png", "jpeg", "png at half", "jpeg at half"];
		BrowserImages.all(requests, images -> {
			var failed = 0;
			for (i in 0...images.length) {
				var im = images[i];
				if (im == null) {
					Sys.println('webdecode: ${names[i]}: FAIL (not decoded)');
					failed++;
					continue;
				}
				var half = i >= 2;
				var ew = half ? w >> 1 : w, eh = half ? h >> 1 : h;
				if (im.width != ew || im.height != eh) {
					Sys.println('webdecode: ${names[i]}: FAIL (${im.width}x${im.height}, not ${ew}x$eh)');
					failed++;
					continue;
				}
				// (both drawn into the size decoded: the browser's by handle, 1:1, helder's as a Bitmap scaled)
				var a = new WebCanvas(ew, eh), b = new WebCanvas(ew, eh), p = new Paint();
				a.drawHandle(im.handle, 0, 0, im.width, im.height, 0, 0, ew, eh, p);
				b.drawImage(ours[i % 2], 0, 0, w, h, 0, 0, ew, eh, p);
				var pa = haxe.io.Bytes.alloc(ew * eh * 4), pb = haxe.io.Bytes.alloc(ew * eh * 4);
				a.readPixels(pa, 0, 0, ew, eh);
				b.readPixels(pb, 0, 0, ew, eh);
				var off = 0;
				for (k in 0...ew * eh * 4)
					if (Std.int(Math.abs(pa.get(k) - pb.get(k))) > 24) off++;
				var share = off / (ew * eh * 4);
				// (JPEG: two decoders' IDCTs and upsampling; at half: two resamplers)
				var ok = share <= (half ? 0.05 : i == 0 ? 0.0 : 0.02);
				if (!ok) failed++;
				Sys.println('webdecode: ${names[i]}: ${ok ? "ok" : "FAIL"} (${Math.round(share * 10000) / 100}% of samples off by more than 24)');
				im.release();
			}
			Sys.println('webdecode: done, $failed failed');
		});
	}
}
