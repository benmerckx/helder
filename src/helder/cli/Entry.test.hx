package helder.cli;

import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

// What a directory builds (Entry.resolve): helder.json's entry, with or
// without a package.json beside it (an app in a repository of its own,
// helder its dependency), named as the package; else src/Main.hx
function tests() {
	test("a package with helder.json's entry: that file, the package's name, its directory the root", () -> {
		var d = fixture("bin/test-entry/app", [
			"package.json" => '{"name": "@studio/little-app", "devDependencies": {"helder": "*"}}',
			"helder.json" => '{"name": "Little App", "entry": "src/LittleApp.hx"}',
			"src/LittleApp.hx" => "class LittleApp {\n\tstatic function main() {}\n}\n",
			"src/Course.hx" => "class Course {}\n"
		]);
		var e = Entry.resolve(d, "linux-x86_64");
		equals([e.main, e.name, e.root], ["LittleApp", "little-app", d]);
		equals(e.classPaths[0], '$d/src');
		equals(e.out("linux-x86_64"), '$d/bin/linux-x86_64/little-app');
	});

	test("helder.json's entry missing: an error naming it", () -> {
		var d = fixture("bin/test-entry/missing", [
			"package.json" => '{"name": "missing"}',
			"helder.json" => '{"name": "Missing", "entry": "src/Gone.hx"}'
		]);
		var message = try {
			Entry.resolve(d);
			"";
		} catch (e:String) e;
		equals(message, '$d/helder.json: entry: src/Gone.hx: no such file');
	});

	test("a package without an entry in helder.json: src/Main.hx", () -> {
		var d = fixture("bin/test-entry/plain", [
			"package.json" => '{"name": "plain"}',
			"helder.json" => '{"name": "Plain"}',
			"src/Main.hx" => "class Main {\n\tstatic function main() {}\n}\n"
		]);
		var e = Entry.resolve(d);
		equals([e.main, e.name], ["Main", "plain"]);
	});
}

// a directory of files (written fresh)
private function fixture(dir:String, files:Map<String, String>):String {
	TestCommand.rmrf(dir);
	for (name => text in files) {
		var f = '$dir/$name';
		FileSystem.createDirectory(haxe.io.Path.directory(f));
		File.saveContent(f, text);
	}
	return dir;
}
