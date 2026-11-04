import haxe.io.Bytes;
import helder.gfx.*;
import helder.image.PngEncoder;
import helder.os.Surface;
import helder.scene.render.*;
import sys.io.File;

// The showcase's frames headless (Mesa's llvmpipe on Linux), for the
// README's comparisons with the sample viewer's renders: each model fetched
// into models/ (fetch.mjs) from its own camera, else from the front, lit by the studio environment,
// in HDR through bloom and ACES, as <out>/<name>.png (on a plain grey, the
// environment lighting it not drawn).
//
//   helder build examples/gltf-showcase/Shots.hx -o bin/shots
//   LIBGL_ALWAYS_SOFTWARE=1 HXMC_GFX_SOFTWARE=1 bin/shots examples/gltf-showcase <out> [names...] [--env k] [--size n]
class Shots {
	static function main() {
		var args = Sys.args();
		var dir = args.shift(), out = args.shift();
		var env = 0, size = 384;
		var names = [];
		while (args.length > 0) {
			var a = args.shift();
			if (a == "--env") env = Std.parseInt(args.shift()) else if (a == "--size") size = Std.parseInt(args.shift()) else names.push(a);
		}
		if (names.length == 0) names = [for (m in Showcase.MODELS) m.name];
		Images.decode = Images.common;
		var device = Device.create(Surface.headless(size, size));
		var renderer = new Renderer(device, true, 1, true);
		var show = new Showcase();
		show.setup(renderer, [for (e in Showcase.ENVIRONMENTS) File.getBytes('$dir/environments/${e.file}.png')]);
		show.environment(renderer, env);
		// (a plain grey behind the models, as the sample viewer's renders)
		for (e in show.environments)
			e.background = false;
		renderer.clearColor = new Color(0.25, 0.25, 0.25, 1);
		var post = new PostProcess(device, RGBA8, true);
		post.bloom = 0.02;
		var color = device.createTexture({width: size, height: size, format: RGBA16F, renderTarget: true});
		var depth = device.createTexture({width: size, height: size, format: Depth32F, renderTarget: true});
		var pixels = Bytes.alloc(size * size * 4);
		for (name in names) {
			var t0 = Sys.time();
			var model = new Model(File.getBytes('$dir/models/$name.glb'), {}, {}, {}, {});
			show.show(model, device);
			show.look(0, 0);
			var t1 = Sys.time();
			var enc = device.beginFrame();
			// (the file's camera where it has one: the sample viewer's view)
			renderer.drawInto(enc, show.world, show.fileCamera ?? show.camera, color, depth, size, size);
			post.run(enc, color, null, size, size);
			device.readPixels(pixels);
			device.endFrame();
			File.saveBytes('$out/$name.png', PngEncoder.encode(pixels, size, size));
			Sys.println('$name: loaded in ${Math.round((t1 - t0) * 1000)} ms, ${renderer.draws} draws');
			model.dispose();
		}
		device.dispose();
	}
}
