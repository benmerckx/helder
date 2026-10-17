package hxmc.ui;

// A node's style: flexbox layout (Layout) and how the node is drawn. Each
// property's setter tells the node what changed (its layout, or only its
// paint), so that only that is redone. The text properties from color on
// are inherited: null takes the parent's (resolved by Node's font() and
// textColor()). Generated once: a property is a field with a setter
// calling the node's styleChanged.
class Style {
	// the root's text properties
	public static inline var DEFAULT_FAMILY = "sans-serif";
	public static inline var DEFAULT_SIZE = 14.0;
	public static inline var DEFAULT_WEIGHT = 400;
	public static inline var DEFAULT_LINE_HEIGHT = 1.25;
	public static inline var DEFAULT_COLOR:Color = 0xFF000000;

	final node:Node;

	@:allow(hxmc.ui.Node) function new(node:Node)
		this.node = node;

	// not laid out nor drawn when None
	public var display(default, set):Display = Flex;

	public var position(default, set):Position = Relative;

	// the main axis (Column, as React Native and Yoga: a UI stacks)
	public var direction(default, set):Direction = Column;

	// items flow into more lines when the main size is too small
	public var wrap(default, set):Bool = false;

	public var justify(default, set):Justify = Normal;

	// the children's default alignment across the main axis
	public var alignItems(default, set):Align = Stretch;

	// this node's alignment in its parent (Auto: the parent's alignItems)
	public var alignSelf(default, set):Align = Align.Auto;

	public var alignContent(default, set):AlignContent = Normal;

	// the explicit grid's columns and rows (Grid.tracks: "1fr 200px auto")
	public var gridTemplateColumns(default, set):Array<Grid.Track> = [];
	public var gridTemplateRows(default, set):Array<Grid.Track> = [];

	// the size of the tracks auto-placement adds beyond them
	public var gridAutoColumns(default, set):Grid.Track = Grid.Track.AUTO;
	public var gridAutoRows(default, set):Grid.Track = Grid.Track.AUTO;

	// what auto-placement fills first: rows (each across, then the next) or columns
	public var gridAutoFlow(default, set):Grid.GridFlow = Grid.GridFlow.Row;

	// the lines this node spans in a grid (Grid.GridPlacement.parse: "1 / 3", "span 2")
	public var gridColumn(default, set):Grid.GridPlacement = Grid.GridPlacement.AUTO;
	public var gridRow(default, set):Grid.GridPlacement = Grid.GridPlacement.AUTO;

	// in a grid: the children's default alignment in their areas along a row, and this node's (Auto: its parent's justifyItems)
	public var justifyItems(default, set):Align = Align.Stretch;
	public var justifySelf(default, set):Align = Align.Auto;

	// flex-grow
	public var grow(default, set):Float = 0;

	// flex-shrink
	public var shrink(default, set):Float = 1;

	// flex-basis (Auto: the main size, else the content's)
	public var basis(default, set):Dim = DimValue.Auto;

	// the border box's size
	public var width(default, set):Dim = DimValue.Auto;

	public var height(default, set):Dim = DimValue.Auto;

	// (Auto: 0)
	public var minWidth(default, set):Dim = DimValue.Auto;

	public var minHeight(default, set):Dim = DimValue.Auto;

	// (Auto: none)
	public var maxWidth(default, set):Dim = DimValue.Auto;

	public var maxHeight(default, set):Dim = DimValue.Auto;

	// width / height when one of them is auto (0: none)
	public var aspectRatio(default, set):Float = 0;

	public var padding(default, set):EdgesValue = Edges.ZERO;

	public var margin(default, set):EdgesValue = Edges.ZERO;

	// on all four sides, inside the border box
	public var borderWidth(default, set):Float = 0;

	// between lines (Column: between items)
	public var rowGap(default, set):Float = 0;

	// between items (Column: between lines)
	public var columnGap(default, set):Float = 0;

	// Absolute: the offsets from the parent's padding box; Relative: shifts
	public var left(default, set):Dim = DimValue.Auto;

	public var top(default, set):Dim = DimValue.Auto;

	public var right(default, set):Dim = DimValue.Auto;

	public var bottom(default, set):Dim = DimValue.Auto;

	public var overflow(default, set):Overflow = Visible;

	public var background(default, set):Color = Color.TRANSPARENT;

	public var borderColor(default, set):Color = Color.TRANSPARENT;

	// the corners' radius
	public var radius(default, set):Float = 0;

	// of the node and its subtree
	public var opacity(default, set):Float = 1;

	public var cursor(default, set):Cursor = Cursor.Auto;

	// under the background (null: none)
	public var shadow(default, set):Null<Shadow> = null;

	// inherited from here on: null takes the parent's (the root's defaults: Style.ROOT)
	public var color(default, set):Null<Color> = null;

	public var fontFamily(default, set):Null<String> = null;

	public var fontSize(default, set):Null<Float> = null;

	// 400 regular, 700 bold
	public var fontWeight(default, set):Null<Int> = null;

	public var italic(default, set):Null<Bool> = null;

	// a multiple of the font size
	public var lineHeight(default, set):Null<Float> = null;

	public var textAlign(default, set):Null<TextAlign> = null;

	// a text's lines at most (0: any), the last ending in an ellipsis when cut (CSS's line-clamp; not inherited)
	public var maxLines(default, set):Int = 0;

	function set_display(v:Display):Display {
		if (v == display) return v;
		display = v;
		node.styleChanged(true);
		return v;
	}

	function set_position(v:Position):Position {
		if (v == position) return v;
		position = v;
		node.styleChanged(true);
		return v;
	}

	function set_direction(v:Direction):Direction {
		if (v == direction) return v;
		direction = v;
		node.styleChanged(true);
		return v;
	}

	function set_wrap(v:Bool):Bool {
		if (v == wrap) return v;
		wrap = v;
		node.styleChanged(true);
		return v;
	}

	function set_justify(v:Justify):Justify {
		if (v == justify) return v;
		justify = v;
		node.styleChanged(true);
		return v;
	}

	function set_alignItems(v:Align):Align {
		if (v == alignItems) return v;
		alignItems = v;
		node.styleChanged(true);
		return v;
	}

	function set_alignSelf(v:Align):Align {
		if (v == alignSelf) return v;
		alignSelf = v;
		node.styleChanged(true);
		return v;
	}

	function set_maxLines(v:Int):Int {
		if (v == maxLines) return v;
		maxLines = v;
		node.styleChanged(true);
		return v;
	}

	function set_alignContent(v:AlignContent):AlignContent {
		if (v == alignContent) return v;
		alignContent = v;
		node.styleChanged(true);
		return v;
	}

	function set_gridTemplateColumns(v:Array<Grid.Track>):Array<Grid.Track> {
		if (v == gridTemplateColumns) return v;
		gridTemplateColumns = v;
		node.styleChanged(true);
		return v;
	}

	function set_gridTemplateRows(v:Array<Grid.Track>):Array<Grid.Track> {
		if (v == gridTemplateRows) return v;
		gridTemplateRows = v;
		node.styleChanged(true);
		return v;
	}

	function set_gridAutoColumns(v:Grid.Track):Grid.Track {
		if (v == gridAutoColumns) return v;
		gridAutoColumns = v;
		node.styleChanged(true);
		return v;
	}

	function set_gridAutoRows(v:Grid.Track):Grid.Track {
		if (v == gridAutoRows) return v;
		gridAutoRows = v;
		node.styleChanged(true);
		return v;
	}

	function set_gridAutoFlow(v:Grid.GridFlow):Grid.GridFlow {
		if (v == gridAutoFlow) return v;
		gridAutoFlow = v;
		node.styleChanged(true);
		return v;
	}

	function set_gridColumn(v:Grid.GridPlacement):Grid.GridPlacement {
		if (v == gridColumn) return v;
		gridColumn = v;
		node.styleChanged(true);
		return v;
	}

	function set_gridRow(v:Grid.GridPlacement):Grid.GridPlacement {
		if (v == gridRow) return v;
		gridRow = v;
		node.styleChanged(true);
		return v;
	}

	function set_justifyItems(v:Align):Align {
		if (v == justifyItems) return v;
		justifyItems = v;
		node.styleChanged(true);
		return v;
	}

	function set_justifySelf(v:Align):Align {
		if (v == justifySelf) return v;
		justifySelf = v;
		node.styleChanged(true);
		return v;
	}

	function set_grow(v:Float):Float {
		if (v == grow) return v;
		grow = v;
		node.styleChanged(true);
		return v;
	}

	function set_shrink(v:Float):Float {
		if (v == shrink) return v;
		shrink = v;
		node.styleChanged(true);
		return v;
	}

	function set_basis(v:Dim):Dim {
		if (v == basis) return v;
		basis = v;
		node.styleChanged(true);
		return v;
	}

	function set_width(v:Dim):Dim {
		if (v == width) return v;
		width = v;
		node.styleChanged(true);
		return v;
	}

	function set_height(v:Dim):Dim {
		if (v == height) return v;
		height = v;
		node.styleChanged(true);
		return v;
	}

	function set_minWidth(v:Dim):Dim {
		if (v == minWidth) return v;
		minWidth = v;
		node.styleChanged(true);
		return v;
	}

	function set_minHeight(v:Dim):Dim {
		if (v == minHeight) return v;
		minHeight = v;
		node.styleChanged(true);
		return v;
	}

	function set_maxWidth(v:Dim):Dim {
		if (v == maxWidth) return v;
		maxWidth = v;
		node.styleChanged(true);
		return v;
	}

	function set_maxHeight(v:Dim):Dim {
		if (v == maxHeight) return v;
		maxHeight = v;
		node.styleChanged(true);
		return v;
	}

	function set_aspectRatio(v:Float):Float {
		if (v == aspectRatio) return v;
		aspectRatio = v;
		node.styleChanged(true);
		return v;
	}

	function set_padding(v:EdgesValue):EdgesValue {
		if (false) return v;
		padding = v;
		node.styleChanged(true);
		return v;
	}

	function set_margin(v:EdgesValue):EdgesValue {
		if (false) return v;
		margin = v;
		node.styleChanged(true);
		return v;
	}

	function set_borderWidth(v:Float):Float {
		if (v == borderWidth) return v;
		borderWidth = v;
		node.styleChanged(true);
		return v;
	}

	function set_rowGap(v:Float):Float {
		if (v == rowGap) return v;
		rowGap = v;
		node.styleChanged(true);
		return v;
	}

	function set_columnGap(v:Float):Float {
		if (v == columnGap) return v;
		columnGap = v;
		node.styleChanged(true);
		return v;
	}

	function set_left(v:Dim):Dim {
		if (v == left) return v;
		left = v;
		node.styleChanged(true);
		return v;
	}

	function set_top(v:Dim):Dim {
		if (v == top) return v;
		top = v;
		node.styleChanged(true);
		return v;
	}

	function set_right(v:Dim):Dim {
		if (v == right) return v;
		right = v;
		node.styleChanged(true);
		return v;
	}

	function set_bottom(v:Dim):Dim {
		if (v == bottom) return v;
		bottom = v;
		node.styleChanged(true);
		return v;
	}

	function set_overflow(v:Overflow):Overflow {
		if (v == overflow) return v;
		overflow = v;
		node.styleChanged(true);
		return v;
	}

	function set_background(v:Color):Color {
		if (v == background) return v;
		background = v;
		node.styleChanged(false);
		return v;
	}

	function set_borderColor(v:Color):Color {
		if (v == borderColor) return v;
		borderColor = v;
		node.styleChanged(false);
		return v;
	}

	function set_radius(v:Float):Float {
		if (v == radius) return v;
		radius = v;
		node.styleChanged(false);
		return v;
	}

	function set_opacity(v:Float):Float {
		if (v == opacity) return v;
		opacity = v;
		node.styleChanged(false);
		return v;
	}

	function set_cursor(v:Cursor):Cursor {
		if (v == cursor) return v;
		cursor = v;
		node.styleChanged(false);
		return v;
	}

	function set_shadow(v:Null<Shadow>):Null<Shadow> {
		if (v == shadow) return v;
		shadow = v;
		node.styleChanged(false);
		return v;
	}

	function set_color(v:Null<Color>):Null<Color> {
		if (v == color) return v;
		color = v;
		node.styleChanged(false);
		return v;
	}

	function set_fontFamily(v:Null<String>):Null<String> {
		if (v == fontFamily) return v;
		fontFamily = v;
		node.styleChanged(true);
		return v;
	}

	function set_fontSize(v:Null<Float>):Null<Float> {
		if (v == fontSize) return v;
		fontSize = v;
		node.styleChanged(true);
		return v;
	}

	function set_fontWeight(v:Null<Int>):Null<Int> {
		if (v == fontWeight) return v;
		fontWeight = v;
		node.styleChanged(true);
		return v;
	}

	function set_italic(v:Null<Bool>):Null<Bool> {
		if (v == italic) return v;
		italic = v;
		node.styleChanged(true);
		return v;
	}

	function set_lineHeight(v:Null<Float>):Null<Float> {
		if (v == lineHeight) return v;
		lineHeight = v;
		node.styleChanged(true);
		return v;
	}

	function set_textAlign(v:Null<TextAlign>):Null<TextAlign> {
		if (v == textAlign) return v;
		textAlign = v;
		node.styleChanged(false);
		return v;
	}

	// sets the properties p gives
	public function set(p:StyleProps):Style {
		if (p.display != null) display = p.display;
		if (p.position != null) position = p.position;
		if (p.direction != null) direction = p.direction;
		if (p.wrap != null) wrap = p.wrap;
		if (p.justify != null) justify = p.justify;
		if (p.alignItems != null) alignItems = p.alignItems;
		if (p.alignSelf != null) alignSelf = p.alignSelf;
		if (p.alignContent != null) alignContent = p.alignContent;
		if (p.grow != null) grow = p.grow;
		if (p.shrink != null) shrink = p.shrink;
		if (p.basis != null) basis = p.basis;
		if (p.width != null) width = p.width;
		if (p.height != null) height = p.height;
		if (p.minWidth != null) minWidth = p.minWidth;
		if (p.minHeight != null) minHeight = p.minHeight;
		if (p.maxWidth != null) maxWidth = p.maxWidth;
		if (p.maxHeight != null) maxHeight = p.maxHeight;
		if (p.aspectRatio != null) aspectRatio = p.aspectRatio;
		if (p.padding != null) padding = p.padding;
		if (p.margin != null) margin = p.margin;
		if (p.borderWidth != null) borderWidth = p.borderWidth;
		if (p.rowGap != null) rowGap = p.rowGap;
		if (p.columnGap != null) columnGap = p.columnGap;
		if (p.left != null) left = p.left;
		if (p.top != null) top = p.top;
		if (p.right != null) right = p.right;
		if (p.bottom != null) bottom = p.bottom;
		if (p.overflow != null) overflow = p.overflow;
		if (p.background != null) background = p.background;
		if (p.borderColor != null) borderColor = p.borderColor;
		if (p.radius != null) radius = p.radius;
		if (p.opacity != null) opacity = p.opacity;
		if (p.cursor != null) cursor = p.cursor;
		if (p.shadow != null) shadow = p.shadow;
		if (p.color != null) color = p.color;
		if (p.fontFamily != null) fontFamily = p.fontFamily;
		if (p.fontSize != null) fontSize = p.fontSize;
		if (p.fontWeight != null) fontWeight = p.fontWeight;
		if (p.italic != null) italic = p.italic;
		if (p.lineHeight != null) lineHeight = p.lineHeight;
		if (p.textAlign != null) textAlign = p.textAlign;
		if (p.maxLines != null) maxLines = p.maxLines;
		if (p.gridTemplateColumns != null) gridTemplateColumns = p.gridTemplateColumns;
		if (p.gridTemplateRows != null) gridTemplateRows = p.gridTemplateRows;
		if (p.gridAutoColumns != null) gridAutoColumns = p.gridAutoColumns;
		if (p.gridAutoRows != null) gridAutoRows = p.gridAutoRows;
		if (p.gridAutoFlow != null) gridAutoFlow = p.gridAutoFlow;
		if (p.gridColumn != null) gridColumn = p.gridColumn;
		if (p.gridRow != null) gridRow = p.gridRow;
		if (p.justifyItems != null) justifyItems = p.justifyItems;
		if (p.justifySelf != null) justifySelf = p.justifySelf;
		return this;
	}
}
