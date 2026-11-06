package helder.asset;

import helder.async.Async;
import helder.async.Task;

// helder.asset for TypeScript programs (helder/asset): image(path), font,
// model, sound and bytes, definitions (as Haxe's Asset.image...: the same
// check, AssetCheck), each a handle (Asset). Their calls are compiled: the
// path a literal, found and bundled when the program is built
// (helder.typescript.lower's TsAssets), the call given its key's marker
// and, where the program reads it from disk (helder dev), the file. Also
// written `import icon from "./icon.png" with {type: "image"}`.
class ScriptAssets {
	// an image (helder.image.Image)
	public static function image(path:String, ?file:String):Asset<helder.image.Image>
		return ImageAsset.load(Assets.key(path), file);

	// a font (helder.text.FontFile)
	public static function font(path:String, ?file:String):Asset<helder.text.FontFile>
		return FontAsset.load(Assets.key(path), file);

	// a glTF model (helder.scene.render.Model; its names are Haxe's alone)
	public static function model(path:String, ?file:String):Asset<helder.scene.render.Model<Dynamic, Dynamic, Dynamic, Dynamic>>
		return helder.scene.render.Model.asset(Assets.key(path), file, null, null, null, null);

	// a sound file's bytes
	public static function sound(path:String, ?file:String):Asset<haxe.io.Bytes>
		return BytesAsset.sound(Assets.key(path), file);

	// a file's bytes
	public static function bytes(path:String, ?file:String):Asset<haxe.io.Bytes>
		return BytesAsset.load(Assets.key(path), file);

	// the asset's value once it is loaded (its AssetError if it failed): a promise
	public static function loaded<T>(asset:Asset<T>):Task<T>
		return Async.launch(@:coroutine function(_) return asset.load());

	// whether it is loaded
	public static function ready<T>(asset:Asset<T>):Bool
		return asset.ready;
}
