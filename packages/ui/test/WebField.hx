import hxmc.theme.Shadcn;
import hxmc.ui.*;
import hxmc.ui.draw.UiWindow;
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

// Native text editors in a browser (web-field.mjs: wasm32-wasi in headless
// Chromium): a field and a text area, native by the window's policy, among
// drawn widgets (a button, a select whose list covers the area when open, a
// field drawn by its host).
// After each frame whose state changed it prints the boxes of the nodes the
// test clicks and the state: "field name=... | notes=... | submitted=... |
// focus=<tag>".
class WebField implements Markup {
	static function main() {
		var w = new UiWindow("Fields", 420, 320);
		w.ui.theme = Shadcn.sheet;
		var name = signal(""), notes = signal(""), submitted = signal(""), fruit = signal("Apple"), drawn = signal("");
		Render.render(<view slot="body" grow={1} padding={20} row-gap={12} align-items="stretch" font-family="DejaVu Sans">
			<view direction="row" column-gap={12}>
				<Select tag="fruit" value={fruit} options={["Apple", "Pear", "Plum", "Fig"]} width={160} label="Fruit"/>
				<view host="drawn" grow={1}><Input tag="drawn" value={drawn} placeholder="Drawn" label="Drawn"/></view>
			</view>
			<Input tag="name" value={name} placeholder="Your name" label="Name" onSubmit={t -> submitted.value = t}/>
			<Textarea tag="notes" value={notes} rows={3} placeholder="Notes" label="Notes"/>
			<Button tag="reset" label="Reset" onClick={() -> name.value = "Reset"}/>
		</view>, w.root);
		var last = "";
		w.onFrame = () -> {
			var parts = [];
			for (tag in ["fruit", "drawn", "name", "notes", "reset"]) {
				var n = w.root.find(tag);
				if (n != null) parts.push('$tag=${n.absX},${n.absY},${n.width},${n.height}');
			}
			var f = w.ui.focus;
			var s = "boxes " + parts.join(" ") + " | name=" + name.peek() + " | notes=" + StringTools.replace(notes.peek(), "\n", "\\n") + " | submitted="
				+ submitted.peek() + " | drawn=" + drawn.peek() + " | focus=" + (f == null ? "" : f.tag);
			if (s != last) {
				last = s;
				Sys.println(s);
			}
		};
		UiWindow.run();
	}
}
