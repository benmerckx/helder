// a story's name is static (in TypeScript: story-not-static.tsx).
// expect: story: title is not static
import helder.story.Story;

class RejectStoryNotStatic {
	static function main() {
		var title = "Card";
		trace(story({name: title, render: c -> helder.view.View.view(<view/>)}));
	}
}
