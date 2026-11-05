// title: Sponza
// summary: Crytek's Sponza atrium (glTF-Sample-Assets' glTF version) with GPU-compressed textures picked for the device (BC1/BC3 on desktops and the web, ASTC 4x4 on phones: the asset step's Pack --textures), a sun with cascaded shadows, image-based light, HDR, bloom and ACES; a scripted fly-through, or fly yourself (drag to look, WASD or the arrows, Q and E), and the numbers over it
// tags: 3d, gltf, pbr, hdr, shadows, compressed textures, assets
// demo: canvas 960x600
// data: models
import helder.asset.Asset;
import helder.gfx.shader.Vec3;
import helder.async.Async;
import helder.async.Fetch;
import helder.scene.*;
import helder.scene.debug.FrameStats;
import helder.scene.render.*;
import helder.scene.view.SceneTags.*;
import helder.ui.Clock;
import helder.ui.Key;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// Sponza in a window: the model packed by the asset step (fetch.mjs:
// Pack, its textures as the file has them, as BC and as ASTC), the file
// fetched at run time picked by what the GPU samples (Device.supports:
// Sponza.bc.hxm3d, else Sponza.astc.hxm3d, else Sponza.hxm3d's PNG and
// JPEG; the second argument forces one: bc, astc, png); a <Scene hdr>
// lit by a sun with two shadow cascades and a prefiltered sky
// (environment.png, gltf-showcase's), bloom and ACES. The camera flies a
// loop through the atrium until a drag or a key takes it (Fly resumes it).
//
//   node examples/sponza/fetch.mjs
//   bun run helder examples/sponza/Sponza.hx
class Sponza implements Markup {
	static final world = new World("sponza");
	static final eye = world.node("eye");
	static final camera = Camera.attach(eye, Camera.perspective(1.0, 0.05, 120));
	static var renderer:Null<Renderer>;
	static var prepared:Null<Renderer>;
	// the fetch under way: its path, the bytes once here, whether it failed
	static var fetching:Null<String>;
	static var fetched:Null<haxe.io.Bytes>;
	static var failed = false;
	static var variant = "";
	static var base = "";
	static final stats = new FrameStats(240);
	static final status = signal("loading…");
	static final numbers = signal("");
	static final flying = signal(true);

	// the free camera: where it is, where it looks (yaw, pitch), the keys held
	static var yaw = Math.PI / 2;
	static var pitch = 0.0;
	static var at = new Vec3(-11, 1.8, 0);
	static final held = new Map<Int, Bool>();
	static var dragging = false;
	static var lastX = 0.0;
	static var lastY = 0.0;

	// the fly-through's keys: places and what they look at (metres; Sponza
	// is 30 by 18 by 12), a loop of PERIOD seconds
	static final PATH:Array<Array<Float>> = [
		[-11, 1.6, 0, 10, 2.2, 0], [-3, 1.8, 1.2, 6, 3, -0.5], [6, 2.0, -1.2, 13, 2.5, 0], [10.5, 5.2, 0, -5, 6, 0], [1, 6.5, 0.8, -10, 6, -1],
		[-9, 4, -1, 5, 1.5, 0]
	];
	static inline var PERIOD = 48.0;

	static function main() {
		var args = Sys.args();
		base = args.length > 0 ? args[0] : #if (hxmc.target == "wasm32-wasi") "models/" #else sys.FileSystem.exists("models") ? "models/" : "examples/sponza/models/" #end;
		variant = args.length > 1 ? args[1] : "";
		Images.decode = Images.common;
		helder.image.Image.decodeInBrowser = true;
		var sky = Asset.embed("environment.png");
		var t0 = Sys.time(), last = -1.0, firstFrame = -1.0, bytes = 0, printed = 0.0, started = 0.0;
		Clock.add(t -> {
			var r = renderer;
			if (r != null && r != prepared) {
				prepared = r;
				r.clearColor = new helder.gfx.Color(0.6, 0.7, 0.9, 1);
				r.use(new NormalMaps(r.device));
				var s = Shadows.cascaded(r.device, 2048, 14);
				s.strength = 0.9;
				r.use(s);
				var env = Environment.prefiltered(r.device, "image/png", sky, 6);
				if (env != null) {
					env.intensity = 2.0;
					r.use(env);
				}
				r.exposure = 1.3;
				if (fetching == null && bytes == 0) {
					// (the GPU's own format, else the images as the file has them)
					if (variant == "") variant = r.device.supports(BC1) ? "bc" : r.device.supports(ASTC4x4) ? "astc" : "png";
					started = Sys.time();
					status("fetching Sponza (" + variant + ")…");
					var path = base + "Sponza" + (variant == "png" ? "" : "." + variant) + ".hxm3d";
					fetching = path;
					Async.launch(_ -> Fetch.bytes(path)).onCompletion((b, e) -> if (fetching == path) {
						if (e != null) failed = true else fetched = b;
					});
				}
			}
			var b = fetched;
			if (b != null && r != null) {
				fetching = null;
				fetched = null;
				bytes = b.length;
				var t1 = Sys.time();
				PackedModel.read(b, r.device).instantiate(world);
				var sun = world.node("sun");
				Light.attach(sun, Light.directional(new Vec3(1, 0.93, 0.82), 7));
				sun.lookAt(new Vec3(0.25, -1, 0.3));
				status("Sponza (" + variant + ") · " + mb(bytes) + " fetched in " + Math.round((t1 - started) * 1000) + " ms, made in "
					+ Math.round((Sys.time() - t1) * 1000) + " ms");
				firstFrame = Sys.time() - t0;
			} else if (failed) {
				status("could not fetch " + fetching + " (node examples/sponza/fetch.mjs)");
				fetching = null;
				failed = false;
			}
			var dt = last >= 0 ? Math.min(t - last, 0.1) : 0;
			if (last >= 0) stats.add(t - last);
			last = t;
			if (flying.peek()) fly(t) else walk(dt);
			if (t - printed > 0.5 && stats.count > 10) {
				printed = t;
				var tex = Std.int(r != null ? r.device.textureBytes : 0);
				numbers("first frame " + (firstFrame < 0 ? "–" : Math.round(firstFrame * 1000) + " ms") + " · frame p50 " + ms(percentile(0.5)) + " p99 "
					+ ms(percentile(0.99)) + " ms · " + (r != null ? r.draws : 0) + " draws · textures " + mb(tex));
				Sys.println('stats: {"firstFrameMs": ${Math.round(firstFrame * 1000)}, "downloadBytes": $bytes, "textureBytes": $tex, "p50Ms": ${ms(percentile(0.5))}, "p99Ms": ${ms(percentile(0.99))}, "variant": "$variant"}');
			}
			true;
		});
		UiWindow.run(<Surface title="Sponza" width={960} height={600}>
			<view grow={1} background="#101014" color="#ececf1" font-family="DejaVu Sans">
				<Scene grow={1} world={world} camera={camera} hdr animate setup={r -> renderer = r}/>
				<view position="absolute" left={0} top={0} right={0} bottom={0} focusable cursor="grab" onPointerDown={e -> {
					dragging = true;
					lastX = e.x;
					lastY = e.y;
					take();
				}} onPointerMove={e -> if (dragging) {
					yaw -= (e.x - lastX) * 0.005;
					pitch = Math.max(-1.4, Math.min(1.4, pitch - (e.y - lastY) * 0.005));
					lastX = e.x;
					lastY = e.y;
				}} onPointerUp={_ -> dragging = false} onPointerCancel={_ -> dragging = false} onKeyDown={e -> {
					held.set(e.key, true);
					if (moveKey(e.key)) take();
				}} onKeyUp={e -> held.remove(e.key)}/>
				<view position="absolute" left={12} top={10} pointer-events="none" row-gap={2} padding="6 10" radius={8} background="#000000a0">
					<text font-size={13}>{status}</text>
					<text font-size={12} color="#c4c4cc">{numbers}</text>
				</view>
				<view position="absolute" right={12} top={10} direction="row" column-gap={8}>
					<view:button role="button" focusable cursor="pointer" padding="5 12" radius={6} background={flying() ? "#2f4f9e" : "#24242b"}
						onPress={() -> flying(true)}><text font-size={13}>Fly-through</text></view:button>
				</view>
				<text position="absolute" left={12} bottom={8} font-size={11} color="#c4c4cc" pointer-events="none" padding="4 8" radius={6} background="#000000a0">
					Sponza: Crytek (CRYENGINE Limited License Agreement), glTF-Sample-Assets · drag to look, WASD or the arrows to move, Q and E down and up
				</text>
			</view>
		</Surface>);
	}

	static function moveKey(k:Int):Bool
		return [0x77, 0x61, 0x73, 0x64, 0x71, 0x65, Key.UP, Key.DOWN, Key.LEFT, Key.RIGHT].contains(k);

	// the free camera takes over where the fly-through is
	static function take() {
		if (!flying.peek()) return;
		flying(false);
		at = eye.position;
		var f = MathToolsForward.forward(eye);
		yaw = Math.atan2(f.x, -f.z);
		pitch = Math.asin(Math.max(-1, Math.min(1, f.y)));
	}

	static function down(k:Int):Bool
		return held.exists(k);

	// the free camera: the keys move it along where it looks
	static function walk(dt:Float) {
		var f = new Vec3(Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), -Math.cos(yaw) * Math.cos(pitch));
		var right = new Vec3(Math.cos(yaw), 0, Math.sin(yaw));
		var speed = 4.0 * dt;
		var move = new Vec3(0, 0, 0);
		if (down(0x77) || down(Key.UP)) move = move + f;
		if (down(0x73) || down(Key.DOWN)) move = move - f;
		if (down(0x64) || down(Key.RIGHT)) move = move + right;
		if (down(0x61) || down(Key.LEFT)) move = move - right;
		if (down(0x65)) move = move + new Vec3(0, 1, 0);
		if (down(0x71)) move = move - new Vec3(0, 1, 0);
		at = at + move * speed;
		eye.position = at;
		eye.lookAt(at + f);
	}

	// the fly-through at time t: Catmull-Rom through PATH's places and targets
	static function fly(t:Float) {
		var u = (t % PERIOD) / PERIOD * PATH.length, k = Math.floor(u), s = u - k;
		function key(i:Int, c:Int):Float
			return PATH[(i % PATH.length + PATH.length) % PATH.length][c];
		function spline(c:Int):Float {
			var p0 = key(k - 1, c), p1 = key(k, c), p2 = key(k + 1, c), p3 = key(k + 2, c);
			return 0.5 * (2 * p1 + (p2 - p0) * s + (2 * p0 - 5 * p1 + 4 * p2 - p3) * s * s + (3 * p1 - p0 - 3 * p2 + p3) * s * s * s);
		}
		eye.position = new Vec3(spline(0), spline(1), spline(2));
		eye.lookAt(new Vec3(spline(3), spline(4), spline(5)));
	}

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

// (the way a node looks: its -z in the world)
private class MathToolsForward {
	public static function forward(n:Node):Vec3 {
		var m = n.worldMatrix();
		var z = m.c2;
		var l = Math.sqrt(z.x * z.x + z.y * z.y + z.z * z.z);
		return new Vec3(-z.x / l, -z.y / l, -z.z / l);
	}
}
