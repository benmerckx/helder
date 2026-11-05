package helder.pack.android;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

// a protocol buffer's fields, in the order written (varints, strings,
// bytes, messages); proto3's defaults left out but for messages
class Pb {
	final b = new BytesBuffer();

	public function new() {}

	function varint(v:Int) {
		while (v >>> 7 != 0) {
			b.addByte((v & 0x7f) | 0x80);
			v >>>= 7;
		}
		b.addByte(v);
	}

	// an unsigned 32-bit field (uint32; an int32's that is not negative); always: written when 0 too (a oneof's)
	public function int(field:Int, v:Int, always = false):Pb {
		if (v == 0 && !always) return this;
		varint(field << 3);
		varint(v);
		return this;
	}

	public function bool(field:Int, v:Bool, always = false):Pb {
		if (!v && !always) return this;
		varint(field << 3);
		b.addByte(v ? 1 : 0);
		return this;
	}

	public function bytes(field:Int, d:Bytes):Pb {
		varint((field << 3) | 2);
		varint(d.length);
		b.add(d);
		return this;
	}

	public function str(field:Int, s:String):Pb
		return s == null || s == "" ? this : bytes(field, Bytes.ofString(s));

	public function msg(field:Int, m:Pb):Pb
		return bytes(field, m.toBytes());

	public function toBytes():Bytes
		return b.getBytes();

	// a message's fields read back: number, wire type, the varint or the bytes (the checks)
	public static function read(d:Bytes):Array<{field:Int, wire:Int, value:Int, data:Null<Bytes>}> {
		var out = [], at = 0;
		function v():Int {
			var r = 0, shift = 0;
			while (true) {
				var c = d.get(at++);
				if (shift < 32) r |= (c & 0x7f) << shift;
				shift += 7;
				if (c & 0x80 == 0) return r;
			}
		}
		while (at < d.length) {
			var k = v(), wire = k & 7;
			switch wire {
				case 0: out.push({field: k >>> 3, wire: 0, value: v(), data: null});
				case 2:
					var n = v();
					out.push({field: k >>> 3, wire: 2, value: n, data: d.sub(at, n)});
					at += n;
				case w: throw 'Pb: wire type $w';
			}
		}
		return out;
	}
}
