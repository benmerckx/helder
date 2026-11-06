// a caption is a store screenshot's (in TypeScript: story-caption.tsx).
// expect: story: caption is a store screenshot's (store: true)
import helder.story.Story;

class RejectStoryCaption {
	static function main() {
		trace(story({name: "Card", caption: "Command a fleet", render: c -> helder.view.View.view(<view/>)}));
	}
}
