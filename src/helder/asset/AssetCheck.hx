package helder.asset;

import helder.definition.Kernel;

// image(path), font, model, sound, bytes and embed's handler (src/helder/
// compiler/DESIGN.md 4), the same for both languages (Haxe's Asset.image...
// through AssetDefinition, TypeScript's helder/asset through
// helder.typescript.lower's Definitions): the argument a path literal
// (anything else rejected as not static by the adapter, or as what it is
// here). Each adapter then finds the file, its path one an asset may
// have (AssetPath.error: Asset.image("path"): why, the same in both), and
// bundles it.
class AssetCheck implements Definition<Adapter, String> {
	public final name:String;

	public function new(kind:String)
		name = "Asset." + kind;

	public function generate(arg:KNode, a:Adapter):String {
		var path = switch arg.value {
			case KString(s): s;
			case _: a.error('takes the file\'s path, a string literal, not ${arg.describe()}', arg.pos);
		}
		return path;
	}
}
