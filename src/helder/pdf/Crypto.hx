package helder.pdf;

import helder.pdf.PdfValue;
import helder.pdf.Document;

import haxe.Int64;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;

// PDF's standard security handler, to read: RC4 (40 to 128 bits, V1 to
// V4), AES-128 (V4's AESV2) and AES-256 (V5, R5 and R6: SHA-256 and R6's
// hash 2.B with SHA-384 and SHA-512), each object's key from the file's
// (MD5 of it with the object's number and generation) where R < 5. The
// password tried first is the user's given one (empty by default), then
// the same as the owner's.
class Crypto implements helder.pdf.Document.Decryptor {
	public final key:Bytes;
	public final aes:Bool;
	final r:Int;
	final stringMethod:String;
	final streamMethod:String;

	function new(key, aes, r, streamMethod, stringMethod) {
		this.key = key;
		this.aes = aes;
		this.r = r;
		this.streamMethod = streamMethod;
		this.stringMethod = stringMethod;
	}

	static final PAD = Bytes.ofHex("28bf4e5e4e758a4164004e56fffa01082e2e00b6d0683e802f0ca9fe6453697a");

	// the handler for an /Encrypt dictionary (null: the password does not open it)
	public static function open(enc:PdfDict, id:Bytes, password:String):Null<Crypto> {
		var filter = Values.name(enc.get("Filter"));
		if (filter != "Standard") throw PdfError.unsupported("encryption by the " + filter + " handler");
		var v = Values.int(enc.get("V")), r = Values.int(enc.get("R"));
		var o = Values.str(enc.get("O")), u = Values.str(enc.get("U")), p = Values.int(enc.get("P"));
		if (o == null || u == null) throw PdfError.corrupt("an /Encrypt without /O and /U");
		if (o.length < (r >= 5 ? 48 : 32) || u.length < (r >= 5 ? 48 : 16)) throw PdfError.corrupt("an /Encrypt's /O or /U too short");
		var pw = Bytes.ofString(password);
		var method = "RC4", strMethod = "RC4";
		if (v >= 4) {
			var cf = Values.dict(enc.get("CF"));
			inline function cfm(name:Null<String>):String {
				if (name == null || name == "Identity") return "None";
				var f = cf == null ? null : Values.dict(cf.get(name));
				var m = f == null ? "V2" : Values.name(f.get("CFM"), "V2");
				return m == "AESV2" || m == "AESV3" ? "AES" : m == "None" ? "None" : "RC4";
			}
			method = cfm(Values.name(enc.get("StmF"), "Identity"));
			strMethod = cfm(Values.name(enc.get("StrF"), "Identity"));
		}
		if (r >= 5) {
			var ue = Values.str(enc.get("UE")), oe = Values.str(enc.get("OE"));
			if (ue == null || oe == null || ue.length < 32 || oe.length < 32) throw PdfError.corrupt("an AES-256 /Encrypt without /UE and /OE");
			var p8 = pw.length > 127 ? pw.sub(0, 127) : pw;
			// (user: the hash of the password and U's validation salt equal to U's first 32 bytes)
			var hu = hash(r, p8, u.sub(32, 8), Bytes.alloc(0));
			if (eq(hu, u.sub(0, 32))) {
				var k = hash(r, p8, u.sub(40, 8), Bytes.alloc(0));
				return new Crypto(aesCbc(k, Bytes.alloc(16), ue, false), true, r, method, strMethod);
			}
			var ho = hash(r, p8, o.sub(32, 8), u.sub(0, 48));
			if (eq(ho, o.sub(0, 32))) {
				var k = hash(r, p8, o.sub(40, 8), u.sub(0, 48));
				return new Crypto(aesCbc(k, Bytes.alloc(16), oe, false), true, r, method, strMethod);
			}
			return null;
		}
		var length = v == 1 ? 5 : Std.int(Values.int(enc.get("Length"), 40) / 8);
		if (length < 5 || length > 16) length = 16;
		var meta = Values.bool(enc.get("EncryptMetadata"), true);
		var k = userKey(pw, o, p, id, r, length, meta);
		if (checkUser(k, u, id, r)) return new Crypto(k, method == "AES", r, method, strMethod);
		// (the owner's password: RC4 of O by its key is the user's)
		var ok = md5(padded(pw));
		if (r >= 3)
			for (_ in 0...50)
				ok = md5(ok.sub(0, length));
		var user = o;
		if (r == 2) user = rc4(ok.sub(0, length), o) else {
			for (i in 0...20) {
				var x = Bytes.alloc(length);
				for (j in 0...length)
					x.set(j, ok.get(j) ^ (19 - i));
				user = rc4(x, user);
			}
		}
		k = userKey(user, o, p, id, r, length, meta);
		if (checkUser(k, u, id, r)) return new Crypto(k, method == "AES", r, method, strMethod);
		return null;
	}

	static function padded(pw:Bytes):Bytes {
		var b = Bytes.alloc(32);
		var n = pw.length > 32 ? 32 : pw.length;
		b.blit(0, pw, 0, n);
		b.blit(n, PAD, 0, 32 - n);
		return b;
	}

	static function userKey(pw:Bytes, o:Bytes, p:Int, id:Bytes, r:Int, length:Int, meta:Bool):Bytes {
		var b = new BytesBuffer();
		b.add(padded(pw));
		b.add(o.sub(0, Std.int(Math.min(32, o.length))));
		b.addByte(p & 255);
		b.addByte((p >> 8) & 255);
		b.addByte((p >> 16) & 255);
		b.addByte((p >> 24) & 255);
		b.add(id);
		if (r >= 4 && !meta) b.add(Bytes.ofHex("ffffffff"));
		var k = md5(b.getBytes());
		if (r >= 3)
			for (_ in 0...50)
				k = md5(k.sub(0, length));
		return k.sub(0, length);
	}

	static function checkUser(k:Bytes, u:Bytes, id:Bytes, r:Int):Bool {
		if (r == 2) return eq(rc4(k, PAD), u.sub(0, 32));
		var b = new BytesBuffer();
		b.add(PAD);
		b.add(id);
		var x = rc4(k, md5(b.getBytes()));
		for (i in 1...20) {
			var kk = Bytes.alloc(k.length);
			for (j in 0...k.length)
				kk.set(j, k.get(j) ^ i);
			x = rc4(kk, x);
		}
		return u.length >= 16 && eq(x.sub(0, 16), u.sub(0, 16));
	}

	static function eq(a:Bytes, b:Bytes):Bool
		return a.length == b.length && a.compare(b) == 0;

	public static inline function md5(b:Bytes):Bytes
		return haxe.crypto.Md5.make(b);

	// an object's string or stream decrypted
	public function decrypt(data:Bytes, num:Int, gen:Int, stream:Bool):Bytes {
		var method = stream ? streamMethod : stringMethod;
		if (method == "None") return data;
		var k = key;
		if (r < 5) {
			var b = new BytesBuffer();
			b.add(key);
			b.addByte(num & 255);
			b.addByte((num >> 8) & 255);
			b.addByte((num >> 16) & 255);
			b.addByte(gen & 255);
			b.addByte((gen >> 8) & 255);
			if (method == "AES") b.add(Bytes.ofString("sAlT"));
			var h = md5(b.getBytes());
			k = h.sub(0, Std.int(Math.min(16, key.length + 5)));
		}
		if (method == "AES") {
			if (data.length < 32 || data.length % 16 != 0) return Bytes.alloc(0);
			return aesCbc(k, data.sub(0, 16), data.sub(16, data.length - 16), true);
		}
		return rc4(k, data);
	}

	public static function rc4(key:Bytes, data:Bytes):Bytes {
		var s = [for (i in 0...256) i], j = 0;
		for (i in 0...256) {
			j = (j + s[i] + key.get(i % key.length)) & 255;
			var t = s[i];
			s[i] = s[j];
			s[j] = t;
		}
		var out = Bytes.alloc(data.length), i = 0;
		j = 0;
		for (k in 0...data.length) {
			i = (i + 1) & 255;
			j = (j + s[i]) & 255;
			var t = s[i];
			s[i] = s[j];
			s[j] = t;
			out.set(k, data.get(k) ^ s[(s[i] + s[j]) & 255]);
		}
		return out;
	}

	// ---- AES (FIPS 197), decryption in CBC mode; pkcs7: the padding removed

	static var SBOX:Array<Int>;
	static var INV:Array<Int>;

	static function tables() {
		if (SBOX != null) return;
		SBOX = [];
		INV = [];
		var p = 1, q = 1;
		var sbox = [for (_ in 0...256) 0];
		do {
			p = p ^ ((p << 1) & 255) ^ ((p & 0x80) != 0 ? 0x1B : 0);
			q ^= q << 1;
			q ^= q << 2;
			q ^= q << 4;
			q &= 255;
			if ((q & 0x80) != 0) q ^= 0x09;
			var x = q ^ rotl8(q, 1) ^ rotl8(q, 2) ^ rotl8(q, 3) ^ rotl8(q, 4);
			sbox[p] = (x ^ 0x63) & 255;
		} while (p != 1);
		sbox[0] = 0x63;
		SBOX = sbox;
		INV = [for (_ in 0...256) 0];
		for (i in 0...256)
			INV[SBOX[i]] = i;
	}

	static inline function rotl8(x:Int, s:Int):Int
		return ((x << s) | (x >> (8 - s))) & 255;

	static inline function xt(a:Int):Int
		return ((a << 1) ^ ((a & 0x80) != 0 ? 0x1B : 0)) & 255;

	static function mul(a:Int, b:Int):Int {
		var r = 0;
		while (b > 0) {
			if ((b & 1) != 0) r ^= a;
			a = xt(a);
			b >>= 1;
		}
		return r;
	}

	static function expand(key:Bytes):Array<Int> {
		tables();
		var nk = Std.int(key.length / 4), nr = nk + 6, w = [for (i in 0...key.length) key.get(i)];
		var rcon = 1;
		var i = nk;
		while (i < 4 * (nr + 1)) {
			var t = w.slice((i - 1) * 4, i * 4);
			if (i % nk == 0) {
				t = [SBOX[t[1]] ^ rcon, SBOX[t[2]], SBOX[t[3]], SBOX[t[0]]];
				rcon = xt(rcon);
			} else if (nk > 6 && i % nk == 4) t = [for (x in t) SBOX[x]];
			for (k in 0...4)
				w.push(w[(i - nk) * 4 + k] ^ t[k]);
			i++;
		}
		return w;
	}

	static function decryptBlock(w:Array<Int>, nr:Int, s:Array<Int>) {
		inline function addKey(round:Int)
			for (k in 0...16)
				s[k] ^= w[round * 16 + k];
		addKey(nr);
		var round = nr - 1;
		while (round >= 0) {
			// inverse shift rows
			var t = s.copy();
			for (c in 0...4)
				for (rr in 0...4)
					s[((c + rr) % 4) * 4 + rr] = t[c * 4 + rr];
			for (k in 0...16)
				s[k] = INV[s[k]];
			addKey(round);
			if (round > 0)
				for (c in 0...4) {
					var a0 = s[c * 4], a1 = s[c * 4 + 1], a2 = s[c * 4 + 2], a3 = s[c * 4 + 3];
					s[c * 4] = mul(a0, 14) ^ mul(a1, 11) ^ mul(a2, 13) ^ mul(a3, 9);
					s[c * 4 + 1] = mul(a0, 9) ^ mul(a1, 14) ^ mul(a2, 11) ^ mul(a3, 13);
					s[c * 4 + 2] = mul(a0, 13) ^ mul(a1, 9) ^ mul(a2, 14) ^ mul(a3, 11);
					s[c * 4 + 3] = mul(a0, 11) ^ mul(a1, 13) ^ mul(a2, 9) ^ mul(a3, 14);
				}
			round--;
		}
	}

	public static function aesCbc(key:Bytes, iv:Bytes, data:Bytes, pkcs7:Bool):Bytes {
		var w = expand(key), nr = Std.int(key.length / 4) + 6;
		var out = Bytes.alloc(data.length), prev = [for (i in 0...16) iv.get(i)];
		var blocks = Std.int(data.length / 16);
		for (bk in 0...blocks) {
			var s = [for (i in 0...16) data.get(bk * 16 + i)], c = s.copy();
			decryptBlock(w, nr, s);
			for (i in 0...16)
				out.set(bk * 16 + i, s[i] ^ prev[i]);
			prev = c;
		}
		if (pkcs7 && out.length > 0) {
			var pad = out.get(out.length - 1);
			if (pad >= 1 && pad <= 16 && pad <= out.length) return out.sub(0, out.length - pad);
		}
		return out;
	}

	static function aesCbcEncrypt(key:Bytes, iv:Bytes, data:Bytes):Bytes {
		// (R6's hash 2.B encrypts: AES-128-CBC without padding)
		tables();
		var w = expand(key), nr = Std.int(key.length / 4) + 6;
		var out = Bytes.alloc(data.length), prev = [for (i in 0...16) iv.get(i)];
		for (bk in 0...Std.int(data.length / 16)) {
			var s = [for (i in 0...16) data.get(bk * 16 + i) ^ prev[i]];
			inline function addKey(round:Int)
				for (k in 0...16)
					s[k] ^= w[round * 16 + k];
			addKey(0);
			for (round in 1...nr + 1) {
				for (k in 0...16)
					s[k] = SBOX[s[k]];
				var t = s.copy();
				for (c in 0...4)
					for (rr in 0...4)
						s[c * 4 + rr] = t[((c + rr) % 4) * 4 + rr];
				if (round < nr)
					for (c in 0...4) {
						var a0 = s[c * 4], a1 = s[c * 4 + 1], a2 = s[c * 4 + 2], a3 = s[c * 4 + 3];
						s[c * 4] = xt(a0) ^ (xt(a1) ^ a1) ^ a2 ^ a3;
						s[c * 4 + 1] = a0 ^ xt(a1) ^ (xt(a2) ^ a2) ^ a3;
						s[c * 4 + 2] = a0 ^ a1 ^ xt(a2) ^ (xt(a3) ^ a3);
						s[c * 4 + 3] = (xt(a0) ^ a0) ^ a1 ^ a2 ^ xt(a3);
					}
				addKey(round);
			}
			for (i in 0...16)
				out.set(bk * 16 + i, s[i]);
			prev = s;
		}
		return out;
	}

	// ---- R5 and R6's password hash (ISO 32000-2's 7.6.4.3.4: algorithm 2.B)

	static function hash(r:Int, pw:Bytes, salt:Bytes, udata:Bytes):Bytes {
		var b = new BytesBuffer();
		b.add(pw);
		b.add(salt);
		b.add(udata);
		var k = haxe.crypto.Sha256.make(b.getBytes());
		if (r < 6) return k;
		var round = 0;
		while (true) {
			var one = new BytesBuffer();
			one.add(pw);
			one.add(k);
			one.add(udata);
			var s = one.getBytes(), k1 = new BytesBuffer();
			for (_ in 0...64)
				k1.add(s);
			var e = aesCbcEncrypt(k.sub(0, 16), k.sub(16, 16), k1.getBytes());
			var sum = 0;
			for (i in 0...16)
				sum += e.get(i);
			k = switch sum % 3 {
				case 0: haxe.crypto.Sha256.make(e);
				case 1: Sha512.make(e, true);
				case _: Sha512.make(e, false);
			}
			round++;
			if (round >= 64 && e.get(e.length - 1) <= round - 32) break;
		}
		return k.sub(0, 32);
	}
}

// SHA-512 and SHA-384 (FIPS 180-4) on haxe.Int64
class Sha512 {
	static var K:Array<Int64>;

	public static function make(data:Bytes, is384:Bool):Bytes {
		if (K == null) K = [for (h in [
			"428a2f98d728ae22", "7137449123ef65cd", "b5c0fbcfec4d3b2f", "e9b5dba58189dbbc", "3956c25bf348b538", "59f111f1b605d019", "923f82a4af194f9b",
			"ab1c5ed5da6d8118", "d807aa98a3030242", "12835b0145706fbe", "243185be4ee4b28c", "550c7dc3d5ffb4e2", "72be5d74f27b896f", "80deb1fe3b1696b1",
			"9bdc06a725c71235", "c19bf174cf692694", "e49b69c19ef14ad2", "efbe4786384f25e3", "0fc19dc68b8cd5b5", "240ca1cc77ac9c65", "2de92c6f592b0275",
			"4a7484aa6ea6e483", "5cb0a9dcbd41fbd4", "76f988da831153b5", "983e5152ee66dfab", "a831c66d2db43210", "b00327c898fb213f", "bf597fc7beef0ee4",
			"c6e00bf33da88fc2", "d5a79147930aa725", "06ca6351e003826f", "142929670a0e6e70", "27b70a8546d22ffc", "2e1b21385c26c926", "4d2c6dfc5ac42aed",
			"53380d139d95b3df", "650a73548baf63de", "766a0abb3c77b2a8", "81c2c92e47edaee6", "92722c851482353b", "a2bfe8a14cf10364", "a81a664bbc423001",
			"c24b8b70d0f89791", "c76c51a30654be30", "d192e819d6ef5218", "d69906245565a910", "f40e35855771202a", "106aa07032bbd1b8", "19a4c116b8d2d0c8",
			"1e376c085141ab53", "2748774cdf8eeb99", "34b0bcb5e19b48a8", "391c0cb3c5c95a63", "4ed8aa4ae3418acb", "5b9cca4f7763e373", "682e6ff3d6b2b8a3",
			"748f82ee5defb2fc", "78a5636f43172f60", "84c87814a1f0ab72", "8cc702081a6439ec", "90befffa23631e28", "a4506cebde82bde9", "bef9a3f7b2c67915",
			"c67178f2e372532b", "ca273eceea26619c", "d186b8c721c0c207", "eada7dd6cde0eb1e", "f57d4f7fee6ed178", "06f067aa72176fba", "0a637dc5a2c898a6",
			"113f9804bef90dae", "1b710b35131c471b", "28db77f523047d84", "32caab7b40c72493", "3c9ebe0a15c9bebc", "431d67c49c100d4c", "4cc5d4becb3e42b6",
			"597f299cfc657e2a", "5fcb6fab3ad6faec", "6c44198c4a475817"
		]) hex(h)];
		var h = is384 ? [for (x in [
			"cbbb9d5dc1059ed8", "629a292a367cd507", "9159015a3070dd17", "152fecd8f70e5939", "67332667ffc00b31", "8eb44a8768581511", "db0c2e0d64f98fa7",
			"47b5481dbefa4fa4"
		]) hex(x)] : [for (x in [
			"6a09e667f3bcc908", "bb67ae8584caa73b", "3c6ef372fe94f82b", "a54ff53a5f1d36f1", "510e527fade682d1", "9b05688c2b3e6c1f", "1f83d9abfb41bd6b",
			"5be0cd19137e2179"
		]) hex(x)];
		var n = data.length, total = Std.int(Math.ceil((n + 17) / 128)) * 128;
		var m = Bytes.alloc(total);
		m.blit(0, data, 0, n);
		m.set(n, 0x80);
		var bits = n * 8;
		m.set(total - 1, bits & 255);
		m.set(total - 2, (bits >> 8) & 255);
		m.set(total - 3, (bits >> 16) & 255);
		m.set(total - 4, (bits >>> 24) & 255);
		var w = [for (_ in 0...80) Int64.make(0, 0)];
		var blk = 0;
		while (blk < total) {
			for (t in 0...16) {
				var o = blk + t * 8;
				w[t] = Int64.make((m.get(o) << 24) | (m.get(o + 1) << 16) | (m.get(o + 2) << 8) | m.get(o + 3),
					(m.get(o + 4) << 24) | (m.get(o + 5) << 16) | (m.get(o + 6) << 8) | m.get(o + 7));
			}
			for (t in 16...80) {
				var s0 = rotr(w[t - 15], 1) ^ rotr(w[t - 15], 8) ^ Int64.ushr(w[t - 15], 7);
				var s1 = rotr(w[t - 2], 19) ^ rotr(w[t - 2], 61) ^ Int64.ushr(w[t - 2], 6);
				w[t] = w[t - 16] + s0 + w[t - 7] + s1;
			}
			var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
			for (t in 0...80) {
				var S1 = rotr(e, 14) ^ rotr(e, 18) ^ rotr(e, 41);
				var ch = (e & f) ^ (~e & g);
				var t1 = hh + S1 + ch + K[t] + w[t];
				var S0 = rotr(a, 28) ^ rotr(a, 34) ^ rotr(a, 39);
				var maj = (a & b) ^ (a & c) ^ (b & c);
				var t2 = S0 + maj;
				hh = g;
				g = f;
				f = e;
				e = d + t1;
				d = c;
				c = b;
				b = a;
				a = t1 + t2;
			}
			h[0] += a;
			h[1] += b;
			h[2] += c;
			h[3] += d;
			h[4] += e;
			h[5] += f;
			h[6] += g;
			h[7] += hh;
			blk += 128;
		}
		var out = Bytes.alloc(is384 ? 48 : 64);
		for (i in 0...Std.int(out.length / 8)) {
			out.setInt32(i * 8, swap(h[i].high));
			out.setInt32(i * 8 + 4, swap(h[i].low));
		}
		return out;
	}

	static inline function swap(x:Int):Int
		return ((x & 255) << 24) | (((x >> 8) & 255) << 16) | (((x >> 16) & 255) << 8) | ((x >>> 24) & 255);

	static inline function rotr(x:Int64, n:Int):Int64
		return Int64.ushr(x, n) | (x << (64 - n));

	static function hex(s:String):Int64
		return Int64.make(Std.parseInt("0x" + s.substr(0, 8)), Std.parseInt("0x" + s.substr(8, 8)));
}
