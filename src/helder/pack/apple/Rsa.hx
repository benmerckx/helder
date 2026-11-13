package helder.pack.apple;

import haxe.ds.Vector;
import haxe.io.Bytes;

// RSA signatures with SHA-256 and PKCS#1 v1.5's padding (RFC 8017, 8.2:
// EMSA-PKCS1-v1_5), in plain Haxe, for code signatures (CodeSign's CMS)
// with an Apple certificate's key: s = m^d mod n by the Chinese remainder
// theorem (m^dp mod p, m^dq mod q, Garner's recombination), and the
// check s^e mod n. Numbers are little-endian vectors of 15-bit limbs (every
// product and carry fits a 32-bit Int), exponentiation Montgomery's (CIOS)
// with a 4-bit window. Not constant-time: it signs on the developer's own
// machine or CI.
class Rsa {
	static inline var BITS = 15;
	static inline var MASK = 0x7fff;

	// (DER of SHA-256's DigestInfo, before the digest)
	static final SHA256_INFO = Bytes.ofHex("3031300d060960864801650304020105000420");

	// the signature of message's SHA-256 (as long as n)
	public static function sign(key:RsaKey, message:Bytes):Bytes {
		var k = byteLength(key.n);
		var m = fromBytes(encode(message, k));
		var p = fromBytes(key.p), q = fromBytes(key.q);
		var m1 = new Mont(p).pow(mod(m, p), fromBytes(key.dp));
		var m2 = new Mont(q).pow(mod(m, q), fromBytes(key.dq));
		// h = qi (m1 - m2) mod p; s = m2 + h q
		var m2p = mod(m2, p);
		var diff = cmp(m1, m2p) >= 0 ? sub(m1, m2p) : sub(add(m1, p), m2p);
		var h = mod(mul(fromBytes(key.qi), diff), p);
		var s = add(m2, mul(h, q));
		var out = toBytes(s, k);
		if (!verify(key.n, key.e, message, out)) throw "RSA: the key's numbers do not agree (the signature does not verify)";
		return out;
	}

	public static function verify(n:Bytes, e:Bytes, message:Bytes, signature:Bytes):Bool {
		var k = byteLength(n);
		if (signature.length != k) return false;
		var nn = fromBytes(n);
		var s = fromBytes(signature);
		if (cmp(s, nn) >= 0) return false;
		return toBytes(new Mont(nn).pow(s, fromBytes(e)), k).compare(encode(message, k)) == 0;
	}

	// EM = 00 01 ff..ff 00 DigestInfo(SHA-256(message))
	static function encode(message:Bytes, k:Int):Bytes {
		var t = SHA256_INFO.length + 32;
		if (k < t + 11) throw "RSA: the key is too short";
		var em = Bytes.alloc(k);
		em.set(1, 1);
		em.fill(2, k - t - 3, 0xff);
		em.blit(k - t, SHA256_INFO, 0, SHA256_INFO.length);
		em.blit(k - 32, haxe.crypto.Sha256.make(message), 0, 32);
		return em;
	}

	// a big-endian number's length without its leading zeros
	public static function byteLength(b:Bytes):Int {
		var i = 0;
		while (i < b.length && b.get(i) == 0)
			i++;
		return b.length - i;
	}

	// ---- numbers: limbs of 15 bits, little-endian, no fixed length

	public static function fromBytes(b:Bytes):Vector<Int> {
		var n = Std.int((8 * b.length + BITS - 1) / BITS) + 1;
		var r = new Vector<Int>(n, 0);
		var acc = 0, accBits = 0, at = 0;
		var i = b.length - 1;
		while (i >= 0) {
			acc |= b.get(i) << accBits;
			accBits += 8;
			while (accBits >= BITS) {
				r[at++] = acc & MASK;
				acc >>>= BITS;
				accBits -= BITS;
			}
			i--;
		}
		if (accBits > 0) r[at] = acc;
		return trim(r);
	}

	public static function toBytes(a:Vector<Int>, len:Int):Bytes {
		var b = Bytes.alloc(len);
		var acc = 0, accBits = 0, at = len - 1;
		for (i in 0...a.length) {
			acc |= a[i] << accBits;
			accBits += BITS;
			while (accBits >= 8 && at >= 0) {
				b.set(at--, acc & 0xff);
				acc >>>= 8;
				accBits -= 8;
			}
		}
		while (at >= 0 && accBits > 0) {
			b.set(at--, acc & 0xff);
			acc >>>= 8;
			accBits -= 8;
		}
		return b;
	}

	static function trim(a:Vector<Int>):Vector<Int> {
		var n = a.length;
		while (n > 1 && a[n - 1] == 0)
			n--;
		if (n == a.length) return a;
		var r = new Vector<Int>(n);
		Vector.blit(a, 0, r, 0, n);
		return r;
	}

	static inline function limb(a:Vector<Int>, i:Int):Int
		return i < a.length ? a[i] : 0;

	public static function cmp(a:Vector<Int>, b:Vector<Int>):Int {
		var i = (a.length > b.length ? a.length : b.length) - 1;
		while (i >= 0) {
			var x = limb(a, i), y = limb(b, i);
			if (x != y) return x < y ? -1 : 1;
			i--;
		}
		return 0;
	}

	static function add(a:Vector<Int>, b:Vector<Int>):Vector<Int> {
		var n = (a.length > b.length ? a.length : b.length) + 1;
		var r = new Vector<Int>(n, 0), c = 0;
		for (i in 0...n) {
			var s = limb(a, i) + limb(b, i) + c;
			r[i] = s & MASK;
			c = s >> BITS;
		}
		return trim(r);
	}

	// a - b, a >= b
	static function sub(a:Vector<Int>, b:Vector<Int>):Vector<Int> {
		var r = new Vector<Int>(a.length, 0), c = 0;
		for (i in 0...a.length) {
			var s = a[i] - limb(b, i) - c;
			c = s < 0 ? 1 : 0;
			r[i] = s & MASK;
		}
		return trim(r);
	}

	static function mul(a:Vector<Int>, b:Vector<Int>):Vector<Int> {
		var r = new Vector<Int>(a.length + b.length + 1, 0);
		for (i in 0...a.length) {
			var c = 0, ai = a[i];
			for (j in 0...b.length) {
				var s = r[i + j] + ai * b[j] + c;
				r[i + j] = s & MASK;
				c = s >> BITS;
			}
			var k = i + b.length;
			while (c != 0) {
				var s = r[k] + c;
				r[k] = s & MASK;
				c = s >> BITS;
				k++;
			}
		}
		return trim(r);
	}

	static function bitLength(a:Vector<Int>):Int {
		var i = a.length - 1;
		while (i > 0 && a[i] == 0)
			i--;
		var v = a[i], n = 0;
		while (v != 0) {
			n++;
			v >>= 1;
		}
		return i * BITS + n;
	}

	static inline function bit(a:Vector<Int>, i:Int):Int
		return (limb(a, Std.int(i / BITS)) >> (i % BITS)) & 1;

	// a mod m: shifted in a bit at a time, m subtracted when reached
	public static function mod(a:Vector<Int>, m:Vector<Int>):Vector<Int> {
		var n = m.length + 1;
		var r = new Vector<Int>(n, 0);
		var i = bitLength(a) - 1;
		while (i >= 0) {
			var c = bit(a, i);
			for (k in 0...n) {
				var s = (r[k] << 1) | c;
				r[k] = s & MASK;
				c = s >> BITS;
			}
			if (cmp(r, m) >= 0) {
				var b = 0;
				for (k in 0...n) {
					var s = r[k] - limb(m, k) - b;
					b = s < 0 ? 1 : 0;
					r[k] = s & MASK;
				}
			}
			i--;
		}
		return trim(r);
	}

	// 2^bits mod m
	public static function pow2(bits:Int, m:Vector<Int>):Vector<Int> {
		var one = new Vector<Int>(Std.int(bits / BITS) + 1, 0);
		one[Std.int(bits / BITS)] = 1 << (bits % BITS);
		return mod(one, m);
	}

	// ---- a new key (helder setup's: Apple's distribution certificate's,
	// Play's upload key): two primes of bits/2, their top two bits set (n
	// exactly bits long), each found from a random odd start counting up
	// by 2, small primes sieved out, then Miller-Rabin with random bases;
	// e = 65537, d its inverse mod (p-1)(q-1), the CRT's numbers. random:
	// the system's (Entropy), a test's own

	public static function generate(bits = 2048, ?random:Int->Bytes):RsaKey {
		if (bits < 512 || bits % 16 != 0) throw 'RSA: $bits bits (512 or more, a multiple of 16)';
		random ??= helder.pack.Entropy.bytes;
		var e = 65537, one = fromInt(1);
		while (true) {
			var p = prime(bits >> 1, e, random), q = prime(bits >> 1, e, random);
			var c = cmp(p, q);
			if (c == 0) continue;
			if (c < 0) {
				var t = p;
				p = q;
				q = t;
			}
			var n = mul(p, q);
			if (bitLength(n) != bits) continue;
			var p1 = sub(p, one), q1 = sub(q, one);
			var phi = mul(p1, q1);
			// (d = (1 + k phi) / e, k = -phi^-1 mod e: e is small)
			var k = (e - inverseSmall(modSmall(phi, e), e)) % e;
			var d = divSmall(add(one, mul(phi, fromInt(k))), e);
			// (q^-1 mod p: q^(p-2), p prime)
			var qi = new Mont(p).pow(mod(q, p), sub(p, fromInt(2)));
			return {
				n: unsigned(n),
				e: unsigned(fromInt(e)),
				d: unsigned(d),
				p: unsigned(p),
				q: unsigned(q),
				dp: unsigned(mod(d, p1)),
				dq: unsigned(mod(d, q1)),
				qi: unsigned(qi)
			};
		}
	}

	static var smallPrimes:Null<Array<Int>> = null;

	// a prime of bits, p - 1 prime to e
	static function prime(bits:Int, e:Int, random:Int->Bytes):Vector<Int> {
		if (smallPrimes == null) {
			var sieve = new Vector<Bool>(2048, true);
			smallPrimes = [];
			for (i in 3...2048) if (sieve[i] && i % 2 == 1) {
				smallPrimes.push(i);
				var j = i * i;
				while (j < 2048) {
					sieve[j] = false;
					j += i;
				}
			}
		}
		var two = fromInt(2);
		while (true) {
			var b = random(bits >> 3);
			b.set(0, b.get(0) | 0xc0);
			b.set(b.length - 1, b.get(b.length - 1) | 1);
			var c = fromBytes(b);
			for (_ in 0...4096) {
				if (bitLength(c) != bits) break;
				if (!Lambda.exists(smallPrimes, s -> modSmall(c, s) == 0) && modSmall(c, e) != 1 && probablyPrime(c, 12, random)) return c;
				c = add(c, two);
			}
		}
	}

	// Miller-Rabin: n - 1 = 2^s d, a^d 1 or -1, or one of its squares -1
	public static function probablyPrime(n:Vector<Int>, rounds:Int, random:Int->Bytes):Bool {
		var one = fromInt(1), two = fromInt(2);
		var n1 = sub(n, one);
		var d = n1, s = 0;
		while (d[0] & 1 == 0) {
			d = shr1(d);
			s++;
		}
		var m = new Mont(n), len = (bitLength(n) + 7) >> 3;
		var r = 0;
		while (r < rounds) {
			var a = fromBytes(random(len - 1));
			if (cmp(a, two) < 0) continue;
			r++;
			var x = m.pow(a, d);
			if (cmp(x, one) == 0 || cmp(x, n1) == 0) continue;
			var witness = true;
			for (_ in 1...s) {
				x = m.pow(x, two);
				if (cmp(x, n1) == 0) {
					witness = false;
					break;
				}
				if (cmp(x, one) == 0) break;
			}
			if (witness) return false;
		}
		return true;
	}

	static function fromInt(v:Int):Vector<Int>
		return fromBytes(Bytes.ofHex(StringTools.hex(v, 8)));

	// (the big-endian bytes without leading zeros)
	static function unsigned(a:Vector<Int>):Bytes {
		var b = toBytes(a, (bitLength(a) + 7) >> 3);
		return b.length == 0 ? Bytes.ofHex("00") : b;
	}

	static function shr1(a:Vector<Int>):Vector<Int> {
		var r = new Vector<Int>(a.length, 0);
		for (i in 0...a.length)
			r[i] = (a[i] >> 1) | (i + 1 < a.length ? (a[i + 1] & 1) << (BITS - 1) : 0);
		return trim(r);
	}

	// (a mod m, m < 2^16: 15 bits a limb in two steps, each product under 2^31)
	static function modSmall(a:Vector<Int>, m:Int):Int {
		var r = 0, i = a.length - 1;
		while (i >= 0) {
			r = (r * 128 + (a[i] >> 8)) % m;
			r = (r * 256 + (a[i] & 0xff)) % m;
			i--;
		}
		return r;
	}

	static function divSmall(a:Vector<Int>, m:Int):Vector<Int> {
		var q = new Vector<Int>(a.length, 0), r = 0, i = a.length - 1;
		while (i >= 0) {
			var t = r * 128 + (a[i] >> 8);
			var q1 = Std.int(t / m);
			r = t - q1 * m;
			t = r * 256 + (a[i] & 0xff);
			var q2 = Std.int(t / m);
			r = t - q2 * m;
			q[i] = q1 * 256 + q2;
			i--;
		}
		return trim(q);
	}

	// x with a x = 1 mod m (a prime to m)
	static function inverseSmall(a:Int, m:Int):Int {
		var t = 0, nt = 1, r = m, nr = a % m;
		while (nr != 0) {
			var q = Std.int(r / nr);
			var x = t - q * nt;
			t = nt;
			nt = x;
			x = r - q * nr;
			r = nr;
			nr = x;
		}
		if (r != 1) throw "RSA: not invertible";
		return t < 0 ? t + m : t;
	}

	public static function pad(a:Vector<Int>, n:Int):Vector<Int> {
		var r = new Vector<Int>(n, 0);
		for (i in 0...(a.length < n ? a.length : n))
			r[i] = a[i];
		return r;
	}
}

// Montgomery arithmetic modulo an odd m of L limbs (R = 2^(15 L))
private class Mont {
	static inline var BITS = 15;
	static inline var MASK = 0x7fff;

	final m:Vector<Int>;
	final l:Int;
	final minv:Int;
	final r2:Vector<Int>;
	final one:Vector<Int>;

	public function new(m:Vector<Int>) {
		l = m.length;
		this.m = m;
		if (m[0] & 1 == 0) throw "RSA: an even modulus";
		var inv = 1;
		for (_ in 0...5)
			inv = (inv * (2 - ((m[0] * inv) & MASK))) & MASK;
		minv = (-inv) & MASK;
		one = Rsa.pad(Rsa.pow2(BITS * l, m), l);
		r2 = Rsa.pad(Rsa.pow2(2 * BITS * l, m), l);
	}

	function geq(a:Vector<Int>):Bool {
		var i = l - 1;
		while (i >= 0) {
			if (a[i] != m[i]) return a[i] > m[i];
			i--;
		}
		return true;
	}

	public function mul(a:Vector<Int>, b:Vector<Int>):Vector<Int> {
		var t = new Vector<Int>(l + 2, 0);
		for (i in 0...l) {
			var ai = a[i], c = 0;
			for (j in 0...l) {
				var s = t[j] + ai * b[j] + c;
				t[j] = s & MASK;
				c = s >> BITS;
			}
			var s = t[l] + c;
			t[l] = s & MASK;
			t[l + 1] = s >> BITS;
			var u = (t[0] * minv) & MASK;
			s = t[0] + u * m[0];
			c = s >> BITS;
			for (j in 1...l) {
				s = t[j] + u * m[j] + c;
				t[j - 1] = s & MASK;
				c = s >> BITS;
			}
			s = t[l] + c;
			t[l - 1] = s & MASK;
			t[l] = t[l + 1] + (s >> BITS);
		}
		var r = new Vector<Int>(l);
		Vector.blit(t, 0, r, 0, l);
		if (t[l] != 0 || geq(r)) {
			var b = 0;
			for (i in 0...l) {
				var s = r[i] - m[i] - b;
				b = s < 0 ? 1 : 0;
				r[i] = s & MASK;
			}
		}
		return r;
	}

	// base^e mod m (base < m), a 4-bit window
	public function pow(base:Vector<Int>, e:Vector<Int>):Vector<Int> {
		var table = new Vector<Vector<Int>>(16);
		table[0] = one;
		table[1] = mul(Rsa.pad(base, l), r2);
		for (k in 2...16)
			table[k] = mul(table[k - 1], table[1]);
		var bits = e.length * BITS;
		var top = (bits + 3) & ~3;
		var r = one;
		var i = top - 4;
		while (i >= 0) {
			for (_ in 0...4)
				r = mul(r, r);
			var w = 0;
			for (k in 0...4) {
				var at = i + 3 - k;
				var limbAt = Std.int(at / BITS);
				w = (w << 1) | (limbAt < e.length ? (e[limbAt] >> (at % BITS)) & 1 : 0);
			}
			if (w != 0) r = mul(r, table[w]);
			i -= 4;
		}
		var o = new Vector<Int>(l, 0);
		o[0] = 1;
		return mul(r, o);
	}
}

// an RSA private key's numbers (big-endian, as PKCS#1's INTEGERs)
typedef RsaKey = {n:Bytes, e:Bytes, d:Bytes, p:Bytes, q:Bytes, dp:Bytes, dq:Bytes, qi:Bytes};
