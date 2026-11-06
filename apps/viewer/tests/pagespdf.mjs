// tests/fixtures/pdf/pages.pdf: three pages drawn without fonts, each a
// colour and a size of its own (page 2 landscape) and as many white bars
// as its number, for the viewer's page navigation:
// node tests/pagespdf.mjs tests/fixtures/pdf/pages.pdf
import { writeFileSync } from "node:fs";

const pages = [
	{ w: 300, h: 400, fill: "0.8 0.2 0.2" },
	{ w: 400, h: 300, fill: "0.2 0.6 0.2" },
	{ w: 300, h: 400, fill: "0.2 0.3 0.8" },
];
const objs = [];
const add = (s) => (objs.push(s), objs.length);
const catalog = add(null), tree = add(null);
const kids = [];
pages.forEach((p, i) => {
	let ops = `${p.fill} rg 20 20 ${p.w - 40} ${p.h - 40} re f 1 1 1 rg`;
	for (let k = 0; k <= i; k++) ops += ` ${40 + k * 40} 60 20 ${p.h - 120} re f`;
	const content = add(`<< /Length ${ops.length} >>\nstream\n${ops}\nendstream`);
	kids.push(add(`<< /Type /Page /Parent ${tree} 0 R /MediaBox [0 0 ${p.w} ${p.h}] /Contents ${content} 0 R /Resources << >> >>`));
});
objs[catalog - 1] = `<< /Type /Catalog /Pages ${tree} 0 R >>`;
objs[tree - 1] = `<< /Type /Pages /Kids [${kids.map((k) => `${k} 0 R`).join(" ")}] /Count ${kids.length} >>`;
let out = "%PDF-1.4\n";
const offsets = [];
objs.forEach((o, i) => {
	offsets.push(out.length);
	out += `${i + 1} 0 obj\n${o}\nendobj\n`;
});
const xref = out.length;
out += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n`;
for (const o of offsets) out += `${String(o).padStart(10, "0")} 00000 n \n`;
out += `trailer\n<< /Size ${objs.length + 1} /Root ${catalog} 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
writeFileSync(process.argv[2], out, "latin1");
