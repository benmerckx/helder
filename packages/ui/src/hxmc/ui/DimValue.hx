package hxmc.ui;

// Dim's cases: style.width = Percent(50); Calc: a percentage plus pixels
// (CSS's calc(100% - 2rem): Calc(100, -32)); MinContent, MaxContent and
// FitContent: CSS's intrinsic sizes, the content's narrowest, widest, or
// widest within the room (widths: width, minWidth, maxWidth; a height as auto)
enum DimValue {
	Auto;
	Px(v:Float);
	Percent(p:Float);
	Calc(p:Float, px:Float);
	MinContent;
	MaxContent;
	FitContent;
}
