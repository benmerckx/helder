package viewer;

import helder.story.StoryText;
import helder.test.Test;
import helder.ui.Key;
import helder.ui.TextNode;
import helder.ui.Ui;
import helder.view.Render;

// A scripted run, headless: the shell's tree in a Ui without a window or
// a GPU, the fixture folder opened (tests/fixtures/folder: a PNG, an
// animated GIF, a JPEG cut short, a WebP, a photo and a JPEG turned by
// EXIF, a text file), then flipped through with the keys and the wheel,
// zoomed, the status line and the picker shown, as a user would
function tests() {
	describe("Viewer, scripted", () -> {
		var dir = "tests/fixtures/folder";
		function text(ui:Ui, tag:String):String {
			var n = ui.root.find(tag);
			if (n == null) return "";
			if (Std.isOfType(n, TextNode)) return (cast n : TextNode).text;
			for (c in n.children)
				if (Std.isOfType(c, TextNode)) return (cast c : TextNode).text;
			return "";
		}
		test("open, flip, zoom, the status line, the picker", () -> {
			var viewer = new Viewer((path, side, done) -> done(Decode.file({path: path, side: side})));
			var ui = new Ui(new StoryText(), 800, 600);
			Render.render(Shell.view(viewer), ui.root);
			Shell.attach(ui.root, viewer, false);
			viewer.camera.setView(800, 600);
			ui.update();
			equals(viewer.state.peek(), Empty);
			equals(text(ui, "title"), "No image open");
			assert(viewer.open(dir));
			helder.view.graph.Graph.flush();
			ui.update();
			equals(viewer.title.peek(), "alpha.png · 1 / 6 · 13×11");
			// (the next: an animated GIF, its frames played)
			ui.keyDown(Key.RIGHT, 0);
			ui.update();
			equals(viewer.title.peek(), "anim.gif · 2 / 6 · 37×29");
			equals(viewer.shown.frames.length, 2);
			viewer.tick(0, 0);
			viewer.tick(0.15, 0.15);
			equals(viewer.frame, 1);
			// (a JPEG cut short: its message in place, flipping goes on)
			ui.keyDown(Key.PAGE_DOWN, 0);
			ui.update();
			equals(viewer.state.peek(), Failed);
			assert(StringTools.startsWith(text(ui, "title"), "Damaged or cut short"), text(ui, "title"));
			equals(viewer.title.peek(), "broken.jpg · 3 / 6");
			// (the wheel, fitted: the next)
			viewer.wheel(400, 300, 40, false, 10);
			helder.view.graph.Graph.flush();
			ui.update();
			equals(viewer.title.peek(), "lossy.webp · 4 / 6 · 50×40");
			ui.keyDown(Key.RIGHT, 0);
			ui.update();
			equals(viewer.title.peek(), "photo 2.jpg · 5 / 6 · 1242×1048");
			equals(viewer.camera.fitted, true);
			equals(viewer.camera.percent(), 57);
			// (the zoom: + (Shift and =), 1, the wheel about the cursor, 0; the viewer's keymap)
			ui.keyDown("=".code, Key.MOD_SHIFT);
			equals(viewer.camera.percent(), 67);
			ui.keyDown("1".code, 0);
			equals(viewer.camera.percent(), 100);
			viewer.wheel(100, 100, -40, true, 11);
			equals(viewer.camera.percent(), 125);
			viewer.pan(50, 0);
			ui.keyDown("0".code, 0);
			equals(viewer.camera.fitted, true);
			// (the status line)
			ui.keyDown("i".code, 0);
			ui.update();
			equals(text(ui, "status"), "57% · 1242×1048 · JPEG · 197 KB · 5 / 6");
			// (EXIF's orientation 6: 37x29 stored, shown 29x37)
			ui.keyDown(Key.END, 0);
			ui.update();
			equals(viewer.title.peek(), "photo 10.jpg · 6 / 6 · 29×37");
			// (wrapping, Home)
			ui.keyDown(Key.RIGHT, 0);
			equals(viewer.folder.name, "alpha.png");
			ui.keyDown(Key.LEFT, 0);
			equals(viewer.folder.name, "photo 10.jpg");
			ui.keyDown(Key.HOME, 0);
			equals(viewer.folder.name, "alpha.png");
			// (the picker: Mod+O, its listing, Escape)
			ui.keyDown("o".code, Key.MOD_CONTROL);
			ui.update();
			equals(viewer.pickerOpen.peek(), true);
			equals(viewer.pickerEntries.peek(), ["../", "alpha.png", "anim.gif", "broken.jpg", "lossy.webp", "photo 2.jpg", "photo 10.jpg"]);
			assert(ui.root.find("picker") != null, "the picker's card");
			viewer.pick("photo 2.jpg");
			helder.view.graph.Graph.flush();
			ui.update();
			equals(viewer.pickerOpen.peek(), false);
			equals(viewer.folder.name, "photo 2.jpg");
			// (fullscreen: F11 and Enter, Escape leaves)
			ui.keyDown(Key.F1 + 10, 0);
			equals(viewer.fullscreen.peek(), true);
			ui.keyDown(Key.ESCAPE, 0);
			equals(viewer.fullscreen.peek(), false);
			// (decoded at the size shown: a small view, the photo at 1/4; at 100% decoded again whole)
			viewer.camera.setView(300, 200);
			viewer.cache.clear();
			viewer.open(dir + "/photo 2.jpg");
			helder.view.graph.Graph.flush();
			equals([viewer.shown.width, viewer.shown.pixelsWidth], [1242, 311]);
			viewer.actual();
			equals([viewer.shown.width, viewer.shown.pixelsWidth], [1242, 1242]);
			viewer.camera.setView(800, 600);
			// (a file that is not there: its message, nothing else)
			equals(viewer.open(dir + "/missing.png"), false);
			helder.view.graph.Graph.flush();
			equals(viewer.state.peek(), Failed);
		});
		test("a PDF's pages: the keys, the wheel, go to page, the next page decoded ahead", () -> {
			var asked = [];
			var viewer = new Viewer((path, side, done) -> {
				asked.push(Decode.parseKey(path).page);
				done(Decode.file({path: path, side: side}));
			});
			var ui = new Ui(new StoryText(), 800, 600);
			Render.render(Shell.view(viewer), ui.root);
			Shell.attach(ui.root, viewer, false);
			viewer.camera.setView(800, 600);
			assert(viewer.open("tests/fixtures/pdf/pages.pdf"));
			helder.view.graph.Graph.flush();
			ui.update();
			equals(viewer.state.peek(), Shown);
			equals(viewer.pages, 3);
			equals(viewer.title.peek(), "pages.pdf · 1 / 1 · page 1 / 3");
			// (its size at 100%: 2 pixels a point; drawn at the view's side)
			equals([viewer.shown.width, viewer.shown.height], [600, 800]);
			equals(viewer.shown.pixelsHeight, 800);
			// (page 2 decoded ahead, before it was asked for)
			equals(asked, [0, 1]);
			assert(viewer.cache.get(Decode.key(viewer.folder.current, 1)) != null, "page 2 ahead");
			// (Page Down: page 2, landscape, fitted again; page 3 ahead)
			ui.keyDown(Key.PAGE_DOWN, 0);
			ui.update();
			equals(viewer.title.peek(), "pages.pdf · 1 / 1 · page 2 / 3");
			equals([viewer.shown.width, viewer.shown.height], [800, 600]);
			equals(viewer.camera.fitted, true);
			equals(asked, [0, 1, 2]);
			// (the status line: the page, not a size)
			ui.keyDown("i".code, 0);
			ui.update();
			equals(text(ui, "status"), "100% · page 2 / 3 · PDF · 1 KB · 1 / 1");
			// (Space the next page; at the last, nothing; Backspace back; the wheel, fitted, by pages)
			ui.keyDown(" ".code, 0);
			equals(viewer.page, 2);
			ui.keyDown(" ".code, 0);
			equals(viewer.page, 2);
			ui.keyDown(Key.BACKSPACE, 0);
			equals(viewer.page, 1);
			viewer.wheel(400, 300, -40, false, 20);
			equals(viewer.page, 0);
			// (Ctrl+End the last page, Ctrl+Home the first)
			ui.keyDown(Key.END, Key.MOD_CONTROL);
			equals(viewer.page, 2);
			ui.keyDown(Key.HOME, Key.MOD_CONTROL);
			equals(viewer.page, 0);
			// (go to page: G, a number, Enter; past the last: the last)
			ui.keyDown("g".code, 0);
			helder.view.graph.Graph.flush();
			ui.update();
			equals(viewer.gotoOpen.peek(), true);
			assert(ui.root.find("goto") != null, "the go to page card");
			equals(viewer.goToTyped("3"), true);
			helder.view.graph.Graph.flush();
			equals(viewer.page, 2);
			equals(viewer.gotoOpen.peek(), false);
			viewer.goToTyped("99");
			equals(viewer.page, 2);
			viewer.goToTyped("1");
			equals(viewer.page, 0);
			// (zoomed in: page 1 drawn again larger, as a JPEG's refine)
			viewer.camera.setView(300, 200);
			viewer.cache.clear();
			viewer.open("tests/fixtures/pdf/pages.pdf");
			helder.view.graph.Graph.flush();
			equals([viewer.shown.width, viewer.shown.pixelsHeight], [600, 300]);
			viewer.actual();
			equals(viewer.shown.pixelsHeight, 800);
			equals(viewer.title.peek(), "pages.pdf · 1 / 1 · page 1 / 3");
			// (past the last page: nothing)
			equals(viewer.toPage(5), false);
		});
	});
}
