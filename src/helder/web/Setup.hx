package helder.web;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;

// -lib helder's initialization (extraParams.hxml): its renderer for
// helder.view, the DOM's in JavaScript (helder.view.renderer.dom), static
// HTML's elsewhere (helder.view.renderer.html). A JavaScript program that
// renders pages too (in node) adds -D helder.view.renderer.html=helder.web.StaticRenderer.
class Setup {
	public static function renderers() {
		if (Context.defined("js")) {
			if (!Context.defined("helder.view.renderer.dom")) Compiler.define("helder.view.renderer.dom", "helder.web.DomRenderer");
		} else if (!Context.defined("helder.view.renderer.html")) Compiler.define("helder.view.renderer.html", "helder.web.StaticRenderer");
	}
}
#end
