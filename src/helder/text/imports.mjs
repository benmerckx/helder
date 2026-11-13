// The JavaScript side of helder.text in the browser, loaded by
// src/helder/os/browser.mjs: the imports of the module "hxmc_text"
// (src/helder/text/WebFonts.hx). A browser gives a WebAssembly module no font
// files: run's option fonts lists the ones it may use (URLs, or
// ArrayBuffers), fetched before the module starts; SystemFonts adds them
// as its fonts.
export default async function (host) {
	const fonts = [];
	for (const f of host.options.fonts ?? []) {
		const b = f instanceof ArrayBuffer ? f : await (await fetch(f)).arrayBuffer();
		fonts.push(new Uint8Array(b));
	}
	const faces = new Map();
	const hxmc_text = {
		font_count: () => fonts.length,
		font_size: (i) => fonts[i].length,
		// (p: the module's memory, font_size(i) bytes)
		font_read: (i, p) => host.bytes(p, fonts[i].length).set(fonts[i]),
		// (a font the program added, or replaced: the page's FontFace too, so
		// its text fields are set in it by the family's name)
		font_face: (family, weight, italic, p, n) => {
			if (!globalThis.document?.fonts) return;
			const name = host.string(family), style = italic ? 'italic' : 'normal', key = `${name}|${weight}|${style}`;
			const old = faces.get(key);
			const face = new FontFace(name, host.bytes(p, n).slice(), { weight: String(weight), style });
			faces.set(key, face);
			if (face.status === 'error') return;
			document.fonts.add(face);
			if (old) document.fonts.delete(old);
		},
	};
	return { hxmc_text };
}
