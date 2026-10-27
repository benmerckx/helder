package helder.ui;

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

	@:allow(helder.ui.Node) function new(node:Node)
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

	// grow, shrink and basis at once (CSS's flex shorthand): a number n is n 1 0%,
	// as CSS's; markup also "none" (0 0 auto), "auto" (1 1 auto), "2 0 40px"
	public var flex(never, set):Float;

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
	// one side of each (CSS's padding-top...: Tailwind's pt-2 and px-4 from
	// separate rules; a margin's side may be Edges.AUTO, ml-auto)
	public var paddingTop(get, set):Float;
	public var paddingRight(get, set):Float;
	public var paddingBottom(get, set):Float;
	public var paddingLeft(get, set):Float;
	public var marginTop(get, set):Float;
	public var marginRight(get, set):Float;
	public var marginBottom(get, set):Float;
	public var marginLeft(get, set):Float;

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

	// both gaps at once (CSS's gap shorthand; markup "8 12": the rows', then the columns')
	public var gap(never, set):Float;

	// Absolute: the offsets from the parent's padding box; Relative: shifts
	public var left(get, set):Dim;

	public var top(get, set):Dim;

	public var right(get, set):Dim;

	public var bottom(get, set):Dim;

	// the four offsets at once (CSS's inset shorthand; markup "10 20": as margins write them)
	public var inset(never, set):Dim;

	// what overflows it, on both axes (CSS's shorthand); read, the two
	// together: Scroll if either scrolls, else Hidden if either clips. As
	// CSS's, both axes clip when either does; an axis scrolls by the wheel,
	// the keys and a scrollbar only where it is Scroll (Hidden: by scrollTo)
	public var overflow(default, set):Overflow = Visible;
	public var overflowX(default, set):Overflow = Visible;
	public var overflowY(default, set):Overflow = Visible;

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

	// a line around the border box, over the node's content: outlineWidth
	// wide (0: none), outlineOffset outside it (negative: inside), in
	// outlineColor (null: the text colour), its corners the box's grown by
	// both, as Chromium draws CSS's solid outline; markup's outline="2px
	// solid red" sets them, outline="none" none
	public var outlineWidth(get, set):Float;
	public var outlineOffset(get, set):Float;
	public var outlineColor(get, set):Null<Color>;
	// a solid outline this wide in the text colour (CSS's shorthand; markup also "2px solid red", "none")
	public var outline(never, set):Float;
	// whether its text can be selected by the pointer (UserSelect; null: the parent's)
	public var userSelect(get, set):Null<UserSelect>;
	// how a text field is sized where this style gives no size (FieldSizing; null: Fixed)
	public var fieldSizing(get, set):Null<FieldSizing>;
	// a scroller's scrollbar: its thickness (ScrollbarWidth; null: Auto), its
	// thumb's and track's colours (CSS's scrollbar-color, inherited; null:
	// the parent's, else the window's, Ui.scrollbarColor, and no track)
	public var scrollbarWidth(get, set):Null<ScrollbarWidth>;
	// paged layout (a document host's; nothing in a window): where pages may
	// break (PageBreak; null: Auto), the named page it is on (CSS's page)
	public var breakBefore(get, set):Null<PageBreak>;
	public var breakAfter(get, set):Null<PageBreak>;
	public var breakInside(get, set):Null<PageBreak>;
	public var page(get, set):Null<String>;
	public var scrollbarColor(get, set):Null<Color>;
	public var scrollbarTrackColor(get, set):Null<Color>;

	// whether the window's focus ring or the outline is drawn (OutlineStyle; null: Auto)
	public var outlineStyle(get, set):Null<OutlineStyle>;

	// a ring around the border box (Tailwind's ring: a box-shadow of no
	// blur, ringWidth wide, in ringColor, null: the text's; ringInset:
	// inside), outside a gap of ringOffsetWidth in ringOffsetColor; drawn
	// with the shadows as Tailwind composes them, the offset over the ring
	// over the shadow, so that each comes from its own rule
	public var ringWidth(get, set):Float;
	public var ringColor(get, set):Null<Color>;
	public var ringOffsetWidth(get, set):Float;
	public var ringOffsetColor(get, set):Color;
	public var ringInset(get, set):Bool;

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

	// a multiple of the font size (inherited as the multiple), or pixels
	// (lineHeightPx, CSS's line-height: 24px, inherited as the pixels;
	// over lineHeight where a node has both, as Tailwind's leading-6 is over
	// text-sm's)
	public var lineHeight(default, set):Null<Float> = null;
	public var lineHeightPx(get, set):Null<Float>;
	// pixels after each character, and on each space (CSS's letter-spacing,
	// word-spacing); letterSpacingEm: a multiple of the node's font size
	// (tracking-tight's -0.025em), inherited as the pixels it comes to, over
	// letterSpacing where a node has both
	public var letterSpacing(get, set):Null<Float>;
	public var letterSpacingEm(get, set):Null<Float>;
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

	// whether the pointer finds it, inherited (null: the parent's; Auto at
	// the root; CSS's pointer-events): None lets presses, hovers and the
	// wheel through to what is under it (its Auto descendants still take them)
	public var pointerEvents(get, set):Null<PointerEvents>;

	// whether text wraps at its box's width, inherited (null: the parent's;
	// Wrap at the root; CSS's text-wrap-mode): NoWrap lays each line out
	// whole, its min-content width that wide (line breaks still break);
	// Balance wraps it into lines of about one width (TextWrap)
	public var textWrap(get, set):Null<TextWrap>;

	// where a word too wide for its line may be cut, inherited (null: the
	// parent's; BreakWord at the root, where CSS's is Normal: text stays in
	// its box; CSS's overflow-wrap)
	public var overflowWrap(get, set):Null<OverflowWrap>;

	// where lines may break inside words, inherited (null: the parent's;
	// Normal at the root; CSS's word-break): BreakAll between letters too,
	// KeepAll not between CJK characters
	public var wordBreak(get, set):Null<WordBreak>;

	// OpenType features, inherited, as CSS's font-feature-settings writes
	// them ("'tnum'", "'liga' 0, 'ss01'"; null: the parent's; "normal": the
	// default ones): their substitutions added, or liga, clig, calt and
	// kern turned off (helder.text.FontFeature)
	public var fontFeatureSettings(get, set):Null<String>;

	// figures' forms, inherited, as CSS's font-variant-numeric writes them
	// ("tabular-nums", "oldstyle-nums slashed-zero"; null: the parent's;
	// "normal"): their features (tnum, onum, zero...), under
	// fontFeatureSettings
	public var fontVariantNumeric(get, set):Null<String>;

	// its text's letters as shown, inherited (null: the parent's; None at
	// the root; CSS's text-transform): upper or lower case, or each word's
	// first in upper case; a text field's own text is shown as typed
	public var textTransform(get, set):Null<TextTransform>;

	// a line too wide for its box (CSS's text-overflow; not inherited):
	// Ellipsis ends it in one within the box (with NoWrap, or a word too
	// long to break); its intrinsic widths are the whole text's
	public var textOverflow(get, set):TextOverflow;

	// a text's lines at most (0: any), the last ending in an ellipsis when cut (CSS's line-clamp; not inherited)
	public var maxLines(get, set):Int;

	// the lines drawn with the text in this node and its descendants, in
	// this node's colour (TextDecoration's flags; 0: none; not inherited,
	// as in CSS: it reaches the text inside)
	public var textDecoration(get, set):Int;

	// the colour of the lines textDecoration draws (null: the node's text
	// colour; not inherited, as CSS's text-decoration-color)
	public var textDecorationColor(get, set):Null<Color>;
	// their thickness (auto: a tenth of the font size; a percentage of it;
	// not inherited) and an underline's place below the baseline (auto: the
	// font's; inherited), as CSS's text-decoration-thickness and
	// text-underline-offset
	public var textDecorationThickness(get, set):Dim;
	public var textUnderlineOffset(get, set):Dim;

	// shadows of the text in this node and its descendants and of its
	// decorations, under them (Shadow.parse, as CSS's text-shadow: x, y,
	// blur and a colour, the text's without one; null: the parent's;
	// Shadow.NONE: none)
	public var textShadow(get, set):Null<Shadow>;

	// how its colours, opacity, transform and shadow ease to a new value
	// once it has been drawn (Transition.parse, as CSS's transition; null:
	// they jump; not inherited). While one moves, the property reads where
	// it is; target, where it goes.
	public var transition(get, set):Null<Transition>;

	// --- the properties rarely set: in a StyleRare made when one is ---

	var rare:Null<StyleRare> = null;

	function more():StyleRare {
		if (rare == null) rare = new StyleRare();
		return rare;
	}

	// (what themes set of the rare properties, apart: shadows, outline, ring,
	// transitions, transforms, pointer events, selection, z-index, text
	// wrapping, corners and borders; a themed control needs none of the rest)
	var themed:Null<StyleThemed> = null;

	function theming():StyleThemed {
		if (themed == null) themed = new StyleThemed();
		return themed;
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
		return themed == null ? null : themed.borders;

	inline function get_corners():Null<CornersValue>
		return themed == null ? null : themed.corners;

	inline function get_backgroundImage():Null<Gradient>
		return rare == null ? null : rare.backgroundImage;

	inline function get_shadow():Null<Shadow>
		return themed == null ? null : themed.shadow;

	inline function get_outlineWidth():Float
		return themed == null ? 0 : themed.outlineWidth;

	inline function get_outlineOffset():Float
		return themed == null ? 0 : themed.outlineOffset;

	inline function get_outlineColor():Null<Color>
		return themed == null ? null : themed.outlineColor;

	inline function get_transform():Null<Transform>
		return themed == null ? null : themed.transform;

	inline function get_transformOrigin():Null<Array<Dim>>
		return rare == null ? null : rare.transformOrigin;

	inline function get_letterSpacing():Null<Float>
		return rare == null ? null : rare.letterSpacing;

	inline function get_wordSpacing():Null<Float>
		return rare == null ? null : rare.wordSpacing;

	inline function get_lineHeightPx():Null<Float>
		return rare == null ? null : rare.lineHeightPx;

	inline function get_letterSpacingEm():Null<Float>
		return rare == null ? null : rare.letterSpacingEm;

	inline function get_maxLines():Int
		return rare == null ? 0 : rare.maxLines;

	inline function get_dir():Null<Dir>
		return rare == null ? null : rare.dir;

	inline function get_userSelect():Null<UserSelect>
		return themed == null ? null : themed.userSelect;

	function set_userSelect(v:Null<UserSelect>):Null<UserSelect> {
		if (v == userSelect) return v;
		theming().userSelect = v;
		return v;
	}

	inline function get_fieldSizing():Null<FieldSizing>
		return rare == null ? null : rare.fieldSizing;

	inline function get_breakBefore():Null<PageBreak>
		return rare == null ? null : rare.breakBefore;

	function set_breakBefore(v:Null<PageBreak>):Null<PageBreak> {
		if (v == breakBefore) return v;
		more().breakBefore = v;
		return v;
	}

	inline function get_breakAfter():Null<PageBreak>
		return rare == null ? null : rare.breakAfter;

	function set_breakAfter(v:Null<PageBreak>):Null<PageBreak> {
		if (v == breakAfter) return v;
		more().breakAfter = v;
		return v;
	}

	inline function get_breakInside():Null<PageBreak>
		return rare == null ? null : rare.breakInside;

	function set_breakInside(v:Null<PageBreak>):Null<PageBreak> {
		if (v == breakInside) return v;
		more().breakInside = v;
		return v;
	}

	inline function get_page():Null<String>
		return rare == null ? null : rare.page;

	function set_page(v:Null<String>):Null<String> {
		if (v == page) return v;
		more().page = v;
		return v;
	}

	inline function get_scrollbarWidth():Null<ScrollbarWidth>
		return rare == null ? null : rare.scrollbarWidth;

	function set_scrollbarWidth(v:Null<ScrollbarWidth>):Null<ScrollbarWidth> {
		if (v == scrollbarWidth) return v;
		more().scrollbarWidth = v;
		node.styleChanged(false);
		return v;
	}

	inline function get_scrollbarColor():Null<Color>
		return rare == null ? null : rare.scrollbarColor;

	function set_scrollbarColor(v:Null<Color>):Null<Color> {
		if (v == scrollbarColor) return v;
		more().scrollbarColor = v;
		node.styleChanged(false);
		return v;
	}

	inline function get_scrollbarTrackColor():Null<Color>
		return rare == null ? null : rare.scrollbarTrackColor;

	function set_scrollbarTrackColor(v:Null<Color>):Null<Color> {
		if (v == scrollbarTrackColor) return v;
		more().scrollbarTrackColor = v;
		node.styleChanged(false);
		return v;
	}

	function set_fieldSizing(v:Null<FieldSizing>):Null<FieldSizing> {
		if (v == fieldSizing) return v;
		more().fieldSizing = v;
		node.styleChanged(true);
		return v;
	}

	inline function get_outlineStyle():Null<OutlineStyle>
		return themed == null ? null : themed.outlineStyle;

	inline function get_ringWidth():Float
		return themed == null ? 0 : themed.ringWidth;

	inline function get_ringColor():Null<Color>
		return themed == null ? null : themed.ringColor;

	inline function get_ringOffsetWidth():Float
		return themed == null ? 0 : themed.ringOffsetWidth;

	inline function get_ringOffsetColor():Color
		return themed == null ? Color.WHITE : themed.ringOffsetColor;

	inline function get_ringInset():Bool
		return themed == null ? false : themed.ringInset;

	function set_ringWidth(v:Float):Float {
		if (themed != null && themed.transition != null && eases("ringWidth", ringWidth, v)) return v;
		if (v == ringWidth) return v;
		theming().ringWidth = v;
		ringed();
		return v;
	}

	function set_ringColor(v:Null<Color>):Null<Color> {
		if (themed != null && themed.transition != null && eases("ringColor", ringColor, v)) return v;
		if (v == ringColor) return v;
		theming().ringColor = v;
		node.styleChanged(false);
		return v;
	}

	function set_ringOffsetWidth(v:Float):Float {
		if (v == ringOffsetWidth) return v;
		theming().ringOffsetWidth = v;
		ringed();
		return v;
	}

	function set_ringOffsetColor(v:Color):Color {
		if (v == ringOffsetColor) return v;
		theming().ringOffsetColor = v;
		node.styleChanged(false);
		return v;
	}

	function set_ringInset(v:Bool):Bool {
		if (v == ringInset) return v;
		theming().ringInset = v;
		node.styleChanged(false);
		return v;
	}

	// (how far outside its box a ring draws: the paint's culling widens bounds by the most seen, as for shadows)
	function ringed() {
		Ui.shadowReach = Math.max(Ui.shadowReach, ringWidth + ringOffsetWidth + 1);
		node.styleChanged(false);
	}

	// its shadows as drawn, the last (the lowest) first: its ring and the
	// ring's offset over its shadow (null: none)
	public function paintedShadows():Null<Array<Shadow>> {
		var r = themed;
		if (r == null || r.ringWidth <= 0 && r.ringOffsetWidth <= 0) return r == null || r.shadow == null ? null : r.shadow.painted();
		var all = r.shadow == null ? [] : r.shadow.painted();
		if (r.ringWidth > 0)
			all.push({spread: r.ringWidth + r.ringOffsetWidth, color: r.ringColor ?? node.textColor(), inset: r.ringInset});
		if (r.ringOffsetWidth > 0) all.push({spread: r.ringOffsetWidth, color: r.ringOffsetColor, inset: r.ringInset});
		return all;
	}

	function set_outlineStyle(v:Null<OutlineStyle>):Null<OutlineStyle> {
		if (v == outlineStyle) return v;
		theming().outlineStyle = v;
		node.styleChanged(false);
		return v;
	}

	inline function get_visibility():Null<Visibility>
		return rare == null ? null : rare.visibility;

	inline function get_pointerEvents():Null<PointerEvents>
		return themed == null ? null : themed.pointerEvents;

	inline function get_textWrap():Null<TextWrap>
		return themed == null ? null : themed.textWrap;

	inline function get_overflowWrap():Null<OverflowWrap>
		return rare == null ? null : rare.overflowWrap;

	inline function get_wordBreak():Null<WordBreak>
		return rare == null ? null : rare.wordBreak;

	inline function get_fontFeatureSettings():Null<String>
		return rare == null ? null : rare.fontFeatureSettings;

	inline function get_fontVariantNumeric():Null<String>
		return rare == null ? null : rare.fontVariantNumeric;

	// font-variant-numeric's keywords as font-feature-settings ("": normal)
	public static function numericFeatures(v:String):String {
		var out = [];
		for (w in StringTools.trim(v).split(" ")) {
			var tag = switch w {
				case "normal" | "": continue;
				case "lining-nums": "lnum";
				case "oldstyle-nums": "onum";
				case "proportional-nums": "pnum";
				case "tabular-nums": "tnum";
				case "diagonal-fractions": "frac";
				case "stacked-fractions": "afrc";
				case "ordinal": "ordn";
				case "slashed-zero": "zero";
				case _: throw "Style.fontVariantNumeric: " + v;
			}
			out.push("'" + tag + "'");
		}
		return out.join(", ");
	}

	inline function get_textTransform():Null<TextTransform>
		return rare == null ? null : rare.textTransform;

	inline function get_textOverflow():TextOverflow
		return rare == null ? Clip : rare.textOverflow;

	inline function get_order():Int
		return rare == null ? 0 : rare.order;

	inline function get_zIndex():Int
		return themed == null ? 0 : themed.zIndex;

	inline function get_textDecoration():Int
		return rare == null ? 0 : rare.textDecoration;

	inline function get_textDecorationThickness():Dim
		return rare == null ? DimValue.Auto : rare.textDecorationThickness;

	inline function get_textUnderlineOffset():Dim
		return rare == null ? DimValue.Auto : rare.textUnderlineOffset;

	inline function get_textDecorationColor():Null<Color>
		return rare == null ? null : rare.textDecorationColor;

	inline function get_textShadow():Null<Shadow>
		return rare == null ? null : rare.textShadow;

	inline function get_transition():Null<Transition>
		return themed == null ? null : themed.transition;

	function set_transition(v:Null<Transition>):Null<Transition> {
		if (v == transition) return v;
		theming().transition = v;
		// (none: what moves there at once)
		if (v == null && themed.moving != null) step(1e300);
		return v;
	}

	// (drawn once: what changes from now on eases, under a transition; Ui's paint sets it)
	@:allow(helder.ui.Ui) var drawn = false;
	// (rules for starting asked of it: restyled once it is drawn)
	@:allow(helder.ui.Rules) var starting = false;

	// a property's value by its id (its place in StyleFields.NAMES), or the one it is moving to under a transition
	public function targetAt(id:Int):Dynamic {
		if (themed != null && themed.moving != null) {
			var name = StyleFields.NAMES[id];
			for (run in themed.moving)
				if (run.name == name) return run.to;
		}
		return StyleFields.getAt(this, id);
	}

	// a property's value (StyleFields' names), or the one it is moving to under a transition
	public function target(name:String):Dynamic {
		if (themed != null && themed.moving != null)
			for (run in themed.moving)
				if (run.name == name) return run.to;
		return StyleFields.get(this, name);
	}

	// (a change of an eased property, drawn, under a transition that names
	// it: the property moving to it on the Clock from where it is, whether
	// it does; the same value again: a run toward another one stopped)
	function eases(name:String, from:Dynamic, to:Dynamic):Bool {
		var r = themed;
		if (r.stepping) return false;
		var m = r.moving, i = -1;
		if (m != null)
			for (k in 0...m.length)
				if (m[k].name == name) i = k;
		var t = r.transition == null || !drawn || node.ui == null || from == null || to == null || from == to ? null : r.transition.timing(name);
		if (t == null) {
			if (i < 0) return false;
			m.splice(i, 1);
			return from == to;
		}
		if (i >= 0 && m[i].to == to) return true;
		var run:Moving = {name: name, from: from, to: to, start: -1, duration: t.duration, delay: t.delay, easing: t.easing};
		if (i >= 0) m[i] = run else {
			if (m == null) r.moving = m = [];
			m.push(run);
		}
		if (!r.ticking) {
			r.ticking = true;
			Clock.add(step);
		}
		node.styleChanged(false);
		return true;
	}

	// (the Clock's tick: each run's value at now; the ones done at their ends)
	function step(now:Float):Bool {
		var r = themed, m = r.moving;
		r.stepping = true;
		var i = 0;
		while (m != null && i < m.length) {
			var run = m[i];
			// (the start is the first tick's time, after the delay: the clock may have been idle)
			if (run.start < 0) run.start = (now >= 1e300 ? 0 : now) + run.delay;
			var k = node.ui == null ? 1 : (now - run.start) / run.duration;
			if (k >= 1) {
				StyleFields.set(this, run.name, run.to);
				m.splice(i, 1);
				continue;
			}
			if (k > 0) StyleFields.set(this, run.name, Transition.between(run.name, run.from, run.to, Transition.ease(run.easing, k)));
			i++;
		}
		r.stepping = false;
		if (m == null || m.length == 0) {
			r.moving = null;
			r.ticking = false;
			return false;
		}
		return true;
	}

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
		theming().zIndex = v;
		node.styleChanged(false);
		return v;
	}

	function set_dir(v:Null<Dir>):Null<Dir> {
		if (v == dir) return v;
		more().dir = v;
		node.styleChanged(true);
		// (inherited: every container under it lays out again, its rules for rtl hold or not)
		@:privateAccess node.dirChanged();
		if (node.ui != null) Rules.restyleTree(node);
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

	function set_pointerEvents(v:Null<PointerEvents>):Null<PointerEvents> {
		if (v == pointerEvents) return v;
		theming().pointerEvents = v;
		return v;
	}

	function set_textWrap(v:Null<TextWrap>):Null<TextWrap> {
		if (v == textWrap) return v;
		theming().textWrap = v;
		// (inherited: the text under it laid out again)
		node.styleChanged(true);
		return v;
	}

	function set_overflowWrap(v:Null<OverflowWrap>):Null<OverflowWrap> {
		if (v == overflowWrap) return v;
		more().overflowWrap = v;
		node.styleChanged(true);
		return v;
	}

	function set_fontVariantNumeric(v:Null<String>):Null<String> {
		if (v == fontVariantNumeric) return v;
		if (v != null) numericFeatures(v);
		more().fontVariantNumeric = v;
		node.styleChanged(true);
		return v;
	}

	function set_fontFeatureSettings(v:Null<String>):Null<String> {
		if (v == fontFeatureSettings) return v;
		// (parsed now: a mistake throws where it is made)
		if (v != null) helder.text.FontFeature.parse(v);
		more().fontFeatureSettings = v;
		node.styleChanged(true);
		return v;
	}

	function set_wordBreak(v:Null<WordBreak>):Null<WordBreak> {
		if (v == wordBreak) return v;
		more().wordBreak = v;
		node.styleChanged(true);
		return v;
	}

	function set_textOverflow(v:TextOverflow):TextOverflow {
		if (v == textOverflow) return v;
		more().textOverflow = v;
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

	function set_gap(v:Float):Float {
		rowGap = columnGap = v;
		return v;
	}

	function set_inset(v:Dim):Dim {
		left = top = right = bottom = v;
		return v;
	}

	function set_flex(v:Float):Float {
		grow = v;
		shrink = 1;
		basis = DimValue.Percent(0);
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

	inline function get_paddingTop():Float
		return padding.top;

	inline function get_paddingRight():Float
		return padding.right;

	inline function get_paddingBottom():Float
		return padding.bottom;

	inline function get_paddingLeft():Float
		return padding.left;

	inline function get_marginTop():Float
		return margin.top;

	inline function get_marginRight():Float
		return margin.right;

	inline function get_marginBottom():Float
		return margin.bottom;

	inline function get_marginLeft():Float
		return margin.left;

	// (a side the same: NaN, auto, as auto)
	static inline function sameSide(a:Float, b:Float):Bool
		return a == b || Math.isNaN(a) && Math.isNaN(b);

	function set_paddingTop(v:Float):Float {
		var p = padding;
		if (!sameSide(v, p.top)) padding = new Edges(v, p.right, p.bottom, p.left);
		return v;
	}

	function set_paddingRight(v:Float):Float {
		var p = padding;
		if (!sameSide(v, p.right)) padding = new Edges(p.top, v, p.bottom, p.left);
		return v;
	}

	function set_paddingBottom(v:Float):Float {
		var p = padding;
		if (!sameSide(v, p.bottom)) padding = new Edges(p.top, p.right, v, p.left);
		return v;
	}

	function set_paddingLeft(v:Float):Float {
		var p = padding;
		if (!sameSide(v, p.left)) padding = new Edges(p.top, p.right, p.bottom, v);
		return v;
	}

	function set_marginTop(v:Float):Float {
		var m = margin;
		if (!sameSide(v, m.top)) margin = new Edges(v, m.right, m.bottom, m.left);
		return v;
	}

	function set_marginRight(v:Float):Float {
		var m = margin;
		if (!sameSide(v, m.right)) margin = new Edges(m.top, v, m.bottom, m.left);
		return v;
	}

	function set_marginBottom(v:Float):Float {
		var m = margin;
		if (!sameSide(v, m.bottom)) margin = new Edges(m.top, m.right, v, m.left);
		return v;
	}

	function set_marginLeft(v:Float):Float {
		var m = margin;
		if (!sameSide(v, m.left)) margin = new Edges(m.top, m.right, m.bottom, v);
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
		theming().borders = v;
		borderEdges = v == null ? new Edges(borderWidth, borderWidth, borderWidth, borderWidth) : v;
		node.styleChanged(true);
		return v;
	}

	function set_corners(v:Null<CornersValue>):Null<CornersValue> {
		if (v == corners) return v;
		theming().corners = v;
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
		if (v == overflow && v == overflowX && v == overflowY) return v;
		overflow = overflowX = overflowY = v;
		node.styleChanged(true);
		return v;
	}

	function set_overflowX(v:Overflow):Overflow {
		if (v == overflowX) return v;
		overflowX = v;
		bothAxes();
		return v;
	}

	function set_overflowY(v:Overflow):Overflow {
		if (v == overflowY) return v;
		overflowY = v;
		bothAxes();
		return v;
	}

	// (the two axes together, as overflow reads)
	function bothAxes() {
		@:bypassAccessor overflow = overflowX == Scroll || overflowY == Scroll ? Scroll : overflowX == Hidden || overflowY == Hidden ? Hidden : Visible;
		node.styleChanged(true);
	}

	function set_background(v:Color):Color {
		if (themed != null && themed.transition != null && eases("background", background, v)) return v;
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
		if (themed != null && themed.transition != null && eases("transform", transform, v)) return v;
		if (v == transform) return v;
		theming().transform = v;
		Ui.accessEpoch++;
		node.styleChanged(false);
		@:privateAccess node.inkChanged();
		return v;
	}

	function set_transformOrigin(v:Null<Array<Dim>>):Null<Array<Dim>> {
		if (v == transformOrigin) return v;
		more().transformOrigin = v;
		node.styleChanged(false);
		@:privateAccess node.inkChanged();
		return v;
	}

	function set_borderColor(v:Color):Color {
		if (themed != null && themed.transition != null && eases("borderColor", borderColor, v)) return v;
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
		if (themed != null && themed.transition != null && eases("opacity", opacity, v)) return v;
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

	function set_outline(v:Float):Float {
		outlineWidth = v;
		outlineColor = null;
		return v;
	}

	function set_outlineWidth(v:Float):Float {
		if (v == outlineWidth) return v;
		theming().outlineWidth = v;
		outlined();
		return v;
	}

	function set_outlineOffset(v:Float):Float {
		if (v == outlineOffset) return v;
		theming().outlineOffset = v;
		outlined();
		return v;
	}

	function set_outlineColor(v:Null<Color>):Null<Color> {
		if (themed != null && themed.transition != null && eases("outlineColor", outlineColor, v)) return v;
		if (v == outlineColor) return v;
		theming().outlineColor = v;
		node.styleChanged(false);
		return v;
	}

	// (how far outside its box an outline draws: the paint's culling widens bounds by the most seen, as for shadows)
	function outlined() {
		if (outlineWidth > 0) Ui.shadowReach = Math.max(Ui.shadowReach, outlineWidth + Math.max(0, outlineOffset) + 1);
		node.styleChanged(false);
	}

	function set_shadow(v:Null<Shadow>):Null<Shadow> {
		if (themed != null && themed.transition != null && eases("shadow", shadow, v)) return v;
		if (v == shadow) return v;
		theming().shadow = v;
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
		if (themed != null && themed.transition != null && eases("color", color, v)) return v;
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

	function set_lineHeightPx(v:Null<Float>):Null<Float> {
		if (v == lineHeightPx) return v;
		more().lineHeightPx = v;
		node.styleChanged(true);
		return v;
	}

	function set_letterSpacingEm(v:Null<Float>):Null<Float> {
		if (v == letterSpacingEm) return v;
		more().letterSpacingEm = v;
		node.styleChanged(true);
		return v;
	}

	function set_lineHeight(v:Null<Float>):Null<Float> {
		if (v == lineHeight) return v;
		lineHeight = v;
		node.styleChanged(true);
		return v;
	}

	function set_textDecorationThickness(v:Dim):Dim {
		if (v == textDecorationThickness) return v;
		more().textDecorationThickness = v;
		node.styleChanged(false);
		return v;
	}

	function set_textUnderlineOffset(v:Dim):Dim {
		if (v == textUnderlineOffset) return v;
		more().textUnderlineOffset = v;
		node.styleChanged(false);
		return v;
	}

	function set_textDecorationColor(v:Null<Color>):Null<Color> {
		if (themed != null && themed.transition != null && eases("textDecorationColor", textDecorationColor, v)) return v;
		if (v == textDecorationColor) return v;
		more().textDecorationColor = v;
		node.styleChanged(false);
		return v;
	}

	function set_textShadow(v:Null<Shadow>):Null<Shadow> {
		if (v == textShadow) return v;
		more().textShadow = v;
		// (its reach outside the text's box, as a box shadow's)
		var sh = v;
		while (sh != null) {
			Ui.shadowReach = Math.max(Ui.shadowReach, Math.max(Math.abs(sh.x), Math.abs(sh.y)) + 1.5 * sh.blur + 1);
			sh = sh.next;
		}
		node.styleChanged(false);
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
		if (p.paddingTop != null) paddingTop = p.paddingTop;
		if (p.paddingRight != null) paddingRight = p.paddingRight;
		if (p.paddingBottom != null) paddingBottom = p.paddingBottom;
		if (p.paddingLeft != null) paddingLeft = p.paddingLeft;
		if (p.marginTop != null) marginTop = p.marginTop;
		if (p.marginRight != null) marginRight = p.marginRight;
		if (p.marginBottom != null) marginBottom = p.marginBottom;
		if (p.marginLeft != null) marginLeft = p.marginLeft;
		if (p.borderWidth != null) borderWidth = p.borderWidth;
		if (p.borders != null) borders = p.borders;
		if (p.rowGap != null) rowGap = p.rowGap;
		if (p.columnGap != null) columnGap = p.columnGap;
		if (p.left != null) left = p.left;
		if (p.top != null) top = p.top;
		if (p.right != null) right = p.right;
		if (p.bottom != null) bottom = p.bottom;
		if (p.overflow != null) overflow = p.overflow;
		if (p.overflowX != null) overflowX = p.overflowX;
		if (p.overflowY != null) overflowY = p.overflowY;
		if (p.background != null) background = p.background;
		if (p.backgroundImage != null) backgroundImage = p.backgroundImage;
		if (p.borderColor != null) borderColor = p.borderColor;
		if (p.radius != null) radius = p.radius;
		if (p.corners != null) corners = p.corners;
		if (p.opacity != null) opacity = p.opacity;
		if (p.cursor != null) cursor = p.cursor;
		if (p.shadow != null) shadow = p.shadow;
		if (p.outlineWidth != null) outlineWidth = p.outlineWidth;
		if (p.outlineOffset != null) outlineOffset = p.outlineOffset;
		if (p.outlineColor != null) outlineColor = p.outlineColor;
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
		if (p.lineHeightPx != null) lineHeightPx = p.lineHeightPx;
		if (p.letterSpacingEm != null) letterSpacingEm = p.letterSpacingEm;
		if (p.textAlign != null) textAlign = p.textAlign;
		if (p.dir != null) dir = p.dir;
		if (p.visibility != null) visibility = p.visibility;
		if (p.outlineStyle != null) outlineStyle = p.outlineStyle;
		if (p.userSelect != null) userSelect = p.userSelect;
		if (p.fieldSizing != null) fieldSizing = p.fieldSizing;
		if (p.scrollbarWidth != null) scrollbarWidth = p.scrollbarWidth;
		if (p.breakBefore != null) breakBefore = p.breakBefore;
		if (p.breakAfter != null) breakAfter = p.breakAfter;
		if (p.breakInside != null) breakInside = p.breakInside;
		if (p.page != null) page = p.page;
		if (p.scrollbarColor != null) scrollbarColor = p.scrollbarColor;
		if (p.scrollbarTrackColor != null) scrollbarTrackColor = p.scrollbarTrackColor;
		if (p.ringWidth != null) ringWidth = p.ringWidth;
		if (p.ringColor != null) ringColor = p.ringColor;
		if (p.ringOffsetWidth != null) ringOffsetWidth = p.ringOffsetWidth;
		if (p.ringOffsetColor != null) ringOffsetColor = p.ringOffsetColor;
		if (p.ringInset != null) ringInset = p.ringInset;
		if (p.pointerEvents != null) pointerEvents = p.pointerEvents;
		if (p.textWrap != null) textWrap = p.textWrap;
		if (p.gap != null) gap = p.gap;
		if (p.inset != null) inset = p.inset;
		if (p.flex != null) flex = p.flex;
		if (p.overflowWrap != null) overflowWrap = p.overflowWrap;
		if (p.wordBreak != null) wordBreak = p.wordBreak;
		if (p.fontFeatureSettings != null) fontFeatureSettings = p.fontFeatureSettings;
		if (p.fontVariantNumeric != null) fontVariantNumeric = p.fontVariantNumeric;
		if (p.textTransform != null) textTransform = p.textTransform;
		if (p.textOverflow != null) textOverflow = p.textOverflow;
		if (p.order != null) order = p.order;
		if (p.zIndex != null) zIndex = p.zIndex;
		if (p.textDecoration != null) textDecoration = p.textDecoration;
		if (p.textShadow != null) textShadow = p.textShadow;
		if (p.transition != null) transition = p.transition;
		if (p.textDecorationColor != null) textDecorationColor = p.textDecorationColor;
		if (p.textDecorationThickness != null) textDecorationThickness = p.textDecorationThickness;
		if (p.textUnderlineOffset != null) textUnderlineOffset = p.textUnderlineOffset;
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
	public var backgroundImage:Null<Gradient> = null;
	public var transformOrigin:Null<Array<Dim>> = null;
	public var letterSpacing:Null<Float> = null;
	public var wordSpacing:Null<Float> = null;
	public var lineHeightPx:Null<Float> = null;
	public var letterSpacingEm:Null<Float> = null;
	public var maxLines:Int = 0;
	public var dir:Null<Dir> = null;
	public var visibility:Null<Visibility> = null;
	public var fieldSizing:Null<FieldSizing> = null;
	public var scrollbarWidth:Null<ScrollbarWidth> = null;
	public var breakBefore:Null<PageBreak> = null;
	public var breakAfter:Null<PageBreak> = null;
	public var breakInside:Null<PageBreak> = null;
	public var page:Null<String> = null;
	public var scrollbarColor:Null<Color> = null;
	public var scrollbarTrackColor:Null<Color> = null;
	public var overflowWrap:Null<OverflowWrap> = null;
	public var wordBreak:Null<WordBreak> = null;
	public var fontFeatureSettings:Null<String> = null;
	public var fontVariantNumeric:Null<String> = null;
	public var textTransform:Null<TextTransform> = null;
	public var textOverflow:TextOverflow = Clip;
	public var order:Int = 0;
	public var textDecoration:Int = 0;
	public var textShadow:Null<Shadow> = null;
	public var textDecorationColor:Null<Color> = null;
	// (the properties moving under it; whether the Clock steps them, whether a step is writing them)
	public var textDecorationThickness:Dim = DimValue.Auto;
	public var textUnderlineOffset:Dim = DimValue.Auto;
	public var left:Dim = DimValue.Auto;
	public var top:Dim = DimValue.Auto;
	public var right:Dim = DimValue.Auto;
	public var bottom:Dim = DimValue.Auto;

	public function new() {}
}

// what a Style keeps of the rare properties themes set (Style.themed)
private class StyleThemed {
	public var borders:Null<EdgesValue> = null;
	public var corners:Null<CornersValue> = null;
	public var transform:Null<Transform> = null;
	public var userSelect:Null<UserSelect> = null;
	public var pointerEvents:Null<PointerEvents> = null;
	public var textWrap:Null<TextWrap> = null;
	public var zIndex:Int = 0;
	public var shadow:Null<Shadow> = null;
	public var outlineWidth:Float = 0;
	public var outlineOffset:Float = 0;
	public var outlineColor:Null<Color> = null;
	public var outlineStyle:Null<OutlineStyle> = null;
	public var ringWidth:Float = 0;
	public var ringColor:Null<Color> = null;
	public var ringOffsetWidth:Float = 0;
	public var ringOffsetColor:Color = Color.WHITE;
	public var ringInset = false;
	public var transition:Null<Transition> = null;
	public var moving:Null<Array<Moving>> = null;
	public var ticking = false;
	public var stepping = false;

	public function new() {}
}

// (a property moving under a transition: from where, to what, since when (-1: the next tick), its timing)
private typedef Moving = {name:String, from:Dynamic, to:Dynamic, start:Float, duration:Float, delay:Float, easing:Array<Float>};
