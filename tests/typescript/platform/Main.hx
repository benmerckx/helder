// main.ts in Haxe: Mem.os()'s constant folded (hxmc.ir.Lower.targetConst),
// the Windows branch, kernel32's GetTickCount64 with it, left out elsewhere.
class Main {
	static function main() {
		if (hxmc.unsafe.Mem.os() == 2) Sys.println("up " + (Win32.ticks() > 0));
		else Sys.println("not windows: " + ["linux", "macos", "windows", "wasi"][hxmc.unsafe.Mem.os()]);
	}
}
