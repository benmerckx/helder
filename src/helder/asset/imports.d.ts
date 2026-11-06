// helder/asset's imports of a program's files (index.d.ts references it):
// `import icon from "./icon.png" with {type: "image"}` is image("icon.png"),
// a definition (its file found and bundled when the program is built), by
// the type the import's attribute gives: image, font, model, sound or bytes.

declare module "*.png" {
	const asset: import("helder/asset").Asset<import("helder/asset").Image>;
	export default asset;
}
declare module "*.jpg" {
	const asset: import("helder/asset").Asset<import("helder/asset").Image>;
	export default asset;
}
declare module "*.jpeg" {
	const asset: import("helder/asset").Asset<import("helder/asset").Image>;
	export default asset;
}
declare module "*.gif" {
	const asset: import("helder/asset").Asset<import("helder/asset").Image>;
	export default asset;
}
declare module "*.webp" {
	const asset: import("helder/asset").Asset<import("helder/asset").Image>;
	export default asset;
}
declare module "*.ttf" {
	const asset: import("helder/asset").Asset<import("helder/asset").FontFile>;
	export default asset;
}
declare module "*.otf" {
	const asset: import("helder/asset").Asset<import("helder/asset").FontFile>;
	export default asset;
}
declare module "*.glb" {
	const asset: import("helder/asset").Asset<import("helder/asset").Model<any, any, any, any>>;
	export default asset;
}
declare module "*.wav" {
	const asset: import("helder/asset").Asset<Uint8Array>;
	export default asset;
}
declare module "*.ogg" {
	const asset: import("helder/asset").Asset<Uint8Array>;
	export default asset;
}
declare module "*.bin" {
	const asset: import("helder/asset").Asset<Uint8Array>;
	export default asset;
}
declare module "*.txt" {
	const asset: import("helder/asset").Asset<Uint8Array>;
	export default asset;
}
