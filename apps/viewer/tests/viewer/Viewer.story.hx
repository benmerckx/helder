package viewer;

import helder.story.Story;

// The viewer's states, in a phone's size: empty, an error in place of the
// image, a photo fitted, at 100%, the status line on (their trees in
// Viewer.story.snap)
final empty = story({name: "Viewer/empty", render: c -> Shell.view(viewer())});

final error = story({
	name: "Viewer/error",
	render: c -> {
		var v = viewer();
		v.open("tests/fixtures/folder/broken.jpg");
		Shell.view(v);
	}
});

final fit = story({
	name: "Viewer/fit",
	render: c -> {
		var v = viewer();
		v.open("tests/fixtures/folder/photo 2.jpg");
		Shell.view(v);
	}
});

final actual = story({
	name: "Viewer/100%",
	render: c -> {
		var v = viewer();
		v.open("tests/fixtures/folder/photo 2.jpg");
		v.actual();
		Shell.view(v);
	}
});

final status = story({
	name: "Viewer/status line",
	render: c -> {
		var v = viewer();
		v.open("tests/fixtures/folder/photo 2.jpg");
		v.statusOn(true);
		Shell.view(v);
	}
});

// (decoded at once; the phone's view in device pixels)
private function viewer():Viewer {
	var v = new Viewer((path, side, done) -> done(Decode.file({path: path, side: side})));
	v.camera.setView(390, 844);
	return v;
}
