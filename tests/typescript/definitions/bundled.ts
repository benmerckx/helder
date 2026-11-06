// helder/asset's definitions in TypeScript (Bundled.hx prints the same):
// a file's bytes and an image by their paths, found and bundled when the
// program is built, and an image imported with its type, the same
// definition; each loaded, then read. Natively only: the tests' WASI
// runner has no fetch for the files beside the module (the asset lane's
// web check reads them).
// targets: linux-x86_64
import {bytes, image, loaded, ready} from "helder/asset";
import pixels from "./files/pixels.png" with {type: "image"};

async function main() {
	const note = bytes("files/note.txt");
	const data = await loaded(note);
	console.log(`${data.length} ${String.fromCharCode(...data.subarray(0, 7))}`);
	const a = image("files/pixels.png");
	await loaded(a);
	await loaded(pixels);
	console.log(`${ready(a)} ${ready(pixels)}`);
}
main();
