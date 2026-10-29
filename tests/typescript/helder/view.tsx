// helder.view from TypeScript: signals, memos and effects, TSX bound to them,
// a component of the program's, control flow, events, rendered headless.
import { signal, memo, effect, batch, For, Show, Render } from "helder/view";
import { TestNode } from "./test-renderer";

const count = signal(1);
const items = signal(["a", "b"]);
const doubled = memo(() => count.value * 2);
effect(() => console.log("count is", count.value));

function Item(props: { label: string }) {
	return <p>item {props.label}</p>;
}

const root = TestNode.root("root");
Render.render(
	<div class="box">
		<p>
			{count} doubled {doubled}
		</p>
		<For each={items} render={(i: string) => <Item label={i} />} />
		<Show when={() => count.value > 2} fallback={<p>small</p>}>
			<p>big</p>
		</Show>
		<button onClick={() => count.value++}>+</button>
	</div>,
	root
);
console.log(root.toHtml());
root.fire("button", "onClick");
root.fire("button", "onClick");
batch(() => {
	items.value = [...items.value, "c"];
	count.value = count.value * 10;
});
console.log(root.toHtml(), doubled.value, items.value.length);
