package studio.web;

#if (hxmc.target == "wasm32-wasi")
import haxe.Json;
import helder.async.*;
import hxmc.unsafe.*;
import studio.web.StudioWeb.WebText;

// The studio's tools (Tools, the desktop's MCP server's) called by the
// page: WebMCP's tools where the browser has it, and a draft's link
// (helder.build's relay: an agent's patches, the tab's results). Calls
// come as JSON (StudioWeb.tool_next), each answered when it is done.
class WebTools {
	@:coroutine public static function serve(studio:Studio) {
		var list = Json.stringify(Tools.list);
		Arena.scoped(a -> StudioWeb.tools(a.cstring(list)));
		while (true) {
			var h;
			while ((h = StudioWeb.tool_next()) != 0) {
				var m:Dynamic = Json.parse(WebText.take(h));
				Async.launch(_ -> {
					var r = studio.tools.call(m.name, m.arguments);
					var s = Json.stringify(r);
					Arena.scoped(a -> StudioWeb.tool_done(m.id, a.cstring(s)));
				});
			}
			Async.delay(0.02);
		}
	}
}
#end
