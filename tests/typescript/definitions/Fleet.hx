import helder.story.Story;
import helder.view.Flow.*;
import helder.view.View;
import helder.view.graph.Signal;

// story({...}) in Haxe: fleet.tsx prints the same.
final plain = story({name: "Card/plain", render: c -> card(c.text("title", "Fleet"), c.number("ships", 3))});

final many = story({name: "Card/many", render: c -> card(c.text("title", "Armada"), c.number("ships", 42), c.bool("warning", true))});

final fleet = story({
	name: "Store/fleet",
	store: true,
	caption: "Command a fleet",
	seed: 7,
	background: 0x111827,
	render: c -> {
		var n = Std.int(10 + c.random() * 90);
		card(c.text("title", "Your fleet"), c.number("ships", n));
	}
});

private function card(title:Signal<String>, ships:Signal<Float>, ?warning:Signal<Bool>):View
	return View.view(<view grow={1} padding={24} row-gap={12} background="#0b1020" color="#e5e7eb" font-size={16}>
		<text tag="title" font-size={28}>{title()}</text>
		<text tag="ships">{Std.int(ships()) + " ships"}</text>
		<Show when={warning != null && warning()}><text tag="warning" color="#f59e0b">Low fuel</text></Show>
	</view>);

class Fleet {
	static function main() {
		for (s in [plain, many, fleet])
			Sys.println(helder.story.Stories.tree(s));
	}
}
