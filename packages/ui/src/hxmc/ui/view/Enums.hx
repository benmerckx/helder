package hxmc.ui.view;

class Enums {
	// [every value of an enum abstract], in order: Enums.values(hxmc.ui.access.Role)
	public static macro function values(e:haxe.macro.Expr):haxe.macro.Expr
		return hxmc.ui.view.AttrMacro.values(e);
}
