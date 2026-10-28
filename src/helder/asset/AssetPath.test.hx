package helder.asset;

import helder.test.Test;

// an asset's path (AssetPath): what the macro accepts, a part's case on
// disk, the bundle's and a URL's form
@:test.interp
function tests() {
	describe("error", () -> {
		test("a path relative to its root, '/' between parts", () -> {
			equals(AssetPath.error("ui/icons/sword.png"), null);
			equals(AssetPath.error("sword.png"), null);
			equals(AssetPath.error("a b/ü.png"), null);
			equals(AssetPath.error(".hidden/x"), null);
		});
		test("empty, absolute, Windows' and URLs' forms", () -> {
			equals(AssetPath.error(""), "an empty path");
			assert(AssetPath.error("/ui/x.png").indexOf("absolute") >= 0);
			assert(AssetPath.error("ui\\x.png").indexOf("backslash") >= 0);
			assert(AssetPath.error("C:/x.png").indexOf("colon") >= 0);
			assert(AssetPath.error("http://x/y.png").indexOf("colon") >= 0);
		});
		test("empty parts, . and ..", () -> {
			assert(AssetPath.error("ui//x.png").indexOf("empty part") >= 0);
			assert(AssetPath.error("ui/").indexOf("empty part") >= 0);
			assert(AssetPath.error("./x.png").indexOf('"."') >= 0);
			assert(AssetPath.error("ui/../x.png").indexOf('".."') >= 0);
		});
		test("control characters", () -> {
			assert(AssetPath.error("a\nb") != null);
			assert(AssetPath.error("a\x7fb") != null);
		});
	});
	describe("caseOf", () -> {
		var tree = ["" => ["ui", "Models"], "ui" => ["Icons"], "ui/Icons" => ["sword.png"], "Models" => []];
		var list = (d:String) -> tree.exists(d) ? tree.get(d) : [];
		test("every part as on disk: null", () -> equals(AssetPath.caseOf("ui/Icons/sword.png", list), null));
		test("a part in another case: it and the name on disk", () -> {
			equals(AssetPath.caseOf("ui/icons/sword.png", list), {part: "icons", actual: "Icons"});
			equals(AssetPath.caseOf("models/x.glb", list), {part: "models", actual: "Models"});
		});
		test("a part not there at all", () -> equals(AssetPath.caseOf("ui/Icons/shield.png", list), {part: "shield.png", actual: null}));
	});
	test("in a bundle: assets/<key>", () -> equals(AssetPath.bundled("ui/sword.png"), "assets/ui/sword.png"));
	test("as a URL: each part encoded", () -> equals(AssetPath.url("a b/ü#.png"), "a%20b/%C3%BC%23.png"));
}
