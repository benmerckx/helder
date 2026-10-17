package hxmc.web;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;

// -lib hxmc.web's initialization (extraParams.hxml): its renderer for
// hxmc.view, the DOM's in JavaScript (hxmc.view.renderer.dom), static
// HTML's elsewhere (hxmc.view.renderer.html). A JavaScript program that
// renders pages too (in node) adds -D hxmc.view.renderer.html=hxmc.web.StaticRenderer.
class Setup {
	public static function renderers() {
		if (Context.defined("js")) {
			if (!Context.defined("hxmc.view.renderer.dom")) Compiler.define("hxmc.view.renderer.dom", "hxmc.web.DomRenderer");
		} else if (!Context.defined("hxmc.view.renderer.html")) Compiler.define("hxmc.view.renderer.html", "hxmc.web.StaticRenderer");
	}
}
#end
