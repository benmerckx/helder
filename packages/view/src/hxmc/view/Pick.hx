package hxmc.view;

import haxe.macro.Expr;

// A component's function for a renderer, which markup's factories call: a
// class limited to some renderers (@:renderer, MarkupMacro) names the class
// whose function of the same name another renderer's markup calls
// (@:renderer(hxmc.ui.view.NodeRenderer, hxmc.web.DomRenderer =>
// hxmc.web.widgets.Widgets): ui's widgets, the DOM's in a page), else
// the component itself
class Pick {
	// the function for renderer pass (its index)
	public static macro function callee(pass:Int, callee:Expr):Expr
		return MarkupMacro.pick(pass, callee);

	// the call for the renderer mounting it (Render.pass), in a literal whose
	// factories every renderer shares
	public static macro function call(callee:Expr, props:Expr):Expr
		return MarkupMacro.pickCall(callee, props);
}
