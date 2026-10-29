import helder.os.Store;

// The save: best strokes per hole (0: not finished yet), kept between runs
// in helder.os's Store ("floating-greens": a file in the app's data
// directory, localStorage on the web), as "best" = "3,2,0,...".
class Save {
	final store:Null<Store>;

	public function new() {
		store = try Store.open("floating-greens") catch (_:Dynamic) null;
	}

	public function best(holes:Int):Array<Int> {
		var text = store == null ? null : store.get("best");
		var parts = text == null ? [] : text.split(",");
		return [for (i in 0...holes) i < parts.length ? (Std.parseInt(parts[i]) ?? 0) : 0];
	}

	public function write(best:Array<Int>)
		if (this.store != null) this.store.set("best", best.join(","));
}
