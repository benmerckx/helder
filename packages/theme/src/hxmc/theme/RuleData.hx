package hxmc.theme;

import hxmc.ui.*;
import hxmc.ui.Grid;

using StringTools;

// The rules Tw makes at compile time, as compact data read when the
// program first needs them (no class or CSS is parsed then: colours and
// transforms excepted, by Color.parse and Transform.parse): a table of
// strings (slots, states, colours, numbers written as Haxe writes them) and
// a stream of small numbers, each one, two or three characters (under 64:
// 48 + n; under 960: 112 + n / 64, then 48 + n % 64; else "!", then 48 + n
// / 64 and 48 + n % 64). A rule is its slot, variant and
// size (strings, 0 for none, else 1 + index), its states (a count, then
// each), its fields (a count, then each field's index in FIELDS and its
// value, read as its kind says; a number "r" and px is --radius plus px,
// Length.token's). A sheet is a count of rules, the rules, the light and
// dark tokens (a count, then name and colour each), then --radius in px.
class RuleData {
	// StyleProps's fields the rules may set and their kinds: e an enum
	// abstract's Int, b Bool, f Float, i Int, d Dim, E EdgesValue, C
	// CornersValue, c Color, s String, S Shadow, t Transform, T an array of
	// grid tracks, k a grid track, p a grid placement
	public static final FIELDS = "display:e position:e direction:e wrap:b justify:e alignItems:e alignSelf:e alignContent:e grow:f shrink:f basis:d "
		+ "width:d height:d minWidth:d minHeight:d maxWidth:d maxHeight:d aspectRatio:f padding:E margin:E borderWidth:f borders:E rowGap:f "
		+ "columnGap:f left:d top:d right:d bottom:d overflow:e background:c letterSpacing:f textDecoration:i borderColor:c radius:f corners:C "
		+ "opacity:f cursor:e shadow:S outlineWidth:f outlineOffset:f outlineColor:c color:c fontFamily:s fontSize:f fontWeight:i italic:b "
		+ "lineHeight:f textAlign:e visibility:e pointerEvents:e textWrap:e gap:f flex:f overflowWrap:e wordBreak:e fontVariantNumeric:s "
		+ "textTransform:e textOverflow:e order:i zIndex:i maxLines:i gridTemplateColumns:T gridTemplateRows:T gridAutoColumns:k gridAutoRows:k "
		+ "gridColumn:p gridRow:p justifyItems:e justifySelf:e transform:t outlineStyle:e ringWidth:f ringColor:c ringOffsetWidth:f ringOffsetColor:c "
		+ "ringInset:b transition:r paddingTop:f paddingRight:f paddingBottom:f paddingLeft:f marginTop:f marginRight:f marginBottom:f marginLeft:f "
		+ "overflowX:e overflowY:e letterSpacingEm:f userSelect:e lineHeightPx:f fieldSizing:e textUnderlineOffset:d "
		+ "scrollbarWidth:e scrollbarColor:c scrollbarTrackColor:c";

	final data:String;
	final table:Array<String>;
	final colors:Array<Null<Color>> = [];
	final transitions = new Map<Int, Transition>();
	final kinds = FIELDS.split(" ");
	var at = 0;

	function new(data:String, table:String) {
		this.data = data;
		this.table = table.split("\n");
	}

	public static function rules(data:String, table:String):Array<Rule> {
		var r = new RuleData(data, table);
		return [while (r.at < data.length) r.rule()];
	}

	public static function sheet(data:String, table:String):StyleSheet {
		var r = new RuleData(data, table);
		var rules = [for (_ in 0...r.int()) r.rule()];
		var light = r.tokens(), dark = r.tokens(), radius = r.num();
		var markers = new Map<String, String>();
		for (_ in 0...r.int())
			markers.set(r.str(), r.str());
		return {rules: rules, light: light, dark: dark, lengths: ["radius" => radius], markers: markers};
	}

	inline function int():Int {
		var c = data.fastCodeAt(at++);
		if (c == "!".code) {
			c = data.fastCodeAt(at++) - 48;
			return (c << 6) | (data.fastCodeAt(at++) - 48);
		}
		return c < 112 ? c - 48 : ((c - 112) << 6) | (data.fastCodeAt(at++) - 48);
	}

	inline function str():String
		return table[int()];

	// (a number; "r" and px: --radius plus px, Length.token's)
	function num():Float {
		var s = str();
		return s.fastCodeAt(0) == "r".code ? Length.token("radius", Std.parseFloat(s.substr(1))) : Std.parseFloat(s);
	}

	function color():Color {
		var i = int();
		var c = colors[i];
		if (c == null) c = colors[i] = Color.parse(table[i]);
		return c;
	}

	function tokens():Map<String, Color>
		return [for (_ in 0...int()) str() => color()];

	function rule():Rule {
		var slot = str();
		var v = int(), s = int();
		var when = [for (_ in 0...int()) str()];
		var style = {};
		for (_ in 0...int()) {
			var f = kinds[int()];
			var colon = f.indexOf(":");
			Reflect.setField(style, f.substr(0, colon), value(f.fastCodeAt(colon + 1)));
		}
		var r:Rule = {slot: slot, style: cast style};
		if (v > 0) r.variant = table[v - 1];
		if (s > 0) r.size = table[s - 1];
		if (when.length > 0) r.when = when;
		return r;
	}

	function value(kind:Int):Dynamic
		return switch kind {
			case "e".code | "b".code: kind == "b".code ? int() == 1 : int();
			case "f".code: num();
			case "i".code: Std.int(num());
			case "d".code: dim();
			case "E".code: new Edges(num(), num(), num(), num());
			case "C".code: new Corners(num(), num(), num(), num());
			case "c".code: color();
			case "s".code: str();
			case "t".code: Transform.parse(str());
			case "r".code:
				// (one Transition for each, as each colour)
				var i = int();
				var t = transitions[i];
				if (t == null) t = transitions[i] = Transition.parse(table[i]);
				t;
			case "S".code:
				var n = int();
				if (n == 0) Shadow.NONE else {
					var first:Null<Shadow> = null, last:Null<Shadow> = null;
					for (_ in 0...n) {
						var sh:Shadow = {x: num(), y: num(), blur: num(), spread: num(), color: color()};
						if (first == null) first = sh else last.next = sh;
						last = sh;
					}
					first;
				}
			case "T".code: [for (_ in 0...int()) track()];
			case "k".code: track();
			case "p".code: new GridPlacement(Std.int(num()), Std.int(num()), Std.int(num()));
			case _: throw "RuleData: kind " + String.fromCharCode(kind);
		}

	function dim():Dim
		return switch int() {
			case 0: DimValue.Px(num());
			case 1: DimValue.Percent(num());
			case 2: DimValue.Auto;
			case 3: DimValue.MinContent;
			case 4: DimValue.MaxContent;
			case 6:
				var p = num();
				DimValue.Calc(p, num());
			case _: DimValue.FitContent;
		}

	function track():Track
		return new Track(trackSize(), trackSize());

	function trackSize():TrackSize
		return switch int() {
			case 0: Px(num());
			case 1: Percent(num());
			case 2: Fr(num());
			case 3: Auto;
			case 4: MinContent;
			case _: MaxContent;
		}
}
