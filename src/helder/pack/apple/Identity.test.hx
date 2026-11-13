package helder.pack.apple;

import helder.pack.apple.Identity.PrivateKey;
import helder.test.Test;

// A signing identity's PEM as people paste it (Identity.pem: a .p8 or a key
// on one line, "\n" written for its newlines, CRLF, its armour lost) and a
// chain completed with Apple's WWDR intermediate when the PEM has the leaf
// alone (Wwdr). The leaf here is a stand-in: a P-256 key's certificate
// signed by a throwaway CA named as WWDR G3, so its issuer's Name is G3's,
// byte for byte; nothing here checks the signature.
function tests() {
	final leaf = "-----BEGIN CERTIFICATE-----
MIICRTCCAeugAwIBAgIUJnb7zO07LIlCHvWjHgF+IfS6/vowCgYIKoZIzj0EAwIw
dTFEMEIGA1UEAww7QXBwbGUgV29ybGR3aWRlIERldmVsb3BlciBSZWxhdGlvbnMg
Q2VydGlmaWNhdGlvbiBBdXRob3JpdHkxCzAJBgNVBAsMAkczMRMwEQYDVQQKDApB
cHBsZSBJbmMuMQswCQYDVQQGEwJVUzAeFw0yNjExMTMxNTMwMjFaFw0zNjExMTAx
NTMwMjFaMIGLMRowGAYKCZImiZPyLGQBAQwKVEVBTUlEMTIzNDE1MDMGA1UEAwws
QXBwbGUgRGlzdHJpYnV0aW9uOiBMaXR0bGUgVGVzdCAoVEVBTUlEMTIzNCkxEzAR
BgNVBAsMClRFQU1JRDEyMzQxFDASBgNVBAoMC0xpdHRsZSBUZXN0MQswCQYDVQQG
EwJVUzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABAsYh0OS72yB4arxjwzy6w22
J2pji0eEKbt4UoywKgJOZX/DuCMA0wky3pViPbR6e9KNSZBnXKJOgpl02PuZ/O6j
QjBAMB0GA1UdDgQWBBSE5xhkl7Vtmmwmz89ufqaynYVv3TAfBgNVHSMEGDAWgBRK
itWTWeAOjJj9OKsQxS78QySg+jAKBggqhkjOPQQDAgNIADBFAiAO/5IhTxyhoskq
m9Evvru8yXU2r51pr4HnyjnT2YtBTAIhAJrk9X8jkgXg89asG5Q3JZ4Gv01wvqt8
dnwzfQ4/hszD
-----END CERTIFICATE-----";
	final key = "-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgq0OGUVPoYffjjwHE
G9xQPWU7UwKK7IvoAfXEGRpjfkKhRANCAAQLGIdDku9sgeGq8Y8M8usNtidqY4tH
hCm7eFKMsCoCTmV/w7gjANMJMt6VYj20envSjUmQZ1yiToKZdNj7mfzu
-----END PRIVATE KEY-----";

	test("a key pasted on one line, with \\n for its newlines, with CRLF or without its armour: the same key", () -> {
		var lines = key.split("\n");
		var head = lines[0], tail = lines[lines.length - 1], body = lines.slice(1, lines.length - 1);
		var expected = PrivateKey.fromPem(key).ec.toHex();
		for (text in [
			head + " " + body.join(" ") + " " + tail,
			head + body.join("") + tail,
			lines.join("\\n"),
			lines.join("\r\n"),
			body.join(""),
			body.join(" ")
		])
			equals(PrivateKey.fromPem(text).ec.toHex(), expected);
		equals(Std.string(throws(() -> PrivateKey.fromPem("not a key"))), "the private key: no -----BEGIN PRIVATE KEY----- block (or RSA PRIVATE KEY, EC PRIVATE KEY)");
	});

	test("the leaf alone: its chain completed with Apple's WWDR G3, which issued it", () -> {
		var id = Identity.fromPem(leaf, key);
		equals(id.chain.length, 2);
		equals([id.chain[1].commonName, id.chain[1].organizationalUnit], ["Apple Worldwide Developer Relations Certification Authority", "G3"]);
		assert(id.complete(), "complete");
		// (G3 and G4, Apple's own, each issued by Apple's root)
		equals([for (c in Wwdr.all()) c.organizationalUnit], ["G3", "G4"]);
		equals(Wwdr.issuerOf(id.leaf.subject), null);
	});
}
