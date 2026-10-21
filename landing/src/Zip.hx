import js.lib.DataView;
import js.lib.Uint8Array;
import js.html.TextEncoder;

typedef ZipFile = {name:String, data:Uint8Array, ?mode:Int};

// A zip of files, stored (no compression): what a native download is, so
// that the executable keeps its mode (Unix permissions in the entries'
// external attributes, which unzip and macOS's Archive Utility apply).
class Zip {
	static final CRC = {
		var t = new js.lib.Uint32Array(256);
		for (n in 0...256) {
			var c = n;
			for (_ in 0...8) c = c & 1 != 0 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
			t[n] = c;
		}
		t;
	}

	static function crc32(b:Uint8Array):Int {
		var c = 0xffffffff;
		for (i in 0...b.length) c = CRC[(c ^ b[i]) & 0xff] ^ (c >>> 8);
		return c ^ 0xffffffff;
	}

	public static function make(files:Array<ZipFile>):Uint8Array {
		var now = Date.now();
		var time = (now.getHours() << 11) | (now.getMinutes() << 5) | (now.getSeconds() >> 1);
		var date = ((now.getFullYear() - 1980) << 9) | ((now.getMonth() + 1) << 5) | now.getDate();
		var parts:Array<Uint8Array> = [], central:Array<Uint8Array> = [];
		var offset = 0;
		for (f in files) {
			var name = new TextEncoder().encode(f.name), crc = crc32(f.data), n = f.data.length;
			var local = new DataView(new js.lib.ArrayBuffer(30));
			local.setUint32(0, 0x04034b50, true);
			local.setUint16(4, 20, true);
			local.setUint16(6, 0x0800, true); // (UTF-8 names)
			local.setUint16(10, time, true);
			local.setUint16(12, date, true);
			local.setUint32(14, crc, true);
			local.setUint32(18, n, true);
			local.setUint32(22, n, true);
			local.setUint16(26, name.length, true);
			parts.push(new Uint8Array(local.buffer));
			parts.push(name);
			parts.push(f.data);
			var c = new DataView(new js.lib.ArrayBuffer(46));
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
			c.setUint32(38, (0x8000 | (f.mode == null ? 420 : f.mode)) << 16, true);
			c.setUint32(42, offset, true);
			central.push(new Uint8Array(c.buffer));
			central.push(name);
			offset += 30 + name.length + n;
		}
		var size = 0;
		for (b in central) size += b.length;
		var end = new DataView(new js.lib.ArrayBuffer(22));
		end.setUint32(0, 0x06054b50, true);
		end.setUint16(8, files.length, true);
		end.setUint16(10, files.length, true);
		end.setUint32(12, size, true);
		end.setUint32(16, offset, true);
		var all = parts.concat(central).concat([new Uint8Array(end.buffer)]);
		var total = 0;
		for (b in all) total += b.length;
		var out = new Uint8Array(total), at = 0;
		for (b in all) {
			out.set(b, at);
			at += b.length;
		}
		return out;
	}
}
