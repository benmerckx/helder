// The pack lane's project (package.json's "helder": the app's id, label,
// versions, a permission, iOS's minimum and entitlements): a line printed
class Main {
	static function main() {
		#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		helder.os.android.Activity.activity;
		#end
		Sys.println("hello from the packed project");
	}
}
