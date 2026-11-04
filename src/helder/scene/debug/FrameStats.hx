package helder.scene.debug;

// Frame timing: the last frames' times (seconds), their average, minimum
// and maximum, and the renderer's counts of the last frame; what the
// overlay (Overlay) shows and a game may log.
class FrameStats {
	public final capacity:Int;
	final times:Array<Float>;
	final cpus:Array<Float>;
	// (percentile's sorted copy, kept)
	final sorted:Array<Float>;
	var next = 0;
	public var count(default, null) = 0;
	public var draws = 0;
	public var culled = 0;
	public var instanced = 0;

	public function new(capacity = 120) {
		this.capacity = capacity;
		times = [for (_ in 0...capacity) 0.0];
		cpus = [for (_ in 0...capacity) 0.0];
		sorted = [for (_ in 0...capacity) 0.0];
	}

	// a frame took seconds (from the last frame's start to this one's), of
	// which cpu seconds were the program's own work (its update and
	// recording, measured by the program; 0: not measured)
	public function add(seconds:Float, cpu = 0.0) {
		times[next] = seconds;
		cpus[next] = cpu;
		next = (next + 1) % capacity;
		if (count < capacity) count++;
	}

	// the k-th newest frame's time (0: the last)
	public function at(k:Int):Float
		return k < count ? times[(next - 1 - k + capacity * 2) % capacity] : 0;

	// forgets the frames kept
	public function clear() {
		count = 0;
		next = 0;
	}

	// the k-th newest frame's CPU time (0: the last)
	public function cpuAt(k:Int):Float
		return k < count ? cpus[(next - 1 - k + capacity * 2) % capacity] : 0;

	// the p-th percentile of the frames' times (0.5: the median, 0.99), or
	// of their CPU times; allocates nothing
	public function percentile(p:Float, cpu = false):Float {
		if (count == 0) return 0;
		for (k in 0...count) {
			var v = cpu ? cpuAt(k) : at(k), j = k - 1;
			while (j >= 0 && sorted[j] > v) {
				sorted[j + 1] = sorted[j];
				j--;
			}
			sorted[j + 1] = v;
		}
		var i = Math.ceil(p * count) - 1;
		return sorted[i < 0 ? 0 : i >= count ? count - 1 : i];
	}

	// frames a second over the frames kept (their average's inverse)
	public function fps():Float {
		var a = average();
		return a > 0 ? 1 / a : 0;
	}

	public function average():Float {
		var s = 0.0;
		for (k in 0...count)
			s += at(k);
		return count > 0 ? s / count : 0;
	}

	public function max():Float {
		var m = 0.0;
		for (k in 0...count)
			if (at(k) > m) m = at(k);
		return m;
	}

	public function min():Float {
		if (count == 0) return 0;
		var m = at(0);
		for (k in 0...count)
			if (at(k) < m) m = at(k);
		return m;
	}

	// a line for the examples site's numbers (site/numbers.mjs reads the
	// last `stats: {...}` printed): the first frame (seconds from the
	// start), the bytes fetched beyond the module, the textures' bytes
	// (Device.textureBytes), the frame times' p50 and p99
	public function report(firstFrame:Float, downloadBytes:Float, textureBytes:Float):String {
		inline function ms(s:Float):Float
			return Math.round(s * 10000) / 10;
		return 'stats: {"firstFrameMs": ${Math.round(firstFrame * 1000)}, "downloadBytes": ${Std.int(downloadBytes)}, "textureBytes": ${Std.int(textureBytes)}, '
			+ '"p50Ms": ${ms(percentile(0.5))}, "p99Ms": ${ms(percentile(0.99))}, "cpuP50Ms": ${ms(percentile(0.5, true))}, "cpuP99Ms": ${ms(percentile(0.99, true))}}';
	}

	// the renderer's counts of its last draw
	public function from(r:helder.scene.render.Renderer) {
		draws = r.draws;
		culled = r.culled;
		instanced = r.instanced;
	}
}
