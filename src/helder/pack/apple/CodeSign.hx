package helder.pack.apple;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.pack.android.Der;
import helder.pack.apple.Identity;
import helder.pack.ios.Plist;

using StringTools;

// A Mach-O executable's code signature by a certificate, as codesign (or
// rcodesign, without Apple's tools) writes one for an app bundle signed
// for distribution: the executable's ad hoc signature (hxmc's, at the end
// of __LINKEDIT) replaced by a SuperBlob (big-endian) of
//   - the CodeDirectory (slot 0; version 0x20400, 0x20500 with the hardened
//     runtime): the identifier (the bundle id), the team id, the SHA-256
//     of each 4 KB page up to the signature, and the "special slots"
//     before them: the hashes of the bundle's Info.plist (1), the
//     requirements (2), _CodeSignature/CodeResources (3), the entitlements
//     (5) and their DER form (7);
//   - the requirements (2): the designated requirement, codesign's for the
//     certificate (Apple's: anchor apple generic, the leaf's common name,
//     WWDR's intermediate; Developer ID's; another's: its root's hash);
//   - the entitlements as XML (5) and as DER (7, CoreEntitlements' form:
//     [APPLICATION 16] { INTEGER 1, the dictionary as [CONTEXT 16] }, its
//     keys sorted);
//   - the CMS signature (0x10000): SignedData, detached, over the
//     CodeDirectory, with the chain's certificates and Apple's signed
//     attributes (1.2.840.113635.100.9.1: a plist of the cdhashes, the
//     CodeDirectory's SHA-256 truncated to 20 bytes; .2: the full hash with
//     its algorithm), signed with the identity's RSA or P-256 key.
// The load commands follow: LC_CODE_SIGNATURE's size, __LINKEDIT's, and
// LC_BUILD_VERSION's SDK (the SDK App Store validation asks for: hxmc links
// against none). The formats as Apple's Security framework documents them
// (cs_blobs.h, requirement.h) and as apple-codesign (rcodesign, MPL-2.0;
// https://github.com/indygreg/apple-platform-rs) describes them: written
// from those descriptions, no code taken. No timestamp (App Store and
// TestFlight do not need one; notarisation would).
class CodeSign {
	static inline var PAGE = 4096;
	public static inline var CS_RUNTIME = 0x10000;

	// the signed executable (exe: hxmc's, signed ad hoc)
	public static function sign(exe:Bytes, o:SignOptions):Bytes {
		var m = MachO.parse(exe);
		var codeLimit = m.sigOff;
		var team = o.team ?? o.identity.leaf.organizationalUnit;
		var reqs = requirements(designated(o.identifier, o.identity));
		var ent = o.entitlements == null ? null : blob(0xfade7171, entitlementsXml(o.entitlements));
		var der = o.entitlements == null ? null : blob(0xfade7172, entitlementsDer(o.entitlements));
		var time = o.time ?? Date.now();
		var pages = (codeLimit + PAGE - 1) >> 12;
		var header = o.runtime != null ? 96 : 88;
		var nSpecial = der != null ? 7 : 3;
		var ident = Bytes.ofString(o.identifier), teamB = team == null ? null : Bytes.ofString(team);
		var cdLen = header + ident.length + 1 + (teamB == null ? 0 : teamB.length + 1) + 32 * (nSpecial + pages);
		var others = [{slot: 2, data: reqs}];
		if (ent != null) others.push({slot: 5, data: ent});
		if (der != null) others.push({slot: 7, data: der});
		// (the CMS's length: built with a stand-in digest and signature)
		var cmsMax = cms(Bytes.alloc(cdLen), o.identity, time, (_) -> Bytes.alloc(o.identity.key.signatureLength())).length + 8 + 16;
		var count = 2 + others.length;
		var size = 12 + 8 * count + cdLen + cmsMax;
		for (x in others)
			size += x.data.length;
		size = (size + 15) & ~15;
		// (the load commands for the new size, the SDK; then the pages hashed)
		var out = Bytes.alloc(codeLimit + size);
		out.blit(0, exe, 0, codeLimit);
		m.resize(out, size);
		if (o.sdk != null) m.setSdk(out, o.sdk);

		var get = o.entitlements == null ? false : Type.enumEq(o.entitlements.get("get-task-allow"), PBool(true));
		var cd = new Be();
		cd.u32(0xfade0c02);
		cd.u32(cdLen);
		cd.u32(o.runtime != null ? 0x20500 : 0x20400);
		cd.u32(o.runtime != null ? CS_RUNTIME : 0);
		var identOff = header, teamOff = teamB == null ? 0 : header + ident.length + 1;
		var hashOff = header + ident.length + 1 + (teamB == null ? 0 : teamB.length + 1) + 32 * nSpecial;
		cd.u32(hashOff);
		cd.u32(identOff);
		cd.u32(nSpecial);
		cd.u32(pages);
		cd.u32(codeLimit);
		cd.u8(32);
		cd.u8(2); // SHA-256
		cd.u8(0);
		cd.u8(12);
		cd.u32(0);
		cd.u32(0); // scatter
		cd.u32(teamOff);
		cd.u32(0);
		cd.u64(0); // codeLimit64
		cd.u64(m.textOff);
		cd.u64(m.textSize);
		// (CS_EXECSEG_MAIN_BINARY; CS_EXECSEG_ALLOW_UNSIGNED with get-task-allow, as codesign)
		cd.u64(1 | (get ? 0x10 : 0));
		if (o.runtime != null) {
			cd.u32(o.runtime);
			cd.u32(0);
		}
		cd.bytes(ident);
		cd.u8(0);
		if (teamB != null) {
			cd.bytes(teamB);
			cd.u8(0);
		}
		var special = new Map<Int, Bytes>();
		if (o.infoPlist != null) special.set(1, o.infoPlist);
		if (o.resources != null) special.set(3, o.resources);
		for (x in others)
			special.set(x.slot, x.data);
		var k = nSpecial;
		while (k >= 1) {
			var d = special.get(k);
			if (d == null) cd.zeros(32) else cd.bytes(haxe.crypto.Sha256.make(d));
			k--;
		}
		for (p in 0...pages) {
			var off = p << 12;
			cd.bytes(haxe.crypto.Sha256.make(out.sub(off, codeLimit - off < PAGE ? codeLimit - off : PAGE)));
		}
		var cdBlob = cd.toBytes();
		if (cdBlob.length != cdLen) throw "CodeSign: the CodeDirectory's length";
		var sig = blob(0xfade0b01, cms(cdBlob, o.identity, time, o.identity.key.sign));
		var blobs = [{slot: 0, data: cdBlob}].concat(others).concat([{slot: 0x10000, data: sig}]);
		var sb = new Be();
		var total = 12 + 8 * blobs.length;
		for (x in blobs)
			total += x.data.length;
		if (total > size) throw "CodeSign: the signature outgrew its room";
		sb.u32(0xfade0cc0);
		sb.u32(total);
		sb.u32(blobs.length);
		var at = 12 + 8 * blobs.length;
		for (x in blobs) {
			sb.u32(x.slot);
			sb.u32(at);
			at += x.data.length;
		}
		for (x in blobs)
			sb.bytes(x.data);
		var s = sb.toBytes();
		out.blit(codeLimit, s, 0, s.length);
		return out;
	}

	// the CodeDirectory's hash (cdhash) of a signed executable, its full SHA-256
	public static function cdhash(signed:Bytes):Bytes {
		var m = MachO.parse(signed), at = m.sigOff;
		for (k in 0...be32(signed, at + 8))
			if (be32(signed, at + 12 + 8 * k) == 0) {
				var cd = at + be32(signed, at + 16 + 8 * k);
				return haxe.crypto.Sha256.make(signed.sub(cd, be32(signed, cd + 4)));
			}
		throw "no CodeDirectory";
	}

	static function blob(magic:Int, data:Bytes):Bytes {
		var b = new Be();
		b.u32(magic);
		b.u32(8 + data.length);
		b.bytes(data);
		return b.toBytes();
	}

	// ---- the designated requirement (requirement.h's expression form)

	static inline var OP_IDENT = 2;
	static inline var OP_ANCHOR_HASH = 4;
	static inline var OP_AND = 6;
	static inline var OP_CERT_FIELD = 11;
	static inline var OP_CERT_GENERIC = 14;
	static inline var OP_APPLE_GENERIC_ANCHOR = 15;
	static inline var MATCH_EXISTS = 0;
	static inline var MATCH_EQUAL = 1;

	// codesign's designated requirement for the identity's certificate, as text and as the expression
	public static function designated(identifier:String, id:Identity):{text:String, expr:Bytes} {
		var leaf = id.leaf;
		var parts:Array<{text:String, expr:Bytes}> = [
			{text: 'identifier "$identifier"', expr: op(OP_IDENT, [data(Bytes.ofString(identifier))])}
		];
		inline function generic(slot:Int, oid:String, label:String)
			parts.push({text: 'certificate $label[field.$oid] /* exists */', expr: op(OP_CERT_GENERIC, [int(slot), data(oidContent(oid)), int(MATCH_EXISTS)])});
		inline function field(slot:Int, name:String, value:String, label:String)
			parts.push({
				text: 'certificate $label[$name] = "$value"',
				expr: op(OP_CERT_FIELD, [int(slot), data(Bytes.ofString(name)), int(MATCH_EQUAL), data(Bytes.ofString(value))])
			});
		if (leaf.apple()) {
			parts.push({text: "anchor apple generic", expr: op(OP_APPLE_GENERIC_ANCHOR, [])});
			if (leaf.extensions.contains("1.2.840.113635.100.6.1.13")) {
				// (Developer ID: its intermediate, the leaf's extension, the team)
				generic(1, "1.2.840.113635.100.6.2.6", "1");
				generic(0, "1.2.840.113635.100.6.1.13", "leaf");
				field(0, "subject.OU", leaf.organizationalUnit ?? "", "leaf");
			} else {
				field(0, "subject.CN", leaf.commonName, "leaf");
				generic(1, "1.2.840.113635.100.6.2.1", "1");
			}
		} else {
			// (another's certificate: its root's SHA-1, else the leaf's)
			var root = id.chain[id.chain.length - 1];
			var top = root.selfSigned() ? root : leaf;
			var h = haxe.crypto.Sha1.make(top.der);
			var slot = root.selfSigned() ? -1 : 0;
			parts.push({text: 'certificate ${slot == -1 ? "root" : "leaf"} = H"${h.toHex()}"', expr: op(OP_ANCHOR_HASH, [int(slot), data(h)])});
		}
		var expr = parts[0].expr;
		for (p in parts.slice(1))
			expr = cat([int(OP_AND), expr, p.expr]);
		return {text: [for (p in parts) p.text].join(" and "), expr: expr};
	}

	// the requirement set (CSMAGIC_REQUIREMENTS) of one designated requirement (CSMAGIC_REQUIREMENT, expression form)
	public static function requirements(dr:{text:String, expr:Bytes}):Bytes {
		var r = new Be();
		r.u32(0xfade0c00);
		r.u32(12 + dr.expr.length);
		r.u32(1);
		r.bytes(dr.expr);
		var req = r.toBytes();
		var s = new Be();
		s.u32(0xfade0c01);
		s.u32(20 + req.length);
		s.u32(1);
		s.u32(3); // kSecDesignatedRequirementType
		s.u32(20);
		s.bytes(req);
		return s.toBytes();
	}

	static function op(code:Int, args:Array<Bytes>):Bytes
		return cat([int(code)].concat(args));

	static function int(v:Int):Bytes {
		var b = new Be();
		b.u32(v);
		return b.toBytes();
	}

	// a length, the bytes, zeros to 4
	static function data(d:Bytes):Bytes {
		var b = new Be();
		b.u32(d.length);
		b.bytes(d);
		while (b.len() % 4 != 0)
			b.u8(0);
		return b.toBytes();
	}

	static function oidContent(oid:String):Bytes {
		var t = Der.oid(oid);
		return t.sub(2, t.length - 2);
	}

	static function cat(parts:Array<Bytes>):Bytes {
		var b = new BytesBuffer();
		for (p in parts)
			b.add(p);
		return b.getBytes();
	}

	// ---- entitlements

	public static function entitlementsXml(e:Map<String, PValue>):Bytes
		return Plist.xml(PDict(e));

	// CoreEntitlements' DER: [APPLICATION 16] { INTEGER 1, [CONTEXT 16] { SEQUENCE { UTF8String key, value } ... } }
	public static function entitlementsDer(e:Map<String, PValue>):Bytes
		return Der.tlv(0x70, cat([Der.small(1), derValue(PDict(e))]));

	static function derValue(v:PValue):Bytes
		return switch v {
			case PString(s): Der.utf8(s);
			case PBool(b): Der.tlv(0x01, Bytes.ofHex(b ? "ff" : "00"));
			case PInt(i):
				if (i < 0) throw "entitlements: a negative integer";
				Der.small(i);
			case PData(d): Der.tlv(0x04, d);
			case PArray(a): Der.seq([for (x in a) derValue(x)]);
			case PDict(d):
				var keys = [for (k in d.keys()) k];
				keys.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
				Der.tlv(0xb0, cat([for (k in keys) Der.seq([Der.utf8(k), derValue(d.get(k))])]));
			case PDate(_): throw "entitlements: a date";
		}

	// the entitlements a distribution signature carries: the app's (the
	// manifest's file, each key one the profile grants), then the
	// profile's own for the bundle: application-identifier (its prefix and
	// the bundle id: the profile's may end in *), the team, get-task-allow
	// and beta-reports-active as the profile says, keychain-access-groups
	// (the prefix and the bundle id for a *)
	public static function entitlements(profile:Profile, bundleId:String, ?app:Map<String, PValue>):Map<String, PValue> {
		var granted = profile.entitlements;
		var appId = switch granted.get("application-identifier") {
			case PString(s): s;
			case _: throw 'the provisioning profile "${profile.name}": no application-identifier';
		}
		var dot = appId.indexOf(".");
		var prefix = appId.substr(0, dot), pattern = appId.substr(dot + 1);
		if (!(pattern == bundleId || pattern.endsWith("*") && bundleId.startsWith(pattern.substr(0, pattern.length - 1))))
			throw 'the provisioning profile "${profile.name}" is for $pattern, not $bundleId';
		var own = ["application-identifier", "com.apple.developer.team-identifier", "get-task-allow", "beta-reports-active", "keychain-access-groups"];
		var out = new Map<String, PValue>();
		if (app != null)
			for (k => v in app) {
				if (!own.contains(k) && !granted.exists(k))
					throw 'the entitlement $k is not in the provisioning profile "${profile.name}" (the App ID\'s capabilities)';
				if (k != "get-task-allow" && k != "beta-reports-active") out.set(k, v);
			}
		out.set("application-identifier", PString('$prefix.$bundleId'));
		for (k in ["com.apple.developer.team-identifier", "get-task-allow", "beta-reports-active"])
			if (granted.exists(k)) out.set(k, granted.get(k));
		if (!out.exists("keychain-access-groups"))
			switch granted.get("keychain-access-groups") {
				case PArray(a): out.set("keychain-access-groups", PArray([for (g in a) switch g {
						case PString(s) if (s.endsWith("*")): PString(s.substr(0, s.length - 1) + bundleId);
						case x: x;
					}]));
				case _:
			}
		return out;
	}

	// the profile against the identity: the certificate one of its own,
	// not expired, for the platform; warnings (a profile with devices: not
	// App Store's)
	public static function checkProfile(profile:Profile, id:Identity, platform:String, now:Date):Array<String> {
		if (!Lambda.exists(profile.certificates, c -> c.compare(id.leaf.der) == 0))
			throw 'the provisioning profile "${profile.name}" does not include the certificate "${id.leaf.commonName}" (a profile made for another certificate)';
		if (profile.expires != null && profile.expires < DateTools.format(now, "%Y-%m-%dT%H:%M:%SZ"))
			throw 'the provisioning profile "${profile.name}" expired on ${profile.expires}';
		if (profile.platforms.length > 0 && !profile.platforms.contains(platform))
			throw 'the provisioning profile "${profile.name}" is for ${profile.platforms.join(", ")}, not $platform';
		var warnings = [];
		if (profile.devices) warnings.push('the provisioning profile "${profile.name}" lists devices: a development or ad hoc profile, not App Store\'s (TestFlight needs an App Store profile)');
		if (!id.complete())
			warnings.push('the certificate chain stops at "${id.leaf.commonName}": add its issuer (Apple\'s AppleWWDRCAG3.cer, https://www.apple.com/certificateauthority/) to the PEM');
		return warnings;
	}

	// ---- the CMS signature (RFC 5652 SignedData, detached)

	static function attr(oid:String, values:Array<Bytes>):Bytes
		return Der.seq([Der.oid(oid), Der.set(values)]);

	public static function cms(cd:Bytes, id:Identity, time:Date, sign:Bytes->Bytes):Bytes {
		var sha256 = Der.seq([Der.oid("2.16.840.1.101.3.4.2.1")]);
		var digest = haxe.crypto.Sha256.make(cd);
		var hashes = Plist.xml(PDict(["cdhashes" => PArray([PData(digest.sub(0, 20))])]));
		var attrs = [
			attr("1.2.840.113549.1.9.3", [Der.oid("1.2.840.113549.1.7.1")]),
			attr("1.2.840.113549.1.9.5", [Der.time(time)]),
			attr("1.2.840.113549.1.9.4", [Der.tlv(0x04, digest)]),
			attr("1.2.840.113635.100.9.1", [Der.tlv(0x04, hashes)]),
			attr("1.2.840.113635.100.9.2", [Der.seq([Der.oid("2.16.840.1.101.3.4.2.1"), Der.tlv(0x04, digest)])])
		];
		// (a SET OF: sorted by their encodings; signed as a SET, carried as [0])
		attrs.sort((a, b) -> a.compare(b));
		var signed = cat(attrs);
		var signature = sign(Der.tlv(0x31, signed));
		var leaf = id.leaf;
		var signer = Der.seq([
			Der.small(1),
			Der.seq([leaf.issuer, leaf.serial]),
			sha256,
			Der.tlv(0xa0, signed),
			id.key.algorithm(),
			Der.tlv(0x04, signature)
		]);
		var data = Der.seq([
			Der.small(1),
			Der.set([sha256]),
			Der.seq([Der.oid("1.2.840.113549.1.7.1")]),
			Der.tlv(0xa0, cat([for (c in id.chain) c.der])),
			Der.set([signer])
		]);
		return Der.seq([Der.oid("1.2.840.113549.1.7.2"), Der.tlv(0xa0, data)]);
	}

	static inline function be32(b:Bytes, at:Int):Int
		return (b.get(at) << 24) | (b.get(at + 1) << 16) | (b.get(at + 2) << 8) | b.get(at + 3);
}

typedef SignOptions = {
	// the CodeDirectory's identifier: the bundle id
	identifier:String,
	identity:Identity,
	// the team id (else the certificate's OU)
	?team:String,
	?infoPlist:Bytes,
	?resources:Bytes,
	// null: none
	?entitlements:Map<String, PValue>,
	// the hardened runtime (macOS, Developer ID): its version (0xMMmmpp, the SDK's), null: off
	?runtime:Int,
	// LC_BUILD_VERSION's sdk (0xMMmmpp), null: as linked
	?sdk:Int,
	?time:Date
};

// a thin 64-bit Mach-O's load commands the signature touches
class MachO {
	public var sigOff = 0;
	public var textOff = 0;
	public var textSize = 0;

	var sigCmd = -1;
	var linkedit = -1;
	var build = -1;
	var linkeditOff = 0;

	function new() {}

	public static function parse(b:Bytes):MachO {
		if (b.length < 32 || b.getInt32(0) != 0xfeedfacf) throw "not a 64-bit Mach-O (a fat or 32-bit one is not signed here)";
		var m = new MachO(), at = 32;
		for (_ in 0...b.getInt32(16)) {
			var cmd = b.getInt32(at), size = b.getInt32(at + 4);
			switch cmd {
				case 0x19:
					var name = b.getString(at + 8, 16).split("\x00")[0];
					if (name == "__TEXT") {
						m.textOff = b.getInt32(at + 40);
						m.textSize = b.getInt32(at + 48);
					} else if (name == "__LINKEDIT") {
						m.linkedit = at;
						m.linkeditOff = b.getInt32(at + 40);
					}
				case 0x1d:
					m.sigCmd = at;
					m.sigOff = b.getInt32(at + 8);
				case 0x32:
					m.build = at;
				case _:
			}
			at += size;
		}
		if (m.sigCmd < 0) throw "the executable has no LC_CODE_SIGNATURE (linked without room for a signature)";
		if (m.linkedit < 0) throw "the executable has no __LINKEDIT";
		return m;
	}

	// the signature's size: LC_CODE_SIGNATURE's, __LINKEDIT's (file and memory: 16 KB pages)
	public function resize(out:Bytes, size:Int) {
		out.setInt32(sigCmd + 12, size);
		var file = sigOff + size - linkeditOff;
		out.setInt32(linkedit + 48, file);
		out.setInt32(linkedit + 52, 0);
		out.setInt32(linkedit + 32, (file + 0x3fff) & ~0x3fff);
		out.setInt32(linkedit + 36, 0);
	}

	public function setSdk(out:Bytes, sdk:Int) {
		if (build < 0) throw "the executable has no LC_BUILD_VERSION";
		out.setInt32(build + 16, sdk);
	}

	// "26.0" as 0x1a0000
	public static function version(v:String):Int {
		var p = v.split(".").map(Std.parseInt);
		return ((p[0] ?? 0) << 16) | ((p[1] ?? 0) << 8) | (p.length > 2 ? p[2] ?? 0 : 0);
	}
}

// a big-endian buffer
private class Be {
	final b = new BytesBuffer();

	public function new() {}

	public inline function len():Int
		return b.length;

	public function u8(v:Int)
		b.addByte(v & 0xff);

	public function u32(v:Int) {
		b.addByte(v >>> 24);
		b.addByte((v >> 16) & 0xff);
		b.addByte((v >> 8) & 0xff);
		b.addByte(v & 0xff);
	}

	public function u64(v:Int) {
		u32(0);
		u32(v);
	}

	public function bytes(d:Bytes)
		b.add(d);

	public function zeros(n:Int)
		for (_ in 0...n)
			b.addByte(0);

	public function toBytes():Bytes
		return b.getBytes();
}
