// story({...}) in TypeScript (Fleet.hx prints the same): stories of a card
// built from their controls, one a store screenshot with its seed, each
// mounted headless and its tree printed as helder test snapshots it.
import {story, tree, type Controls} from "helder/story";
import {Show, type Signal} from "helder/view";

function card(title: Signal<string>, ships: Signal<number>, warning?: Signal<boolean>) {
	return <view grow={1} padding={24} row-gap={12} background="#0b1020" color="#e5e7eb" font-size={16}>
		<text tag="title" font-size={28}>{title()}</text>
		<text tag="ships">{Math.trunc(ships()) + " ships"}</text>
		<Show when={() => warning !== undefined && warning()}><text tag="warning" color="#f59e0b">Low fuel</text></Show>
	</view>;
}

export const plain = story({name: "Card/plain", render: (c) => card(c.text("title", "Fleet"), c.number("ships", 3))});
export const many = story({name: "Card/many", render: (c: Controls) => card(c.text("title", "Armada"), c.number("ships", 42), c.bool("warning", true))});
export const fleet = story({
	name: "Store/fleet",
	store: true,
	caption: "Command a fleet",
	seed: 7,
	background: 0x111827,
	render: (c) => {
		const n = Math.trunc(10 + c.random() * 90);
		return card(c.text("title", "Your fleet"), c.number("ships", n));
	},
});

for (const s of [plain, many, fleet]) console.log(tree(s));
