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
	const hxmc_text = {
		font_count: () => fonts.length,
		font_size: (i) => fonts[i].length,
		// (p: the module's memory, font_size(i) bytes)
		font_read: (i, p) => host.bytes(p, fonts[i].length).set(fonts[i]),
	};
	return { hxmc_text };
}
