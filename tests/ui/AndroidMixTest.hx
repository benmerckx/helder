import helder.gfx.*;
import helder.os.android.MainThread;
import helder.ui.*;
import helder.ui.native.*;
import helder.ui.native.Controls.*;
import helder.ui.native.android.AndroidBackend;
import helder.ui.native.android.GpuView;
import helder.view.*;
import helder.view.graph.Graph.*;

// A GPU view among Android's views (CI's android job, read from logcat by
// tests/ui/android-mix.sh): gfx's cube turning in a GpuView
// between a label, a slider and a button of a NativeHost. Checked: the
// views made and placed around it, frames drawn into its SurfaceView and
// lit, the button stopping and starting its frames (a signal); then left
// to the script: Home takes its surface (no frames), the activity back
// gives it a new one and the frames go on; then the window closes.
//   haxe -lib helder -cp examples -cp tests/ui -main AndroidMixTest
//     --custom-target hxmc=AndroidMixTest.apk -D hxmc.target=android-x86_64 -D hxmc.android-package=org.hxmc.mixtest
class AndroidMixTest implements Markup {
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) failed++;
		Sys.println('AndroidMixTest: ${ok ? "ok" : "FAIL"}: $what' + (detail == null ? "" : " (" + detail + ")"));
	}

	static inline function on(f:Void->Void)
		MainThread.run(f);

	static function settle(seconds = 0.4) {
		var t = haxe.Timer.stamp();
		while (haxe.Timer.stamp() - t < seconds)
			MainThread.wait(0.05);
	}

	public final speed = signal(1.0);
	public final spinning = signal(true);

	public function new() {}

	public function view():View
		return <view grow={1} padding={16} row-gap={10} font-size={14}>
			<text font-size={18} font-weight={700}>A GPU view among views</text>
			<view tag="stage" height={220}/>
			<view direction="row" column-gap={10} align-items="center">
				<Slider tag="speed" value={speed} max={3} style={{width: 160}}/>
				<Button tag="spin" label={() -> spinning() ? "Stop" : "Spin"} onClick={() -> spinning(!spinning())}/>
			</view>
		</view>;

	static function main() {
		Sys.println("AndroidMixTest: start");
		var backend = new AndroidBackend();
		var driver:NativeDriver = backend;
		var host = new NativeHost("AndroidMixTest", 0, 0, backend);
		var app = new AndroidMixTest();
		Render.render(app.view(), host.root);
		var gpu = new GpuView("cube");
		gpu.style.set({grow: 1});
		var stage = host.root.find("stage");
		stage.append(gpu);
		// the cube, turning while spinning, at the slider's speed; a frame's pixels read back
		var cube:Cube = null, angle = 0.0, drawn = 0, lit = "";
		gpu.onDevice = d -> cube = new Cube(d);
		gpu.draw = enc -> {
			angle += 0.03 * app.speed();
			cube.draw(enc, angle);
			drawn++;
			if (drawn == 20) {
				var d = gpu.device, px = haxe.io.Bytes.alloc(d.width * d.height * 4);
				d.readPixels(px);
				var c = 4 * ((d.height >> 1) * d.width + (d.width >> 1));
				lit = '${d.width}x${d.height} ' + (Math.abs(px.get(c) - px.get(0)) + Math.abs(px.get(c + 1) - px.get(1)) + Math.abs(px.get(c + 2) - px.get(2)) > 30 ? "lit" : "nothing drawn");
			}
		};
		root(_ -> renderEffect(() -> app.spinning(), on -> gpu.animate = on));
		AndroidBackend.start(host);
		var t0 = haxe.Timer.stamp(), frames = 0;
		while (frames < 60 && haxe.Timer.stamp() - t0 < 20) {
			settle(0.25);
			on(() -> frames = gpu.frames);
		}
		on(() -> {
			var slider:Control = cast host.root.find("speed"), spin:Control = cast host.root.find("spin");
			check("the views made", slider.handle != 0 && spin.handle != 0);
			check("frames in the GPU view", gpu.frames >= 60 && gpu.hasSurface(), gpu.frames + " frames");
			check("its pixels lit", StringTools.endsWith(lit, " lit"), lit);
			check("laid out between the views", gpu.absY >= stage.absY && gpu.height == 220 && slider.absY >= gpu.absY + gpu.height,
				'gpu at ${gpu.absY} ${gpu.width}x${gpu.height}, slider at ${slider.absY}');
			var a = driver.allocation(slider.handle);
			check("the slider placed", a.length == 4 && Math.abs(a[1] - slider.absY) <= 1, a.join(","));
			driver.click(spin.handle);
		});
		// the button stops the frames (a signal), and starts them again
		settle(0.5);
		var stopped = 0;
		on(() -> stopped = gpu.frames);
		settle(0.6);
		on(() -> {
			check("Stop: no frames", gpu.frames == stopped && !app.spinning(), '$stopped -> ${gpu.frames}');
			driver.click((cast host.root.find("spin") : Control).handle);
		});
		settle(0.6);
		on(() -> check("Spin: frames again", gpu.frames > stopped + 10, '$stopped -> ${gpu.frames}'));
		Sys.println("AndroidMixTest: ready");
		// the script: Home (the surface goes, no frames), back (a new one, frames)
		var lost = false, back = false, at = 0, last = "";
		t0 = haxe.Timer.stamp();
		while (haxe.Timer.stamp() - t0 < 90 && !host.closed) {
			var surface = false, n = 0;
			on(() -> {
				surface = gpu.hasSurface();
				n = gpu.frames;
			});
			var now = surface ? "surface" : "no surface";
			if (now != last) Sys.println('AndroidMixTest: $now, $n frames');
			last = now;
			if (!surface) lost = true;
			if (lost && surface && !back) {
				back = true;
				at = n;
			}
			if (back && n > at + 30) break;
			settle(0.2);
		}
		check("the surface taken and given back, frames after", lost && back, last);
		Sys.println("AndroidMixTest: resumed");
		settle(3);
		Sys.println('AndroidMixTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		on(() -> host.close());
		Sys.println("AndroidMixTest: done");
	}
}
