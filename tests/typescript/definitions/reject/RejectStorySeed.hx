// a story's seed is an integer (in TypeScript: story-seed.tsx).
// expect: story: seed is an integer literal, not a number
import helder.story.Story;

class RejectStorySeed {
	static function main() {
		trace(story({name: "Card", seed: 1.5, render: c -> helder.view.View.view(<view/>)}));
	}
}
