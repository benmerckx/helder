package helder.os.uikit;

import helder.os.objc.*;
import hxmc.unsafe.*;

// The start of an iOS app: UIKit needs UIApplicationMain on the main
// thread, which never returns, before any window. hxmc's generated main
// (hxmc/src/hxmc/DataGen.hx) runs this export instead of the program's
// body when the program has it: it makes the app delegate's class
// (HxmcAppDelegate, at run time) and calls UIApplicationMain, on the big
// stack the body would have had. Once the app has launched, a timer on the
// main run loop (so that application:didFinishLaunchingWithOptions:
// returns first, and UIKit's launch completes) runs the program's body
// (its static initializers, then main) inside UIKit's loop: App.run turns
// the run loop itself (UIKitWindow.poll), as SDL does; the program's main
// returning ends the process. Until then nothing here may use a static
// with an initializer (Msg's, ObjC.str's): only C calls.
// The delegate's lifecycle callbacks become Suspend (the app went to the
// background: no GPU work there) and Resume (UIKitWindow).
// (kept, with its export, for iOS only: @:hxmc.ios leaves a class out of
// other targets only in hxmc's own packages)
@:hxmc.ios #if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64") @:keep #end
class UIKitApp {
	// the program's main runs (its statics are set)
	public static var running:Bool;

	#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64") @:hxmc.export("hxmc_ui_main") #end
	static function main():Void {
		#if hxmc.dev_host
		helder.dev.Hosted.block();
		#end
		var cls = Runtime.objc_allocateClassPair(ObjC.cls("UIResponder"), Mem.cstr("HxmcAppDelegate"), 0);
		Runtime.class_addMethod(cls, ObjC.sel("application:didFinishLaunchingWithOptions:"), Callback.addr(didFinishLaunching), Mem.cstr("B@:@@"));
		Runtime.class_addMethod(cls, ObjC.sel("applicationDidEnterBackground:"), Callback.addr(didEnterBackground), Mem.cstr("v@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("applicationWillEnterForeground:"), Callback.addr(willEnterForeground), Mem.cstr("v@:@"));
		Runtime.objc_registerClassPair(cls);
		UIKit.UIApplicationMain(Mem.getI32(Mem.sym("rt_argc"), 0), Mem.getPtr(Mem.sym("rt_argv"), 0), Ptr.nil(), Foundation.NSStringFromClass(cls));
	}

	// launched: the program's body on the next turn of the run loop
	@:hxmc.callback static function didFinishLaunching(self:Ptr, cmd:Ptr, app:Ptr, options:Ptr):Int {
		var mode = CF.CFStringCreateWithCString(Ptr.nil(), Mem.cstr("kCFRunLoopDefaultMode"), 0x08000100); // (kCFStringEncodingUTF8)
		var timer = CF.CFRunLoopTimerCreate(Ptr.nil(), CF.CFAbsoluteTimeGetCurrent(), 0, 0, 0, Callback.addr(start), Ptr.nil());
		CF.CFRunLoopAddTimer(CF.CFRunLoopGetMain(), timer, mode);
		return 1; // (YES)
	}

	@:hxmc.callback static function start(timer:Ptr, info:Ptr):Void {
		Mem.call0(Mem.sym("hx_main_body"));
		#if hxmc.dev_host
		// (hxmc dev: handed over: the next build's dylib loaded and run here, on the main thread, inside UIKit's loop)
		while (Mem.getU8(helder.dev.Hosted.block(), helder.dev.DevHost.NEXT) != 0) {
			var path = LibC.malloc(helder.dev.DevHost.NEXT_BYTES);
			LibC.memcpy(path, helder.dev.Hosted.block().add(helder.dev.DevHost.NEXT), helder.dev.DevHost.NEXT_BYTES);
			Mem.setI8(helder.dev.Hosted.block(), helder.dev.DevHost.NEXT, 0);
			var lib = Posix.dlopen(path, 2); // (RTLD_NOW)
			LibC.free(path);
			if (lib.isNull()) {
				Sys.stderr().writeString("helder.dev: " + (cast Posix.dlerror() : CString).toString() + "\n");
				break;
			}
			var slot = Posix.dlsym(lib, Mem.cstr("hxmc_dev_state")), run = Posix.dlsym(lib, Mem.cstr("hxmc_dev_run"));
			if (slot.isNull() || run.isNull()) break;
			Mem.setPtr(slot, 0, helder.dev.Hosted.block());
			HostedRun.run(run, 1);
		}
		#end
		Sys.exit(0);
	}

	#if hxmc.dev_host
	// (hxmc dev: a build loaded into the running app: the delegate's lifecycle methods this build's)
	public static function adopt() {
		var cls = Runtime.objc_getClass(Mem.cstr("HxmcAppDelegate"));
		if (cls.isNull()) return;
		Runtime.class_replaceMethod(cls, ObjC.sel("applicationDidEnterBackground:"), Callback.addr(didEnterBackground), Mem.cstr("v@:@"));
		Runtime.class_replaceMethod(cls, ObjC.sel("applicationWillEnterForeground:"), Callback.addr(willEnterForeground), Mem.cstr("v@:@"));
	}
	#end

	@:hxmc.callback static function didEnterBackground(self:Ptr, cmd:Ptr, app:Ptr):Void
		if (running) UIKitWindow.suspend(true);

	@:hxmc.callback static function willEnterForeground(self:Ptr, cmd:Ptr, app:Ptr):Void
		if (running) UIKitWindow.suspend(false);
}

#if hxmc.dev_host
@:hxmc.c extern class HostedRun {
	@:hxmc.indirect static function run(f:Ptr, arg:Int):Int;
}
#end

// UIKit's C function (and the framework loaded: its classes are found by name)
@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/UIKit.framework/UIKit") extern class UIKit {
	static function UIApplicationMain(argc:Int, argv:Ptr, principal:Ptr, delegate:Ptr):Int;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/Foundation.framework/Foundation") extern class Foundation {
	static function NSStringFromClass(cls:Ptr):Ptr;
}

// CoreFoundation's run loop: the app's loop is UIKit's (UIKitWindow.poll, wait)
@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation") extern class CF {
	static function CFStringCreateWithCString(alloc:Ptr, s:Ptr, encoding:Int):Ptr;
	static function CFAbsoluteTimeGetCurrent():Float;
	static function CFRunLoopGetMain():Ptr;
	static function CFRunLoopTimerCreate(alloc:Ptr, fire:Float, interval:Float, flags:Int64, order:Int64, callout:Ptr, context:Ptr):Ptr;
	static function CFRunLoopAddTimer(loop:Ptr, timer:Ptr, mode:Ptr):Void;
	// 1 finished, 2 stopped, 3 timed out, 4 a source handled
	static function CFRunLoopRunInMode(mode:Ptr, seconds:Float, returnAfterSourceHandled:Bool):Int;
}
