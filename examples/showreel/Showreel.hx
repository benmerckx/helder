// title: Showreel
// summary: helder's showreel: purpose-made 1280×720 scenes (a launch assembling on springs, a matched photo zoom, rolling numbers, a million rows flung end to end, type at every size, a glowing 3D material, a generative canvas, a theme morphing), each animating itself from the clock so a headless --video records it frame-exact
// tags: ui, view, motion, 3d, canvas, showcase
// demo: canvas 1280x720
import Reel.*;
import Reel.SceneDef;
import helder.ui.Clock;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

// The scenes play one after another (cross-fading: each a keyed row whose
// presence fades), looping; `-- --scene <name>` plays one alone:
//
//   helder run examples/showreel -- --scene launch
//   helder run --headless examples/showreel --video reel.mp4 --duration 60
//   helder run --headless examples/showreel --video zoom.mp4 --duration 7 -- --scene zoom
//
// Every scene is a function of its own time (Reel.hx), read from ui's
// Clock: the display's, or a headless run's virtual one, frame n at n / 60
// s, so the recording is frame-exact. site/reel.mjs records the reel and a
// clip of each scene for the site. Under reduced motion (--reduced-motion)
// each scene shows its last state, still.
class Showreel implements Markup {
	public static final SCENES:Array<SceneDef> = [Title.scene, Launch.scene, Zoom.scene, Odometer.scene, Fling.scene, Specimen.scene, Knot.scene, Threads.scene, Morph.scene];

	// seconds since the reel (or the scene) began
	static final clock:Signal<Float> = signal(0.0);

	static function main() {
		Reel.fonts();
		var args = Sys.args(), only = -1;
		var k = args.indexOf("--scene");
		if (k >= 0 && k + 1 < args.length) {
			for (i in 0...SCENES.length)
				if (SCENES[i].name == args[k + 1]) only = i;
			if (only < 0) {
				Sys.println("showreel: no scene " + args[k + 1] + " (" + [for (s in SCENES) s.name].join(", ") + ")");
				Sys.exit(2);
			}
		}
		var start = -1.0;
		Clock.add(now -> {
			if (start < 0) start = now;
			clock(now - start);
			true;
		});
		UiWindow.run(<Surface title="helder · showreel" width={W} height={H} background={NIGHT}>{view(only)}</Surface>);
	}

	// the total length of the reel (s)
	public static function length():Float {
		var s = 0.0;
		for (d in SCENES)
			s += d.duration;
		return s;
	}

	// which scene plays at time t, and since when
	static function sceneAt(t:Float):{index:Int, start:Float} {
		var total = length(), x = t % total, s = 0.0;
		var loop = Math.floor(t / total) * total;
		for (i in 0...SCENES.length) {
			if (x < s + SCENES[i].duration) return {index: i, start: loop + s};
			s += SCENES[i].duration;
		}
		return {index: SCENES.length - 1, start: loop + s - SCENES[SCENES.length - 1].duration};
	}

	// a scene from its start on: its own time, fading in over the last and out under the next
	static function playing(start:Float):View {
		var s = sceneAt(start + 0.001), t = memo(() -> clock() - start);
		return <view position="absolute" left={0} top={0} right={0} bottom={0} transition="fade" motion-presence="calm">{SCENES[s.index].view(t)}</view>;
	}

	public static function view(only:Int):View {
		if (only >= 0) {
			// (reduced motion: the scene's last state, still)
			var t = memo(() -> Clock.reducedMotion ? SCENES[only].duration : clock());
			return <view grow={1}>{SCENES[only].view(t)}</view>;
		}
		// (the scene playing, by its start: a new row each time one begins, the last fading out under it)
		var current = memo(() -> sceneAt(clock()).start);
		var starts = memo(() -> [current()]);
		return <view grow={1} background={NIGHT}>
			<For each={starts}>{(start:Read<Float>) -> playing(untrack(() -> start()))}</For>
		</view>;
	}
}
