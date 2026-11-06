// a story's name is static (in Haxe: RejectStoryNotStatic.hx).
// expect: story: title is not static
import {story} from "helder/story";

export function f() {
	const title = "Card";
	return story({name: title, render: (c) => <view/>});
}
