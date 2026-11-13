package helder.story;

import helder.test.Test;
import sys.FileSystem;

// where the screenshots go (StoreShots): a project's bin/ by its absolute
// path, as `helder publish` names it (a drive's on Windows), made with the
// directories above it; one there already left as it is
function tests() {
	test("an absolute path's directories made", () -> {
		var d = FileSystem.fullPath("bin") + "/test-store-shots/run/phone";
		if (FileSystem.exists(d)) FileSystem.deleteDirectory(d);
		@:privateAccess StoreShots.mkdirs(d);
		assert(FileSystem.isDirectory(d), d);
		@:privateAccess StoreShots.mkdirs(d);
		assert(FileSystem.isDirectory(d), "again");
	});
}
