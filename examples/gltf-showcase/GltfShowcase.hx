// title: glTF sample models
// summary: Khronos' glTF sample models (DamagedHelmet, FlightHelmet, SciFiHelmet, MetalRoughSpheres and the extension tests: texture transform, emissive strength, clear coat, transmission) fetched from glTF-Sample-Assets, lit by prefiltered HDR environments through bloom and ACES; drag to orbit, pinch or scroll to zoom, pick a model and an environment
// tags: 3d, gltf, pbr, ibl, hdr, assets
// demo: canvas 960x600
// data: models
import helder.asset.Asset;
import helder.async.Async;
import helder.async.Fetch;
import helder.scene.debug.FrameStats;
import helder.scene.render.*;
import helder.scene.view.SceneTags.*;
import helder.ui.Clock;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// The showcase in a window: a <Scene hdr> of the model picked (Showcase:
// Khronos' sample models, prefiltered environments), <OrbitControls> about
// it, the pickers and the numbers over it. The models are fetched at run
// time (not bundled: tens of MB): from the first argument's folder (the
// site passes its own), else models/ or examples/gltf-showcase/models/
// natively (node examples/gltf-showcase/fetch.mjs puts them there); the
// second argument names the model to start with.
//
//   node examples/gltf-showcase/fetch.mjs
//   bun run helder examples/gltf-showcase/GltfShowcase.hx
class GltfShowcase implements Markup {
	static final show = new Showcase();
	static var renderer:Null<Renderer>;
	// (the renderer the environments were made for: a <Scene> may make its renderer again)
	static var prepared:Null<Renderer>;
	static var orbit:Null<helder.scene.view.OrbitControls>;
	static var base = "";
	// the load under way: its path, the bytes once here, whether it failed,
	// the model's index, when it started
	static var fetching:Null<String>;
	static var fetched:Null<haxe.io.Bytes>;
	static var failed = false;
	static var pending = -1;
	static var started = 0.0;
	static final stats = new FrameStats(240);

	static final model = signal(0);
	static final env = signal(0);
	static final status = signal("loading…");
	static final numbers = signal("");

	static function main() {
		var args = Sys.args();
		base = args.length > 0 ? args[0] : #if (hxmc.target == "wasm32-wasi") "models/" #else sys.FileSystem.exists("models") ? "models/" : "examples/gltf-showcase/models/" #end;
		Images.decode = Images.common;
		// (in a browser: the images decoded by the browser, off the module's memory)
		helder.image.Image.decodeInBrowser = true;
		// (Showcase.ENVIRONMENTS' atlases, in order, in the module itself: 350 KB)
		var envs = [
			Asset.embed("environments/studio_small_09.png"),
			Asset.embed("environments/venice_sunset.png"),
			Asset.embed("environments/kloofendal_48d_partly_cloudy_puresky.png")
		];
		var t0 = Sys.time(), last = -1.0, firstFrame = -1.0, loaded = 0.0, bytes = 0, printed = 0.0;
		// (the second argument: the model to start with, by name)
		var first = 0;
		for (k in 0...Showcase.MODELS.length)
			if (args.length > 1 && Showcase.MODELS[k].name == args[1]) first = k;
		load(first);
		Clock.add(t -> {
			// (the environments once their files are here, then the model once fetched)
			var r = renderer;
			if (r != null && r != prepared) {
				prepared = r;
				show.setup(r, envs);
				show.environment(r, env.peek());
			}
			var b = fetched;
			if (b != null && r != null) {
				fetching = null;
				fetched = null;
				var m = new Model(b, {}, {}, {}, {});
				show.show(m, r.device);
				bytes = b.length;
				loaded = Sys.time() - started;
				status(Showcase.MODELS[pending].name + " · " + mb(bytes) + " · " + Math.round(loaded * 1000) + " ms");
				var o = orbit;
				if (o != null) {
					o.target = show.centre();
					o.distance = show.fitDistance(960 / 600);
					o.yaw = 0;
					o.pitch = 0.15;
					o.minDistance = o.distance * 0.2;
					o.maxDistance = o.distance * 4;
					o.apply();
				}
				if (firstFrame < 0) firstFrame = Sys.time() - t0;
			} else if (failed) {
				status("could not fetch " + fetching + " (node examples/gltf-showcase/fetch.mjs)");
				fetching = null;
				failed = false;
			}
			if (last >= 0) stats.add(t - last);
			last = t;
			if (t - printed > 0.5 && stats.count > 10) {
				printed = t;
				var line = "first frame " + (firstFrame < 0 ? "–" : Math.round(firstFrame * 1000) + " ms") + " · frame p50 " + ms(percentile(0.5)) + " p99 "
					+ ms(percentile(0.99)) + " · textures " + mb(Std.int(r != null ? r.device.textureBytes : 0));
				numbers(line);
				// (the numbers for the site's page: site/numbers.mjs reads these lines)
				Sys.println('stats: {"firstFrameMs": ${Math.round(firstFrame * 1000)}, "downloadBytes": $bytes, "textureBytes": ${Std.int(r != null ? r.device.textureBytes : 0)}, "p50Ms": ${ms(percentile(0.5))}, "p99Ms": ${ms(percentile(0.99))}}');
			}
			true;
		});
		UiWindow.run(<Surface title="glTF sample models" width={960} height={600}>
			<view grow={1} direction="row" background="#101014" color="#ececf1" font-family="DejaVu Sans">
				<view width={190} padding={14} row-gap={6} background="#18181d">
					<text font-size={15} font-weight={700}>Model</text>
					{[for (k in 0...Showcase.MODELS.length) <Pick label={Showcase.MODELS[k].name} on={() -> model() == k} onPress={() -> load(k)}/>]}
					<text font-size={15} font-weight={700} margin-top={10}>Environment</text>
					{[for (k in 0...Showcase.ENVIRONMENTS.length) <Pick label={Showcase.ENVIRONMENTS[k].label} on={() -> env() == k} onPress={() -> {
						env(k);
						if (renderer != null) show.environment(renderer, k);
					}}/>]}
				</view>
				<view grow={1}>
					<Scene grow={1} world={show.world} camera={show.camera} hdr animate setup={r -> renderer = r}>
						<OrbitControls ref={o -> orbit = o} damping={0.15}/>
					</Scene>
					<view position="absolute" left={12} top={10} pointer-events="none" row-gap={2} padding="6 10" radius={8} background="#000000a0">
						<text font-size={13}>{status}</text>
						<text font-size={12} color="#a1a1ad">{numbers}</text>
					</view>
					<text position="absolute" left={12} bottom={8} right={12} font-size={11} color="#c4c4cc" pointer-events="none" padding="4 8" radius={6} background="#000000a0">{Showcase.MODELS[model()].name + ": "
						+ Showcase.MODELS[model()].credit + " · KhronosGroup/glTF-Sample-Assets · panoramas: Poly Haven (CC0)"}</text>
				</view>
			</view>
		</Surface>);
	}

	static function Pick(props:{label:String, on:Void->Bool, onPress:Void->Void}):View
		return <view:button role="button" focusable cursor="pointer" padding="5 10" radius={6} background={props.on() ? "#2f4f9e" : "#24242b"}
			onPress={props.onPress}><text font-size={13}>{props.label}</text></view:button>;

	// model k fetched (shown when it is here)
	static function load(k:Int) {
		model(k);
		pending = k;
		started = Sys.time();
		status("loading " + Showcase.MODELS[k].name + "…");
		var path = base + Showcase.MODELS[k].name + ".glb";
		fetching = path;
		fetched = null;
		failed = false;
		Async.launch(_ -> Fetch.bytes(path)).onCompletion((b, e) -> if (fetching == path) {
			if (e != null) failed = true else fetched = b;
		});
	}

	// the frames' time at a share of them (0.5: the median), in seconds
	static function percentile(p:Float):Float {
		var xs = [for (k in 0...stats.count) stats.at(k)];
		xs.sort(Reflect.compare);
		return xs.length == 0 ? 0 : xs[Std.int(Math.min(xs.length - 1, Math.floor(p * xs.length)))];
	}

	static function ms(s:Float):Float
		return Math.round(s * 10000) / 10;

	static function mb(bytes:Int):String
		return Math.round(bytes / 104857.6) / 10 + " MB";
}
