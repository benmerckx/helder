package viewer;

import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

// FolderModel: natural order, opening a file or a folder, wrapping, the
// neighbours by distance, the watch (files added, removed, the one shown
// gone or changed)
function tests() {
	describe("FolderModel", () -> {
		test("natural order: numbers by value, letters without case", () -> {
			var names = ["img10.png", "IMG2.png", "img1.png", "a.jpg", "img02.png", "B.gif", "img2.png", "photo 10.jpg", "photo 9.jpg"];
			names.sort(FolderModel.compare);
			equals(names, ["a.jpg", "B.gif", "img1.png", "IMG2.png", "img2.png", "img02.png", "img10.png", "photo 9.jpg", "photo 10.jpg"]);
			equals(FolderModel.compare("x", "x"), 0);
			assert(FolderModel.compare("file99999999999999999999.png", "file100000000000000000000.png") < 0, "long runs by length");
		});
		test("images only, by extension", () -> {
			var m = new FolderModel();
			m.setEntries(["notes.txt", "b.JPG", "a.webp", "c.gif", "d.png", "e.jpeg", ".hidden"]);
			equals(m.files, ["a.webp", "b.JPG", "c.gif", "d.png", "e.jpeg"]);
			equals(m.index, 0);
		});
		test("next and previous wrap; first, last; the neighbours nearest first", () -> {
			var m = new FolderModel();
			m.setEntries(["1.png", "2.png", "3.png", "4.png", "5.png"], "1.png");
			m.go(-1);
			equals(m.name, "5.png");
			m.go(1);
			equals(m.name, "1.png");
			equals(m.around(2), [0, 1, 4, 2, 3]);
			m.last();
			equals(m.name, "5.png");
			m.first();
			equals(m.name, "1.png");
			var one = new FolderModel();
			one.setEntries(["only.png"]);
			equals(one.go(1), false);
			equals(one.around(2), [0]);
		});
		test("a file opens its folder at it; a folder at its first image", () -> {
			var dir = fixture();
			var m = new FolderModel();
			assert(m.open('$dir/img10.png'));
			equals(m.files, ["img1.png", "img2.png", "img10.png"]);
			equals(m.name, "img10.png");
			assert(m.open(dir + "/"));
			equals(m.name, "img1.png");
			equals(m.open('$dir/missing.png'), false);
		});
		test("the watch: added, removed, the one shown gone, changed", () -> {
			var dir = fixture();
			var m = new FolderModel();
			m.open('$dir/img2.png');
			equals(m.rescan().listChanged, false);
			File.saveContent('$dir/img3.png', "x");
			var r = m.rescan();
			equals(r.listChanged, true);
			equals(m.files, ["img1.png", "img2.png", "img3.png", "img10.png"]);
			equals(m.name, "img2.png");
			// (the one shown removed: the one after it)
			FileSystem.deleteFile('$dir/img2.png');
			m.rescan();
			equals(m.name, "img3.png");
			// (changed on disk: named to decode again)
			File.saveContent('$dir/img3.png', "changed, longer");
			r = m.rescan();
			equals(r.listChanged, false);
			equals(r.modified, ['$dir/img3.png']);
		});
	});
}

// (a folder of three images and a text file, made again for each test)
private function fixture():String {
	var dir = "bin/test-fixtures/folder";
	if (FileSystem.exists(dir)) for (f in FileSystem.readDirectory(dir)) FileSystem.deleteFile('$dir/$f');
	FileSystem.createDirectory(dir);
	for (n in ["img1.png", "img2.png", "img10.png", "notes.txt"])
		File.saveContent('$dir/$n', n);
	return dir;
}
