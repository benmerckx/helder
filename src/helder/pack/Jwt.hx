package helder.pack;

import haxe.io.Bytes;
import helder.pack.android.Der;

// JSON Web Tokens (RFC 7519) signed the two ways the stores' APIs take:
// RS256 (Google's service accounts: RSA PKCS#1 v1.5, helder.pack.apple.Rsa)
// and ES256 (App Store Connect's .p8 keys: P-256, its signature as r and s,
// 32 bytes each, not DER). The claims as given, in order.
class Jwt {
	public static function sign(header:Dynamic, claims:Dynamic, key:helder.pack.apple.Identity.PrivateKey):String {
		var input = b64url(Bytes.ofString(haxe.Json.stringify(header))) + "." + b64url(Bytes.ofString(haxe.Json.stringify(claims)));
		var sig = key.sign(Bytes.ofString(input));
		if (key.ec != null) sig = raw(sig);
		return input + "." + b64url(sig);
	}

	// ECDSA's DER (SEQUENCE { r, s }) as JWS's r || s
	public static function raw(der:Bytes):Bytes {
		var p = Der.children(der, Der.read(der, 0));
		var out = Bytes.alloc(64);
		for (k in 0...2) {
			var n = p[k], s = n.start;
			while (n.end - s > 32)
				s++;
			out.blit(32 * (k + 1) - (n.end - s), der, s, n.end - s);
		}
		return out;
	}

	public static function b64url(b:Bytes):String
		return StringTools.replace(StringTools.replace(haxe.crypto.Base64.encode(b, false), "+", "-"), "/", "_");
}
