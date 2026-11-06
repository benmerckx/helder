package helder.pack.windows;

import haxe.io.Bytes;
import helder.pack.android.Der;
import helder.pack.apple.Identity;
import helder.test.Test;

// A Windows executable made into a release's (Pe): a stand-in PE32+ (as
// hxmc's linker writes one: headers of 0x400, a section, the console
// subsystem) made a GUI program, given a resource section (the tree read
// back: types, names, languages, the data entries' RVAs; an icon's group
// and DIBs; the version's VS_FIXEDFILEINFO and strings), its checksum
// (imagehlp's); then signed (Authenticode: the image's hash without the
// checksum, the security directory and the table; the WIN_CERTIFICATE; the
// SpcIndirectDataContent's digest; the CMS's signature verified). osslsigncode
// verifies a signed viewer in the viewer-package lane.
function tests() {
	// (headers: MZ, PE, a COFF header of one section, PE32+'s optional header, the section table; .text at 0x400)
	final exe = () -> {
		var b = Bytes.alloc(0x600);
		b.fill(0, b.length, 0);
		b.setUInt16(0, 0x5a4d);
		b.setInt32(60, 64);
		b.setInt32(64, 0x4550);
		var coff = 68, opt = coff + 20;
		b.setUInt16(coff, 0x8664);
		b.setUInt16(coff + 2, 1);
		b.setUInt16(coff + 16, 240);
		b.setUInt16(opt, 0x20b);
		b.setInt32(opt + 32, 0x1000);
		b.setInt32(opt + 36, 0x200);
		b.setInt32(opt + 56, 0x2000);
		b.setInt32(opt + 60, 0x400);
		b.setUInt16(opt + 68, 3);
		b.setInt32(opt + 108, 16);
		var sec = opt + 240;
		b.blit(sec, Bytes.ofString(".text"), 0, 5);
		b.setInt32(sec + 8, 0x180);
		b.setInt32(sec + 12, 0x1000);
		b.setInt32(sec + 16, 0x200);
		b.setInt32(sec + 20, 0x400);
		for (i in 0x400...0x580)
			b.set(i, (i * 7) & 0xff);
		b;
	};
	final rgba = (px:Int) -> {
		var b = Bytes.alloc(px * px * 4);
		for (i in 0...px * px) {
			b.set(4 * i, 10);
			b.set(4 * i + 1, 20);
			b.set(4 * i + 2, 30);
			b.set(4 * i + 3, i == 0 ? 0 : 255);
		}
		b;
	};

	describe("the executable", () -> {
		test("GUI, not the console's", () -> {
			var g = Pe.gui(exe());
			equals(new Pe(g).subsystem, 2);
			equals(new Pe(exe()).subsystem, 3);
		});
		test("a resource section appended, the headers told", () -> {
			var res = [
				{type: Pe.Resources.RT_VERSION, id: 1, data: Bytes.ofString("version")},
				{type: Pe.Resources.RT_ICON, id: 2, data: Bytes.ofString("two")},
				{type: Pe.Resources.RT_ICON, id: 1, data: Bytes.ofString("one")}
			];
			var out = Pe.withResources(exe(), va -> Pe.Resources.section(res, va));
			var p = new Pe(out);
			equals(p.count, 2);
			var s = p.section(1);
			equals(s.name, ".rsrc");
			equals([s.va, s.rawAt], [0x2000, 0x600]);
			equals(out.getInt32(p.directoryAt(2)), 0x2000);
			equals(out.getInt32(p.opt + 56), 0x3000);
			// (the tree: two types, by id; RT_ICON's names 1 and 2, each English; the data by RVA)
			var r = out.sub(s.rawAt, s.vsize);
			equals([r.getUInt16(12), r.getUInt16(14)], [0, 2]);
			equals([r.getInt32(16), r.getInt32(24)], [3, 16]);
			var icons = r.getInt32(20) & 0x7fffffff;
			equals([r.getUInt16(icons + 14), r.getInt32(icons + 16), r.getInt32(icons + 24)], [2, 1, 2]);
			var lang = r.getInt32(icons + 20) & 0x7fffffff;
			equals(r.getInt32(lang + 16), 0x409);
			var entry = r.getInt32(lang + 20);
			var rva = r.getInt32(entry), size = r.getInt32(entry + 4);
			equals(r.getString(rva - 0x2000, size), "one");
			throws(() -> Pe.withResources(out, va -> Bytes.alloc(4)));
		});
		test("an icon's group and its DIBs (bottom-up BGRA, an empty mask), a PNG at 256", () -> {
			var r = Pe.Resources.icon([16, 256], rgba, px -> Bytes.ofString("png"));
			equals([for (x in r) x.type], [Pe.Resources.RT_ICON, Pe.Resources.RT_ICON, Pe.Resources.RT_GROUP_ICON]);
			var dib = r[0].data;
			equals([dib.getInt32(0), dib.getInt32(4), dib.getInt32(8), dib.getUInt16(14)], [40, 16, 32, 32]);
			equals(dib.length, 40 + 16 * 16 * 4 + 4 * 16);
			// (the first pixel, transparent, is the last row's: bottom-up)
			equals(dib.sub(40 + 15 * 16 * 4, 4).toHex(), "1e140a00");
			equals(dib.sub(40, 4).toHex(), "1e140aff");
			var g = r[2].data;
			equals([g.getUInt16(2), g.getUInt16(4)], [1, 2]);
			equals([g.get(6), g.getInt32(6 + 8), g.getUInt16(6 + 12)], [16, dib.length, 1]);
			equals([g.get(20), g.getInt32(20 + 8), g.getUInt16(20 + 12)], [0, 3, 2]);
		});
		test("the version: VS_FIXEDFILEINFO's numbers, the strings", () -> {
			var v = Pe.Resources.version([0, 1, 2, 7], [{key: "ProductName", value: "Viewer"}]).data;
			equals(v.getUInt16(0), v.length);
			equals(v.getUInt16(2), 52);
			// ("VS_VERSION_INFO" in UTF-16, its NUL, padded: the value at 40)
			equals(v.getInt32(40), 0xfeef04bd);
			equals([v.getInt32(48), v.getInt32(52)], [1, (2 << 16) | 7]);
			var text = [for (i in 0...v.length >> 1) String.fromCharCode(v.getUInt16(2 * i))].join("");
			assert(text.indexOf("ProductName") > 0 && text.indexOf("Viewer") > 0 && text.indexOf("040904B0") > 0, "the strings");
		});
		test("the checksum: imagehlp's of the file without it", () -> {
			var a = Pe.withChecksum(exe()), p = new Pe(a);
			var sum = a.getInt32(p.checksumAt);
			assert(sum > a.length, "the length added");
			// (the same file, another checksum in the field: the same sum)
			var b = exe();
			b.setInt32(p.checksumAt, 0x12345678);
			equals(Pe.withChecksum(b).getInt32(p.checksumAt), sum);
		});
	});

	describe("Authenticode", () -> {
		// (tests/pack/signing's throwaway RSA leaf and CA)
		final cert = "-----BEGIN CERTIFICATE-----\nMIIDgzCCAmugAwIBAgIFEjRWeJAwDQYJKoZIhvcNAQELBQAwMDEXMBUGA1UEAwwO\nSGVsZGVyIFRlc3QgQ0ExFTATBgNVBAoMDGhlbGRlciB0ZXN0czAeFw0yNjExMDQy\nMjM3NTNaFw00NjEwMzAyMjM3NTNaMFwxLjAsBgNVBAMMJUhlbGRlciBUZXN0IERp\nc3RyaWJ1dGlvbiAoSExEUlRFU1QwMSkxEzARBgNVBAsMCkhMRFJURVNUMDExFTAT\nBgNVBAoMDGhlbGRlciB0ZXN0czCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC\nggEBAJR8aPEGqf6gMjnBJKrI5d3oUknmgeVwGenStU28jysUycrG03ISW40/+BkX\nIn9pCh4V3HP3qJDwLz86dsBmtpaczLZtUjWklrCAXzkzHiXKYQ1yRSY+6N/cfN+Z\nD0PEbsC7SR8kz043n7U0EeEx7ZQef6WUhoZNWoE86vMc8KXVWjsvcHnoC5UxWYPp\nEmUDAGwHTh8vqSc2Xe8jTYTqexw6RQR0tsg/Ubm9oU5AYnZxIvTmhz/k54dvETCX\n6L0WPHQ0pl/y/N5dYC6SFlI0c3lBr+gaJJq2VwAA8CrX/j7plAZ6T/I76GgHs5kQ\nTRAH5CF0TlmF4UE+hs2ULoMJqlcCAwEAAaN4MHYwDAYDVR0TAQH/BAIwADAOBgNV\nHQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwMwHQYDVR0OBBYEFNqF\n+PYbOnRvceZpzf+YoD7i4hUTMB8GA1UdIwQYMBaAFIKR6f8389SBCx8N7CNDqWyh\nHqyHMA0GCSqGSIb3DQEBCwUAA4IBAQBNhaJI7eOJFQa0IivGfHhqKf010N/UGSer\ngMA6LFjRQy17YCMpzOoGYebpr6otg82B15abOCp0l5WC4yoPohlG0HN2ICCoamd5\nxW2xa9iYdvHOAxYQACLjmYqkgyQaPRJby4niTtdJZ2gKSFELD71VtUXsPiWmADOH\nWUeYb6T1aLXJcBP762cgtwc9WFWEuVEGJgvFPp5YDcRB34MSqn1KPNeUw4cgs/iw\nEJMJpzIAO/kx9nWlfm15FybYp2ynCtmQMOgEIglA6Mtfp+pQBmyXbYV3/Wv6/l0B\n8vs6FrejWjy1/pnLC8iv/jlwfJSKZk1vWCaTZ8U/zczRjq3XaJVM\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nMIIDUTCCAjmgAwIBAgIURHhlTW5HwkS3QSLEH7rl9fBbkyAwDQYJKoZIhvcNAQEL\nBQAwMDEXMBUGA1UEAwwOSGVsZGVyIFRlc3QgQ0ExFTATBgNVBAoMDGhlbGRlciB0\nZXN0czAeFw0yNjExMDQyMjM3NTNaFw00NjEwMzAyMjM3NTNaMDAxFzAVBgNVBAMM\nDkhlbGRlciBUZXN0IENBMRUwEwYDVQQKDAxoZWxkZXIgdGVzdHMwggEiMA0GCSqG\nSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCjNlD6BvX5dw+W90HvMKjfsWGpNoqJmBGb\nU3BSjuznCnGwkJI4TLBRZKSbOHm3MKpZdSXFcHl5x9YhQtv1L5ZI+gcZrkEZ1YJf\nT3jf5NM/nkSMVOyVeP0oNicnRTv5hBYVFwVFG/l8LE4lFLle9M/8N3JLDDFCmulG\nQwgVeVLcNWF6NBEc+hHzq2JU4EcrzLtK9rYia4+g9GXN9bX9Xj4qZENUzthGu1Yb\nfMgn4heDyyly3myyRp+I/nVBCnEVp0xiqayMO3n1WQUTHsPLNDwMgzFddCZ6MuWk\nE8z8uMjkhnS0RE4Smzqqi96GD0VzmprT8c4VmqwG4+ZUCctoA0xvAgMBAAGjYzBh\nMB0GA1UdDgQWBBSCken/N/PUgQsfDewjQ6lsoR6shzAfBgNVHSMEGDAWgBSCken/\nN/PUgQsfDewjQ6lsoR6shzAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIB\nBjANBgkqhkiG9w0BAQsFAAOCAQEAeuBvFIvFbnX/+t5XdkMTJiFrpyO15b+j1+rB\nDvd8xgFOI5o5rEVBeGBqc3UOSZiaZDlKGz2JdZvNX6o0YyL6wmXZaedDeRi7ul6S\nsCvpzYxs1MH/BBGpUS44u8YVTkjZNjgmIptklTCfPtxCQG+0YYSoTvxcJVCZAEBF\nteNzazGvkold3to0Ljyr96HLXPEGMb06gNdZzZSh89CwOW773XKvmfCHL3n1KKFu\nTuKSNQeQUj13MRT6GgvhBD9PnxKJmG2z2yTn+XWHMN77akxL8bFx1N1rUl8xbeMj\nXvRNMmSJCne316Z/ljr8zeFT5r+p12Vx9we2C0B2dQBfKvFvwQ==\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nMIIDUTCCAjmgAwIBAgIURHhlTW5HwkS3QSLEH7rl9fBbkyAwDQYJKoZIhvcNAQEL\nBQAwMDEXMBUGA1UEAwwOSGVsZGVyIFRlc3QgQ0ExFTATBgNVBAoMDGhlbGRlciB0\nZXN0czAeFw0yNjExMDQyMjM3NTNaFw00NjEwMzAyMjM3NTNaMDAxFzAVBgNVBAMM\nDkhlbGRlciBUZXN0IENBMRUwEwYDVQQKDAxoZWxkZXIgdGVzdHMwggEiMA0GCSqG\nSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCjNlD6BvX5dw+W90HvMKjfsWGpNoqJmBGb\nU3BSjuznCnGwkJI4TLBRZKSbOHm3MKpZdSXFcHl5x9YhQtv1L5ZI+gcZrkEZ1YJf\nT3jf5NM/nkSMVOyVeP0oNicnRTv5hBYVFwVFG/l8LE4lFLle9M/8N3JLDDFCmulG\nQwgVeVLcNWF6NBEc+hHzq2JU4EcrzLtK9rYia4+g9GXN9bX9Xj4qZENUzthGu1Yb\nfMgn4heDyyly3myyRp+I/nVBCnEVp0xiqayMO3n1WQUTHsPLNDwMgzFddCZ6MuWk\nE8z8uMjkhnS0RE4Smzqqi96GD0VzmprT8c4VmqwG4+ZUCctoA0xvAgMBAAGjYzBh\nMB0GA1UdDgQWBBSCken/N/PUgQsfDewjQ6lsoR6shzAfBgNVHSMEGDAWgBSCken/\nN/PUgQsfDewjQ6lsoR6shzAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIB\nBjANBgkqhkiG9w0BAQsFAAOCAQEAeuBvFIvFbnX/+t5XdkMTJiFrpyO15b+j1+rB\nDvd8xgFOI5o5rEVBeGBqc3UOSZiaZDlKGz2JdZvNX6o0YyL6wmXZaedDeRi7ul6S\nsCvpzYxs1MH/BBGpUS44u8YVTkjZNjgmIptklTCfPtxCQG+0YYSoTvxcJVCZAEBF\nteNzazGvkold3to0Ljyr96HLXPEGMb06gNdZzZSh89CwOW773XKvmfCHL3n1KKFu\nTuKSNQeQUj13MRT6GgvhBD9PnxKJmG2z2yTn+XWHMN77akxL8bFx1N1rUl8xbeMj\nXvRNMmSJCne316Z/ljr8zeFT5r+p12Vx9we2C0B2dQBfKvFvwQ==\n-----END CERTIFICATE-----\n";
		final id = Identity.fromPem(cert, "-----BEGIN PRIVATE KEY-----\nMIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCUfGjxBqn+oDI5\nwSSqyOXd6FJJ5oHlcBnp0rVNvI8rFMnKxtNyEluNP/gZFyJ/aQoeFdxz96iQ8C8/\nOnbAZraWnMy2bVI1pJawgF85Mx4lymENckUmPujf3HzfmQ9DxG7Au0kfJM9ON5+1\nNBHhMe2UHn+llIaGTVqBPOrzHPCl1Vo7L3B56AuVMVmD6RJlAwBsB04fL6knNl3v\nI02E6nscOkUEdLbIP1G5vaFOQGJ2cSL05oc/5OeHbxEwl+i9Fjx0NKZf8vzeXWAu\nkhZSNHN5Qa/oGiSatlcAAPAq1/4+6ZQGek/yO+hoB7OZEE0QB+QhdE5ZheFBPobN\nlC6DCapXAgMBAAECggEAPzfavCewr7qHt8QuNtJS39A+XL1Zt5QrTDyMOX0a3WY7\n5ewR8UK0nOZL3G7XnrRbfOSk1/Ds4UyJaRucnJz+hxBaLh9MPY+GIr59DE7huog4\nGu/4Vei54DmxJse1Uo5q8v6qCqry4iPXiOAS7rSBqKr1gMtEHSEI8/Y6N+it4oRV\n6sUhVv09QugwUo8yIK8iItCvqlIkekEGMLN2WmnyQ5lZNbfCfGw4laXUcKxNhSTn\nFmTohPDJtCdyPiAIwMBLhA+anTufFTi3PZOB6OovRzTPv2U+4IVAUmgoWdUdXUwz\n6MKo7R3Qxjcjgbqhtt1+REOuI4liTQqofe0Fe/MqtQKBgQDNLcocXriWAoru7eTb\nN3SzM9IhSPsgZbeodGsH9V9rMzvikLbDUt05udukBrstZCfY+ySs0YQPfEEglmOK\nhMC0ATsp8MsvUF/gjDzGoZOVXidqPhPne+I/5w9f3LSjNWhoYUOQc0Vl7AaokrJK\nQpUJON3TbQ9abOrhLvEflGJvlQKBgQC5Q8ZCZKSKjxKFXpwSE34QWrhqlBo9tiLz\nwq5VvK41jc8ROO1cJV4oXlxx1zWWKg8U9ftaQFhxbIuyuORJcOtWNrtPt7sJjgKr\nPm5c/CZh1rZ6atnviljKnWQrHJ87ZguuPWjTtcjl7giwL7P6uWGmsT7xues1cL08\nIa9mNmFnOwKBgCwNc8KJl8ole5z3GNb0XisHqksZN0nqbPdPH5fS2AzVMDth5Mul\nI/h77iuWgmOpiGCu813jkh4dCIKtp2ubOyCqzwAfQhDDigJVOctP77b3QzEtaOqf\nj6E2w/dKFMKh+evHTlFaXoEWnwtci8kj6InVWtNFLDG3BusYQA8Otd/NAoGAPAAY\nMJ55r6pAfFM0xqHrfQ50lYfbq8rWLQ4K+hd+cDe6LUC7ltE/WmGdHP1vDHAYrFgy\nDHu0aR+Xas14mdRpU2Wsalf9yk1kzeMNSS4cnCk2thTu+iZbNVud+lxtsYYOGGMp\nFQ/VvanGxJDegEATwTG8SftFkuwtTVE3hinsh8sCgYBUE/9PH0W+xQgBQhArjRNk\nLkYQWndR91b7hHZrYMiqP72u2XqlDrWbU3pHyRICJhV1zY+OhQ/H/W3WWzaivyv4\nwAIsweD1Lh7QbqnPi2UCd0hWGyPBUGo4ejAUKpLDUTBVyStWKV9nXoZZ9MQUCMqC\nwI403I5i346uu4oWvKOaLw==\n-----END PRIVATE KEY-----\n");
		test("a WIN_CERTIFICATE appended, the security directory at it, the digest of the image's hash", () -> {
			var e = Pe.gui(exe());
			var signed = Authenticode.sign(e, id);
			var p = new Pe(signed), c = p.certificates();
			equals(c.at, 0x600);
			equals(c.at + c.size, signed.length);
			equals([signed.getUInt16(c.at + 4), signed.getUInt16(c.at + 6)], [0x200, 2]);
			// (the image's hash: the same as the unsigned file's, the checksum and directory not counted)
			equals(Authenticode.hash(signed, p).toHex(), Authenticode.hash(e, new Pe(e)).toHex());
			var cms = signed.sub(c.at + 8, signed.getInt32(c.at) - 8);
			var sd = Der.children(cms, Der.children(cms, Der.children(cms, Der.read(cms, 0))[1])[0]);
			var content = Der.children(cms, Der.children(cms, sd[2])[1])[0];
			var indirect = cms.sub(content.at, content.end - content.at);
			equals(indirect.toHex(), Authenticode.indirectData(Authenticode.hash(e, new Pe(e))).toHex());
			var si = Der.children(cms, Der.children(cms, sd[4])[0]);
			var found = new Map<String, Bytes>();
			for (a in Der.children(cms, si[3])) {
				var parts = Der.children(cms, a);
				var v = Der.children(cms, parts[1])[0];
				found.set(Certificate.oidString(cms, parts[0]), cms.sub(v.at, v.end - v.at));
			}
			var inner = Der.read(indirect, 0);
			equals(found.get("1.2.840.113549.1.9.4").toHex(), "0420" + haxe.crypto.Sha256.make(indirect.sub(inner.start, inner.end - inner.start)).toHex());
			var attrs = cms.sub(si[3].at, si[3].end - si[3].at);
			attrs.set(0, 0x31);
			assert(helder.pack.apple.Rsa.verify(id.key.rsa.n, id.key.rsa.e, attrs, cms.sub(si[5].start, si[5].end - si[5].start)), "the signature");
			// (signed again: the old signature replaced, not kept)
			equals(Authenticode.sign(signed, id).length, signed.length);
		});
	});
}
