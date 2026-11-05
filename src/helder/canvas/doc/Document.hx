package helder.canvas.doc;

// Pages of recordings (each its own size): a multi-page PDF, an SVG a page
class Document {
	public final pages:Array<Recorder> = [];

	public function new() {}

	public function newPage(width:Int, height:Int):Recorder {
		var r = new Recorder(width, height);
		pages.push(r);
		return r;
	}
}
