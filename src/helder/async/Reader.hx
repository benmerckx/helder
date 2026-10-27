package helder.async;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.async.Stream.Source;

// A Source read through a buffer: lines, exact counts, everything.
//
//   var r = new Reader(process.stdout);
//   var line; while ((line = r.readLine()) != null) trace(line);
class Reader implements Source {
	final source:Source;
	var buf:Bytes;
	var pos = 0;
	var end = 0;
	var eof = false;

	public function new(source:Source, size = 16384) {
		this.source = source;
		buf = Bytes.alloc(size);
	}

	// what the buffer has, else what the source has
	@:coroutine public function read(b:Bytes, at:Int, len:Int):Int {
		if (pos == end && !fill()) return 0;
		var n = len < end - pos ? len : end - pos;
		b.blit(at, buf, pos, n);
		pos += n;
		return n;
	}

	// the next line without its "\n" (or "\r\n"); null at the end (a last
	// line without "\n" is a line)
	@:coroutine public function readLine():Null<String> {
		var out:Null<BytesBuffer> = null;
		while (true) {
			if (pos == end && !fill()) {
				if (out == null) return null;
				return text(out.getBytes(), 0);
			}
			var i = pos;
			while (i < end && buf.get(i) != 10)
				i++;
			if (i < end) {
				var line = if (out == null) buf.getString(pos, trim(pos, i) - pos) else {
					out.addBytes(buf, pos, i - pos);
					text(out.getBytes(), 0);
				}
				pos = i + 1;
				return line;
			}
			out ??= new BytesBuffer();
			out.addBytes(buf, pos, end - pos);
			pos = end;
		}
	}

	// exactly n bytes (an error if the source ends before)
	@:coroutine public function readBytes(n:Int):Bytes {
		var b = Bytes.alloc(n);
		var got = 0;
		while (got < n) {
			var k = read(b, got, n - got);
			if (k == 0) throw new haxe.io.Eof();
			got += k;
		}
		return b;
	}

	// everything until the end
	@:coroutine public function readAll():Bytes {
		var out = new BytesBuffer();
		while (true) {
			if (pos == end && !fill()) return out.getBytes();
			out.addBytes(buf, pos, end - pos);
			pos = end;
		}
	}

	@:coroutine function fill():Bool {
		if (eof) return false;
		var n = source.read(buf, 0, buf.length);
		pos = 0;
		end = n;
		if (n == 0) eof = true;
		return n > 0;
	}

	inline function trim(from:Int, i:Int):Int
		return i > from && buf.get(i - 1) == 13 ? i - 1 : i;

	static function text(b:Bytes, _):String {
		var n = b.length;
		if (n > 0 && b.get(n - 1) == 13) n--;
		return b.getString(0, n);
	}
}
