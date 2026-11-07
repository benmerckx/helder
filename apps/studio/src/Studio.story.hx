import helder.story.Story;

// The studio's own screens (`helder studio apps/studio`: the studio in the
// studio), at its window's size: no project open, and examples/todo opened
// but not started (its screens waiting for their build).
final none = story({
	name: "Studio/No project",
	width: 1180,
	height: 740,
	render: () -> {
		Main.fonts();
		studio.Shell.view(new studio.Studio(null, {}));
	}
});

final todo = story({
	name: "Studio/Todo, not started",
	width: 1180,
	height: 740,
	render: () -> {
		Main.fonts();
		var s = new studio.Studio("../../examples/todo", {});
		studio.Shell.view(s);
	}
});
