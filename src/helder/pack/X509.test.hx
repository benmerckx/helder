package helder.pack;

import haxe.io.Bytes;
import helder.pack.android.Der;
import helder.pack.apple.Identity;
import helder.pack.apple.Rsa;
import helder.test.Test;

// helder setup's keys: an RSA key made here (Rsa.generate: its numbers
// agree, it signs and verifies), written as PKCS#8 and read back by
// Identity, a certificate request and a self-signed certificate of it
// (X509) that parse as X.509 does; Miller-Rabin on known numbers. (Their
// signatures are checked by node's crypto too, in tests/pack/publish.mjs.)
function tests() {
	test("Miller-Rabin: a Mersenne prime is prime, Fermat's seventh number is not", () -> {
		assert(Rsa.probablyPrime(Rsa.fromBytes(Bytes.ofHex("7fffffffffffffffffffffffffffffff")), 12, Entropy.bytes), "2^127 - 1");
		assert(!Rsa.probablyPrime(Rsa.fromBytes(Bytes.ofHex("0100000000000000000000000000000001")), 12, Entropy.bytes), "2^128 + 1");
	});

	test("a new key: n of 1024 bits, e 65537, signs and verifies; PKCS#8 read back the same", () -> {
		var k = Rsa.generate(1024);
		equals(k.n.length, 128);
		equals(k.e.toHex(), "010001");
		var msg = Bytes.ofString("helder setup");
		var sig = Rsa.sign(k, msg);
		assert(Rsa.verify(k.n, k.e, msg, sig), "verifies");
		var back = PrivateKey.fromPem(X509.pem("PRIVATE KEY", X509.privateKey(k)));
		equals([back.rsa.n.toHex(), back.rsa.d.toHex(), back.rsa.qi.toHex()], [k.n.toHex(), k.d.toHex(), k.qi.toHex()]);
	});

	test("a self-signed certificate: its key's, its subject its issuer; an identity of one PEM", () -> {
		var k = Rsa.generate(1024);
		var subject = X509.name([{type: "CN", value: "Little Skies upload key"}, {type: "O", value: "Little Skies"}]);
		var der = X509.selfSigned(k, subject, Bytes.ofHex("0102030405060708"), new Date(2026, 10, 13, 12, 0, 0), 30);
		var c = Certificate.parse(der);
		assert(c.selfSigned(), "self-signed");
		equals(c.commonName, "Little Skies upload key");
		var id = Identity.fromPem(X509.pem("CERTIFICATE", der) + X509.pem("PRIVATE KEY", X509.privateKey(k)), X509.pem("PRIVATE KEY", X509.privateKey(k)));
		assert(id.complete(), "complete");
		// (the signature over the TBSCertificate, by the key)
		var top = Der.children(der, Der.read(der, 0));
		var tbs = der.sub(top[0].at, top[0].end - top[0].at);
		assert(Rsa.verify(k.n, k.e, tbs, der.sub(top[2].start + 1, top[2].end - top[2].start - 1)), "signature");
		equals(X509.fingerprint(Bytes.ofString("abc"), false), "A9:99:3E:36:47:06:81:6A:BA:3E:25:71:78:50:C2:6C:9C:D0:D8:9D");
	});

	test("a certificate request: version 0, the subject, the key, its signature", () -> {
		var k = Rsa.generate(1024);
		var der = X509.request(k, X509.name([{type: "CN", value: "Distribution"}, {type: "C", value: "BE"}]));
		var top = Der.children(der, Der.read(der, 0));
		var info = Der.children(der, top[0]);
		equals([info.length, der.get(info[0].start), info[3].tag], [4, 0, 0xa0]);
		var signed = der.sub(top[0].at, top[0].end - top[0].at);
		assert(Rsa.verify(k.n, k.e, signed, der.sub(top[2].start + 1, top[2].end - top[2].start - 1)), "signature");
	});
}
