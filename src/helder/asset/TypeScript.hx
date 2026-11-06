package helder.asset;

// helder.asset for TypeScript programs (helder.typescript): image(path),
// font, model, sound and bytes, each a handle (Asset) of a file of the
// program found and bundled when it is built (definitions: ScriptAssets);
// loaded(asset), a promise of its value. imports.d.ts declares the
// imports of files with a type (`import icon from "./icon.png" with
// {type: "image"}`, the same definition).
@:typescript("helder/asset")
@:typescript.references("imports.d.ts")
@:typescript.types(helder.asset.Asset, helder.image.Image, helder.text.FontFile, helder.scene.render.Model)
@:typescript.functions(image = helder.asset.ScriptAssets.image, font = helder.asset.ScriptAssets.font, model = helder.asset.ScriptAssets.model,
	sound = helder.asset.ScriptAssets.sound, bytes = helder.asset.ScriptAssets.bytes, loaded = helder.asset.ScriptAssets.loaded,
	ready = helder.asset.ScriptAssets.ready)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
