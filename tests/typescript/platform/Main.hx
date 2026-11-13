// main.ts in Haxe: Platform.os()'s constant folded (hxmc.ir.Lower.targetConst),
// the Windows branch, kernel32's GetTickCount64 with it, left out elsewhere.
class Main {
	static function main() {
		if (hxmc.Platform.os() == 2) Sys.println("up " + (Win32.ticks() > 0));
		else Sys.println("not windows: " + ["linux", "macos", "windows", "wasi"][hxmc.Platform.os()]);
	}
}
