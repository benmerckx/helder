package helder.pack;

import haxe.io.Bytes;
import helder.pack.android.Der;

// RFC 3161's time-stamp protocol, what a signature needs to outlive its
// certificate (Authenticode's) or to be notarised (Apple's code signature):
// the request for a signature's bytes (a TimeStampReq: their SHA-256, a
// nonce, the TSA's certificate asked for), sent by the caller (helder.cli:
// curl, application/timestamp-query) to a time-stamping authority
// (timestamp.apple.com/ts01, a code signing CA's), and its reply's token
// (TimeStampResp's timeStampToken: a CMS SignedData), which the signature
// carries as an unsigned attribute.
class Timestamp {
	// the request (DER) for the signature's bytes
	public static function request(signature:Bytes, ?nonce:Bytes):Bytes {
		var n = nonce ?? Entropy.bytes(8);
		return Der.seq([
			Der.small(1),
			Der.seq([Der.seq([Der.oid("2.16.840.1.101.3.4.2.1"), Bytes.ofHex("0500")]), Der.tlv(0x04, haxe.crypto.Sha256.make(signature))]),
			Der.integer(n),
			Der.tlv(0x01, Bytes.ofHex("ff"))
		]);
	}

	// the reply's token (its DER), or the TSA's refusal thrown
	public static function token(reply:Bytes):Bytes {
		var top = try Der.read(reply, 0) catch (e:Dynamic) throw 'the time-stamp reply is not DER ($e)';
		var parts = Der.children(reply, top);
		if (parts.length == 0) throw "the time-stamp reply is empty";
		var status = Der.children(reply, parts[0]);
		var code = status.length == 0 ? -1 : reply.get(status[0].end - 1);
		// (0 granted, 1 granted with modifications)
		if (code != 0 && code != 1 || parts.length < 2) throw 'the time-stamping authority refused: status $code';
		return reply.sub(parts[1].at, parts[1].end - parts[1].at);
	}
}
