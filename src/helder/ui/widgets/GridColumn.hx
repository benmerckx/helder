package helder.ui.widgets;

// A data grid's column: its title, a detail drawn quieter beside it (a
// type), its width (pixels; the user resizes it) and how its cells align.
class GridColumn {
	public final title:String;
	public final detail:String;
	public var width:Float;
	public final align:TextAlign;

	public function new(title:String, width = 160.0, ?align:TextAlign, detail = "") {
		this.title = title;
		this.width = width;
		this.align = align ?? Left;
		this.detail = detail;
	}
}
