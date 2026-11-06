// native.objc on macOS (run.mjs runs it there): Foundation's NSProcessInfo,
// its processName (an NSString, read through its UTF8String), its
// processorCount (an NSUInteger); an NSString made from a C string, its
// length (UTF-16 units), released.
import { native, id, pointer, usize, cstring } from "helder/native";

const NSProcessInfo = native.objc({
	class: "NSProcessInfo",
	lib: "/System/Library/Frameworks/Foundation.framework/Foundation",
	statics: { processInfo: (): id => 0 },
	methods: {
		processName: (self: id): id => 0,
		processorCount: (self: id): usize => 0,
	},
});

const NSString = native.objc({
	class: "NSString",
	lib: "/System/Library/Frameworks/Foundation.framework/Foundation",
	statics: { alloc: (): id => 0 },
	methods: {
		initWithUTF8String_: (self: id, s: cstring): id => 0,
		UTF8String: (self: id): pointer => 0,
		length: (self: id): usize => 0,
		release: (self: id): void => {},
	},
});

const info = NSProcessInfo.processInfo();
console.log(NSProcessInfo.class !== 0, info !== 0);
console.log(native.string(NSString.UTF8String(NSProcessInfo.processName(info))));
console.log(NSProcessInfo.processorCount(info) > 0);
const s = NSString.initWithUTF8String_(NSString.alloc(), "héllo, wörld");
console.log(NSString.length(s), native.string(NSString.UTF8String(s)));
NSString.release(s);
