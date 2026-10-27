import helder.ui.*;

// A ui program without a window for the devtools lane: a Ui of a few boxes
// laid out each frame (no text engine: no text), as App's loop has it.
class Boxes {
	static function main() {
		var ui = new Ui(new NoText(), 320, 200);
		var row = new Node("row");
		row.style.direction = Row;
		row.style.padding = 8;
		row.style.background = Color.rgb(0x18181b);
		for (i in 0...3) {
			var b = new Node("box");
			b.style.width = 60;
			b.style.height = 40;
			row.append(b);
		}
		ui.root.append(row);
		trace("v1 boxes");
		#if hxmc.dev
		while (helder.dev.Hot.poll()) {
			ui.update();
			helder.dev.Hot.framed();
			Sys.sleep(1 / 60);
		}
		#end
	}
}

class NoText implements TextEngine {
	public function new() {}

	public function layout(text:String, font:Font, maxWidth:Float, ?spans:Array<TextSpan>, maxLines:Int = 0, justify:Bool = false, base:Int = -1,
			cut:Float = -1, ?into:Paragraph):Paragraph
		throw "no text here";
}
