package helder.os.audio;

import haxe.ds.Vector;
import haxe.io.Bytes;

// An Ogg Vorbis file decoded a packet at a time (the Vorbis I
// specification; one logical stream, floor 1, residues 0, 1 and 2, any
// channels): open parses the three headers and allocates everything the
// decoding needs, then next() decodes the following packet into `out` (a
// buffer a channel, -1 to 1) without allocating, so it can run on the audio
// thread (Sfx's music: streamed from the compressed bytes, never decoded
// whole). rewind() goes back to the first audio packet (a loop). Floor 0,
// which no encoder has written since 2002, is refused, as is anything else
// it cannot read: a String naming why.
//
//   var v = Vorbis.open(bytes);
//   var n;
//   while ((n = v.next()) >= 0) use(v.out, n);   // n frames a channel (0: none yet)
//
// Vorbis.decode(bytes) decodes it whole (a Wav: Sfx's effects).
@:allow(helder.os.audio)
class Vorbis {
	public final rate:Int;
	public final channels:Int;
	// the frames of the whole stream, from its last page (-1: not known)
	public final length:Int;
	// the frames next() decoded, a buffer a channel
	public final out:Vector<Vector<Float>>;

	final data:Bytes;
	final serial:Int;
	// the page being read: where its segment table is, how many, the next
	// segment, where that segment's bytes are, where the next page starts
	var segTable = 0;
	var segCount = 0;
	var seg = 0;
	var body = 0;
	var nextPage = 0;
	var pageFlags = 0;
	var pageGranule = 0;
	// where the first audio packet's page starts, and its first segment in it
	var audioPage = 0;
	var audioSeg = 0;
	// the packet, copied from its segments
	final packet:Bytes;
	var packetLen = 0;
	var bytePos = 0;
	var bitPos = 0;
	var eop = false;
	// the packet just read was the stream's last: the frames it may give
	var lastPacket = false;
	var lastGranule = 0;
	var emitted = 0;

	final blocksize0:Int;
	final blocksize1:Int;
	final books:Array<Codebook> = [];
	final floors:Array<Floor1> = [];
	final residues:Array<Residue> = [];
	final mappings:Array<Mapping> = [];
	final modeBlock:Array<Bool> = [];
	final modeMapping:Array<Int> = [];
	var modeBits = 0;

	// the decoding's buffers
	final spectrum:Vector<Vector<Float>>; // a channel's residue, then its floor applied, then its IMDCT (blocksize1)
	final prev:Vector<Vector<Float>>; // the previous block's second half, windowed
	var prevN = 0;
	final noResidue:Vector<Bool>;
	final floorUsed:Vector<Bool>;
	final floorY:Vector<Vector<Int>>; // a channel's floor values (the largest floor's)
	final finalY:Vector<Int>;
	final step2:Vector<Bool>;
	final curve:Vector<Int>;
	final classes:Vector<Int>; // residue classifications: channels * partitions + slack
	final interleaved:Vector<Float>; // residue 2's vector (blocksize1 / 2 * channels)
	final imdct0:Imdct;
	final imdct1:Imdct;
	final window0:Vector<Float>; // the slopes: blocksize0 / 2 and blocksize1 / 2 long
	final window1:Vector<Float>;
	final vector:Vector<Float>; // a VQ codebook's entry

	static var dB:Null<Vector<Float>>;

	public static function open(bytes:Bytes):Vorbis
		return new Vorbis(bytes);

	// the whole stream decoded: interleaved samples (Wav's shape)
	public static function decode(bytes:Bytes):Wav {
		var v = new Vorbis(bytes);
		var samples = new Array<Float>();
		var frames = 0, n;
		while ((n = v.next()) >= 0)
			for (i in 0...n) {
				for (c in 0...v.channels)
					samples.push(v.out[c][i]);
				frames++;
			}
		return Wav.of(v.rate, v.channels, frames, samples);
	}

	function new(bytes:Bytes) {
		data = bytes;
		if (bytes.length < 28 || bytes.getString(0, 4) != "OggS") throw "helder.os.audio.Vorbis: not an Ogg file";
		serial = bytes.getInt32(14);
		// (the largest packet and the last granule position, from the pages' headers)
		var maxPacket = 0, run = 0, p = 0, last = -1;
		while (p + 27 <= bytes.length && bytes.getString(p, 4) == "OggS") {
			var n = bytes.get(p + 26), size = 0;
			if (p + 27 + n > bytes.length) break;
			var mine = bytes.getInt32(p + 14) == serial;
			for (i in 0...n) {
				var s = bytes.get(p + 27 + i);
				size += s;
				if (mine) {
					run += s;
					if (s < 255) {
						if (run > maxPacket) maxPacket = run;
						run = 0;
					}
				}
			}
			if (mine && bytes.getInt32(p + 6) != -1) last = bytes.getInt32(p + 6);
			p += 27 + n + size;
		}
		if (run > maxPacket) maxPacket = run;
		length = last;
		packet = Bytes.alloc(maxPacket + 8);
		nextPage = 0;
		// identification
		if (!readPacket() || bits(8) != 1 || !vorbisTag()) throw "helder.os.audio.Vorbis: no identification header";
		if (bits(32) != 0) throw "helder.os.audio.Vorbis: not Vorbis I";
		channels = bits(8);
		rate = bits(32);
		bits(32);
		bits(32);
		bits(32);
		blocksize0 = 1 << bits(4);
		blocksize1 = 1 << bits(4);
		if (channels <= 0 || rate <= 0 || blocksize0 < 64 || blocksize1 < blocksize0 || blocksize1 > 8192)
			throw "helder.os.audio.Vorbis: a bad identification header";
		// comments
		if (!readPacket() || bits(8) != 3 || !vorbisTag()) throw "helder.os.audio.Vorbis: no comment header";
		// setup
		if (!readPacket() || bits(8) != 5 || !vorbisTag()) throw "helder.os.audio.Vorbis: no setup header";
		setup();
		audioPage = pageStart;
		audioSeg = seg;
		if (seg >= segCount) {
			audioPage = nextPage;
			audioSeg = 0;
		}

		var half = blocksize1 >> 1;
		spectrum = new Vector(channels);
		prev = new Vector(channels);
		out = new Vector(channels);
		floorY = new Vector(channels);
		var maxValues = 2;
		for (f in floors)
			if (f.values > maxValues) maxValues = f.values;
		for (c in 0...channels) {
			spectrum[c] = zeros(blocksize1);
			prev[c] = zeros(half);
			out[c] = zeros(half);
			floorY[c] = new Vector(maxValues);
		}
		noResidue = new Vector(channels);
		floorUsed = new Vector(channels);
		finalY = new Vector(maxValues);
		step2 = new Vector(maxValues);
		curve = new Vector(half);
		var maxParts = 0;
		for (r in residues) {
			var parts = Std.int((r.end - r.begin) / r.partitionSize) + books[r.classbook].dimensions + 1;
			if (parts > maxParts) maxParts = parts;
		}
		classes = new Vector((maxParts + 1) * channels);
		interleaved = zeros(half * channels);
		imdct0 = new Imdct(blocksize0);
		imdct1 = new Imdct(blocksize1);
		window0 = slope(blocksize0 >> 1);
		window1 = slope(blocksize1 >> 1);
		var maxDim = 1;
		for (b in books)
			if (b.dimensions > maxDim) maxDim = b.dimensions;
		vector = zeros(maxDim);
		if (dB == null) {
			var t = new Vector<Float>(256);
			// (the specification's floor1_inverse_dB_table: 140 dB over 256 steps)
			for (i in 0...256)
				t[i] = Math.pow(10, (i - 255) * 140 / 256 / 20);
			dB = t;
		}
	}

	static function zeros(n:Int):Vector<Float> {
		var v = new Vector<Float>(n);
		for (i in 0...n)
			v[i] = 0;
		return v;
	}

	static function slope(n:Int):Vector<Float> {
		var w = new Vector<Float>(n);
		for (i in 0...n) {
			var s = Math.sin((i + 0.5) / n * Math.PI / 2);
			w[i] = Math.sin(Math.PI / 2 * s * s);
		}
		return w;
	}

	function vorbisTag():Bool {
		var tag = "vorbis";
		for (i in 0...6)
			if (bits(8) != tag.charCodeAt(i)) return false;
		return true;
	}

	// ---- Ogg

	var pageStart = 0;

	// the next page of the stream (false: none)
	function page():Bool {
		var p = nextPage;
		while (true) {
			if (p + 27 > data.length) return false;
			if (data.get(p) != "O".code || data.get(p + 1) != "g".code || data.get(p + 2) != "g".code || data.get(p + 3) != "S".code) {
				p++;
				continue;
			}
			var n = data.get(p + 26), size = 0;
			if (p + 27 + n > data.length) return false;
			for (i in 0...n)
				size += data.get(p + 27 + i);
			if (data.getInt32(p + 14) != serial) {
				p += 27 + n + size;
				continue;
			}
			pageStart = p;
			pageFlags = data.get(p + 5);
			pageGranule = data.getInt32(p + 6);
			segTable = p + 27;
			segCount = n;
			seg = 0;
			body = p + 27 + n;
			nextPage = body + size;
			return true;
		}
	}

	// the next packet into `packet` (false: the stream's end)
	function readPacket():Bool {
		packetLen = 0;
		bytePos = 0;
		bitPos = 0;
		eop = false;
		while (true) {
			if (seg >= segCount) {
				if (!page()) return false;
				// (a continued packet's rest, without its start: skipped)
				if (pageFlags & 1 != 0 && packetLen == 0) {
					while (seg < segCount) {
						var s = data.get(segTable + seg);
						body += s;
						seg++;
						if (s < 255) break;
					}
					continue;
				}
			}
			var s = data.get(segTable + seg);
			seg++;
			var n = s;
			if (body + n > data.length) n = data.length - body;
			if (packetLen + n > packet.length) n = packet.length - packetLen;
			if (n > 0) packet.blit(packetLen, data, body, n);
			packetLen += n;
			body += s;
			if (s < 255) {
				// (the page's last packet: its granule position is where it ends)
				lastPacket = pageFlags & 4 != 0 && seg >= segCount;
				lastGranule = pageGranule;
				return true;
			}
		}
	}

	// ---- bits, least significant first

	inline function bit():Int {
		if (bytePos >= packetLen) {
			eop = true;
			return 0;
		}
		var b = (packet.get(bytePos) >> bitPos) & 1;
		if (++bitPos == 8) {
			bitPos = 0;
			bytePos++;
		}
		return b;
	}

	function bits(n:Int):Int {
		var r = 0, k = 0;
		while (k < n) {
			if (bytePos >= packetLen) {
				eop = true;
				return 0;
			}
			var take = 8 - bitPos;
			if (take > n - k) take = n - k;
			r |= ((packet.get(bytePos) >> bitPos) & ((1 << take) - 1)) << k;
			k += take;
			bitPos += take;
			if (bitPos == 8) {
				bitPos = 0;
				bytePos++;
			}
		}
		return r;
	}

	static function ilog(x:Int):Int {
		var n = 0;
		while (x > 0) {
			n++;
			x >>>= 1;
		}
		return n;
	}

	// ---- the setup header

	function fail(s:String):Dynamic
		throw "helder.os.audio.Vorbis: " + s;

	function setup() {
		for (_ in 0...bits(8) + 1)
			books.push(codebook());
		for (_ in 0...bits(6) + 1)
			if (bits(16) != 0) fail("a time domain transform");
		for (_ in 0...bits(6) + 1) {
			var type = bits(16);
			if (type != 1) fail('floor $type (floor 1 only)');
			floors.push(floor1());
		}
		for (_ in 0...bits(6) + 1) {
			var r = new Residue();
			r.type = bits(16);
			if (r.type > 2) fail("residue " + r.type);
			r.begin = bits(24);
			r.end = bits(24);
			r.partitionSize = bits(24) + 1;
			r.classifications = bits(6) + 1;
			r.classbook = bits(8);
			if (r.classbook >= books.length) fail("a residue's class book");
			var cascade = [];
			for (_ in 0...r.classifications) {
				var low = bits(3);
				cascade.push(bit() == 1 ? bits(5) * 8 + low : low);
			}
			r.books = new Vector(r.classifications * 8);
			for (c in 0...r.classifications)
				for (j in 0...8) {
					var b = cascade[c] & (1 << j) != 0 ? bits(8) : -1;
					if (b >= books.length) fail("a residue's book");
					r.books[c * 8 + j] = b;
				}
			residues.push(r);
		}
		for (_ in 0...bits(6) + 1) {
			if (bits(16) != 0) fail("a mapping type");
			var m = new Mapping();
			m.submaps = bit() == 1 ? bits(4) + 1 : 1;
			var steps = bit() == 1 ? bits(8) + 1 : 0;
			m.magnitude = new Vector(steps);
			m.angle = new Vector(steps);
			var b = ilog(channels - 1);
			for (i in 0...steps) {
				m.magnitude[i] = bits(b);
				m.angle[i] = bits(b);
				if (m.magnitude[i] >= channels || m.angle[i] >= channels || m.magnitude[i] == m.angle[i]) fail("a coupling step");
			}
			if (bits(2) != 0) fail("a mapping's reserved bits");
			m.mux = new Vector(channels);
			for (c in 0...channels)
				m.mux[c] = m.submaps > 1 ? bits(4) : 0;
			m.floor = new Vector(m.submaps);
			m.residue = new Vector(m.submaps);
			for (s in 0...m.submaps) {
				bits(8);
				m.floor[s] = bits(8);
				m.residue[s] = bits(8);
				if (m.floor[s] >= floors.length || m.residue[s] >= residues.length) fail("a submap");
			}
			mappings.push(m);
		}
		var modes = bits(6) + 1;
		for (_ in 0...modes) {
			modeBlock.push(bit() == 1);
			bits(16);
			bits(16);
			var m = bits(8);
			if (m >= mappings.length) fail("a mode's mapping");
			modeMapping.push(m);
		}
		modeBits = ilog(modes - 1);
		if (bit() != 1 || eop) fail("a setup header cut short");
	}

	static function float32(x:Int):Float {
		var mantissa = x & 0x1fffff, exponent = (x >>> 21) & 0x3ff;
		var v = mantissa * Math.pow(2, exponent - 788);
		return x < 0 ? -v : v;
	}

	function codebook():Codebook {
		if (bits(24) != 0x564342) fail("a codebook's sync pattern");
		var b = new Codebook();
		b.dimensions = bits(16);
		b.entries = bits(24);
		var lengths = new Vector<Int>(b.entries);
		if (bit() == 0) {
			var sparse = bit() == 1;
			for (i in 0...b.entries)
				lengths[i] = !sparse || bit() == 1 ? bits(5) + 1 : 0;
		} else {
			var current = 0, len = bits(5) + 1;
			while (current < b.entries) {
				var n = bits(ilog(b.entries - current));
				if (current + n > b.entries) fail("a codebook's lengths");
				for (i in current...current + n)
					lengths[i] = len;
				current += n;
				len++;
			}
		}
		var lookup = bits(4);
		if (lookup == 1 || lookup == 2) {
			var min = float32(bits(32)), delta = float32(bits(32));
			var valueBits = bits(4) + 1, sequence = bit() == 1;
			var count = lookup == 1 ? lookup1(b.entries, b.dimensions) : b.entries * b.dimensions;
			var mult = new Vector<Int>(count);
			for (i in 0...count)
				mult[i] = bits(valueBits);
			var vq = new Vector<Float>(b.entries * b.dimensions);
			for (e in 0...b.entries) {
				var last = 0.0, divisor = 1;
				for (d in 0...b.dimensions) {
					var off = lookup == 1 ? Std.int(e / divisor) % count : e * b.dimensions + d;
					var v = mult[off] * delta + min + last;
					if (sequence) last = v;
					vq[e * b.dimensions + d] = v;
					if (lookup == 1) divisor *= count;
				}
			}
			b.vq = vq;
		} else if (lookup != 0) fail("a codebook's lookup type " + lookup);
		if (eop) fail("a codebook cut short");
		b.build(lengths, this);
		return b;
	}

	// the largest r with r^dimensions <= entries
	static function lookup1(entries:Int, dimensions:Int):Int {
		var r = Std.int(Math.pow(entries, 1 / dimensions));
		while (Math.pow(r + 1, dimensions) <= entries)
			r++;
		while (r > 0 && Math.pow(r, dimensions) > entries)
			r--;
		return r;
	}

	function floor1():Floor1 {
		var f = new Floor1();
		var partitions = bits(5);
		f.partitionClass = new Vector(partitions);
		var maxClass = -1;
		for (i in 0...partitions) {
			f.partitionClass[i] = bits(4);
			if (f.partitionClass[i] > maxClass) maxClass = f.partitionClass[i];
		}
		f.classDimensions = new Vector(maxClass + 1);
		f.classSubclasses = new Vector(maxClass + 1);
		f.classMasterbook = new Vector(maxClass + 1);
		f.subclassBooks = new Vector((maxClass + 1) * 8);
		for (c in 0...maxClass + 1) {
			f.classDimensions[c] = bits(3) + 1;
			f.classSubclasses[c] = bits(2);
			f.classMasterbook[c] = f.classSubclasses[c] > 0 ? bits(8) : -1;
			if (f.classMasterbook[c] >= books.length) fail("a floor's master book");
			for (j in 0...1 << f.classSubclasses[c]) {
				f.subclassBooks[c * 8 + j] = bits(8) - 1;
				if (f.subclassBooks[c * 8 + j] >= books.length) fail("a floor's book");
			}
		}
		f.multiplier = bits(2) + 1;
		var rangeBits = bits(4);
		var xs = [0, 1 << rangeBits];
		for (i in 0...partitions)
			for (_ in 0...f.classDimensions[f.partitionClass[i]])
				xs.push(bits(rangeBits));
		f.values = xs.length;
		if (f.values > 65) fail("a floor of " + f.values + " values");
		f.x = new Vector(f.values);
		for (i in 0...f.values)
			f.x[i] = xs[i];
		// (the values' order by x, and each one's neighbours before it)
		var order = [for (i in 0...f.values) i];
		order.sort((a, b) -> xs[a] - xs[b]);
		f.sorted = new Vector(f.values);
		for (i in 0...f.values)
			f.sorted[i] = order[i];
		f.low = new Vector(f.values);
		f.high = new Vector(f.values);
		for (i in 2...f.values) {
			var lo = 0, hi = 1, lx = -1, hx = 1 << 30;
			for (j in 0...i) {
				if (xs[j] < xs[i] && xs[j] > lx) {
					lx = xs[j];
					lo = j;
				}
				if (xs[j] > xs[i] && xs[j] < hx) {
					hx = xs[j];
					hi = j;
				}
			}
			f.low[i] = lo;
			f.high[i] = hi;
		}
		return f;
	}

	// ---- audio packets

	// the stream from its first audio packet again
	public function rewind() {
		nextPage = audioPage;
		page();
		seg = audioSeg;
		// (the segments before it, skipped)
		for (i in 0...audioSeg)
			body += data.get(segTable + i);
		prevN = 0;
		emitted = 0;
	}

	// the next packet decoded: the frames now in `out` (0: none, the first
	// packet or one it could not read), -1 at the stream's end
	public function next():Int {
		if (!readPacket()) return -1;
		var n = decodePacket();
		if (lastPacket && lastGranule >= 0 && emitted + n > lastGranule) n = lastGranule - emitted < 0 ? 0 : lastGranule - emitted;
		emitted += n;
		return n;
	}

	function decodePacket():Int {
		if (bit() != 0) return 0;
		var mode = bits(modeBits);
		if (eop || mode >= modeMapping.length) return 0;
		var long = modeBlock[mode];
		var n = long ? blocksize1 : blocksize0, half = n >> 1;
		var prevLong = false, nextLong = false;
		if (long) {
			prevLong = bit() == 1;
			nextLong = bit() == 1;
		}
		var m = mappings[modeMapping[mode]];
		var dBt:Vector<Float> = dB;
		// floors
		for (c in 0...channels) {
			var f = floors[m.floor[m.mux[c]]];
			floorUsed[c] = decodeFloor(f, floorY[c]);
			noResidue[c] = !floorUsed[c];
			var s = spectrum[c];
			for (i in 0...half)
				s[i] = 0;
		}
		for (i in 0...m.magnitude.length) {
			var a = m.magnitude[i], b = m.angle[i];
			if (!noResidue[a] || !noResidue[b]) {
				noResidue[a] = false;
				noResidue[b] = false;
			}
		}
		// residues, a submap at a time
		for (s in 0...m.submaps) {
			decodeResidue(residues[m.residue[s]], m, s, half);
		}
		// inverse coupling
		var i = m.magnitude.length;
		while (--i >= 0) {
			var mv = spectrum[m.magnitude[i]], av = spectrum[m.angle[i]];
			for (j in 0...half) {
				var mg = mv[j], an = av[j];
				if (mg > 0) {
					if (an > 0) {
						av[j] = mg - an;
					} else {
						av[j] = mg;
						mv[j] = mg + an;
					}
				} else {
					if (an > 0) {
						av[j] = mg + an;
					} else {
						av[j] = mg;
						mv[j] = mg - an;
					}
				}
			}
		}
		// the floor curves times the residues, the IMDCT, the window
		var imdct = long ? imdct1 : imdct0;
		var ls, ln, rs, rn;
		if (long && !prevLong) {
			ls = (n >> 2) - (blocksize0 >> 2);
			ln = blocksize0 >> 1;
		} else {
			ls = 0;
			ln = half;
		}
		if (long && !nextLong) {
			rs = (n * 3 >> 2) - (blocksize0 >> 2);
			rn = blocksize0 >> 1;
		} else {
			rs = half;
			rn = half;
		}
		var lw = ln == (blocksize0 >> 1) ? window0 : window1, rw = rn == (blocksize0 >> 1) ? window0 : window1;
		var pn = prevN, frames = pn == 0 ? 0 : (pn >> 2) + (n >> 2);
		for (c in 0...channels) {
			var s = spectrum[c];
			if (floorUsed[c]) {
				renderFloor(floors[m.floor[m.mux[c]]], floorY[c], half);
				for (j in 0...half)
					s[j] *= dBt[curve[j]];
			} else
				for (j in 0...half)
					s[j] = 0;
			imdct.run(s);
			for (j in 0...ls)
				s[j] = 0;
			for (j in 0...ln)
				s[ls + j] *= lw[j];
			for (j in 0...rn)
				s[rs + j] *= rw[rn - 1 - j];
			for (j in rs + rn...n)
				s[j] = 0;
			// (the previous block's second half and this one's first, overlapped)
			if (pn > 0) {
				var o = out[c], p = prev[c], ph = pn >> 1, shift = (n >> 2) - (pn >> 2);
				for (t in 0...frames) {
					var v = t < ph ? p[t] : 0.0, k = t + shift;
					if (k >= 0 && k < n) v += s[k];
					o[t] = v;
				}
			}
			var p = prev[c];
			for (j in 0...half)
				p[j] = s[half + j];
		}
		prevN = n;
		return frames;
	}

	// floor 1's values (false: the channel is unused this packet)
	function decodeFloor(f:Floor1, y:Vector<Int>):Bool {
		if (bit() == 0 || eop) return false;
		var range = f.multiplier == 1 ? 256 : f.multiplier == 2 ? 128 : f.multiplier == 3 ? 86 : 64;
		var rb = ilog(range - 1);
		y[0] = bits(rb);
		y[1] = bits(rb);
		var off = 2;
		for (i in 0...f.partitionClass.length) {
			var cls = f.partitionClass[i], cdim = f.classDimensions[cls], cbits = f.classSubclasses[cls];
			var csub = (1 << cbits) - 1, cval = 0;
			if (cbits > 0) {
				cval = books[f.classMasterbook[cls]].decode(this);
				if (cval < 0) return false;
			}
			for (j in 0...cdim) {
				var book = f.subclassBooks[cls * 8 + (cval & csub)];
				cval >>>= cbits;
				if (book >= 0) {
					var v = books[book].decode(this);
					if (v < 0) return false;
					y[off + j] = v;
				} else
					y[off + j] = 0;
			}
			off += cdim;
		}
		return !eop;
	}

	static inline function renderPoint(x0:Int, y0:Int, x1:Int, y1:Int, x:Int):Int {
		var dy = y1 - y0, adx = x1 - x0, ady = dy < 0 ? -dy : dy;
		var off = Std.int(ady * (x - x0) / adx);
		return dy < 0 ? y0 - off : y0 + off;
	}

	// floor 1's curve into `curve` (n values: indexes of the dB table)
	function renderFloor(f:Floor1, y:Vector<Int>, n:Int) {
		var range = f.multiplier == 1 ? 256 : f.multiplier == 2 ? 128 : f.multiplier == 3 ? 86 : 64;
		step2[0] = true;
		step2[1] = true;
		finalY[0] = y[0];
		finalY[1] = y[1];
		for (i in 2...f.values) {
			var lo = f.low[i], hi = f.high[i];
			var predicted = renderPoint(f.x[lo], finalY[lo], f.x[hi], finalY[hi], f.x[i]);
			var v = y[i], highroom = range - predicted, lowroom = predicted;
			var room = (highroom < lowroom ? highroom : lowroom) * 2;
			if (v != 0) {
				step2[lo] = true;
				step2[hi] = true;
				step2[i] = true;
				if (v >= room) finalY[i] = highroom > lowroom ? v - lowroom + predicted : predicted - v + highroom - 1;
				else finalY[i] = v & 1 == 1 ? predicted - ((v + 1) >> 1) : predicted + (v >> 1);
			} else {
				step2[i] = false;
				finalY[i] = predicted;
			}
		}
		var hx = 0, hy = 0, lx = 0, ly = finalY[f.sorted[0]] * f.multiplier;
		for (k in 1...f.values) {
			var i = f.sorted[k];
			if (step2[i]) {
				hy = finalY[i] * f.multiplier;
				hx = f.x[i];
				line(lx, ly, hx, hy, n);
				lx = hx;
				ly = hy;
			}
		}
		if (hx < n) line(hx, hy, n, hy, n);
	}

	inline function clampY(y:Int):Int
		return y < 0 ? 0 : y > 255 ? 255 : y;

	function line(x0:Int, y0:Int, x1:Int, y1:Int, n:Int) {
		var dy = y1 - y0, adx = x1 - x0;
		if (adx <= 0) return;
		var ady = dy < 0 ? -dy : dy;
		var base = Std.int(dy / adx), sy = dy < 0 ? base - 1 : base + 1;
		ady -= (base < 0 ? -base : base) * adx;
		var y = y0, err = 0;
		if (x0 < n) curve[x0] = clampY(y);
		var x = x0 + 1;
		var end = x1 < n ? x1 : n;
		while (x < end) {
			err += ady;
			if (err >= adx) {
				err -= adx;
				y += sy;
			} else
				y += base;
			curve[x] = clampY(y);
			x++;
		}
	}

	function decodeResidue(r:Residue, m:Mapping, submap:Int, half:Int) {
		var classbook = books[r.classbook];
		var cpc = classbook.dimensions;
		// (the channels of this submap, residue 2: as one of their lengths together)
		var chs = 0, any = false;
		for (c in 0...channels)
			if (m.mux[c] == submap) {
				chs++;
				if (!noResidue[c]) any = true;
			}
		if (!any) return;
		var size = r.type == 2 ? half * chs : half;
		var begin = r.begin < size ? r.begin : size, end = r.end < size ? r.end : size;
		var psize = r.partitionSize;
		var parts = Std.int((end - begin) / psize);
		if (parts <= 0) return;
		var vecs = r.type == 2 ? 1 : chs;
		var stride = parts + cpc;
		if (r.type == 2)
			for (i in 0...size)
				interleaved[i] = 0;
		for (pass in 0...8) {
			var p = 0;
			while (p < parts) {
				if (pass == 0) {
					var k = 0;
					for (c in 0...channels) {
						if (m.mux[c] != submap) continue;
						if (r.type != 2 && noResidue[c]) {
							k++;
							continue;
						}
						var t = classbook.decode(this);
						if (t < 0) return finishResidue(r, m, submap, half, chs);
						var i = cpc;
						while (--i >= 0) {
							if (p + i < stride) classes[k * stride + p + i] = t % r.classifications;
							t = Std.int(t / r.classifications);
						}
						k++;
						if (r.type == 2) break;
					}
				}
				var i = 0;
				while (i < cpc && p < parts) {
					var k = 0;
					for (c in 0...channels) {
						if (m.mux[c] != submap) continue;
						if (r.type != 2 && noResidue[c]) {
							k++;
							continue;
						}
						var book = r.books[classes[k * stride + p] * 8 + pass];
						if (book >= 0) {
							var target = r.type == 2 ? interleaved : spectrum[c];
							if (!partition(r.type, books[book], target, begin + p * psize, psize)) return finishResidue(r, m, submap, half, chs);
						}
						k++;
						if (r.type == 2) break;
					}
					i++;
					p++;
				}
			}
		}
		finishResidue(r, m, submap, half, chs);
	}

	// (residue 2: the interleaved vector into the channels)
	function finishResidue(r:Residue, m:Mapping, submap:Int, half:Int, chs:Int) {
		if (r.type != 2) return;
		var k = 0;
		for (c in 0...channels) {
			if (m.mux[c] != submap) continue;
			var s = spectrum[c];
			for (j in 0...half)
				s[j] = interleaved[j * chs + k];
			k++;
		}
	}

	// a partition's vectors added into v at off (false: the packet ended)
	function partition(type:Int, b:Codebook, v:Vector<Float>, off:Int, psize:Int):Bool {
		var dims = b.dimensions, vq = b.vq;
		if (vq == null) return false;
		if (type == 0) {
			var step = Std.int(psize / dims);
			for (i in 0...step) {
				var e = b.decode(this);
				if (e < 0) return false;
				for (j in 0...dims)
					v[off + i + j * step] += vq[e * dims + j];
			}
		} else {
			var i = 0;
			while (i < psize) {
				var e = b.decode(this);
				if (e < 0) return false;
				for (j in 0...dims)
					if (i + j < psize) v[off + i + j] += vq[e * dims + j];
				i += dims;
			}
		}
		return true;
	}

	// (Codebook.decode's bits)
	inline function readBit():Int
		return bit();

	inline function ended():Bool
		return eop;
}

@:allow(helder.os.audio.Vorbis)
private class Codebook {
	var dimensions = 0;
	var entries = 0;
	var vq:Null<Vector<Float>> = null;
	// the Huffman tree: two slots a node (0: none; < 0: entry -slot - 1; else the child node)
	var tree:Vector<Int>;

	function new() {}

	function build(lengths:Vector<Int>, v:Vorbis) {
		var used = 0, first = -1;
		for (i in 0...entries)
			if (lengths[i] > 0) {
				used++;
				if (first < 0) first = i;
			}
		tree = new Vector((used * 2 + 2) * 2);
		for (i in 0...tree.length)
			tree[i] = 0;
		if (used == 0) return;
		if (used == 1) {
			tree[0] = -first - 1;
			tree[1] = -first - 1;
			return;
		}
		var nodes = 1;
		// (the specification's codewords: each the lowest free one of its length, in order)
		var available = new Vector<Int>(33);
		for (i in 0...33)
			available[i] = 0;
		inline function add(code:Int, len:Int, entry:Int) {
			var node = 0;
			for (k in 0...len) {
				var b = (code >>> (31 - k)) & 1;
				var slot = node * 2 + b;
				if (k == len - 1) {
					tree[slot] = -entry - 1;
				} else {
					if (tree[slot] <= 0) {
						if (nodes * 2 + 1 >= tree.length) throw "helder.os.audio.Vorbis: a codebook's tree";
						tree[slot] = nodes++;
					}
					node = tree[slot];
				}
			}
		}
		add(0, lengths[first], first);
		for (i in 1...lengths[first] + 1)
			available[i] = 1 << (32 - i);
		for (i in first + 1...entries) {
			var len = lengths[i];
			if (len == 0) continue;
			var z = len;
			while (z > 0 && available[z] == 0)
				z--;
			if (z == 0) throw "helder.os.audio.Vorbis: a codebook overspecified";
			var res = available[z];
			available[z] = 0;
			add(res, len, i);
			if (z != len) {
				var y = len;
				while (y > z) {
					available[y] = res + (1 << (32 - y));
					y--;
				}
			}
		}
	}

	// the next entry (-1: the packet ended, or a code that is no entry)
	function decode(v:Vorbis):Int {
		var node = 0;
		while (true) {
			var b = v.readBit();
			if (v.ended()) return -1;
			var c = tree[node * 2 + b];
			if (c < 0) return -c - 1;
			if (c == 0) return -1;
			node = c;
		}
	}
}

@:allow(helder.os.audio.Vorbis)
private class Floor1 {
	var partitionClass:Vector<Int>;
	var classDimensions:Vector<Int>;
	var classSubclasses:Vector<Int>;
	var classMasterbook:Vector<Int>;
	var subclassBooks:Vector<Int>;
	var multiplier = 1;
	var values = 0;
	var x:Vector<Int>;
	var sorted:Vector<Int>;
	var low:Vector<Int>;
	var high:Vector<Int>;

	function new() {}
}

@:allow(helder.os.audio.Vorbis)
private class Residue {
	var type = 0;
	var begin = 0;
	var end = 0;
	var partitionSize = 1;
	var classifications = 1;
	var classbook = 0;
	var books:Vector<Int>;

	function new() {}
}

@:allow(helder.os.audio.Vorbis)
private class Mapping {
	var submaps = 1;
	var magnitude:Vector<Int>;
	var angle:Vector<Int>;
	var mux:Vector<Int>;
	var floor:Vector<Int>;
	var residue:Vector<Int>;

	function new() {}
}

// The inverse MDCT of n samples from n/2 coefficients, in place: a DCT-IV
// of n/2 through an n/4-point complex FFT (pre- and post-twiddles), then
// the DCT-IV's output unfolded into the n samples.
@:allow(helder.os.audio.Vorbis)
private class Imdct {
	final n:Int;
	final m:Int; // n / 2
	final q:Int; // n / 4, the FFT's size
	final preCos:Vector<Float>;
	final preSin:Vector<Float>;
	final postCos:Vector<Float>;
	final postSin:Vector<Float>;
	final rootCos:Vector<Float>;
	final rootSin:Vector<Float>;
	final rev:Vector<Int>;
	final re:Vector<Float>;
	final im:Vector<Float>;
	final u:Vector<Float>;

	function new(n:Int) {
		this.n = n;
		m = n >> 1;
		q = n >> 2;
		preCos = new Vector(q);
		preSin = new Vector(q);
		postCos = new Vector(q);
		postSin = new Vector(q);
		rootCos = new Vector(q >> 1 > 0 ? q >> 1 : 1);
		rootSin = new Vector(q >> 1 > 0 ? q >> 1 : 1);
		rev = new Vector(q);
		re = new Vector(q);
		im = new Vector(q);
		u = new Vector(m);
		for (k in 0...q) {
			var a = -Math.PI * (4 * k + 1) / (4 * m);
			preCos[k] = Math.cos(a);
			preSin[k] = Math.sin(a);
			var b = -Math.PI * k / m;
			postCos[k] = Math.cos(b);
			postSin[k] = Math.sin(b);
		}
		for (k in 0...q >> 1) {
			var a = -2 * Math.PI * k / q;
			rootCos[k] = Math.cos(a);
			rootSin[k] = Math.sin(a);
		}
		var bits = 0;
		while (1 << bits < q)
			bits++;
		for (k in 0...q) {
			var r = 0;
			for (b in 0...bits)
				if (k & (1 << b) != 0) r |= 1 << (bits - 1 - b);
			rev[k] = r;
		}
	}

	// x: m coefficients in, n samples out
	function run(x:Vector<Float>) {
		for (k in 0...q) {
			var a = x[2 * k], b = x[m - 1 - 2 * k], c = preCos[k], s = preSin[k];
			var r = rev[k];
			re[r] = a * c - b * s;
			im[r] = a * s + b * c;
		}
		var size = 2;
		while (size <= q) {
			var h = size >> 1, step = Std.int(q / size);
			var i = 0;
			while (i < q) {
				for (j in 0...h) {
					var wr = rootCos[j * step], wi = rootSin[j * step];
					var a = i + j, b = a + h;
					var tr = re[b] * wr - im[b] * wi, ti = re[b] * wi + im[b] * wr;
					re[b] = re[a] - tr;
					im[b] = im[a] - ti;
					re[a] += tr;
					im[a] += ti;
				}
				i += size;
			}
			size <<= 1;
		}
		for (k in 0...q) {
			var c = postCos[k], s = postSin[k];
			var wr = re[k] * c - im[k] * s, wi = re[k] * s + im[k] * c;
			u[2 * k] = wr;
			u[m - 1 - 2 * k] = -wi;
		}
		var h = m >> 1;
		for (t in 0...h)
			x[t] = u[t + h];
		for (t in h...3 * h)
			x[t] = -u[3 * h - 1 - t];
		for (t in 3 * h...n)
			x[t] = -u[t - 3 * h];
	}
}
