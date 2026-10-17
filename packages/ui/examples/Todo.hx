// title: Todo
// summary: A todo list in markup: signals, a keyed list, a text field, checkboxes and filters
// tags: ui, view, widgets, text input
// demo: canvas 480x560
import hxmc.ui.*;
import hxmc.ui.draw.UiWindow;
import hxmc.view.*;
import hxmc.view.Flow.*;
import hxmc.view.Reactive.*;
import hxmc.ui.widgets.Widgets.*;

// A todo list in markup on hxmc.ui: signals hold the state, For keeps a
// row per item, the text field adds one on Enter, the checkboxes and the
// filters update what is shown. In a window:
//
//   haxe -lib hxmc.ui -cp packages/ui/examples -main Todo --custom-target hxmc=todo -D hxmc.libc=glibc
//
// (TodoTest drives it headless.)
class Todo implements Markup {
	static function main() {
		var w = new UiWindow("Todo", 480, 560);
		w.ui.theme = Plain.sheet;
		Render.render(new Todo().view(), w.root);
		UiWindow.run();
	}

	public final todos = signal(new Array<Item>());
	public final draft = signal("");
	public final filter = signal("all");

	public function new() {}

	public function add() {
		var t = StringTools.trim(draft.value);
		if (t == "") return;
		batch(() -> {
			todos.value = todos.value.concat([new Item(t)]);
			draft.value = "";
		});
	}

	public function remove(i:Item)
		todos.value = todos.value.filter(x -> x != i);

	function visible():Array<Item>
		return todos.value.filter(i -> switch filter.value {
			case "active": !i.done.value;
			case "done": i.done.value;
			case _: true;
		});

	public function view():View {
		var left = memo(() -> todos.value.filter(i -> !i.done.value).length);
		return <view grow={1} padding={24} row-gap={14} background="#fafafa" font-family="DejaVu Sans" font-size={14} color="#18181b">
			<text font-size={28} font-weight={700} color="#3b82f6">todos</text>
			<view direction="row" column-gap={8}>
				<view grow={1}><Input tag="draft" value={draft} placeholder="What needs to be done?" onSubmit={_ -> add()}/></view>
				<Button tag="add" label="Add" onClick={add}/>
			</view>
			<scroll tag="list" grow={1} min-height={0} row-gap={6} background="#ffffff" radius={8} border-width={1} border-color="#e4e4e7" padding={8}>
				<For each={visible} render={(i:Item) -> <view direction="row" align-items="center" column-gap={8} padding="4 6" radius={6}>
					<view grow={1}><Checkbox checked={i.done} label={i.title}/></view>
					<Button label="Remove" onClick={() -> remove(i)}/>
				</view>}/>
				<Show when={() -> visible().length == 0}><text color="#a1a1aa" padding={6}>Nothing here.</text></Show>
			</scroll>
			<view direction="row" align-items="center" justify="space-between">
				<text tag="left">{() -> left.value == 1 ? "1 item left" : left.value + " items left"}</text>
				<view direction="row" column-gap={6}>{() -> [
					for (f in ["all", "active", "done"])
						<Button tag={"filter-" + f} label={f} variant={filter.value == f ? "default" : "outline"} onClick={() -> filter.value = f}/>
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
