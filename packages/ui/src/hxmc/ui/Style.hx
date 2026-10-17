package hxmc.ui;

// A node's style: flexbox layout (Layout) and how the node is drawn. Each
// property's setter tells the node what changed (its layout, or only its
// paint), so that only that is redone. The text properties from color on
// are inherited: null takes the parent's (resolved by Node's font() and
// textColor()). Generated once: a property is a field with a setter
// calling the node's styleChanged; those rarely set are kept in a
// StyleRare made when the first of them is (most nodes set none).
class Style {
	// the root's text properties
	public static inline var DEFAULT_FAMILY = "sans-serif";
	public static inline var DEFAULT_SIZE = 14.0;
	public static inline var DEFAULT_WEIGHT = 400;
	public static inline var DEFAULT_LINE_HEIGHT = 1.25;
	public static inline var DEFAULT_COLOR:Color = 0xFF000000;

	static final NO_TRACKS:Array<Grid.Track> = [];

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

	public var alignContent(get, set):AlignContent;

	// the explicit grid's columns and rows (Grid.tracks: "1fr 200px auto"; none: one empty array shared)
	public var gridTemplateColumns(get, set):Array<Grid.Track>;
	public var gridTemplateRows(get, set):Array<Grid.Track>;

	// the explicit grid's named areas (Grid.GridAreas.parse: "'head head' 'side main'"),
	// which make it at least as many columns and rows (beyond the templates' sized as auto tracks)
	public var gridTemplateAreas(get, set):Null<Grid.GridAreas>;

	// the size of the tracks auto-placement adds beyond them
	public var gridAutoColumns(get, set):Grid.Track;
	public var gridAutoRows(get, set):Grid.Track;

	// what auto-placement fills first: rows (each across, then the next) or columns
	public var gridAutoFlow(get, set):Grid.GridFlow;

	// the lines this node spans in a grid (Grid.GridPlacement.parse: "1 / 3", "span 2")
	public var gridColumn(get, set):Grid.GridPlacement;
	public var gridRow(get, set):Grid.GridPlacement;
	// both (Grid.area: "header", "1 / 2 / 3 / 4")
	public var gridArea(never, set):String;

	// in a grid: the children's default alignment in their areas along a row, and this node's (Auto: its parent's justifyItems)
	public var justifyItems(get, set):Align;
	public var justifySelf(get, set):Align;

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
	public var aspectRatio(get, set):Float;

	public var padding(default, set):EdgesValue = Edges.ZERO;

	public var margin(default, set):EdgesValue = Edges.ZERO;

	// on all four sides, inside the border box
	public var borderWidth(default, set):Float = 0;

	// each side's (CSS's border-top-width...; null: borderWidth on all four)
	public var borders(get, set):Null<EdgesValue>;

	// the border's widths as laid out and drawn: borders, else borderWidth on each side
	public var borderEdges(default, null):Edges = Edges.ZERO;

	// between lines (Column: between items)
	public var rowGap(default, set):Float = 0;

	// between items (Column: between lines)
	public var columnGap(default, set):Float = 0;

	// Absolute: the offsets from the parent's padding box; Relative: shifts
	public var left(get, set):Dim;

	public var top(get, set):Dim;

	public var right(get, set):Dim;

	public var bottom(get, set):Dim;

	public var overflow(default, set):Overflow = Visible;

	public var background(default, set):Color = Color.TRANSPARENT;

	public var borderColor(default, set):Color = Color.TRANSPARENT;

	// the corners' radius
	public var radius(default, set):Float = 0;

	// each corner's (CSS's border-radius with several values; null: radius on all four)
	public var corners(get, set):Null<CornersValue>;

	// of the node and its subtree
	public var opacity(default, set):Float = 1;

	public var cursor(default, set):Cursor = Cursor.Auto;

	// over the background colour, under the border: a CSS gradient (Gradient.parse; null: none)
	public var backgroundImage(get, set):Null<Gradient>;

	// under the background (null: none)
	public var shadow(get, set):Null<Shadow>;

	// how the node and its subtree are drawn and hit, not laid out (Transform.parse; null: none)
	public var transform(get, set):Null<Transform>;

	// the point the transform is about: x and y in the border box (Transform.origin; null: its centre)
	public var transformOrigin(get, set):Null<Array<Dim>>;

	// inherited from here on: null takes the parent's (the root's defaults: Style.ROOT)
	public var color(default, set):Null<Color> = null;

	public var fontFamily(default, set):Null<String> = null;

	public var fontSize(default, set):Null<Float> = null;

	// 400 regular, 700 bold
	public var fontWeight(default, set):Null<Int> = null;

	public var italic(default, set):Null<Bool> = null;

	// a multiple of the font size
	public var lineHeight(default, set):Null<Float> = null;
	// pixels after each character, and on each space (CSS's letter-spacing, word-spacing)
	public var letterSpacing(get, set):Null<Float>;
	public var wordSpacing(get, set):Null<Float>;

	public var textAlign(default, set):Null<TextAlign> = null;

	// where it is laid out among its siblings (CSS's order: lower first, ties
	// in the tree's order); painted and hit in that order too; Tab still
	// follows the tree
	public var order(get, set):Int;

	// painted over its siblings with lower ones, under those with higher (and
	// hit the other way round), whatever their order (CSS's z-index among
	// siblings: no stacking contexts across levels)
	public var zIndex(get, set):Int;

	// the inline direction, inherited (null: the parent's; Ltr at the root):
	// Rtl mirrors rows, columns' cross axis, grids' columns and text's
	// default alignment; margins, padding and offsets stay physical
	public var dir(get, set):Null<Dir>;

	// whether it is seen, inherited (null: the parent's; Visible at the
	// root): Hidden keeps its place but draws, hits, focuses and shows
	// nothing of it to assistive technology (its Visible descendants still are)
	public var visibility(get, set):Null<Visibility>;

	// whether text wraps at its box's width, inherited (null: the parent's;
	// Wrap at the root; CSS's text-wrap-mode): NoWrap lays each line out
	// whole, its min-content width that wide (line breaks still break)
	public var textWrap(get, set):Null<TextWrap>;

	// its text's letters as shown, inherited (null: the parent's; None at
	// the root; CSS's text-transform): upper or lower case, or each word's
	// first in upper case; a text field's own text is shown as typed
	public var textTransform(get, set):Null<TextTransform>;

	// a text's lines at most (0: any), the last ending in an ellipsis when cut (CSS's line-clamp; not inherited)
	public var maxLines(get, set):Int;

	// the lines drawn with the text in this node and its descendants, in
	// this node's colour (TextDecoration's flags; 0: none; not inherited,
	// as in CSS: it reaches the text inside)
	public var textDecoration(get, set):Int;

	// --- the properties rarely set: in a StyleRare made when one is ---

	var rare:Null<StyleRare> = null;

	function more():StyleRare {
		if (rare == null) rare = new StyleRare();
		return rare;
	}

	inline function get_gridTemplateColumns():Array<Grid.Track>
		return rare == null ? NO_TRACKS : rare.gridTemplateColumns;

	inline function get_gridTemplateRows():Array<Grid.Track>
		return rare == null ? NO_TRACKS : rare.gridTemplateRows;

	inline function get_gridTemplateAreas():Null<Grid.GridAreas>
		return rare == null ? null : rare.gridTemplateAreas;

	inline function get_gridAutoColumns():Grid.Track
		return rare == null ? Grid.Track.AUTO : rare.gridAutoColumns;

	inline function get_gridAutoRows():Grid.Track
		return rare == null ? Grid.Track.AUTO : rare.gridAutoRows;

	inline function get_gridAutoFlow():Grid.GridFlow
		return rare == null ? Grid.GridFlow.Row : rare.gridAutoFlow;

	inline function get_gridColumn():Grid.GridPlacement
		return rare == null ? Grid.GridPlacement.AUTO : rare.gridColumn;

	inline function get_gridRow():Grid.GridPlacement
		return rare == null ? Grid.GridPlacement.AUTO : rare.gridRow;

	inline function get_justifyItems():Align
		return rare == null ? Align.Stretch : rare.justifyItems;

	inline function get_justifySelf():Align
		return rare == null ? Align.Auto : rare.justifySelf;

	inline function get_alignContent():AlignContent
		return rare == null ? Normal : rare.alignContent;

	inline function get_aspectRatio():Float
		return rare == null ? 0 : rare.aspectRatio;

	inline function get_borders():Null<EdgesValue>
		return rare == null ? null : rare.borders;

	inline function get_corners():Null<CornersValue>
		return rare == null ? null : rare.corners;

	inline function get_backgroundImage():Null<Gradient>
		return rare == null ? null : rare.backgroundImage;

	inline function get_shadow():Null<Shadow>
		return rare == null ? null : rare.shadow;

	inline function get_transform():Null<Transform>
		return rare == null ? null : rare.transform;

	inline function get_transformOrigin():Null<Array<Dim>>
		return rare == null ? null : rare.transformOrigin;

	inline function get_letterSpacing():Null<Float>
		return rare == null ? null : rare.letterSpacing;

	inline function get_wordSpacing():Null<Float>
		return rare == null ? null : rare.wordSpacing;

	inline function get_maxLines():Int
		return rare == null ? 0 : rare.maxLines;

	inline function get_dir():Null<Dir>
		return rare == null ? null : rare.dir;

	inline function get_visibility():Null<Visibility>
		return rare == null ? null : rare.visibility;

	inline function get_textWrap():Null<TextWrap>
		return rare == null ? null : rare.textWrap;

	inline function get_textTransform():Null<TextTransform>
		return rare == null ? null : rare.textTransform;

	inline function get_order():Int
		return rare == null ? 0 : rare.order;

	inline function get_zIndex():Int
		return rare == null ? 0 : rare.zIndex;

	inline function get_textDecoration():Int
		return rare == null ? 0 : rare.textDecoration;

	inline function get_left():Dim
		return rare == null ? DimValue.Auto : rare.left;

	inline function get_top():Dim
		return rare == null ? DimValue.Auto : rare.top;

	inline function get_right():Dim
		return rare == null ? DimValue.Auto : rare.right;

	inline function get_bottom():Dim
		return rare == null ? DimValue.Auto : rare.bottom;

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

	function set_order(v:Int):Int {
		if (v == order) return v;
		more().order = v;
		node.styleChanged(true);
		// (the parent lays its children out in the new order)
		if (node.parent != null) node.parent.markDirty();
		return v;
	}

	function set_zIndex(v:Int):Int {
		if (v == zIndex) return v;
		more().zIndex = v;
		node.styleChanged(false);
		return v;
	}

	function set_dir(v:Null<Dir>):Null<Dir> {
		if (v == dir) return v;
		more().dir = v;
		node.styleChanged(true);
		// (inherited: every container under it lays out again)
		@:privateAccess node.dirChanged();
		return v;
	}

	function set_visibility(v:Null<Visibility>):Null<Visibility> {
		if (v == visibility) return v;
		more().visibility = v;
		node.styleChanged(false);
		// (what assistive technology sees changes)
		Ui.accessEpoch++;
		return v;
	}

	function set_textWrap(v:Null<TextWrap>):Null<TextWrap> {
		if (v == textWrap) return v;
		more().textWrap = v;
		// (inherited: the text under it laid out again)
		node.styleChanged(true);
		return v;
	}

	function set_textTransform(v:Null<TextTransform>):Null<TextTransform> {
		if (v == textTransform) return v;
		more().textTransform = v;
		node.styleChanged(true);
		return v;
	}

	function set_maxLines(v:Int):Int {
		if (v == maxLines) return v;
		more().maxLines = v;
		node.styleChanged(true);
		return v;
	}

	function set_alignContent(v:AlignContent):AlignContent {
		if (v == alignContent) return v;
		more().alignContent = v;
		node.styleChanged(true);
		return v;
	}

	function set_gridTemplateColumns(v:Array<Grid.Track>):Array<Grid.Track> {
		if (v == gridTemplateColumns) return v;
		more().gridTemplateColumns = v;
		node.styleChanged(true);
		return v;
	}

	function set_gridTemplateRows(v:Array<Grid.Track>):Array<Grid.Track> {
		if (v == gridTemplateRows) return v;
		more().gridTemplateRows = v;
		node.styleChanged(true);
		return v;
	}

	function set_gridAutoColumns(v:Grid.Track):Grid.Track {
		if (v == gridAutoColumns) return v;
		more().gridAutoColumns = v;
		node.styleChanged(true);
		return v;
	}

	function set_gridAutoRows(v:Grid.Track):Grid.Track {
		if (v == gridAutoRows) return v;
		more().gridAutoRows = v;
		node.styleChanged(true);
		return v;
	}

	function set_gridAutoFlow(v:Grid.GridFlow):Grid.GridFlow {
		if (v == gridAutoFlow) return v;
		more().gridAutoFlow = v;
		node.styleChanged(true);
		return v;
	}

	function set_gridColumn(v:Grid.GridPlacement):Grid.GridPlacement {
		if (v == gridColumn) return v;
		more().gridColumn = v;
		node.styleChanged(true);
		return v;
	}

	function set_gridTemplateAreas(v:Null<Grid.GridAreas>):Null<Grid.GridAreas> {
		if (v == gridTemplateAreas) return v;
		more().gridTemplateAreas = v;
		node.styleChanged(true);
		return v;
	}

	function set_gridArea(v:String):String {
		var a = Grid.area(v);
		gridRow = a.row;
		gridColumn = a.column;
		return v;
	}

	function set_gridRow(v:Grid.GridPlacement):Grid.GridPlacement {
		if (v == gridRow) return v;
		more().gridRow = v;
		node.styleChanged(true);
		return v;
	}

	function set_justifyItems(v:Align):Align {
		if (v == justifyItems) return v;
		more().justifyItems = v;
		node.styleChanged(true);
		return v;
	}

	function set_justifySelf(v:Align):Align {
		if (v == justifySelf) return v;
		more().justifySelf = v;
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
		more().aspectRatio = v;
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
		if (borders == null) borderEdges = new Edges(v, v, v, v);
		node.styleChanged(true);
		return v;
	}

	function set_borders(v:Null<EdgesValue>):Null<EdgesValue> {
		if (v == borders) return v;
		more().borders = v;
		borderEdges = v == null ? new Edges(borderWidth, borderWidth, borderWidth, borderWidth) : v;
		node.styleChanged(true);
		return v;
	}

	function set_corners(v:Null<CornersValue>):Null<CornersValue> {
		if (v == corners) return v;
		more().corners = v;
		node.styleChanged(false);
		return v;
	}

	// the corners as drawn: corners, else radius on each
	public function cornerRadii():Corners
		return corners != null ? corners : Corners.all(radius);

	// whether the corners or the border's sides differ (drawn by Canvas.rect's corners and sides)
	public function irregular():Bool
		return corners != null && !(corners : Corners).uniform() || borders != null && !(borderEdges.top == borderEdges.right
			&& borderEdges.right == borderEdges.bottom && borderEdges.bottom == borderEdges.left);

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
		more().left = v;
		node.styleChanged(true);
		return v;
	}

	function set_top(v:Dim):Dim {
		if (v == top) return v;
		more().top = v;
		node.styleChanged(true);
		return v;
	}

	function set_right(v:Dim):Dim {
		if (v == right) return v;
		more().right = v;
		node.styleChanged(true);
		return v;
	}

	function set_bottom(v:Dim):Dim {
		if (v == bottom) return v;
		more().bottom = v;
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

	function set_backgroundImage(v:Null<Gradient>):Null<Gradient> {
		if (v == backgroundImage) return v;
		more().backgroundImage = v;
		node.styleChanged(false);
		return v;
	}

	function set_transform(v:Null<Transform>):Null<Transform> {
		if (v == transform) return v;
		var was = transform != null;
		more().transform = v;
		Ui.accessEpoch++;
		node.styleChanged(false);
		if (was != (v != null)) @:privateAccess node.inkChanged();
		return v;
	}

	function set_transformOrigin(v:Null<Array<Dim>>):Null<Array<Dim>> {
		if (v == transformOrigin) return v;
		more().transformOrigin = v;
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
		if ((v <= 0) != (opacity <= 0)) Ui.accessEpoch++;
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
		more().shadow = v;
		// (how far outside its box a shadow draws: the paint's culling widens bounds by the most seen)
		var sh = v;
		while (sh != null) {
			if (!sh.inset) Ui.shadowReach = Math.max(Ui.shadowReach, Math.max(Math.abs(sh.x), Math.abs(sh.y)) + sh.spread + 1.5 * sh.blur + 1);
			sh = sh.next;
		}
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

	function set_letterSpacing(v:Null<Float>):Null<Float> {
		if (v == letterSpacing) return v;
		more().letterSpacing = v;
		node.styleChanged(true);
		return v;
	}

	function set_wordSpacing(v:Null<Float>):Null<Float> {
		if (v == wordSpacing) return v;
		more().wordSpacing = v;
		node.styleChanged(true);
		return v;
	}

	function set_lineHeight(v:Null<Float>):Null<Float> {
		if (v == lineHeight) return v;
		lineHeight = v;
		node.styleChanged(true);
		return v;
	}

	function set_textDecoration(v:Int):Int {
		if (v == textDecoration) return v;
		more().textDecoration = v;
		node.styleChanged(false);
		return v;
	}

	function set_textAlign(v:Null<TextAlign>):Null<TextAlign> {
		if (v == textAlign) return v;
		// (justified: laid out again, its glyphs move)
		var layout = v == Justify || textAlign == Justify;
		textAlign = v;
		node.styleChanged(layout);
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
		if (p.borders != null) borders = p.borders;
		if (p.rowGap != null) rowGap = p.rowGap;
		if (p.columnGap != null) columnGap = p.columnGap;
		if (p.left != null) left = p.left;
		if (p.top != null) top = p.top;
		if (p.right != null) right = p.right;
		if (p.bottom != null) bottom = p.bottom;
		if (p.overflow != null) overflow = p.overflow;
		if (p.background != null) background = p.background;
		if (p.backgroundImage != null) backgroundImage = p.backgroundImage;
		if (p.borderColor != null) borderColor = p.borderColor;
		if (p.radius != null) radius = p.radius;
		if (p.corners != null) corners = p.corners;
		if (p.opacity != null) opacity = p.opacity;
		if (p.cursor != null) cursor = p.cursor;
		if (p.shadow != null) shadow = p.shadow;
		if (p.transform != null) transform = p.transform;
		if (p.transformOrigin != null) transformOrigin = p.transformOrigin;
		if (p.color != null) color = p.color;
		if (p.fontFamily != null) fontFamily = p.fontFamily;
		if (p.fontSize != null) fontSize = p.fontSize;
		if (p.fontWeight != null) fontWeight = p.fontWeight;
		if (p.italic != null) italic = p.italic;
		if (p.lineHeight != null) lineHeight = p.lineHeight;
		if (p.letterSpacing != null) letterSpacing = p.letterSpacing;
		if (p.wordSpacing != null) wordSpacing = p.wordSpacing;
		if (p.textAlign != null) textAlign = p.textAlign;
		if (p.dir != null) dir = p.dir;
		if (p.visibility != null) visibility = p.visibility;
		if (p.textWrap != null) textWrap = p.textWrap;
		if (p.textTransform != null) textTransform = p.textTransform;
		if (p.order != null) order = p.order;
		if (p.zIndex != null) zIndex = p.zIndex;
		if (p.textDecoration != null) textDecoration = p.textDecoration;
		if (p.maxLines != null) maxLines = p.maxLines;
		if (p.gridTemplateColumns != null) gridTemplateColumns = p.gridTemplateColumns;
		if (p.gridTemplateRows != null) gridTemplateRows = p.gridTemplateRows;
		if (p.gridAutoColumns != null) gridAutoColumns = p.gridAutoColumns;
		if (p.gridAutoRows != null) gridAutoRows = p.gridAutoRows;
		if (p.gridAutoFlow != null) gridAutoFlow = p.gridAutoFlow;
		if (p.gridColumn != null) gridColumn = p.gridColumn;
		if (p.gridRow != null) gridRow = p.gridRow;
		if (p.gridArea != null) gridArea = p.gridArea;
		if (p.gridTemplateAreas != null) gridTemplateAreas = p.gridTemplateAreas;
		if (p.justifyItems != null) justifyItems = p.justifyItems;
		if (p.justifySelf != null) justifySelf = p.justifySelf;
		return this;
	}
}

// what a Style keeps of the properties rarely set (their defaults at first)
private class StyleRare {
	public var gridTemplateColumns:Array<Grid.Track> = @:privateAccess Style.NO_TRACKS;
	public var gridTemplateRows:Array<Grid.Track> = @:privateAccess Style.NO_TRACKS;
	public var gridTemplateAreas:Null<Grid.GridAreas> = null;
	public var gridAutoColumns:Grid.Track = Grid.Track.AUTO;
	public var gridAutoRows:Grid.Track = Grid.Track.AUTO;
	public var gridAutoFlow:Grid.GridFlow = Grid.GridFlow.Row;
	public var gridColumn:Grid.GridPlacement = Grid.GridPlacement.AUTO;
	public var gridRow:Grid.GridPlacement = Grid.GridPlacement.AUTO;
	public var justifyItems:Align = Align.Stretch;
	public var justifySelf:Align = Align.Auto;
	public var alignContent:AlignContent = Normal;
	public var aspectRatio:Float = 0;
	public var borders:Null<EdgesValue> = null;
	public var corners:Null<CornersValue> = null;
	public var backgroundImage:Null<Gradient> = null;
	public var shadow:Null<Shadow> = null;
	public var transform:Null<Transform> = null;
	public var transformOrigin:Null<Array<Dim>> = null;
	public var letterSpacing:Null<Float> = null;
	public var wordSpacing:Null<Float> = null;
	public var maxLines:Int = 0;
	public var dir:Null<Dir> = null;
	public var visibility:Null<Visibility> = null;
	public var textWrap:Null<TextWrap> = null;
	public var textTransform:Null<TextTransform> = null;
	public var order:Int = 0;
	public var zIndex:Int = 0;
	public var textDecoration:Int = 0;
	public var left:Dim = DimValue.Auto;
	public var top:Dim = DimValue.Auto;
	public var right:Dim = DimValue.Auto;
	public var bottom:Dim = DimValue.Auto;

	public function new() {}
}
