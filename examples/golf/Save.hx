// Best strokes per hole (0: not finished).
class Save {
	var data:Array<Int> = [];

	public function new() {}

	public function best(holes:Int):Array<Int>
		return [for (i in 0...holes) data[i] ?? 0];

	public function store(best:Array<Int>)
		data = best.copy();
}
