package helder.pack;

import haxe.io.Bytes;
import helder.pack.android.Der;
import helder.pack.apple.Rsa;
import helder.pack.apple.Rsa.RsaKey;

using StringTools;

// An RSA key's files, for helder setup (helder.cli.Setup), without
// openssl: its private key as PKCS#8 (what openssl writes, and
// helder.pack.apple.Identity reads), a PKCS#10 certificate request
// (RFC 2986: App Store Connect's POST /v1/certificates takes one), a
// self-signed X.509 v3 certificate (Google Play's upload key's), all
// signed sha256WithRSAEncryption; PEM's armour and a certificate's
// fingerprints as the stores print them (SHA-1, SHA-256: AB:CD:...).
class X509 {
	static final NULL = Bytes.ofHex("0500");

	static function rsaEncryption():Bytes
		return Der.seq([Der.oid("1.2.840.113549.1.1.1"), NULL]);

	static function sha256WithRsa():Bytes
		return Der.seq([Der.oid("1.2.840.113549.1.1.11"), NULL]);

	// a Name of attributes in order: CN, O, OU, C (PrintableString), emailAddress
	public static function name(attributes:Array<{type:String, value:String}>):Bytes {
		var oids = ["CN" => "2.5.4.3", "O" => "2.5.4.10", "OU" => "2.5.4.11", "C" => "2.5.4.6", "emailAddress" => "1.2.840.113549.1.9.1"];
		return Der.seq([for (a in attributes) {
			var oid = oids.get(a.type);
			if (oid == null) throw 'X509: no attribute ${a.type}';
			Der.set([Der.seq([Der.oid(oid), a.type == "C" ? Der.printable(a.value) : a.type == "emailAddress" ? Der.tlv(0x16, Bytes.ofString(a.value)) : Der.utf8(a.value)])]);
		}]);
	}

	// the SubjectPublicKeyInfo
	public static function publicKeyInfo(k:RsaKey):Bytes
		return Der.seq([rsaEncryption(), Der.bitString(Der.seq([Der.integer(k.n), Der.integer(k.e)]))]);

	// PKCS#1's RSAPrivateKey in PKCS#8's PrivateKeyInfo
	public static function privateKey(k:RsaKey):Bytes {
		var pkcs1 = Der.seq([
			Der.small(0), Der.integer(k.n), Der.integer(k.e), Der.integer(k.d), Der.integer(k.p), Der.integer(k.q), Der.integer(k.dp), Der.integer(k.dq),
			Der.integer(k.qi)
		]);
		return Der.seq([Der.small(0), rsaEncryption(), Der.tlv(0x04, pkcs1)]);
	}

	// a certificate request of the key for subject (no attributes)
	public static function request(k:RsaKey, subject:Bytes):Bytes {
		var info = Der.seq([Der.small(0), subject, publicKeyInfo(k), Bytes.ofHex("a000")]);
		return Der.seq([info, sha256WithRsa(), Der.bitString(Rsa.sign(k, info))]);
	}

	// a self-signed certificate of the key, from until years later (serial: positive)
	public static function selfSigned(k:RsaKey, subject:Bytes, serial:Bytes, from:Date, years:Int):Bytes {
		var until = new Date(from.getFullYear() + years, from.getMonth(), from.getDate(), from.getHours(), from.getMinutes(), from.getSeconds());
		var tbs = Der.seq([
			Der.explicit(0, Der.small(2)), Der.integer(serial), sha256WithRsa(), subject, Der.seq([Der.time(from), Der.time(until)]), subject, publicKeyInfo(k)
		]);
		return Der.seq([tbs, sha256WithRsa(), Der.bitString(Rsa.sign(k, tbs))]);
	}

	public static function pem(label:String, der:Bytes):String {
		var b = haxe.crypto.Base64.encode(der), lines = [];
		var i = 0;
		while (i < b.length) {
			lines.push(b.substr(i, 64));
			i += 64;
		}
		return '-----BEGIN $label-----\n${lines.join("\n")}\n-----END $label-----\n';
	}

	// "AB:CD:...": SHA-1's or SHA-256's of the DER
	public static function fingerprint(der:Bytes, sha256:Bool):String {
		var h = (sha256 ? haxe.crypto.Sha256.make(der) : haxe.crypto.Sha1.make(der)).toHex().toUpperCase();
		return [for (i in 0...(h.length >> 1)) h.substr(2 * i, 2)].join(":");
	}
}
