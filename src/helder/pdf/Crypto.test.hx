package helder.pdf;

import haxe.io.Bytes;
import helder.test.Test;

// helder.pdf's crypto against the standards' vectors (the test lane):
// AES-128 and AES-256 (FIPS 197's appendix C), RC4, SHA-384 and SHA-512
// (FIPS 180's "abc"); its lexer on hostile input ending in PdfErrors
function tests() {
	describe("pdf Crypto", () -> {
		test("AES decrypts FIPS 197's vectors (one block, CBC with a zero IV)", () -> {
			var plain = "00112233445566778899aabbccddeeff";
			var c128 = Crypto.aesCbc(Bytes.ofHex("000102030405060708090a0b0c0d0e0f"), Bytes.alloc(16), Bytes.ofHex("69c4e0d86a7b0430d8cdb78070b4c55a"), false);
			equals(c128.toHex(), plain);
			var c256 = Crypto.aesCbc(Bytes.ofHex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"), Bytes.alloc(16),
				Bytes.ofHex("8ea2b7ca516745bfeafc49904b496089"), false);
			equals(c256.toHex(), plain);
		});
		test("RC4, SHA-384, SHA-512", () -> {
			equals(Crypto.rc4(Bytes.ofString("Key"), Bytes.ofString("Plaintext")).toHex(), "bbf316e8d940af0ad3");
			equals(Crypto.Sha512.make(Bytes.ofString("abc"), false).toHex().substr(0, 32), "ddaf35a193617abacc417349ae204131");
			equals(Crypto.Sha512.make(Bytes.ofString("abc"), true).toHex().substr(0, 32), "cb00753f45a35e8bb5a03d699ac65007");
		});
		test("a document that is none: a PdfError", () -> {
			// (a catalog without pages: a document of none)
			equals(Pdf.open(Bytes.ofString("%PDF-1.7\n1 0 obj << /Type /Catalog >> endobj")).pages.length, 0);
			for (s in ["", "%PDF-1.4", "%PDF-1.7\nxref\n0 99999999999\ntrailer << >>\nstartxref\n9\n%%EOF"]) {
				var kind = try {
					Pdf.open(Bytes.ofString(s));
					"opened";
				} catch (e:PdfError) "error";
				equals(kind, "error");
			}
		});
	});
}
