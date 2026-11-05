package helder.image;

// A decode's running total (an animation's frames), within maxMemory
class DecodeBudget {
	public var used(default, null):Float;

	final format:String;

	public function new(format:String, initial:Float) {
		this.format = format;
		used = initial;
		ImageLimits.memory(format, used);
	}

	public function add(bytes:Float) {
		used += bytes;
		ImageLimits.memory(format, used);
	}
}
