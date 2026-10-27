package helder.ui.view;

class Enums {
	// [every value of an enum abstract], in order: Enums.values(helder.ui.access.Role)
	public static macro function values(e:haxe.macro.Expr):haxe.macro.Expr
		return helder.ui.view.AttrMacro.values(e);
}
