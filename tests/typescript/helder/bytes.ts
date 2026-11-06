// helder's bytes as typed arrays (helder/canvas): ImageData's data a
// Uint8ClampedArray sharing its pixels (what the program writes there
// putImageData draws), a new ImageData over a typed array's bytes,
// toBuffer's file a Uint8Array.
import { Canvas, ImageData } from "helder/canvas";

const canvas = new Canvas(4, 2);
const ctx = canvas.getContext("2d")!;
ctx.fillStyle = "#ff0000";
ctx.fillRect(0, 0, 2, 2);
const d = ctx.getImageData(0, 0, 4, 2);
console.log(d.data instanceof Uint8ClampedArray, d.data.length, Array.from(d.data.subarray(0, 8)));
// (clamped: 300 is 255, -4 is 0, 127.5 rounds to the even 128)
d.data[4] = 300;
d.data[5] = -4;
d.data[6] = 127.5;
d.data[7] = 255;
console.log(Array.from(d.data.subarray(4, 8)));
ctx.putImageData(d, 0, 0);
console.log(Array.from(ctx.getImageData(1, 0, 1, 1).data));

const pixels = new Uint8ClampedArray(2 * 1 * 4);
pixels.set([0, 0, 255, 255, 0, 255, 0, 255]);
ctx.putImageData(new ImageData(pixels, 2, 1), 2, 1);
console.log(Array.from(ctx.getImageData(2, 1, 2, 1).data));

const png = canvas.toBuffer("png");
console.log(png instanceof Uint8Array, Array.from(png.subarray(1, 4)).map(c => String.fromCharCode(c)).join(""), png.length > 40);
