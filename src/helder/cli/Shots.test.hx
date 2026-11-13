package helder.cli;

import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

// an app's screenshots from its stories (Shots): the entry's own story
// files (a helder.json's directory, a TypeScript program's), the store
// ones counted from their text, in path order and as written; a
// TypeScript program's main importing each exported story
function tests() {
	test("a helder.json's directory: its story files in path order, the store stories counted", () -> {
		var d = fixture("bin/test-shots/game", [
			"helder.json" => '{"name": "Game", "entry": "Game.hx", "run": {"name": "game"}}',
			"Game.hx" => "class Game {\n\tstatic function main() {}\n}\n",
			"Game.story.hx" => 'import helder.story.Story;\n\nfinal one = story({name: "Holes/One", store: true, caption: "A hole", render: c -> null});\nfinal plain = story({name: "Holes/Plain", render: c -> null});\n',
			"more/More.story.hx" => 'package more;\n\nimport helder.story.Story;\n\nfinal two = story({\n\tname: "Holes/Two",\n\tstore: true,\n\trender: c -> null\n});\n',
			"bin/Old.story.hx" => "// (built output: not a story file of the project)\n"
		]);
		var f = Shots.find(Entry.resolve(d), false);
		equals(f.files, ['$d/Game.story.hx', '$d/more/More.story.hx']);
		equals([f.stores, f.own ? 1 : 0], [2, 1]);
		equals([for (s in Shots.stories('$d/Game.story.hx')) '${s.binding} ${s.name} ${s.store}'], ['one "Holes/One" true', 'plain "Holes/Plain" false']);
	});

	test("no story with store: true: none (helder.run takes one of the program)", () -> {
		var d = fixture("bin/test-shots/plain", [
			"helder.json" => '{"name": "Plain", "entry": "Plain.hx"}',
			"Plain.hx" => "class Plain {\n\tstatic function main() {}\n}\n",
			"Plain.story.hx" => 'import helder.story.Story;\n\nfinal a = story({name: "A", render: c -> null});\n'
		]);
		var f = Shots.find(Entry.resolve(d), false);
		equals([f.files.length, f.stores], [1, 0]);
	});

	test("a TypeScript program: its .story.tsx files, each exported story imported by the main", () -> {
		var d = fixture("bin/test-shots/ts", [
			"main.tsx" => 'console.log("app");\n',
			"app.story.tsx" => 'import { story } from "helder/story";\n\nexport const home = story({ name: "Home", store: true, caption: "Home", render: () => null });\nexport const list = story({ name: "List", store: true, render: () => null });\n',
			"Ignored.story.hx" => 'final x = story({name: "X", store: true, render: c -> null});\n'
		]);
		var f = Shots.find(Entry.resolve(d), false);
		// (a TypeScript program's: its full path)
		equals(f.files, [FileSystem.fullPath(d).split("\\").join("/") + "/app.story.tsx"]);
		equals(f.stores, 2);
		var main:String = @:privateAccess Shots.typescriptMain(f.files, FileSystem.fullPath('$d/bin/shots'));
		equals(main.split("\n").slice(1, 4), ['import { shots } from "helder/story";', 'import { home as s0, list as s1 } from "../../app.story";', "shots([s0, s1]);"]);
	});
}

// a directory of files (written fresh)
private function fixture(dir:String, files:Map<String, String>):String {
	TestCommand.rmrf(dir);
	for (name => text in files) {
		var p = '$dir/$name';
		TestCommand.mkdirs(haxe.io.Path.directory(p));
		File.saveContent(p, text);
	}
	return dir;
}
