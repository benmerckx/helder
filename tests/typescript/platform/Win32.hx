// Something only Windows links, for the platform checks (tests/typescript/run.mjs):
// kernel32's GetTickCount64, which a build for another platform must not
// name (main.ts's and Main.hx's Windows branch, helder/platform's and
// Platform.os()'s constants folded).
class Win32 {
	// milliseconds since Windows started
	public static function ticks():Float {
		#if (target.name == "hxmc")
		var t = Kernel32.GetTickCount64();
		return haxe.Int64.toInt(t);
		#else
		return 0;
		#end
	}
}

#if (target.name == "hxmc")
@:hxmc.c @:hxmc.lib("kernel32") private extern class Kernel32 {
	static function GetTickCount64():haxe.Int64;
}
#end
