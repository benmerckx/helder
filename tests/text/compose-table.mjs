// Writes src/helder/text/Compose.hx: Unicode's canonical
// compositions of a character and a mark (the pairs NFC composes, Hangul's
// syllables and pairs beyond the BMP left out), from node's own Unicode
// data (ICU). Run it after a Unicode update:
//   node tests/text/compose-table.mjs
import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const pairs = [];
for (let c = 0; c < 0x10000; c++) {
	if (c >= 0xd800 && c < 0xe000) continue;
	if (c >= 0xac00 && c <= 0xd7a3) continue;
	const s = String.fromCodePoint(c);
	if (s.normalize('NFC') !== s) continue;
	const d = [...s.normalize('NFD')];
	if (d.length < 2) continue;
	const mark = d[d.length - 1];
	const base = [...d.slice(0, -1).join('').normalize('NFC')];
	if (base.length !== 1 || (base[0] + mark).normalize('NFC') !== s) continue;
	pairs.push([base[0].codePointAt(0), mark.codePointAt(0), c]);
}
const hex = (n) => n.toString(16).toUpperCase().padStart(4, '0');
const lines = [];
for (let i = 0; i < pairs.length; i += 8) lines.push('\t\t+ "' + pairs.slice(i, i + 8).map((p) => p.map(hex).join('')).join('') + '"');
const out = `package helder.text;

// Unicode's canonical compositions of a character and the mark after it
// (Unicode ${process.versions.unicode}; written by tests/text/compose-table.mjs):
// what HarfBuzz composes when the font has the composed character
class Compose {
	static var table:Null<Map<Int, Int>> = null;

	// the composition of a and mark (0: none)
	public static function pair(a:Int, mark:Int):Int {
		if (a > 0xFFFF || mark > 0xFFFF) return 0;
		if (table == null) {
			table = new Map();
			var i = 0;
			while (i < DATA.length) {
				table.set(Std.parseInt("0x" + DATA.substr(i, 4)) << 16 | Std.parseInt("0x" + DATA.substr(i + 4, 4)), Std.parseInt("0x" + DATA.substr(i + 8, 4)));
				i += 12;
			}
		}
		var c = table.get(a << 16 | mark);
		return c == null ? 0 : c;
	}

	// (each pair: the character, the mark, the composition; four hex digits each)
	static final DATA = ""
${lines.join('\n')};
}
`;
await writeFile(path.join(here, '../../src/helder/text/Compose.hx'), out);
console.log(`compose-table.mjs: ${pairs.length} pairs`);
