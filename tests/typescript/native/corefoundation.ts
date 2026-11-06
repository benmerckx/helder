// native.c on macOS (run.mjs runs it there): Core Foundation's C API, a
// framework by its path: a CFString made from a C string, its length read,
// released; the absolute time, a double.
import { native, f64, i64, u32, pointer, cstring } from "helder/native";

const cf = native.c({
	lib: "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
	fns: {
		CFAbsoluteTimeGetCurrent: (): f64 => 0,
		CFStringCreateWithCString: (allocator: pointer, s: cstring, encoding: u32): pointer => 0,
		CFStringGetLength: (s: pointer): i64 => 0,
		CFRelease: (o: pointer): void => {},
	},
});

// (kCFStringEncodingUTF8)
const s = cf.CFStringCreateWithCString(0, "héllo, wörld", 0x08000100);
console.log(s !== 0, cf.CFStringGetLength(s));
cf.CFRelease(s);
console.log(cf.CFAbsoluteTimeGetCurrent() > 7e8);
