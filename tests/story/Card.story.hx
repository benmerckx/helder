package story;

import helder.story.Story;
import helder.view.Flow.*;
import helder.view.View;
import helder.view.graph.Signal;

// helder.story's own stories (the test lane snapshots their trees in
// Card.story.snap; the pack lane renders the store one as screenshots): a
// card of a title and a count, its controls signals
function stories() {
	story("Card/plain", c -> card(c.text("title", "Fleet"), c.number("ships", 3)));
	story("Card/many", c -> card(c.text("title", "Armada"), c.number("ships", 42), c.bool("warning", true)));
	story("Store/fleet", c -> {
		var n = Std.int(10 + c.random() * 90);
		card(c.text("title", "Your fleet"), c.number("ships", n));
	}).store({caption: "Command a fleet", seed: 7});
}

private function card(title:Signal<String>, ships:Signal<Float>, ?warning:Signal<Bool>):View
	return View.view(<view grow={1} padding={24} row-gap={12} background="#0b1020" color="#e5e7eb" font-size={16}>
		<text tag="title" font-size={28}>{title()}</text>
		<text tag="ships">{Std.int(ships()) + " ships"}</text>
		<Show when={warning != null && warning()}><text tag="warning" color="#f59e0b">Low fuel</text></Show>
	</view>);
