import helder.theme.Shadcn;
import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.view.Render;

// The todo example in a browser (web.mjs: wasm32-wasi in headless Chromium,
// on WebGPU and on WebGL2): a 420x480 window on the page's canvas, the
// fonts the page gives (DejaVu Sans). After each frame whose layout
// changed it prints the boxes of the nodes the test clicks ("boxes
// draft=x,y,w,h add=... "), so that the page can drive it with real
// pointer and keyboard events, then the count, the items and the wheel's
// scrolling the root heard (pixels, added up).
class WebTodo {
	static function main() {
		var w = new UiWindow("Todo", 420, 480);
		// (shadcn's, its buttons' cursor a pointer as many apps make it: what
		// Window.cursor gives the canvas over one)
		var sheet = Shadcn.sheet;
		// (its fields drawn: web.mjs types into the canvas, input methods included; web-field.mjs has the native editors)
		w.ui.policy["text-field"] = Host.Drawn;
		w.ui.theme = {rules: sheet.rules.concat([{slot: "button", style: {cursor: Pointer}}]), light: sheet.light, dark: sheet.dark, lengths: sheet.lengths};
		var app = new Todo();
		Render.render(app.view(), w.root);
		var last = "", wheel = 0.0;
		w.root.onWheel = e -> {
			wheel += e.deltaY;
			w.ui.requestFrame();
		};
		w.onFrame = () -> {
			var parts = [];
			for (tag in ["draft", "add", "checkbox", "filter-all", "filter-active", "left"]) {
				var n = w.root.find(tag);
				if (n != null) parts.push('$tag=${n.absX},${n.absY},${n.width},${n.height}');
			}
			var t:TextNode = cast w.root.find("left");
			var s = "boxes " + parts.join(" ") + " | " + (t != null ? t.text : "") + " | " + app.todos.peek().length + " | wheel " + wheel + " | dark " + UiWindow.dark.value;
			if (s != last) {
				last = s;
				Sys.println(s);
			}
		};
		UiWindow.run();
	}
}
