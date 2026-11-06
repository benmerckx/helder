// native.jni on Android (CI's android job runs it on its emulator,
// tests/typescript/native/android.sh): static fields of android.os.Build
// and Build.VERSION (an int, strings), a static method taking a string and
// returning one, an object made and a method called on it; its line in
// logcat under the tag hxmc.
import { native, i32, i64, Java } from "helder/native";

const Version = native.jni({
	class: "android.os.Build$VERSION",
	staticFields: {
		SDK_INT: (): i32 => 0,
		RELEASE: (): string => "",
	},
});

const System = native.jni({
	class: "java.lang.System",
	statics: {
		getProperty: (key: string): string => "",
		currentTimeMillis: (): i64 => 0,
	},
});

const StringBuilder = native.jni({
	class: "java.lang.StringBuilder",
	statics: { new: (s: string): Java<"java/lang/StringBuilder"> => 0 },
	methods: {
		append: (o: Java<"java/lang/StringBuilder">, n: i32): Java<"java/lang/StringBuilder"> => 0,
		length: (o: Java<"java/lang/StringBuilder">): i32 => 0,
		toString: (o: Java<"java/lang/StringBuilder">): string => "",
	},
});

console.log("native.jni: started");
const sdk = Version.SDK_INT();
const b = StringBuilder.new("jni ");
StringBuilder.append(b, 42);
console.log(`native.jni: SDK_INT ${sdk} (${sdk >= 21}), release ${Version.RELEASE() !== ""}, time ${System.currentTimeMillis() > 1.6e12}, vm ${System.getProperty("java.vm.name")}, ${StringBuilder.toString(b)} ${StringBuilder.length(b)}`);
