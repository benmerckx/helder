package helder.pack.apple;

import haxe.io.Bytes;
import helder.pack.android.Der;
import helder.pack.apple.CodeSign;
import helder.pack.apple.Identity;
import helder.pack.ios.Plist;
import helder.test.Test;

// A distribution signature (CodeSign) of a stand-in Mach-O, parsed back:
// the identity from PEM (tests/pack/signing: a throwaway CA, an RSA and a
// P-256 leaf), RSA's PKCS#1 v1.5 against openssl's signature, the
// SuperBlob's slots, the CodeDirectory's fields, page hashes and special
// slots, the load commands resized and the SDK set, the designated
// requirement, the entitlements (the profile's merged with the app's;
// DER), the CMS's signed attributes and its signature verified. openssl
// verifies the CMS of a built app (tests/pack/PackCheck.hx).
function tests() {
	final cert = "-----BEGIN CERTIFICATE-----\nMIIDgzCCAmugAwIBAgIFEjRWeJAwDQYJKoZIhvcNAQELBQAwMDEXMBUGA1UEAwwO\nSGVsZGVyIFRlc3QgQ0ExFTATBgNVBAoMDGhlbGRlciB0ZXN0czAeFw0yNjExMDQy\nMjM3NTNaFw00NjEwMzAyMjM3NTNaMFwxLjAsBgNVBAMMJUhlbGRlciBUZXN0IERp\nc3RyaWJ1dGlvbiAoSExEUlRFU1QwMSkxEzARBgNVBAsMCkhMRFJURVNUMDExFTAT\nBgNVBAoMDGhlbGRlciB0ZXN0czCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC\nggEBAJR8aPEGqf6gMjnBJKrI5d3oUknmgeVwGenStU28jysUycrG03ISW40/+BkX\nIn9pCh4V3HP3qJDwLz86dsBmtpaczLZtUjWklrCAXzkzHiXKYQ1yRSY+6N/cfN+Z\nD0PEbsC7SR8kz043n7U0EeEx7ZQef6WUhoZNWoE86vMc8KXVWjsvcHnoC5UxWYPp\nEmUDAGwHTh8vqSc2Xe8jTYTqexw6RQR0tsg/Ubm9oU5AYnZxIvTmhz/k54dvETCX\n6L0WPHQ0pl/y/N5dYC6SFlI0c3lBr+gaJJq2VwAA8CrX/j7plAZ6T/I76GgHs5kQ\nTRAH5CF0TlmF4UE+hs2ULoMJqlcCAwEAAaN4MHYwDAYDVR0TAQH/BAIwADAOBgNV\nHQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwMwHQYDVR0OBBYEFNqF\n+PYbOnRvceZpzf+YoD7i4hUTMB8GA1UdIwQYMBaAFIKR6f8389SBCx8N7CNDqWyh\nHqyHMA0GCSqGSIb3DQEBCwUAA4IBAQBNhaJI7eOJFQa0IivGfHhqKf010N/UGSer\ngMA6LFjRQy17YCMpzOoGYebpr6otg82B15abOCp0l5WC4yoPohlG0HN2ICCoamd5\nxW2xa9iYdvHOAxYQACLjmYqkgyQaPRJby4niTtdJZ2gKSFELD71VtUXsPiWmADOH\nWUeYb6T1aLXJcBP762cgtwc9WFWEuVEGJgvFPp5YDcRB34MSqn1KPNeUw4cgs/iw\nEJMJpzIAO/kx9nWlfm15FybYp2ynCtmQMOgEIglA6Mtfp+pQBmyXbYV3/Wv6/l0B\n8vs6FrejWjy1/pnLC8iv/jlwfJSKZk1vWCaTZ8U/zczRjq3XaJVM\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nMIIDUTCCAjmgAwIBAgIURHhlTW5HwkS3QSLEH7rl9fBbkyAwDQYJKoZIhvcNAQEL\nBQAwMDEXMBUGA1UEAwwOSGVsZGVyIFRlc3QgQ0ExFTATBgNVBAoMDGhlbGRlciB0\nZXN0czAeFw0yNjExMDQyMjM3NTNaFw00NjEwMzAyMjM3NTNaMDAxFzAVBgNVBAMM\nDkhlbGRlciBUZXN0IENBMRUwEwYDVQQKDAxoZWxkZXIgdGVzdHMwggEiMA0GCSqG\nSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCjNlD6BvX5dw+W90HvMKjfsWGpNoqJmBGb\nU3BSjuznCnGwkJI4TLBRZKSbOHm3MKpZdSXFcHl5x9YhQtv1L5ZI+gcZrkEZ1YJf\nT3jf5NM/nkSMVOyVeP0oNicnRTv5hBYVFwVFG/l8LE4lFLle9M/8N3JLDDFCmulG\nQwgVeVLcNWF6NBEc+hHzq2JU4EcrzLtK9rYia4+g9GXN9bX9Xj4qZENUzthGu1Yb\nfMgn4heDyyly3myyRp+I/nVBCnEVp0xiqayMO3n1WQUTHsPLNDwMgzFddCZ6MuWk\nE8z8uMjkhnS0RE4Smzqqi96GD0VzmprT8c4VmqwG4+ZUCctoA0xvAgMBAAGjYzBh\nMB0GA1UdDgQWBBSCken/N/PUgQsfDewjQ6lsoR6shzAfBgNVHSMEGDAWgBSCken/\nN/PUgQsfDewjQ6lsoR6shzAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIB\nBjANBgkqhkiG9w0BAQsFAAOCAQEAeuBvFIvFbnX/+t5XdkMTJiFrpyO15b+j1+rB\nDvd8xgFOI5o5rEVBeGBqc3UOSZiaZDlKGz2JdZvNX6o0YyL6wmXZaedDeRi7ul6S\nsCvpzYxs1MH/BBGpUS44u8YVTkjZNjgmIptklTCfPtxCQG+0YYSoTvxcJVCZAEBF\nteNzazGvkold3to0Ljyr96HLXPEGMb06gNdZzZSh89CwOW773XKvmfCHL3n1KKFu\nTuKSNQeQUj13MRT6GgvhBD9PnxKJmG2z2yTn+XWHMN77akxL8bFx1N1rUl8xbeMj\nXvRNMmSJCne316Z/ljr8zeFT5r+p12Vx9we2C0B2dQBfKvFvwQ==\n-----END CERTIFICATE-----";
	final key = "-----BEGIN PRIVATE KEY-----\nMIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCUfGjxBqn+oDI5\nwSSqyOXd6FJJ5oHlcBnp0rVNvI8rFMnKxtNyEluNP/gZFyJ/aQoeFdxz96iQ8C8/\nOnbAZraWnMy2bVI1pJawgF85Mx4lymENckUmPujf3HzfmQ9DxG7Au0kfJM9ON5+1\nNBHhMe2UHn+llIaGTVqBPOrzHPCl1Vo7L3B56AuVMVmD6RJlAwBsB04fL6knNl3v\nI02E6nscOkUEdLbIP1G5vaFOQGJ2cSL05oc/5OeHbxEwl+i9Fjx0NKZf8vzeXWAu\nkhZSNHN5Qa/oGiSatlcAAPAq1/4+6ZQGek/yO+hoB7OZEE0QB+QhdE5ZheFBPobN\nlC6DCapXAgMBAAECggEAPzfavCewr7qHt8QuNtJS39A+XL1Zt5QrTDyMOX0a3WY7\n5ewR8UK0nOZL3G7XnrRbfOSk1/Ds4UyJaRucnJz+hxBaLh9MPY+GIr59DE7huog4\nGu/4Vei54DmxJse1Uo5q8v6qCqry4iPXiOAS7rSBqKr1gMtEHSEI8/Y6N+it4oRV\n6sUhVv09QugwUo8yIK8iItCvqlIkekEGMLN2WmnyQ5lZNbfCfGw4laXUcKxNhSTn\nFmTohPDJtCdyPiAIwMBLhA+anTufFTi3PZOB6OovRzTPv2U+4IVAUmgoWdUdXUwz\n6MKo7R3Qxjcjgbqhtt1+REOuI4liTQqofe0Fe/MqtQKBgQDNLcocXriWAoru7eTb\nN3SzM9IhSPsgZbeodGsH9V9rMzvikLbDUt05udukBrstZCfY+ySs0YQPfEEglmOK\nhMC0ATsp8MsvUF/gjDzGoZOVXidqPhPne+I/5w9f3LSjNWhoYUOQc0Vl7AaokrJK\nQpUJON3TbQ9abOrhLvEflGJvlQKBgQC5Q8ZCZKSKjxKFXpwSE34QWrhqlBo9tiLz\nwq5VvK41jc8ROO1cJV4oXlxx1zWWKg8U9ftaQFhxbIuyuORJcOtWNrtPt7sJjgKr\nPm5c/CZh1rZ6atnviljKnWQrHJ87ZguuPWjTtcjl7giwL7P6uWGmsT7xues1cL08\nIa9mNmFnOwKBgCwNc8KJl8ole5z3GNb0XisHqksZN0nqbPdPH5fS2AzVMDth5Mul\nI/h77iuWgmOpiGCu813jkh4dCIKtp2ubOyCqzwAfQhDDigJVOctP77b3QzEtaOqf\nj6E2w/dKFMKh+evHTlFaXoEWnwtci8kj6InVWtNFLDG3BusYQA8Otd/NAoGAPAAY\nMJ55r6pAfFM0xqHrfQ50lYfbq8rWLQ4K+hd+cDe6LUC7ltE/WmGdHP1vDHAYrFgy\nDHu0aR+Xas14mdRpU2Wsalf9yk1kzeMNSS4cnCk2thTu+iZbNVud+lxtsYYOGGMp\nFQ/VvanGxJDegEATwTG8SftFkuwtTVE3hinsh8sCgYBUE/9PH0W+xQgBQhArjRNk\nLkYQWndR91b7hHZrYMiqP72u2XqlDrWbU3pHyRICJhV1zY+OhQ/H/W3WWzaivyv4\nwAIsweD1Lh7QbqnPi2UCd0hWGyPBUGo4ejAUKpLDUTBVyStWKV9nXoZZ9MQUCMqC\nwI403I5i346uu4oWvKOaLw==\n-----END PRIVATE KEY-----";
	final certEc = "-----BEGIN CERTIFICATE-----\nMIICuDCCAaCgAwIBAgICI0UwDQYJKoZIhvcNAQELBQAwMDEXMBUGA1UEAwwOSGVs\nZGVyIFRlc3QgQ0ExFTATBgNVBAoMDGhlbGRlciB0ZXN0czAeFw0yNjExMDQyMjM3\nNTNaFw00NjEwMzAyMjM3NTNaMF8xMTAvBgNVBAMMKEhlbGRlciBUZXN0IERpc3Ry\naWJ1dGlvbiBFQyAoSExEUlRFU1QwMSkxEzARBgNVBAsMCkhMRFJURVNUMDExFTAT\nBgNVBAoMDGhlbGRlciB0ZXN0czBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABOgC\nD0oE6HyaqwsDFbL7kW5T3sGgGDwXYj03Bpxq3ZJbVWIHNFIofMh/HRcvfprr26nb\nLCQDyY3dRjjHbNU33nejeDB2MAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/BAQDAgeA\nMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBQzw59UxXmFX+sn/+sB\noA4F1LTeTjAfBgNVHSMEGDAWgBSCken/N/PUgQsfDewjQ6lsoR6shzANBgkqhkiG\n9w0BAQsFAAOCAQEAdVNf0C+pT1bWnbM6l9XRqLyNlVFhi1FP3/k7IAfy8Bhmj6k+\nGx3o+UebW1SHCjIfDqeCptAd6CBCBNXRs/4X0u7HL+d3XYnt0ZYE2wOCH8YnNHS3\n8C9dYekP88a7rQEig5uuSfyU1woeN8yTR9/oSTEwpQJMYYr00fvJ/ApzGXWosecP\nVVvO7kfJIcC+WJJ1uljBuzLB7OPbxygn5z+0JiplXdt7KPSszdo+f7LhEms7rbKq\nrd1sN3MRHCbzQ+Yjitlgffwng54U58vvoNhJ96QF7P89o7negbsV7B5+QqoJ/SFc\nVbSCoEBLKhD+88ar+x/EdjQFTshWAzdOiNQyaw==\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nMIIDUTCCAjmgAwIBAgIURHhlTW5HwkS3QSLEH7rl9fBbkyAwDQYJKoZIhvcNAQEL\nBQAwMDEXMBUGA1UEAwwOSGVsZGVyIFRlc3QgQ0ExFTATBgNVBAoMDGhlbGRlciB0\nZXN0czAeFw0yNjExMDQyMjM3NTNaFw00NjEwMzAyMjM3NTNaMDAxFzAVBgNVBAMM\nDkhlbGRlciBUZXN0IENBMRUwEwYDVQQKDAxoZWxkZXIgdGVzdHMwggEiMA0GCSqG\nSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCjNlD6BvX5dw+W90HvMKjfsWGpNoqJmBGb\nU3BSjuznCnGwkJI4TLBRZKSbOHm3MKpZdSXFcHl5x9YhQtv1L5ZI+gcZrkEZ1YJf\nT3jf5NM/nkSMVOyVeP0oNicnRTv5hBYVFwVFG/l8LE4lFLle9M/8N3JLDDFCmulG\nQwgVeVLcNWF6NBEc+hHzq2JU4EcrzLtK9rYia4+g9GXN9bX9Xj4qZENUzthGu1Yb\nfMgn4heDyyly3myyRp+I/nVBCnEVp0xiqayMO3n1WQUTHsPLNDwMgzFddCZ6MuWk\nE8z8uMjkhnS0RE4Smzqqi96GD0VzmprT8c4VmqwG4+ZUCctoA0xvAgMBAAGjYzBh\nMB0GA1UdDgQWBBSCken/N/PUgQsfDewjQ6lsoR6shzAfBgNVHSMEGDAWgBSCken/\nN/PUgQsfDewjQ6lsoR6shzAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIB\nBjANBgkqhkiG9w0BAQsFAAOCAQEAeuBvFIvFbnX/+t5XdkMTJiFrpyO15b+j1+rB\nDvd8xgFOI5o5rEVBeGBqc3UOSZiaZDlKGz2JdZvNX6o0YyL6wmXZaedDeRi7ul6S\nsCvpzYxs1MH/BBGpUS44u8YVTkjZNjgmIptklTCfPtxCQG+0YYSoTvxcJVCZAEBF\nteNzazGvkold3to0Ljyr96HLXPEGMb06gNdZzZSh89CwOW773XKvmfCHL3n1KKFu\nTuKSNQeQUj13MRT6GgvhBD9PnxKJmG2z2yTn+XWHMN77akxL8bFx1N1rUl8xbeMj\nXvRNMmSJCne316Z/ljr8zeFT5r+p12Vx9we2C0B2dQBfKvFvwQ==\n-----END CERTIFICATE-----";
	final keyEc = "-----BEGIN PRIVATE KEY-----\nMIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgTfmZOrmlAjsENI1m\n/lISVIl2BCuKpstWoheOWh+VptqhRANCAAToAg9KBOh8mqsLAxWy+5FuU97BoBg8\nF2I9Nwacat2SW1ViBzRSKHzIfx0XL36a69up2ywkA8mN3UY4x2zVN953\n-----END PRIVATE KEY-----";
	final id = Identity.fromPem(cert, key);
	final idEc = Identity.fromPem(certEc, keyEc);

	// (a stand-in executable: __TEXT 16 KB, __LINKEDIT after it, the old signature at 0x4100)
	final exe = () -> {
		var b = Bytes.alloc(0x4200);
		for (i in 200...0x4100)
			b.set(i, (i * 31) & 0xff);
		b.setInt32(0, 0xfeedfacf);
		b.setInt32(4, 0x0100000c);
		b.setInt32(12, 2);
		b.setInt32(16, 4);
		var at = 32;
		function seg(name:String, off:Int, size:Int) {
			b.setInt32(at, 0x19);
			b.setInt32(at + 4, 72);
			b.blit(at + 8, Bytes.ofString(name), 0, name.length);
			b.setInt32(at + 32, size);
			b.setInt32(at + 40, off);
			b.setInt32(at + 48, size);
			at += 72;
		}
		seg("__TEXT", 0, 0x4000);
		seg("__LINKEDIT", 0x4000, 0x200);
		b.setInt32(at, 0x32);
		b.setInt32(at + 4, 24);
		b.setInt32(at + 8, 2);
		b.setInt32(at + 12, 0x100000);
		b.setInt32(at + 16, 0x120000);
		at += 24;
		b.setInt32(at, 0x1d);
		b.setInt32(at + 4, 16);
		b.setInt32(at + 8, 0x4100);
		b.setInt32(at + 12, 0x100);
		b;
	};
	final be = (b:Bytes, at:Int) -> (b.get(at) << 24) | (b.get(at + 1) << 16) | (b.get(at + 2) << 8) | b.get(at + 3);
	final profile = Profile.parse(Bytes.ofString("(a CMS around it)<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict>"
		+ "<key>Name</key><string>Test</string><key>TeamIdentifier</key><array><string>HLDRTEST01</string></array>"
		+ "<key>ExpirationDate</key><date>2046-01-01T00:00:00Z</date><key>Platform</key><array><string>iOS</string></array>"
		+ "<key>DeveloperCertificates</key><array><data>" + haxe.crypto.Base64.encode(id.leaf.der) + "</data></array>"
		+ "<key>Entitlements</key><dict><key>application-identifier</key><string>HLDRTEST01.org.example.*</string>"
		+ "<key>keychain-access-groups</key><array><string>HLDRTEST01.*</string></array><key>get-task-allow</key><false/>"
		+ "<key>beta-reports-active</key><true/><key>com.apple.developer.team-identifier</key><string>HLDRTEST01</string>"
		+ "<key>com.apple.developer.game-center</key><true/></dict></dict></plist>(its signature)"));

	describe("the identity", () -> {
		test("the leaf by its key, the chain up to the CA", () -> {
			equals(id.leaf.commonName, "Helder Test Distribution (HLDRTEST01)");
			equals(id.leaf.organizationalUnit, "HLDRTEST01");
			equals([for (c in id.chain) c.commonName], ["Helder Test Distribution (HLDRTEST01)", "Helder Test CA"]);
			assert(id.complete() && !id.leaf.apple());
			equals(idEc.leaf.commonName, "Helder Test Distribution EC (HLDRTEST01)");
			assert(idEc.key.ec != null);
		});
		test("an encrypted key, a key of another certificate: messages", () -> {
			throws(() -> PrivateKey.fromPem("-----BEGIN ENCRYPTED PRIVATE KEY-----\nAAAA\n-----END ENCRYPTED PRIVATE KEY-----"));
			throws(() -> Identity.fromPem(cert, keyEc));
		});
		test("RSA PKCS#1 v1.5 with SHA-256: openssl's signature of \"hello\"", () -> {
			var s = id.key.sign(Bytes.ofString("hello"));
			equals(s.toHex(), "8cc0f617182407627f9214a81d8a2cb589069609cb28fd1344c382511b59130eb0067c3210a423f32e13650dbfcd8f77a41580507a4ac93a04e67dade25eea01d60690776342699588f38fffc2ac7e6d2cef90bfcbf964470f63f66c5daa2e499aeb67e7773496370eb3302ddb14dbe1b7f8923c2468efce8ae7e2048d0a53ea31046481854822106cddf9c7d9aec3687560d725952f8b66452c0a25eb73d9de795faa77811b788ccd6a28a9ed2145866ced90ab734d2afcc95cbde895ddd445fa21ee3dcd66e79fca59490b7e44efa1ab78b27336685cccb2bb938a5378df4931f85188035d44cfc2f42fe5e2fd3a75ec10663daf57ab891dad0b06f2e6a41c");
			assert(Rsa.verify(id.key.rsa.n, id.key.rsa.e, Bytes.ofString("hello"), s));
			assert(!Rsa.verify(id.key.rsa.n, id.key.rsa.e, Bytes.ofString("hellO"), s));
		});
	});

	describe("the profile and the entitlements", () -> {
		test("the profile read: its team, certificates, expiry", () -> {
			equals([profile.name, profile.team, profile.expires], ["Test", "HLDRTEST01", "2046-01-01T00:00:00Z"]);
			equals(CodeSign.checkProfile(profile, id, "iOS", new Date(2026, 0, 1, 0, 0, 0)), []);
			throws(() -> CodeSign.checkProfile(profile, idEc, "iOS", new Date(2026, 0, 1, 0, 0, 0)));
			throws(() -> CodeSign.checkProfile(profile, id, "iOS", new Date(2047, 0, 1, 0, 0, 0)));
		});
		test("the profile's for the bundle, the app's it grants", () -> {
			var e = CodeSign.entitlements(profile, "org.example.hello", ["com.apple.developer.game-center" => PBool(true), "get-task-allow" => PBool(true)]);
			equals(e.get("application-identifier"), PString("HLDRTEST01.org.example.hello"));
			equals(e.get("keychain-access-groups"), PArray([PString("HLDRTEST01.org.example.hello")]));
			equals(e.get("get-task-allow"), PBool(false));
			equals(e.get("beta-reports-active"), PBool(true));
			equals(e.get("com.apple.developer.game-center"), PBool(true));
			throws(() -> CodeSign.entitlements(profile, "org.other.hello"));
			throws(() -> CodeSign.entitlements(profile, "org.example.hello", ["aps-environment" => PString("production")]));
		});
		test("DER: [APPLICATION 16] { 1, [CONTEXT 16] { key, value } sorted }", () -> {
			equals(CodeSign.entitlementsDer(["b" => PArray([PString("x")]), "a" => PBool(true)]).toHex(), "70170201" + "01b012" + "3006" + "0c0161" + "0101ff" + "3008" + "0c0162" + "3003" + "0c0178");
		});
	});

	describe("the signature", () -> {
		final ent = CodeSign.entitlements(profile, "org.example.hello");
		final info = Bytes.ofString("<plist>info</plist>"), res = Bytes.ofString("<plist>resources</plist>");
		final signed = CodeSign.sign(exe(), {
			identifier: "org.example.hello",
			identity: id,
			infoPlist: info,
			resources: res,
			entitlements: ent,
			sdk: MachO.version("26.0"),
			time: new Date(2026, 10, 4, 12, 0, 0)
		});
		final blobs = new Map<Int, Int>();
		for (k in 0...be(signed, 0x4100 + 8))
			blobs.set(be(signed, 0x4100 + 12 + 8 * k), 0x4100 + be(signed, 0x4100 + 16 + 8 * k));
		final cd = blobs.get(0);
		final blob = (slot:Int) -> signed.sub(blobs.get(slot), be(signed, blobs.get(slot) + 4));

		test("the load commands: the signature's size, __LINKEDIT's, the SDK", () -> {
			var size = signed.getInt32(32 + 72 + 72 + 24 + 12);
			equals(signed.length, 0x4100 + size);
			equals(size % 16, 0);
			equals(signed.getInt32(32 + 72 + 48), 0x100 + size);
			equals(signed.getInt32(32 + 72 + 32), (0x100 + size + 0x3fff) & ~0x3fff);
			equals(signed.getInt32(32 + 144 + 16), 0x1a0000);
		});
		test("a SuperBlob: CodeDirectory, requirements, entitlements, DER, CMS", () -> {
			equals(be(signed, 0x4100), 0xfade0cc0);
			equals([for (k in 0...be(signed, 0x4108)) be(signed, 0x4100 + 12 + 8 * k)], [0, 2, 5, 7, 0x10000]);
			equals([be(signed, cd), be(signed, blobs.get(2)), be(signed, blobs.get(5)), be(signed, blobs.get(7)), be(signed, blobs.get(0x10000))],
				[0xfade0c02, 0xfade0c01, 0xfade7171, 0xfade7172, 0xfade0b01]);
		});
		test("the CodeDirectory: identifier, team, not ad hoc, pages and special slots", () -> {
			equals(be(signed, cd + 8), 0x20400);
			equals(be(signed, cd + 12), 0);
			var hashOff = be(signed, cd + 16), nSpecial = be(signed, cd + 24), nCode = be(signed, cd + 28);
			equals(signed.getString(cd + be(signed, cd + 20), 17), "org.example.hello");
			equals(signed.getString(cd + be(signed, cd + 48), 10), "HLDRTEST01");
			equals([nSpecial, nCode, be(signed, cd + 32)], [7, 5, 0x4100]);
			equals([be(signed, cd + 68), be(signed, cd + 76), be(signed, cd + 84)], [0, 0x4000, 1]);
			for (k in 0...nCode) {
				var off = k << 12, n = 0x4100 - off < 4096 ? 0x4100 - off : 4096;
				equals(signed.sub(cd + hashOff + 32 * k, 32).toHex(), haxe.crypto.Sha256.make(signed.sub(off, n)).toHex());
			}
			var slot = (k:Int) -> signed.sub(cd + hashOff - 32 * k, 32).toHex();
			equals(slot(1), haxe.crypto.Sha256.make(info).toHex());
			equals(slot(2), haxe.crypto.Sha256.make(blob(2)).toHex());
			equals(slot(3), haxe.crypto.Sha256.make(res).toHex());
			equals(slot(4), StringTools.lpad("", "0", 64));
			equals(slot(5), haxe.crypto.Sha256.make(blob(5)).toHex());
			equals(slot(7), haxe.crypto.Sha256.make(blob(7)).toHex());
		});
		test("the designated requirement: the identifier and the root's hash", () -> {
			var dr = CodeSign.designated("org.example.hello", id);
			equals(dr.text, 'identifier "org.example.hello" and certificate root = H"7ed2791d3542386fa53e9886d77b1f226e78f058"');
			equals([blob(2).sub(28, 4).toHex(), blob(2).sub(32, 4).toHex()], ["00000001", "00000006"]);
			equals(blob(2).toHex(), CodeSign.requirements(dr).toHex());
		});
		test("the entitlements: XML and DER of the same", () -> {
			equals(Plist.parse(blob(5).sub(8, blob(5).length - 8).toString()), PDict(ent));
			equals(blob(7).sub(8, blob(7).length - 8).toHex(), CodeSign.entitlementsDer(ent).toHex());
		});
		test("the CMS: Apple's attributes, the chain, the signature verified", () -> {
			var c = blob(0x10000).sub(8, blob(0x10000).length - 8);
			var top = Der.children(c, Der.read(c, 0));
			equals(c.sub(top[0].at, top[0].end - top[0].at).toHex(), Der.oid("1.2.840.113549.1.7.2").toHex());
			var sd = Der.children(c, Der.children(c, top[1])[0]);
			equals(Der.children(c, sd[3]).length, 2);
			var si = Der.children(c, Der.children(c, sd[4])[0]);
			var attrs = si[3];
			equals(attrs.tag, 0xa0);
			var hash = CodeSign.cdhash(signed);
			var found = new Map<String, Bytes>();
			for (a in Der.children(c, attrs)) {
				var p = Der.children(c, a);
				var v = Der.children(c, p[1])[0];
				found.set(Certificate.oidString(c, p[0]), c.sub(v.at, v.end - v.at));
			}
			equals(found.get("1.2.840.113549.1.9.4").toHex(), "0420" + hash.toHex());
			var plist = Der.read(found.get("1.2.840.113635.100.9.1"), 0);
			equals(Plist.parse(found.get("1.2.840.113635.100.9.1").sub(plist.start, plist.end - plist.start).toString()),
				PDict(["cdhashes" => PArray([PData(hash.sub(0, 20))])]));
			equals(found.get("1.2.840.113635.100.9.2").toHex(), Der.seq([Der.oid("2.16.840.1.101.3.4.2.1"), Der.tlv(0x04, hash)]).toHex());
			var signedAttrs = c.sub(attrs.at, attrs.end - attrs.at);
			signedAttrs.set(0, 0x31);
			var sig = c.sub(si[5].start, si[5].end - si[5].start);
			assert(Rsa.verify(id.key.rsa.n, id.key.rsa.e, signedAttrs, sig));
		});
		test("signed with P-256: a CMS with ecdsa-with-SHA256", () -> {
			var s = CodeSign.sign(exe(), {identifier: "org.example.hello", identity: idEc});
			var size = s.getInt32(32 + 72 + 72 + 24 + 12);
			equals(s.length, 0x4100 + size);
			assert(CodeSign.cdhash(s).length == 32);
		});
	});
}
