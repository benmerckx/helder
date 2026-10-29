import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.ui.view.UiFlow.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import helder.view.graph.Read;

// Native text editors in a browser (web-field.mjs: wasm32-wasi in headless
// Chromium): a field and a text area, native by the window's policy, among
// drawn nodes (a button, a select whose list covers the field when open,
// a field drawn by its host).
// After each frame whose state changed it prints the boxes of the nodes the
// test clicks and the state: "field name=... | notes=... | submitted=... |
// focus=<tag>".
class WebField implements Markup {
	static function main() {
		var w = new UiWindow("Fields", 420, 320);
		var name = signal(""), notes = signal(""), submitted = signal(""), fruit = signal("Apple"), drawn = signal("");
		Render.render(<view grow={1} padding={20} row-gap={12} align-items="stretch" font-family="DejaVu Sans" background="#ffffff">
			<view direction="row" column-gap={12}>
				<Select tag="fruit" value={fruit} options={["Apple", "Pear", "Plum", "Fig"]} label="Fruit"/>
				<view host="drawn" grow={1}><field tag="drawn" value={drawn} placeholder="Drawn" label="Drawn" onInput={e -> drawn(e.text)} padding="6 10"
					border-width={1}/></view>
			</view>
			<field tag="name" value={name} placeholder="Your name" label="Name" onInput={e -> name(e.text)}
				onKeyDown={e -> if (e.key == Key.ENTER) submitted(name.peek())} padding="6 10" border-width={1}/>
			<field:textarea tag="notes" value={notes} rows={3} placeholder="Notes" label="Notes" onInput={e -> notes(e.text)} padding="6 10" border-width={1}/>
			<view:button tag="reset" role="button" focusable align-self="start" padding="6 12" border-width={1} onPress={_ -> name("Reset")}>Reset</view:button>
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

	// (a select: its value on a button, its options in a popup under it while open)
	static function Select(props:{value:Signal<String>, options:Array<String>, tag:String, label:String}):View {
		var open = signal(false);
		return <view:button tag={props.tag} role="combobox" label={props.label} expanded={open} focusable width={160} padding="6 10" border-width={1}
			onPress={() -> open(o -> !o)}>
			{props.value}
			<Popover open={open} placement="below" onDismiss={() -> open(false)}>
				<view tag={props.tag + "-list"} role="listbox" width={160} padding={4} border-width={1} background="#ffffff">
					<For each={props.options}>{option -> {
						var o = option();
						<view:button role="option" focusable padding="4 8" onPress={() -> {
							props.value(o);
							open(false);
						}}>{o}</view:button>;
					}}</For>
				</view>
			</Popover>
		</view:button>;
	}
}
