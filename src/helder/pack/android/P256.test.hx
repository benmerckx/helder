package helder.pack.android;

import haxe.io.Bytes;
import helder.test.Test;

// ECDSA P-256 with SHA-256 (P256) against RFC 6979's vectors (A.2.5: the
// key, and the deterministic signatures of "sample" and "test")
function tests() {
	final d = Bytes.ofHex("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721");

	test("RFC 6979 A.2.5: the public key", () -> {
		equals(P256.publicKey(d).toHex(),
			"0460fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb67903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299");
	});
	test("RFC 6979 A.2.5: the signature of \"sample\" (SHA-256)", () -> {
		equals(P256.sign(d, Bytes.ofString("sample")).toHex(),
			"3046022100efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716022100f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8");
	});
	test("RFC 6979 A.2.5: the signature of \"test\" (SHA-256; s under 2^255: no 0 before it)", () -> {
		equals(P256.sign(d, Bytes.ofString("test")).toHex(),
			"3045022100f1abb023518351cd71d881567b1ea663ed3efcf6c5132b354f28d3b0b7d383670220019f4113742a2b14bd25926b49c649155f267e60d3814b4c0cc84250e46f0083");
	});
	test("deterministic: the same message signs the same way", () -> {
		equals(P256.sign(d, Bytes.ofString("again")).toHex(), P256.sign(d, Bytes.ofString("again")).toHex());
	});
	test("a private scalar: 1 <= d < n, 32 bytes", () -> {
		assert(P256.validPrivate(d));
		assert(!P256.validPrivate(Bytes.alloc(32)));
		assert(!P256.validPrivate(Bytes.ofHex("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551")));
		assert(P256.validPrivate(Bytes.ofHex("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550")));
		assert(!P256.validPrivate(Bytes.ofHex("01")));
	});
}
