// a caption is a store screenshot's (in Haxe: RejectStoryCaption.hx).
// expect: story: caption is a store screenshot's (store: true)
import {story} from "helder/story";

export const s = story({name: "Card", caption: "Command a fleet", render: (c) => <view/>});
