package helder.view;

import haxe.macro.Expr;

// A component's function for a renderer, which markup's factories call: a
// class limited to some renderers (@:renderer, MarkupMacro) names the class
// whose function of the same name another renderer's markup calls
// (@:renderer(helder.ui.view.NodeRenderer, helder.web.DomRenderer =>
// DomControls): drawn controls, DomControls' in a page; none for it an
// error), else the component itself
class Pick {
	// the function for renderer (its class path)
	public static macro function callee(renderer:String, callee:Expr):Expr
		return MarkupMacro.pick(renderer, callee);

	// the call for the renderer mounting it (Render.pass), in an agnostic literal
	public static macro function call(callee:Expr, props:Expr):Expr
		return MarkupMacro.pickCall(callee, props);
}
