package helder.pack.android;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.pack.android.Arsc.Value;
import helder.pack.android.Axml.Element;
import helder.pack.android.Apk.Signer;
import helder.pack.android.Der.DerNode;

// An Android App Bundle (.aab, what Google Play takes), the same app as
// Apk's: a zip of the base module, in aapt2's protobuf formats where an
// APK has binary ones (aapt2's Resources.proto, bundletool's config.proto:
// the formats are Apache-2.0 Android's, the code helder's):
//   BundleConfig.pb                     bundletool's version
//   base/manifest/AndroidManifest.xml   the manifest as an XmlNode
//   base/resources.pb                   the resource table (Arsc's) as a ResourceTable
//   base/res/...                        its files (XML ones as XmlNodes)
//   base/dex/classes.dex                when the program needs Java
//   base/lib/<abi>/libmain.so           one an ABI
//   base/assets/...                     the program's assets
// signed with JAR signing (v1: META-INF/MANIFEST.MF, HELDER.SF and the
// PKCS#7 signature HELDER.RSA or .EC) by the upload key, as jarsigner signs
// one; Play signs the APKs it makes with its own key. Pure.
class Aab {
	public static inline var BUNDLETOOL = "1.18.1";

	// the bundle: libs an ABI's library each (target: android-arm64, ...),
	// the manifest, the resources (null: none; xml: their XML files'
	// elements by path), assets under assets/
	public static function write(libs:Array<{target:String, so:Bytes}>, dex:Null<Bytes>, manifest:Element, resources:Null<{
		table:Arsc,
		files:Array<{name:String, data:Bytes}>,
		xml:Map<String, Element>
	}>, assets:Array<{name:String, data:Bytes}>, key:Signer):Bytes {
		var entries:Array<{name:String, data:Bytes}> = [];
		var config = new Pb();
		config.msg(1, new Pb().str(2, BUNDLETOOL));
		entries.push({name: "BundleConfig.pb", data: config.toBytes()});
		entries.push({name: "base/manifest/AndroidManifest.xml", data: xml(manifest).toBytes()});
		if (resources != null) {
			entries.push({name: "base/resources.pb", data: table(resources.table, resources.xml)});
			for (f in resources.files) {
				if (f.name == "resources.arsc") continue;
				var x = resources.xml.get(f.name);
				entries.push({name: "base/" + f.name, data: x != null ? xml(x).toBytes() : f.data});
			}
		}
		if (dex != null) entries.push({name: "base/dex/classes.dex", data: dex});
		for (l in libs)
			entries.push({name: 'base/lib/${Apk.abiDir(l.target)}/${Apk.LIBRARY}', data: l.so});
		for (a in assets)
			entries.push({name: "base/" + a.name, data: a.data});
		var signed = JarSign.sign(entries, key);
		return helder.pack.Zip.stored([for (e in signed) {name: e.name, data: e.data, align: 1}]);
	}

	// ---- XML as aapt2's XmlNode

	public static function xml(e:Element, root = true):Pb {
		var el = new Pb();
		if (root) el.msg(1, new Pb().str(1, "android").str(2, Axml.ANDROID));
		el.str(3, e.name);
		for (a in e.attrs) {
			var at = new Pb();
			if (a.android) at.str(1, Axml.ANDROID);
			at.str(2, a.name);
			var item = new Pb();
			switch a.type {
				case Axml.STRING:
					at.str(3, a.string);
					item.msg(2, new Pb().str(1, a.string));
				case Axml.INT_DEC:
					at.str(3, Std.string(a.value));
					item.msg(7, new Pb().int(6, a.value, true));
				case Axml.INT_HEX:
					at.str(3, "0x" + StringTools.hex(a.value, 8).toLowerCase());
					item.msg(7, new Pb().int(7, a.value, true));
				case Axml.BOOLEAN:
					at.str(3, a.value != 0 ? "true" : "false");
					item.msg(7, new Pb().bool(8, a.value != 0, true));
				case Axml.REFERENCE:
					at.str(3, "@0x" + StringTools.hex(a.value, 8).toLowerCase());
					item.msg(1, new Pb().int(2, a.value));
				case t:
					throw 'Aab: an attribute of type $t';
			}
			if (a.android) at.int(5, Axml.IDS.get(a.name));
			at.msg(6, item);
			el.msg(4, at);
		}
		for (c in e.children)
			el.msg(5, xml(c, false));
		return new Pb().msg(1, el);
	}

	// ---- the resource table as aapt2's ResourceTable

	static function item(v:Value):Pb
		return switch v {
			case FilePath(p): new Pb().msg(5, new Pb().str(1, p).int(2, StringTools.endsWith(p, ".xml") ? 3 : 1));
			case Argb(c): new Pb().msg(7, new Pb().int(9, c, true));
			case Ref(id): new Pb().msg(1, new Pb().int(2, id));
			case Style(_, _): throw "Aab: a style is not an item";
		}

	public static function table(t:Arsc, xmlFiles:Map<String, Element>):Bytes {
		var pkg = new Pb();
		pkg.msg(1, new Pb().int(1, 0x7f));
		pkg.str(2, t.pkg);
		for (ti => type in t.types) {
			var ty = new Pb();
			ty.msg(1, new Pb().int(1, ti + 1));
			ty.str(2, type.name);
			for (ei => entry in type.entries) {
				var en = new Pb();
				en.msg(1, new Pb().int(1, ei));
				en.str(2, entry.name);
				for (cv in entry.values) {
					var config = new Pb();
					if (cv.config.night == true) config.int(17, 1);
					if (cv.config.density != null) config.int(18, cv.config.density);
					var value = new Pb();
					switch cv.value {
						case Style(parent, items):
							var style = new Pb();
							style.msg(1, new Pb().int(2, parent));
							for (i in items)
								style.msg(3, new Pb().msg(3, new Pb().int(2, i.attr)).msg(4, item(i.value)));
							value.msg(5, new Pb().msg(2, style));
						case v:
							value.msg(4, item(v));
					}
					en.msg(6, new Pb().msg(1, config).msg(2, value));
				}
				ty.msg(3, en);
			}
			pkg.msg(3, ty);
		}
		return new Pb().msg(2, pkg).msg(4, new Pb().str(1, "helder").str(2, "0.1")).toBytes();
	}
}

// JAR signing (v1), as jarsigner signs: MANIFEST.MF with each entry's
// SHA-256, the signature file with the manifest's and each section's, and
// a detached PKCS#7 SignedData over the signature file (no signed
// attributes) by the key
class JarSign {
	public static inline var NAME = "HELDER";

	// a header line, wrapped at 72 bytes (continuations begin with a space)
	static function line(b:StringBuf, s:String) {
		var first = true;
		while (s.length > (first ? 72 : 71)) {
			var n = first ? 72 : 71;
			b.add((first ? "" : " ") + s.substr(0, n) + "\r\n");
			s = s.substr(n);
			first = false;
		}
		b.add((first ? "" : " ") + s + "\r\n");
	}

	static function b64(d:Bytes):String
		return haxe.crypto.Base64.encode(d);

	public static function sign(entries:Array<{name:String, data:Bytes}>, key:Signer):Array<{name:String, data:Bytes}> {
		var main = "Manifest-Version: 1.0\r\nCreated-By: 1.0 (helder)\r\n\r\n";
		var mf = new StringBuf(), sf = new StringBuf();
		mf.add(main);
		var sections = [];
		for (e in entries) {
			var s = new StringBuf();
			line(s, "Name: " + e.name);
			line(s, "SHA-256-Digest: " + b64(haxe.crypto.Sha256.make(e.data)));
			s.add("\r\n");
			sections.push({name: e.name, text: s.toString()});
			mf.add(s.toString());
		}
		var manifest = Bytes.ofString(mf.toString());
		sf.add("Signature-Version: 1.0\r\n");
		sf.add("Created-By: 1.0 (helder)\r\n");
		line(sf, "SHA-256-Digest-Manifest: " + b64(haxe.crypto.Sha256.make(manifest)));
		line(sf, "SHA-256-Digest-Manifest-Main-Attributes: " + b64(haxe.crypto.Sha256.make(Bytes.ofString(main))));
		sf.add("\r\n");
		for (s in sections) {
			line(sf, "Name: " + s.name);
			line(sf, "SHA-256-Digest: " + b64(haxe.crypto.Sha256.make(Bytes.ofString(s.text))));
			sf.add("\r\n");
		}
		var signature = Bytes.ofString(sf.toString());
		var ec = key.algorithm == 0x0201;
		return [
			{name: "META-INF/MANIFEST.MF", data: manifest},
			{name: 'META-INF/$NAME.SF', data: signature},
			{name: 'META-INF/$NAME.${ec ? "EC" : "RSA"}', data: pkcs7(signature, key)}
		].concat(entries);
	}

	// SignedData (RFC 2315/5652), detached, no signed attributes
	public static function pkcs7(content:Bytes, key:Signer):Bytes {
		var cert = key.cert;
		var c = Der.children(cert, Der.read(cert, 0));
		var tbs = Der.children(cert, c[0]);
		var i = tbs[0].tag == 0xa0 ? 1 : 0;
		var tlv = (n:DerNode) -> cert.sub(n.at, n.end - n.at);
		var sha256 = Der.seq([Der.oid("2.16.840.1.101.3.4.2.1")]);
		var alg = key.algorithm == 0x0201 ? Der.seq([Der.oid("1.2.840.10045.4.3.2")]) : Der.seq([Der.oid("1.2.840.113549.1.1.1"), Bytes.ofHex("0500")]);
		var signer = Der.seq([
			Der.small(1),
			Der.seq([tlv(tbs[i + 2]), tlv(tbs[i])]),
			sha256,
			alg,
			Der.tlv(0x04, key.sign(content))
		]);
		var data = Der.seq([
			Der.small(1),
			Der.set([sha256]),
			Der.seq([Der.oid("1.2.840.113549.1.7.1")]),
			Der.tlv(0xa0, cert),
			Der.set([signer])
		]);
		return Der.seq([Der.oid("1.2.840.113549.1.7.2"), Der.tlv(0xa0, data)]);
	}
}
