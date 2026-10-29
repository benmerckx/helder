package helder.os;

// A frame's time (App.frame): when the display showed the frame before it
// (Android's Choreographer, iOS's CADisplayLink: the vsync's timestamp),
// else when the frame began, in haxe.Timer.stamp()'s seconds; the time since
// the frame before (delta), and the display's period (its refresh interval,
// estimated from the deltas: those under 1.5 periods, smoothed). The first
// frame, and the first after a pause (the app in the background, the
// window lost), has a delta of one period, not the time it was away. Plain
// fields and arithmetic: nothing allocated a frame. It imports nothing (its
// tests: FrameClock.test.hx).
class FrameClock {
	// a 60 Hz display's period, until frames tell
	public static inline var PERIOD = 1 / 60;

	// the frame's time (s), the time since the last frame (s)
	public var time(default, null) = 0.0;
	public var delta(default, null) = PERIOD;
	// the display's refresh interval (s)
	public var period(default, null) = PERIOD;
	// frames since the start
	public var count(default, null) = 0;
	// whether the frame comes from the display's vsync (Android, iOS), not the loop
	public var vsync(default, null) = false;

	// (the next tick starts afresh: the first, or after a pause)
	var fresh = true;
	// (the deltas the period was smoothed from)
	var samples = 0;

	public function new() {}

	// a frame at t (s); fromDisplay: a vsync's time
	public function tick(t:Float, fromDisplay:Bool) {
		vsync = fromDisplay;
		if (fresh) {
			delta = period;
			fresh = false;
		} else {
			var d = t - time;
			// (a clock that went back, or the same vsync twice: no time passed)
			delta = d > 0 ? d : 0;
			// (frames missed, a stall: not the display's period; the first few taken as they come)
			if (d > 0.002 && d < 0.25 && (samples < 3 || d < period * 1.5)) {
				period = samples < 3 ? (period * samples + d) / (samples + 1) : period * 0.9 + d * 0.1;
				samples++;
			}
		}
		time = t;
		count++;
	}

	// frames stopped (the background, the surface lost): the next delta is a period
	public function pause()
		fresh = true;

	// the display's time `display` (a vsync's, in its clock: seconds) in
	// haxe.Timer.stamp()'s, now being displayNow there and stampNow here
	public static inline function toStamp(display:Float, displayNow:Float, stampNow:Float):Float
		return stampNow - (displayNow - display);
}
