package helder.story;

import helder.story.Story;

// A project's stories as the studio's screens (apps/studio): the program
// the studio builds of a project (a dev build, headless: -D hxmc.dev -D
// helder.headless) shows one story in a window of the story's size
// (width, height; a phone's without), the one HELDER_STUDIO_SCREEN names
// (the first without). The studio starts one such process for each screen,
// so a screen's state (a TypeScript module's signals) is its own. Over the
// devtools protocol, `Studio.screens` answers which one this is and the
// others: {screen, screens: [{name, width, height}]}.
//
//   // the studio's generated main (bin/studio/<name>/ScreensMain.hx, screens.tsx)
//   helder.story.Screens.run(helder.story.Stories.of("Todo_story"));
//   import { screens } from "helder/story"; screens([empty, items]);
class Screens {
	public static function run(stories:Array<Story>) {
		var list = [for (s in stories) if (s != null) s];
		if (list.length == 0) throw "helder.story.Screens: no stories (a release build has none)";
		var want = Sys.getEnv("HELDER_STUDIO_SCREEN");
		var s = Lambda.find(list, x -> x.name == want) ?? list[0];
		#if hxmc.dev
		helder.devtools.Agent.method("Studio.screens", _ -> {
			screen: s.name,
			screens: [for (x in list) {name: x.name, width: x.width ?? Stories.WIDTH, height: x.height ?? Stories.HEIGHT}]
		});
		#end
		var w = new helder.ui.draw.UiWindow(s.name, s.width ?? Stories.WIDTH, s.height ?? Stories.HEIGHT);
		helder.view.Render.render(s.build(new Controls(s.seed)), w.root);
		helder.ui.draw.UiWindow.run();
	}
}
