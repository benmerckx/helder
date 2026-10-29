// title: Todo
// summary: A todo list in markup: signals, a keyed list, a text field, checkboxes and filters
// tags: ui, view, text input
// demo: canvas 480x560
import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import helder.view.graph.Read;

// A todo list in markup on helder.ui: signals hold the state, For keeps a
// row per item, the text field adds one on Enter, the checkboxes and the
// filters update what is shown. Its buttons and checkboxes are its own
// (views with a role, focusable, pressed by a click, Enter or Space), their
// look a small StyleSheet (Todo.sheet: their slots, hovered, checked). In
// a window:
//
//   haxe -lib helder -cp examples/todo -main Todo --custom-target hxmc=todo -D hxmc.libc=glibc
//
// (TodoTest drives it headless, WebTodo in a browser.)
class Todo implements Markup {
	static function main() {
		UiWindow.run(<Surface title="Todo" width={480} height={560} theme={sheet}>{new Todo().view()}</Surface>);
	}

	public static final sheet:StyleSheet = {
		rules: [
			{slot: "button", style: {direction: Row, alignItems: Center, justify: Center, padding: [6, 12], radius: 6, background: Color.rgb(0x18181B),
				color: Color.rgb(0xFAFAFA), cursor: Pointer}},
			{slot: "button", when: ["hover"], style: {background: Color.rgb(0x3F3F46)}},
			{slot: "button", variant: "outline", style: {background: Color.rgb(0xFFFFFF), color: Color.rgb(0x18181B), borderWidth: 1, borderColor: Color.rgb(0xE4E4E7)}},
			{slot: "button", variant: "outline", when: ["hover"], style: {background: Color.rgb(0xF4F4F5)}},
			{slot: "button", variant: "ghost", style: {background: Color.TRANSPARENT, color: Color.rgb(0x71717A)}},
			{slot: "button", variant: "ghost", when: ["hover"], style: {background: Color.rgb(0xF4F4F5), color: Color.rgb(0x18181B)}},
			{slot: "button", size: "sm", style: {padding: [4, 8]}},
			{slot: "input", style: {padding: [8, 12], radius: 6, borderWidth: 1, borderColor: Color.rgb(0xE4E4E7), background: Color.rgb(0xFFFFFF)}},
			{slot: "input", when: ["focus"], style: {borderColor: Color.rgb(0xA1A1AA)}},
			{slot: "input", when: ["placeholder"], style: {color: Color.rgb(0xA1A1AA)}},
			{slot: "checkbox", style: {width: 16, height: 16, radius: 4, borderWidth: 1, borderColor: Color.rgb(0xA1A1AA), alignItems: Center,
				justify: Center, cursor: Pointer}},
			{slot: "checkbox", when: ["data-state=checked"], style: {background: Color.rgb(0x18181B), borderColor: Color.rgb(0x18181B), color: Color.rgb(0xFAFAFA)}}
		]
	};

	public final todos = signal(new Array<Item>());
	public final draft = signal("");
	public final filter = signal("all");

	public function new() {}

	public function add() {
		var t = StringTools.trim(draft());
		if (t == "") return;
		todos(todos().concat([new Item(t)]));
		draft("");
	}

	public function remove(i:Item)
		todos(todos().filter(x -> x != i));

	function visible():Array<Item>
		return todos().filter(i -> switch filter() {
			case "active": !i.done();
			case "done": i.done();
			case _: true;
		});

	static function Button(props:{label:String, onClick:Void->Void, ?tag:String, ?variant:Read<Null<String>>, ?size:String}):View
		return <view:button tag={props.tag ?? "button"} slot="button" variant={props.variant != null ? props.variant() : null} size={props.size} role="button" focusable
			onPress={props.onClick}>{props.label}</view:button>;

	// (the label pressed toggles it too; the box named by it, the text hidden from assistive technology)
	static function Checkbox(props:{checked:Signal<Bool>, label:String}):View {
		var toggle = () -> props.checked(c -> !c);
		return <view direction="row" align-items="center" column-gap={8}>
			<view:button tag="checkbox" slot="checkbox" role="checkbox" label={props.label} checked={props.checked}
				data-state={props.checked() ? "checked" : "unchecked"} focusable onPress={toggle}>
				<Show when={props.checked}><icon name="check" width={12} height={12}/></Show>
			</view:button>
			<text hidden cursor="pointer" color={props.checked() ? "#a1a1aa" : "#18181b"}
				text-decoration={props.checked() ? "line-through" : "none"} onClick={toggle}>{props.label}</text>
		</view>;
	}

	public function view():View {
		var left = memo(() -> todos().filter(i -> !i.done()).length);
		return <view grow={1} padding={24} row-gap={14} background="#fafafa" font-family="DejaVu Sans" font-size={14} color="#18181b">
			<text font-size={28} font-weight={700} color="#3b82f6">todos</text>
			<view direction="row" column-gap={8}>
				<field tag="draft" slot="input" grow={1} value={draft} placeholder="What needs to be done?" label="What needs to be done?"
					onInput={e -> draft(e.text)} onKeyDown={e -> if (e.key == Key.ENTER) add()}/>
				<Button tag="add" label="Add" onClick={add}/>
			</view>
			<scroll tag="list" grow={1} min-height={0} row-gap={6} background="#ffffff" radius={8} border-width={1} border-color="#e4e4e7" padding={8}>
				<For each={visible()}>{(item:Read<Item>) -> {
					var i = item();
					<view direction="row" align-items="center" column-gap={8} padding="4 6" radius={6}>
						<view grow={1}><Checkbox checked={i.done} label={i.title}/></view>
						<Button label="Remove" variant="ghost" size="sm" onClick={() -> remove(i)}/>
					</view>;
				}}</For>
				<Show when={visible().length == 0}><text color="#a1a1aa" padding={6}>Nothing here.</text></Show>
			</scroll>
			<view direction="row" align-items="center" justify="space-between">
				<text tag="left">{left() == 1 ? "1 item left" : left() + " items left"}</text>
				<view direction="row" column-gap={6}>{() -> [
					for (f in ["all", "active", "done"])
						<Button tag={"filter-" + f} label={f} variant={filter() == f ? null : "outline"} size="sm" onClick={() -> filter(f)}/>
				]}</view>
			</view>
		</view>;
	}
}

class Item {
	public final title:String;
	public final done = signal(false);

	public function new(title:String)
		this.title = title;
}
