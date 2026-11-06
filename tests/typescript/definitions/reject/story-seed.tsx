// a story's seed is an integer (in Haxe: RejectStorySeed.hx).
// expect: story: seed is an integer literal, not a number
import {story} from "helder/story";

export const s = story({name: "Card", seed: 1.5, render: (c) => <view/>});
