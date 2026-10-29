// helder.view from TypeScript: signals, memos and effects, TSX bound to them,
// a component of the program's, control flow, events, rendered headless.
import { signal, memo, effect, flush, For, Show, Render } from "helder/view";
import { TestNode } from "./test-renderer";

const count = signal(1);
const items = signal(["a", "b"]);
const doubled = memo(() => count() * 2);
effect(() => count(), v => console.log("count is", v));

function Item(props: { label: string }) {
	return <p>item {props.label}</p>;
}

const root = TestNode.root("root");
Render.render(
	<div class="box">
		<p>
			{count} doubled {doubled}
		</p>
		<For each={items}>{i => <Item label={i()} />}</For>
		<Show when={() => count() > 2} fallback={<p>small</p>}>
			<p>big</p>
		</Show>
		<button onClick={() => count(c => c + 1)}>+</button>
	</div>,
	root
);
console.log(root.toHtml());
root.fire("button", "onClick");
flush();
root.fire("button", "onClick");
flush();
items([...items(), "c"]);
count(count() * 10);
flush();
console.log(root.toHtml(), doubled(), items().length);
