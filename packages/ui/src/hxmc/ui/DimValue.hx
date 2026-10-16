package hxmc.ui;

// Dim's cases: style.width = Percent(50)
enum DimValue {
	Auto;
	Px(v:Float);
	Percent(p:Float);
}
