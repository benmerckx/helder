package studio;

import helder.test.Test;

// The sidebar's tree: what a file is by its name (the view it opens in), a
// path from a design file's folder (an image dropped on its frame)
function tests() {
	describe("FileTree", () -> {
		test("a file's kind by its name", () -> {
			equals([for (n in ["app.helder", "Todo.story.hx", "app.story.tsx", "Todo.hx", "logo.PNG", "icon.svg", "Inter.ttf", "ship.glb", "hit.wav", "notes.bin"])
				(FileTree.kindOf(n) : String)], ["design", "story", "story", "code", "image", "image", "font", "model", "audio", "other"]);
		});
		test("a path from a folder, ../ where it is above", () -> {
			equals(FileTree.relativeTo("/p", "/p/assets/a.png"), "assets/a.png");
			equals(FileTree.relativeTo("/p/pages", "/p/assets/a.png"), "../assets/a.png");
			equals(FileTree.relativeTo("/p/a/b", "/p/a/b/c.png"), "c.png");
		});
	});
}
