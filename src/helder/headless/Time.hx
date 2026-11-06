package helder.headless;

// A headless run's virtual clock (helder.headless.Headless): the seconds
// since the run began, as the loop has stepped them (each frame 1/fps
// later; an event's own time while it is handled). What reads the time in
// a build for a headless run (-D helder.headless: App's frames, ui's Clock
// and events, helder.async's timers) reads this instead of
// haxe.Timer.stamp(), so a run is the same whatever the machine's speed.
// It imports nothing: the loops below helder.os read it too.
class Time {
	public static var now = 0.0;

	// the clock a build reads: this one in a headless build, the system's otherwise
	public static inline function stamp():Float
		return #if helder.headless now #else haxe.Timer.stamp() #end;
}
