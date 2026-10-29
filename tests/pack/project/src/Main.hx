// The pack lane's project (package.json's "helder": the app's id, label,
// versions, a permission, iOS's minimum and entitlements, landscape,
// fullscreen): a line printed, which says whether the build had
// -D helder.fullscreen (PackCheck finds it in the binary)
class Main {
	static function main() {
		#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		helder.os.android.Activity.activity;
		#end
		#if helder.fullscreen
		Sys.println("hello from the packed project (fullscreen)");
		#else
		Sys.println("hello from the packed project");
		#end
	}
}
