package helder.os;

import helder.test.Test;

// text/uri-list's file paths (X11's drops: helder.os.x11.X11Window)
@:test.interp function tests() {
	describe("UriList", () -> {
		test("file URIs, CRLF and LF, comments and other schemes left out", () -> {
			equals(UriList.paths("file:///home/a/one.jpg\r\nfile:///home/a/two.png\r\n"), ["/home/a/one.jpg", "/home/a/two.png"]);
			equals(UriList.paths("# a comment\nhttps://example.com/x.png\nfile:/tmp/x.gif\n"), ["/tmp/x.gif"]);
		});
		test("a host's authority dropped, escapes decoded as UTF-8", () -> {
			equals(UriList.paths("file://laptop/home/a/b%20c.jpg"), ["/home/a/b c.jpg"]);
			equals(UriList.paths("file:///tmp/caf%C3%A9.webp"), ["/tmp/café.webp"]);
		});
		test("broken escapes and empty paths left out", () -> {
			equals(UriList.paths("file:///tmp/a%2\nfile:///tmp/a%zz\nfile://host\n\n"), []);
		});
	});
}
