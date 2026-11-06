// an asset's path has no .. (in TypeScript: asset-parent.ts).
// expect: Asset.image("files/../files/pixels.png"): a part ".."
class RejectAssetParent {
	static function main() {
		trace(helder.asset.Asset.image("files/../files/pixels.png"));
	}
}
