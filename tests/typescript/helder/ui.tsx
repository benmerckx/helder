// helder.ui's markup from TypeScript, headless (UiProbe): the neutral
// elements and their attributes (ui's setters), a field's input, a key's
// handler given ui's Event (its parameter untyped: typed by the
// declarations' JSX), components of the program's, a Read prop given a
// constant or bound to what its value reads, For, Show, holes and
// attributes that read bound; examples/ts-todo's shape.
import { signal, memo, For, Show, Render, Signal, Read } from "helder/view";
import { Event, Key } from "helder/ui";
import { UiProbe } from "./ui-probe";

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

function visible(): Item[] {
	const f = filter();
	return todos().filter(i => f === "active" ? !i.done() : f === "done" ? i.done() : true);
}

function Button(props: { label: string; onClick: () => void; tag?: string; outline?: Read<boolean> }) {
	return <view:button tag={props.tag ?? "button"} role="button" focusable padding="4 8" border-width={props.outline?.() ? 1 : 0}
		onPress={() => props.onClick()}>{props.outline?.() ? "(" + props.label + ")" : props.label}</view:button>;
}

function Checkbox(props: { checked: Signal<boolean>; label: string; tag: string }) {
	return <view direction="row" column-gap={8}>
		<view:button tag={props.tag} role="checkbox" checked={props.checked} focusable width={16} height={16}
			background={props.checked() ? "#18181b" : "#ffffff"} onPress={() => props.checked(c => !c)}>
			<Show when={props.checked}><icon name="check" width={12} height={12}/></Show>
		</view:button>
		<text color={props.checked() ? "#a1a1aa" : "#18181b"}>{props.label}</text>
	</view>;
}

const left = memo(() => todos().filter(i => !i.done()).length);

const root = UiProbe.root(480, 560);
Render.render(
	<view grow={1} padding={24} row-gap={14}>
		<text font-size={28}>todos</text>
		<view direction="row" column-gap={8}>
			<field tag="draft" grow={1} value={draft} placeholder="What needs to be done?"
				onInput={(e: Event) => draft(e.text)} onKeyDown={e => { if (e.key === Key.ENTER) add(); }}/>
			<Button tag="add" label="Add" outline onClick={add}/>
		</view>
		<scroll tag="list" grow={1} row-gap={6}>
			<For each={visible}>{item => <view direction="row" column-gap={8}>
				<Checkbox checked={item().done} label={item().title} tag={"check-" + item().title}/>
			</view>}</For>
			<Show when={visible().length === 0}><text>Nothing here.</text></Show>
		</scroll>
		<text tag="left">{left() === 1 ? "1 item left" : left() + " items left"}</text>
		<view direction="row" column-gap={6}>{["all", "active", "done"].map(f =>
			<Button tag={"filter-" + f} label={f} outline={filter() !== f} onClick={() => filter(f)}/>)}</view>
	</view>,
	root
);
console.log(UiProbe.dump());
UiProbe.click("draft");
UiProbe.type("Buy milk");
UiProbe.key(Key.ENTER);
UiProbe.type("Walk");
UiProbe.click("add");
console.log(UiProbe.dump());
UiProbe.click("check-Walk");
UiProbe.click("filter-done");
console.log(UiProbe.dump());
