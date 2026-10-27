// layout-fuzz.mjs's random trees laid out and compared with Chromium's
// boxes, as UiTest compares its layout cases: LayoutFuzz <dir>
class LayoutFuzz {
	static function main() {
		var dir = Sys.args().length > 0 ? Sys.args()[0] : "bin/ui/fuzz";
		@:privateAccess UiTest.layouts(dir);
		@:privateAccess {
			Sys.println('LayoutFuzz: ${UiTest.failed} differ');
			Sys.exit(UiTest.failed == 0 ? 0 : 1);
		}
	}
}
