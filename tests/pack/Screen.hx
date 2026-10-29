import helder.os.*;

// The screen of a phone, without a GPU (CI's emulator and simulator jobs:
// tests/pack/android.sh and ios.sh read its lines, logcat's and simctl's):
// a Window, its size, scale and safe area; the display's frames (App.run's
// from Choreographer, CADisplayLink): the first ones' times, then over 120
// frames their mean, least and largest delta, the period App.frame
// learnt, whether they were vsyncs, and what was allocated meanwhile
// (nothing: the loop's frames are allocation-free); then the bars hidden
// (Window.immersive) and the safe area again. Then it runs until the system
// ends it, a line for each Resize (a rotation: its size and safe area),
// ScaleChange, Suspend and Resume (the first frame after it: its delta one
// period, not the time away), and every 240 frames.
//   helder build tests/pack/Screen.hx --target android-x86_64 | ios-sim
class Screen {
	static inline var MEASURED = 120;

	static final deltas = [for (_ in 0...MEASURED) 0.0];
	static var frames = 0;
	static var measuredFrom = -1;
	static var allocated = 0.0;
	static var resumed = false;

	static function main() {
		var w = new Window("Screen", 0, 0);
		Sys.println('screen: window ${w.width}x${w.height} scale ${w.scale} safe ${safe(w)}');
		App.run(() -> {
			frames++;
			var f = App.frame;
			if (frames <= 5) Sys.println('screen: frame $frames at ${ms(f.time)} delta ${ms(f.delta)} vsync ${f.vsync}');
			if (resumed) {
				resumed = false;
				Sys.println('screen: first frame after resume: delta ${ms(f.delta)} ms, period ${ms(f.period)} ms');
			}
			// (the frames measured: from the 10th, nothing printed meanwhile)
			if (frames == 10) {
				measuredFrom = frames;
				allocated = hxmc.GcStats.bytesAllocated();
			} else if (measuredFrom > 0 && frames <= measuredFrom + MEASURED) {
				deltas[frames - measuredFrom - 1] = f.delta;
				if (frames == measuredFrom + MEASURED) {
					allocated = hxmc.GcStats.bytesAllocated() - allocated;
					report(f);
					w.immersive = true;
					Sys.println("screen: immersive");
				}
			}
			if (frames % 240 == 0) Sys.println('screen: frames $frames');
		}, e -> switch e.kind {
			case Resize: Sys.println('screen: resize ${e.x}x${e.y} scale ${w.scale} safe ${safe(w)}');
			case ScaleChange: Sys.println('screen: scale ${w.scale}');
			case Suspend: Sys.println('screen: suspend at frame $frames');
			case Resume:
				resumed = true;
				Sys.println('screen: resume ${e.x}x${e.y} at frame $frames');
			case Close: w.close();
			case _:
		});
	}

	static function report(f:FrameClock) {
		var sum = 0.0, min = 1e9, max = 0.0;
		for (d in deltas) {
			sum += d;
			if (d < min) min = d;
			if (d > max) max = d;
		}
		Sys.println('screen: frames $MEASURED mean ${ms(sum / MEASURED)} min ${ms(min)} max ${ms(max)} period ${ms(f.period)} vsync ${f.vsync}');
		Sys.println('screen: allocated ${Std.int(allocated)} bytes in $MEASURED frames');
	}

	// top,left,bottom,right in pixels
	static function safe(w:Window):String
		return '${w.safeTop},${w.safeLeft},${w.safeBottom},${w.safeRight}';

	// seconds as ms, to a hundredth
	static function ms(s:Float):Float
		return Math.round(s * 100000) / 100;
}
