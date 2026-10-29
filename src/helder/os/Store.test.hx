package helder.os;

import helder.test.Test;

// Store, a small key-value store kept between runs: values written through
// and read back by a store opened again, removed and cleared, quotes,
// newlines and non-ASCII text kept, a damaged file opened empty, a name
// that is not one refused (natively and as wasm32-wasi: a file under
// bin/test/store; the web's localStorage: the golf example's save in
// Chromium, examples/golf/README.md).
function tests() {
	describe("Store", () -> {
		final dir = "bin/test/store";
		beforeEach(() -> {
			if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
			for (f in sys.FileSystem.readDirectory(dir))
				sys.FileSystem.deleteFile(dir + "/" + f);
		});
		test("empty at first; a value set is there when opened again", () -> {
			var s = Store.open("app", dir);
			equals(s.keys(), []);
			equals(s.get("best"), null);
			s.set("best", "3,2,4");
			s.set("name", "Ada");
			assert(s.written);
			equals(s.path, dir + "/app.json");
			var again = Store.open("app", dir);
			equals(again.keys(), ["best", "name"]);
			equals(again.get("best"), "3,2,4");
			assert(again.exists("name"));
		});
		test("remove and clear reach the file", () -> {
			var s = Store.open("app", dir);
			s.set("a", "1");
			s.set("b", "2");
			s.remove("a");
			equals(Store.open("app", dir).keys(), ["b"]);
			s.clear();
			equals(Store.open("app", dir).keys(), []);
		});
		test("text of any kind kept", () -> {
			var odd = "quote \" backslash \\ newline\n tab\t é ★ 😀";
			Store.open("app", dir).set("odd", odd);
			equals(Store.open("app", dir).get("odd"), odd);
		});
		test("stores of other names apart", () -> {
			Store.open("one", dir).set("k", "1");
			Store.open("two", dir).set("k", "2");
			equals(Store.open("one", dir).get("k"), "1");
			equals(Store.open("two", dir).get("k"), "2");
		});
		test("a damaged file opens empty, and is written whole again", () -> {
			sys.io.File.saveContent(dir + "/app.json", "{\"best\": \"3\", oops");
			var s = Store.open("app", dir);
			equals(s.keys(), []);
			s.set("best", "2");
			equals(Store.open("app", dir).get("best"), "2");
			assert(!sys.FileSystem.exists(dir + "/app.json.tmp"));
		});
		test("a name that is not one", () -> {
			throws(() -> Store.open("../up", dir));
			throws(() -> Store.open("", dir));
			throws(() -> Store.open(".hidden", dir));
		});
	});
}
