package hxmc.web;

import hxmc.view.Render;
import hxmc.web.HtmlNode;

// Static pages: components rendered to HTML at build time with the static
// renderer (StaticRenderer), natively, on Eval or in node:
//
//   class Site implements Markup {
//     static function main() {
//       Static.write("out/index.html", Static.document(<html lang="en">
//         <head><title>hxmc</title><script src="islands-loader.js" defer></script></head>
//         <body><Layout><Demo.Counter start={3}/></Layout></body>
//       </html>));
//     }
//   }
//
// Effects run once, then the page's root is disposed; listeners are
// dropped. Islands (Island) carry their props and the module that hydrates
// them; regions carry the markers hydration reads (HtmlNode).
class Static {
	// content as HTML
	public static function render(content:Any):String {
		var root = new HtmlNode(Root, "#root");
		var dispose = Render.render(content, root);
		var html = root.innerHtml();
		dispose();
		return html;
	}

	// a whole page: <!doctype html> and content (an <html> element)
	public static function document(content:Any):String
		return "<!doctype html>\n" + render(content);

	#if sys
	// writes a page (or any text), its directories made
	public static function write(path:String, text:String) {
		var dir = haxe.io.Path.directory(path);
		if (dir != "") sys.FileSystem.createDirectory(dir);
		sys.io.File.saveContent(path, text);
	}

	// copies a file (an example's wasm build, a script), its directories made
	public static function copy(from:String, to:String) {
		var dir = haxe.io.Path.directory(to);
		if (dir != "") sys.FileSystem.createDirectory(dir);
		sys.io.File.copy(from, to);
	}
	#end
}
