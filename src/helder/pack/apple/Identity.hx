package helder.pack.apple;

import haxe.io.Bytes;
import helder.pack.android.Der;
import helder.pack.android.P256;
import helder.pack.apple.Rsa.RsaKey;
import helder.pack.ios.Plist;

using StringTools;

// A signing identity from PEM text, as `openssl pkcs12` writes a .p12's
// (Keychain's export of an Apple Distribution or Developer ID certificate):
// the certificates (the signer's, and its chain: Apple's WWDR
// intermediate, Apple's root) and the private key, RSA (PKCS#1 or PKCS#8)
// or ECDSA P-256 (SEC 1 or PKCS#8), unencrypted (openssl pkcs12 -nodes, or
// -noenc). The signer is the certificate of the key; its chain the
// certificates up from it by issuer, as far as they go. Errors are
// messages for the developer.
class Identity {
	public final leaf:Certificate;
	// the leaf first, then each issuer
	public final chain:Array<Certificate>;
	public final key:PrivateKey;

	function new(leaf:Certificate, chain:Array<Certificate>, key:PrivateKey) {
		this.leaf = leaf;
		this.chain = chain;
		this.key = key;
	}

	// certificates: PEM text with one or more CERTIFICATE blocks; key: PEM
	// text with the private key (both may be one text)
	public static function fromPem(certificates:String, key:String):Identity {
		var certs = [for (b in pem(certificates)) if (b.label == "CERTIFICATE") Certificate.parse(b.der)];
		if (certs.length == 0) throw "the certificate: no -----BEGIN CERTIFICATE----- block";
		var k = PrivateKey.fromPem(key);
		var leaf = Lambda.find(certs, c -> k.matches(c));
		if (leaf == null) throw 'the key is not one of the certificates\' (${[for (c in certs) c.commonName].join(", ")}): export the certificate with its private key';
		var chain = [leaf];
		while (!chain[chain.length - 1].selfSigned()) {
			var last = chain[chain.length - 1];
			var issuer = Lambda.find(certs, c -> c.subject.compare(last.issuer) == 0 && !chain.contains(c));
			if (issuer == null) break;
			chain.push(issuer);
		}
		return new Identity(leaf, chain, k);
	}

	// whether the chain reaches its issuer: the leaf self-signed, or its issuer given
	public function complete():Bool
		return chain.length > 1 || leaf.selfSigned();

	// PEM's blocks: each label and its DER
	public static function pem(text:String):Array<{label:String, der:Bytes, headers:Bool}> {
		var out = [], re = ~/-----BEGIN ([A-Z0-9 ]+)-----([\s\S]*?)-----END \1-----/;
		var rest = text.replace("\\n", "\n");
		while (re.match(rest)) {
			var body = re.matched(2), headers = body.indexOf(":") >= 0;
			var lines = [for (l in body.split("\n")) if (l.trim() != "" && l.indexOf(":") < 0) l.trim()];
			out.push({label: re.matched(1), der: haxe.crypto.Base64.decode(lines.join("")), headers: headers});
			rest = re.matchedRight();
		}
		return out;
	}
}

// an X.509 certificate's parts the signature needs
class Certificate {
	public final der:Bytes;
	public final serial:Bytes; // the INTEGER, its TLV
	public final issuer:Bytes; // the Names, their TLVs
	public final subject:Bytes;
	public final commonName:String;
	public final organizationalUnit:Null<String>;
	public final publicKey:Bytes; // the SubjectPublicKeyInfo's BIT STRING's content (without its unused-bits byte)
	public final extensions:Array<String>; // their OIDs, dotted

	function new(der, serial, issuer, subject, cn, ou, key, ext) {
		this.der = der;
		this.serial = serial;
		this.issuer = issuer;
		this.subject = subject;
		this.commonName = cn;
		this.organizationalUnit = ou;
		this.publicKey = key;
		this.extensions = ext;
	}

	public static function parse(der:Bytes):Certificate {
		try {
			var top = Der.read(der, 0);
			var tbs = Der.children(der, Der.children(der, top)[0]);
			var i = tbs[0].tag == 0xa0 ? 1 : 0;
			var tlv = (n:DerNode) -> der.sub(n.at, n.end - n.at);
			var subject = tbs[i + 4];
			var attr = (oid:String) -> {
				var want = Der.oid(oid);
				var found:Null<String> = null;
				for (rdn in Der.children(der, subject))
					for (atv in Der.children(der, rdn)) {
						var p = Der.children(der, atv);
						if (tlv(p[0]).compare(want) == 0) found = der.getString(p[1].start, p[1].end - p[1].start);
					}
				found;
			};
			var spki = Der.children(der, tbs[i + 5]);
			var bits = spki[1];
			var ext = [];
			for (n in tbs.slice(i + 6))
				if (n.tag == 0xa3)
					for (e in Der.children(der, Der.children(der, n)[0])) ext.push(oidString(der, Der.children(der, e)[0]));
			return new Certificate(der, tlv(tbs[i]), tlv(tbs[i + 2]), tlv(subject), attr("2.5.4.3") ?? "", attr("2.5.4.11"),
				der.sub(bits.start + 1, bits.end - bits.start - 1), ext);
		} catch (e:String) {
			throw 'a certificate that is not X.509 ($e)';
		}
	}

	public function selfSigned():Bool
		return issuer.compare(subject) == 0;

	// whether Apple issued it for code signing (an extension of 1.2.840.113635.100.6.1: iPhone or Mac developer or distribution, Developer ID)
	public function apple():Bool
		return Lambda.exists(extensions, e -> e.startsWith("1.2.840.113635.100.6.1."));

	public static function oidString(b:Bytes, n:DerNode):String {
		var parts = [], v = 0;
		for (i in n.start...n.end) {
			var x = b.get(i);
			v = (v << 7) | (x & 0x7f);
			if (x & 0x80 == 0) {
				if (parts.length == 0) {
					var first = v < 80 ? Std.int(v / 40) : 2;
					parts.push(first);
					parts.push(v - 40 * first);
				} else
					parts.push(v);
				v = 0;
			}
		}
		return parts.join(".");
	}
}

// an RSA or ECDSA P-256 private key
class PrivateKey {
	public final rsa:Null<RsaKey>;
	public final ec:Null<Bytes>; // P-256's scalar

	function new(rsa, ec) {
		this.rsa = rsa;
		this.ec = ec;
	}

	public static function fromPem(text:String):PrivateKey {
		for (b in Identity.pem(text)) {
			switch b.label {
				case "ENCRYPTED PRIVATE KEY":
					throw "the private key is encrypted: export it without a passphrase (openssl pkcs12 -in identity.p12 -nodes)";
				case "RSA PRIVATE KEY" | "EC PRIVATE KEY" if (b.headers):
					throw "the private key is encrypted: export it without a passphrase (openssl pkcs12 -in identity.p12 -nodes)";
				case "RSA PRIVATE KEY":
					return new PrivateKey(pkcs1(b.der), null);
				case "EC PRIVATE KEY":
					return new PrivateKey(null, sec1(b.der));
				case "PRIVATE KEY":
					var d = b.der;
					var p = Der.children(d, Der.read(d, 0));
					var alg = Der.children(d, p[1]);
					var inner = d.sub(p[2].start, p[2].end - p[2].start);
					var oid = d.sub(alg[0].at, alg[0].end - alg[0].at);
					if (oid.compare(Der.oid("1.2.840.113549.1.1.1")) == 0) return new PrivateKey(pkcs1(inner), null);
					if (oid.compare(Der.oid("1.2.840.10045.2.1")) == 0) {
						if (alg.length < 2 || d.sub(alg[1].at, alg[1].end - alg[1].at).compare(Der.oid("1.2.840.10045.3.1.7")) != 0)
							throw "the private key: an EC key, not on P-256";
						return new PrivateKey(null, sec1(inner));
					}
					throw "the private key: neither RSA nor EC";
				case _:
			}
		}
		throw "the private key: no -----BEGIN PRIVATE KEY----- block (or RSA PRIVATE KEY, EC PRIVATE KEY)";
	}

	static function int(d:Bytes, n:DerNode):Bytes {
		var s = n.start;
		while (s < n.end - 1 && d.get(s) == 0)
			s++;
		return d.sub(s, n.end - s);
	}

	static function pkcs1(d:Bytes):RsaKey {
		var p = Der.children(d, Der.read(d, 0));
		return {
			n: int(d, p[1]),
			e: int(d, p[2]),
			d: int(d, p[3]),
			p: int(d, p[4]),
			q: int(d, p[5]),
			dp: int(d, p[6]),
			dq: int(d, p[7]),
			qi: int(d, p[8])
		};
	}

	static function sec1(d:Bytes):Bytes {
		var p = Der.children(d, Der.read(d, 0));
		var s = d.sub(p[1].start, p[1].end - p[1].start);
		if (s.length > 32) s = s.sub(s.length - 32, 32);
		if (s.length < 32) {
			var z = Bytes.alloc(32);
			z.blit(32 - s.length, s, 0, s.length);
			s = z;
		}
		if (!P256.validPrivate(s)) throw "the private key: not a P-256 scalar";
		return s;
	}

	// whether the certificate is this key's: RSA's modulus, or P-256's point
	public function matches(c:Certificate):Bool {
		if (ec != null) return c.publicKey.compare(P256.publicKey(ec)) == 0;
		try {
			var k = c.publicKey;
			var p = Der.children(k, Der.read(k, 0));
			return int(k, p[0]).compare(rsa.n) == 0;
		} catch (_:Dynamic) {
			return false;
		}
	}

	// the signature of message (SHA-256): PKCS#1 v1.5, or ECDSA's DER
	public function sign(message:Bytes):Bytes
		return rsa != null ? Rsa.sign(rsa, message) : P256.sign(ec, message);

	// the signature's longest length
	public function signatureLength():Int
		return rsa != null ? Rsa.byteLength(rsa.n) : 72;

	// CMS's signatureAlgorithm: rsaEncryption (NULL), ecdsa-with-SHA256
	public function algorithm():Bytes
		return rsa != null ? Der.seq([Der.oid("1.2.840.113549.1.1.1"), Bytes.ofHex("0500")]) : Der.seq([Der.oid("1.2.840.10045.4.3.2")]);
}

// a provisioning profile (embedded.mobileprovision): a CMS-signed property
// list, read without checking Apple's signature (the device and App Store
// Connect do)
class Profile {
	public final der:Bytes;
	public final name:String;
	public final team:String;
	public final entitlements:Map<String, PValue>;
	public final certificates:Array<Bytes>;
	public final expires:Null<String>;
	public final devices:Bool; // ProvisionedDevices: a development or ad hoc profile, not App Store's
	public final platforms:Array<String>;

	function new(der, name, team, ent, certs, expires, devices, platforms) {
		this.der = der;
		this.name = name;
		this.team = team;
		this.entitlements = ent;
		this.certificates = certs;
		this.expires = expires;
		this.devices = devices;
		this.platforms = platforms;
	}

	public static function parse(der:Bytes):Profile {
		var start = indexOf(der, "<?xml"), end = indexOf(der, "</plist>") + 8;
		if (start < 0 || end < 8) throw "the provisioning profile: no property list in it (a .mobileprovision)";
		var d = switch Plist.parse(der.getString(start, end - start)) {
			case PDict(d): d;
			case _: throw "the provisioning profile: not a dictionary";
		}
		inline function s(k:String):Null<String>
			return switch d.get(k) {
				case PString(v): v;
				case PDate(v): v;
				case _: null;
			}
		var team = switch d.get("TeamIdentifier") {
			case PArray([PString(t)]) | PArray([PString(t), _]): t;
			case _: throw "the provisioning profile: no TeamIdentifier";
		}
		var ent = switch d.get("Entitlements") {
			case PDict(e): e;
			case _: throw "the provisioning profile: no Entitlements";
		}
		var certs = switch d.get("DeveloperCertificates") {
			case PArray(a): [for (c in a) switch c {
					case PData(b): b;
					case _: continue;
				}];
			case _: [];
		}
		var platforms = switch d.get("Platform") {
			case PArray(a): [for (p in a) switch p {
					case PString(v): v;
					case _: continue;
				}];
			case _: [];
		}
		return new Profile(der, s("Name") ?? "", team, ent, certs, s("ExpirationDate"), d.exists("ProvisionedDevices"), platforms);
	}

	static function indexOf(b:Bytes, s:String):Int {
		var n = Bytes.ofString(s);
		for (i in 0...b.length - n.length + 1) {
			var k = 0;
			while (k < n.length && b.get(i + k) == n.get(k))
				k++;
			if (k == n.length) return i;
		}
		return -1;
	}
}
