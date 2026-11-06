package helder.pack.windows;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.pack.android.Der;
import helder.pack.apple.Identity;

// A Windows executable's Authenticode signature, as signtool (or
// osslsigncode) writes one, without them: the PE image's SHA-256 (the file
// without its checksum, the certificate table's directory entry and the
// table itself), in an SpcIndirectDataContent (SPC_PE_IMAGE_DATAOBJ), signed
// as a CMS SignedData by a code signing certificate's key (RSA PKCS#1 v1.5
// or ECDSA P-256: Identity's) with its chain, the signed attributes
// signtool writes (the content type, an empty SpcSpOpusInfo, the statement
// type: individual, the message digest), and optionally an RFC 3161
// timestamp's token as an unsigned attribute (Timestamp: the signature
// outlives its certificate); appended as a WIN_CERTIFICATE (revision 2,
// PKCS_SIGNED_DATA), the security directory pointing at it, the checksum
// written again. Microsoft's "Windows Authenticode Portable Executable
// Signature Format" describes it; checked by osslsigncode verify in the
// pack lane.
class Authenticode {
	static inline var SPC_INDIRECT_DATA = "1.3.6.1.4.1.311.2.1.4";
	static inline var SPC_PE_IMAGE_DATA = "1.3.6.1.4.1.311.2.1.15";
	static inline var SPC_SP_OPUS_INFO = "1.3.6.1.4.1.311.2.1.12";
	static inline var SPC_STATEMENT_TYPE = "1.3.6.1.4.1.311.2.1.11";
	static inline var SPC_INDIVIDUAL = "1.3.6.1.4.1.311.2.1.21";
	static inline var TIMESTAMP_TOKEN = "1.3.6.1.4.1.311.3.3.1";

	// exe signed (an unsigned one: a signed one's signature is replaced);
	// timestamp: the signature's bytes to an RFC 3161 TimeStampToken (DER),
	// null for none
	public static function sign(exe:Bytes, id:Identity, ?timestamp:Bytes->Bytes):Bytes {
		var p = new Pe(exe);
		var old = p.certificates();
		// (an earlier signature: the file without it)
		var image = old.size > 0 && old.at + old.size == exe.length ? exe.sub(0, old.at) : exe.sub(0, exe.length);
		if (old.size > 0) {
			image.setInt32(p.directoryAt(4), 0);
			image.setInt32(p.directoryAt(4) + 4, 0);
		}
		// (the table starts 8-byte aligned: the file padded first, the padding hashed)
		var padded = Pe.align(image.length, 8);
		if (padded != image.length) {
			var b = Bytes.alloc(padded);
			b.fill(0, padded, 0);
			b.blit(0, image, 0, image.length);
			image = b;
		}
		var digest = hash(image, p);
		var content = indirectData(digest);
		var cms = signedData(content, id, timestamp);
		var length = 8 + cms.length, size = Pe.align(length, 8);
		var out = Bytes.alloc(image.length + size);
		out.fill(0, out.length, 0);
		out.blit(0, image, 0, image.length);
		out.setInt32(image.length, length);
		out.setUInt16(image.length + 4, 0x0200);
		out.setUInt16(image.length + 6, 0x0002);
		out.blit(image.length + 8, cms, 0, cms.length);
		out.setInt32(p.directoryAt(4), image.length);
		out.setInt32(p.directoryAt(4) + 4, size);
		return Pe.withChecksum(out);
	}

	// the image's Authenticode SHA-256 (the file up to the certificate
	// table, without the checksum and the security directory's entry)
	public static function hash(image:Bytes, p:Pe):Bytes {
		var c = p.checksumAt, d = p.directoryAt(4);
		var cert = p.certificates();
		var end = cert.size > 0 ? cert.at : image.length;
		var b = new BytesBuffer();
		b.addBytes(image, 0, c);
		b.addBytes(image, c + 4, d - (c + 4));
		b.addBytes(image, d + 8, end - (d + 8));
		return haxe.crypto.Sha256.make(b.getBytes());
	}

	// SpcIndirectDataContent: the PE image data (no flags, an obsolete file link) and the digest
	public static function indirectData(digest:Bytes):Bytes {
		var obsolete = Bytes.alloc(28);
		var s = "<<<Obsolete>>>";
		for (i in 0...s.length) {
			obsolete.set(2 * i, 0);
			obsolete.set(2 * i + 1, StringTools.fastCodeAt(s, i));
		}
		var peData = Der.seq([Der.tlv(0x03, Bytes.ofHex("00")), Der.tlv(0xa0, Der.tlv(0xa2, Der.tlv(0x80, obsolete)))]);
		return Der.seq([
			Der.seq([Der.oid(SPC_PE_IMAGE_DATA), peData]),
			Der.seq([Der.seq([Der.oid("2.16.840.1.101.3.4.2.1"), Bytes.ofHex("0500")]), Der.tlv(0x04, digest)])
		]);
	}

	static function attr(oid:String, values:Array<Bytes>):Bytes
		return Der.seq([Der.oid(oid), Der.set(values)]);

	static function cat(parts:Array<Bytes>):Bytes {
		var b = new BytesBuffer();
		for (x in parts)
			b.add(x);
		return b.getBytes();
	}

	// (a TLV's content: past its tag and length)
	static function inner(tlv:Bytes):Bytes {
		var n = Der.read(tlv, 0);
		return tlv.sub(n.start, n.end - n.start);
	}

	public static function signedData(content:Bytes, id:Identity, ?timestamp:Bytes->Bytes):Bytes {
		var sha256 = Der.seq([Der.oid("2.16.840.1.101.3.4.2.1"), Bytes.ofHex("0500")]);
		// (the message digest: of the content's value, without its SEQUENCE's tag and length)
		var attrs = [
			attr("1.2.840.113549.1.9.3", [Der.oid(SPC_INDIRECT_DATA)]),
			attr(SPC_SP_OPUS_INFO, [Der.seq([])]),
			attr(SPC_STATEMENT_TYPE, [Der.seq([Der.oid(SPC_INDIVIDUAL)])]),
			attr("1.2.840.113549.1.9.4", [Der.tlv(0x04, haxe.crypto.Sha256.make(inner(content)))])
		];
		attrs.sort((a, b) -> a.compare(b));
		var signed = cat(attrs);
		var signature = id.key.sign(Der.tlv(0x31, signed));
		var leaf = id.leaf;
		var signer = [
			Der.small(1),
			Der.seq([leaf.issuer, leaf.serial]),
			sha256,
			Der.tlv(0xa0, signed),
			id.key.algorithm(),
			Der.tlv(0x04, signature)
		];
		if (timestamp != null) signer.push(Der.tlv(0xa1, attr(TIMESTAMP_TOKEN, [timestamp(signature)])));
		var data = Der.seq([
			Der.small(1),
			Der.set([sha256]),
			Der.seq([Der.oid(SPC_INDIRECT_DATA), Der.tlv(0xa0, content)]),
			Der.tlv(0xa0, cat([for (c in id.chain) c.der])),
			Der.set([Der.seq(signer)])
		]);
		return Der.seq([Der.oid("1.2.840.113549.1.7.2"), Der.tlv(0xa0, data)]);
	}
}
