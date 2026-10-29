// title: Todo in TypeScript
// summary: The todo list in TSX: signals, For keeping a row per item, a text field, checkboxes and filters, components of its own
// tags: typescript, ui, view, text input
// demo: canvas 480x560
// The todo list in TypeScript: signals hold the state, For keeps a row per
// item, the text field adds one on Enter, the checkboxes and the filters
// update what is shown. Its buttons and checkboxes are components of its
// own (TypeScript functions), styled inline; a hole or an attribute that
// reads follows what it reads, as in Haxe (a filter's outline: a Read prop).
// (examples/todo in Haxe.)
import { signal, memo, For, Show, Signal, Read } from "helder/view";
import { UiWindow, Surface, Event, Key } from "helder/ui";

class Item {
	readonly done = signal(false);
	constructor(readonly title: string) {}
}

const todos = signal<Item[]>([]);
const draft = signal("");
const filter = signal("all");

function add() {
	const t = draft().trim();
	if (t === "") return;
	todos(todos().concat([new Item(t)]));
	draft("");
}

function remove(i: Item) {
	todos(todos().filter(x => x !== i));
}

function visible(): Item[] {
	const f = filter();
	return todos().filter(i => f === "active" ? !i.done() : f === "done" ? i.done() : true);
}

function Button(props: { label: string; onClick: () => void; tag?: string; outline?: Read<boolean>; small?: boolean }) {
	return <view:button tag={props.tag ?? "button"} role="button" focusable cursor="pointer" direction="row" align-items="center" justify="center"
		padding={props.small ? "4 8" : "6 12"} radius={6} border-width={props.outline?.() ? 1 : 0} border-color="#e4e4e7"
		background={props.outline?.() ? "#ffffff" : "#18181b"} color={props.outline?.() ? "#18181b" : "#fafafa"}
		onPress={() => props.onClick()}>{props.label}</view:button>;
}

// (the label pressed toggles it too)
function Checkbox(props: { checked: Signal<boolean>; label: string }) {
	const toggle = () => props.checked(c => !c);
	return <view direction="row" align-items="center" column-gap={8}>
		<view:button role="checkbox" label={props.label} checked={props.checked} focusable cursor="pointer" width={16} height={16} radius={4}
			border-width={1} align-items="center" justify="center" border-color={props.checked() ? "#18181b" : "#a1a1aa"}
			background={props.checked() ? "#18181b" : "#ffffff"} onPress={toggle}>
			<Show when={props.checked}><icon name="check" width={12} height={12} color="#fafafa"/></Show>
		</view:button>
		<text hidden cursor="pointer" color={props.checked() ? "#a1a1aa" : "#18181b"}
			text-decoration={props.checked() ? "line-through" : "none"} onClick={toggle}>{props.label}</text>
	</view>;
}

const left = memo(() => todos().filter(i => !i.done()).length);

UiWindow.run(
	<Surface title="Todo" width={480} height={560}>
		<view grow={1} padding={24} row-gap={14} background="#fafafa" font-family="DejaVu Sans" font-size={14} color="#18181b">
			<text font-size={28} font-weight={700} color="#3b82f6">todos</text>
			<view direction="row" column-gap={8}>
				<field tag="draft" grow={1} value={draft} placeholder="What needs to be done?" label="What needs to be done?" padding="8 12" radius={6}
					border-width={1} border-color="#e4e4e7" background="#ffffff"
					onInput={(e: Event) => draft(e.text)} onKeyDown={(e: Event) => { if (e.key === Key.ENTER) add(); }}/>
				<Button tag="add" label="Add" onClick={add}/>
			</view>
			<scroll tag="list" grow={1} min-height={0} row-gap={6} background="#ffffff" radius={8} border-width={1} border-color="#e4e4e7" padding={8}>
				<For each={visible}>{item => <view direction="row" align-items="center" column-gap={8} padding="4 6" radius={6}>
					<view grow={1}><Checkbox checked={item().done} label={item().title}/></view>
					<Button label="Remove" outline small onClick={() => remove(item())}/>
				</view>}</For>
				<Show when={visible().length === 0}><text color="#a1a1aa" padding={6}>Nothing here.</text></Show>
			</scroll>
			<view direction="row" align-items="center" justify="space-between">
				<text tag="left">{left() === 1 ? "1 item left" : left() + " items left"}</text>
				<view direction="row" column-gap={6}>{["all", "active", "done"].map(f =>
					<Button tag={"filter-" + f} label={f} outline={filter() !== f} small onClick={() => filter(f)}/>)}</view>
			</view>
		</view>
	</Surface>
);
