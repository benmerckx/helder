// A zip of files, stored (no compression): what a native download is, so
// that the executable keeps its mode (Unix permissions in the entries'
// external attributes, which unzip and macOS's Archive Utility apply).
//
//   zip([{name: 'Cube', data: bytes, mode: 0o755}, ...]) -> Uint8Array

const CRC = (() => {
	const t = new Uint32Array(256);
	for (let n = 0; n < 256; n++) {
		let c = n;
		for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
		t[n] = c >>> 0;
	}
	return t;
})();

function crc32(b) {
	let c = 0xffffffff;
	for (let i = 0; i < b.length; i++) c = CRC[(c ^ b[i]) & 0xff] ^ (c >>> 8);
	return (c ^ 0xffffffff) >>> 0;
}

export function zip(files) {
	const enc = new TextEncoder();
	const now = new Date();
	const time = (now.getHours() << 11) | (now.getMinutes() << 5) | (now.getSeconds() >> 1);
	const date = ((now.getFullYear() - 1980) << 9) | ((now.getMonth() + 1) << 5) | now.getDate();
	const parts = [], central = [];
	let offset = 0;
	for (const f of files) {
		const name = enc.encode(f.name), crc = crc32(f.data), n = f.data.length;
		const local = new DataView(new ArrayBuffer(30));
		local.setUint32(0, 0x04034b50, true);
		local.setUint16(4, 20, true);
		local.setUint16(6, 0x0800, true); // (UTF-8 names)
		local.setUint16(10, time, true);
		local.setUint16(12, date, true);
		local.setUint32(14, crc, true);
		local.setUint32(18, n, true);
		local.setUint32(22, n, true);
		local.setUint16(26, name.length, true);
		parts.push(new Uint8Array(local.buffer), name, f.data);
		const c = new DataView(new ArrayBuffer(46));
		c.setUint32(0, 0x02014b50, true);
		c.setUint16(4, (3 << 8) | 20, true); // (made by Unix: the mode is read)
		c.setUint16(6, 20, true);
		c.setUint16(8, 0x0800, true);
		c.setUint16(12, time, true);
		c.setUint16(14, date, true);
		c.setUint32(16, crc, true);
		c.setUint32(20, n, true);
		c.setUint32(24, n, true);
		c.setUint16(28, name.length, true);
		c.setUint32(38, ((0o100000 | (f.mode ?? 0o644)) << 16) >>> 0, true);
		c.setUint32(42, offset, true);
		central.push(new Uint8Array(c.buffer), name);
		offset += 30 + name.length + n;
	}
	const size = central.reduce((s, b) => s + b.length, 0);
	const end = new DataView(new ArrayBuffer(22));
	end.setUint32(0, 0x06054b50, true);
	end.setUint16(8, files.length, true);
	end.setUint16(10, files.length, true);
	end.setUint32(12, size, true);
	end.setUint32(16, offset, true);
	const all = [...parts, ...central, new Uint8Array(end.buffer)];
	const out = new Uint8Array(all.reduce((s, b) => s + b.length, 0));
	let at = 0;
	for (const b of all) {
		out.set(b, at);
		at += b.length;
	}
	return out;
}
