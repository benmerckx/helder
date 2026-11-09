package studio;

import helder.test.Test;

// A design file's frames and the places of the frames the program draws
// (<Frame story="file#name" canvas:at>, <Frame app canvas:at>: the free
// canvas' stories and app)
function tests() {
	describe("DesignFile", () -> {
		test("design frames, and the stories' and the app's places apart", () -> {
			var text = '<Design>\n\t<Frame name="Home" canvas:at="0 0"><text>Hi</text></Frame>\n\t<Frame story="Todo.story.hx#done" canvas:at="1130 744"/>\n\t<Frame app canvas:at="-500 20"/>\n\t<Frame story="b.story.tsx#plain"/>\n</Design>\n';
			var d = new DesignFile(text);
			equals([for (f in d.frames) f.name], ["Home"]);
			equals([for (p in d.places) p.ref], ["Todo.story.hx#done", "app", "b.story.tsx#plain"]);
			equals([for (p in d.places) p.at], [{x: 1130.0, y: 744.0}, {x: -500.0, y: 20.0}, null]);
			equals(text.substr(d.places[1].start, 10), "<Frame app");
		});
	});
}
