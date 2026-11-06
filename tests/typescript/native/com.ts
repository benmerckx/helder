// native.com on Windows (run.mjs runs it there, and under Wine where it is
// installed): Windows Imaging Component's factory made by its CLSID, a
// bitmap made by one of its methods (slot 17), its size read back through
// IWICBitmapSource's GetSize ([out] parameters: buffers), both released.
import { native, i32, u32, pointer, buffer } from "helder/native";

// IWICImagingFactory: its methods from CreateBitmap on (after IUnknown's
// three and thirteen others)
const Factory = native.com({
	clsid: "{cacaf262-9370-4615-a13b-9f5539da4c0a}",
	iid: "{ec5ec8a9-c395-4314-9c77-54d7a935ff70}",
	base: 17,
	methods: {
		CreateBitmap: (self: pointer, width: u32, height: u32, format: pointer, option: i32, out: buffer): i32 => 0,
	},
});

// IWICBitmap, from IWICBitmapSource's GetSize
const Bitmap = native.com({
	iid: "{00000121-a8f2-4877-ba0a-fd2b6645fb94}",
	methods: {
		GetSize: (self: pointer, width: buffer, height: buffer): i32 => 0,
	},
});

const BGRA = native.guid("{6fddc324-4e03-4bfe-b185-3d77768dc90f}");

function word(b: Uint8Array): number {
	const d = new DataView(b.buffer);
	return d.getUint32(0, true) + d.getUint32(4, true) * 4294967296;
}

const factory = Factory.create();
console.log(factory !== 0);
const out = new Uint8Array(8);
// (WICBitmapCacheOnLoad)
console.log(Factory.CreateBitmap(factory, 7, 5, BGRA, 2, out));
const bitmap = word(out);
const w = new Uint8Array(4), h = new Uint8Array(4);
console.log(Bitmap.GetSize(bitmap, w, h), new DataView(w.buffer).getUint32(0, true), new DataView(h.buffer).getUint32(0, true));
// (a QueryInterface of the bitmap for IWICBitmap itself: S_OK, a reference more)
const again = new Uint8Array(8);
console.log(Bitmap.QueryInterface(bitmap, Bitmap.iid, again), word(again) === bitmap);
Bitmap.Release(word(again));
console.log(Bitmap.Release(bitmap), Factory.Release(factory) >= 0);
