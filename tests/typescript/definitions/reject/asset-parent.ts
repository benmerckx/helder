// an asset's path has no .. (in Haxe: RejectAssetParent.hx).
// expect: Asset.image("files/../files/pixels.png"): a part ".."
import {bytes, image} from "helder/asset";

export const a = image("files/../files/pixels.png");
