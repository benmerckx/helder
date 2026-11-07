package helder.story;

import helder.story.Story;

// A project's stories as the studio's screens (apps/studio): the program
// the studio builds of a project (a dev build, -D hxmc.dev) runs every
// story in one program, the studio's preview host (helder.story.Host: each
// story a root of its own with a context of its own): natively one process
// (helder.story.NativeHost: its frames GPU textures the studio's process
// opens, or shared memory where the GPU shares none), built for the web
// (wasm32-wasi) a worker (helder.story.web.Preview). Over the devtools
// protocol `Studio.screens` answers the screens: {screens: [{name, width,
// height}]}.
//
//   // the studio's generated main (bin/studio/<name>/gen/StudioScreens.hx, screens.tsx)
//   helder.story.Screens.run(helder.story.Stories.of("Todo_story"));
//   import { screens } from "helder/story"; screens([empty, items]);
class Screens {
	public static function run(stories:Array<Story>) {
		var list = [for (s in stories) if (s != null) s];
		if (list.length == 0) throw "helder.story.Screens: no stories (a release build has none)";
		#if (hxmc.target == "wasm32-wasi")
		helder.story.web.Preview.run(list);
		#else
		helder.story.NativeHost.run(list);
		#end
	}
}
