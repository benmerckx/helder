// helder/platform's constants folded: the Windows branch (kernel32's
// GetTickCount64, Win32.ticks) is left out of other platforms' builds, and
// with it the symbol (run.mjs: the binary does not name it).
import { platform } from "helder/platform";
import { Win32 } from "./win32";

function uptime(): string {
	return "up " + (Win32.ticks() > 0);
}

if (platform.os === "windows") console.log(uptime());
else console.log("not windows:", platform.os, platform.target);
console.log(platform.os === "wasi" || platform.arm ? "no x86-64 code" : "x86-64");
console.log(platform.os !== "windows" && platform.os !== "macos" ? "a Linux or a WASI build" : "a desktop's");
