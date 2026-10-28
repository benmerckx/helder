// The smallest app helder packages (the pack lane; CI's emulator and
// simulator jobs, tests/pack/android.sh and ios.sh): it prints a line and
// returns. On Android its library is NativeActivity's through
// helder.os.android.Activity (ANativeActivity_onCreate, the program on a
// thread of its own, its output in logcat under the tag hxmc); on iOS
// hxmc's generated main runs it as on any other target.
class Hello {
	static function main() {
		#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		helder.os.android.Activity.activity;
		#end
		// (the collector, a map, an exception: the runtime at work)
		var squares = [for (i in 0...1000) Std.string(i * i)];
		var m = new Map<String, Int>();
		for (s in squares) m[s] = s.length;
		var caught = try {
			throw "boom";
		} catch (e:String) e;
		Sys.println('hello from helder on ' + Sys.systemName() + ': ' + squares[999] + ' ' + m["998001"] + ' ' + caught);
	}
}
