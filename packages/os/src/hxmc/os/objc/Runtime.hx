package hxmc.os.objc;

import hxmc.unsafe.*;

// The Objective-C runtime (libobjc): classes and selectors by name, classes
// made at run time (their methods are @:hxmc.callback functions: delegates),
// retain counts and autorelease pools. id, Class, SEL and IMP are Ptr;
// messages go through Msg.
@:hxmc.c @:hxmc.lib("/usr/lib/libobjc.A.dylib") extern class Runtime {
	static function objc_getClass(name:Ptr):Ptr;
	static function sel_registerName(name:Ptr):Ptr;
	static function objc_allocateClassPair(superclass:Ptr, name:Ptr, extraBytes:Int64):Ptr;
	static function objc_registerClassPair(cls:Ptr):Void;
	// types: the method's type encoding ("v@:@": void, self, _cmd, an id)
	static function class_addMethod(cls:Ptr, sel:Ptr, imp:Ptr, types:Ptr):Bool;
	#if hxmc.dev_host
	// (hxmc dev: a class an earlier build made, its methods this build's)
	static function class_replaceMethod(cls:Ptr, sel:Ptr, imp:Ptr, types:Ptr):Ptr;
	#end
	static function object_getClass(o:Ptr):Ptr;
	static function object_setClass(o:Ptr, cls:Ptr):Ptr;
	static function objc_retain(o:Ptr):Ptr;
	static function objc_release(o:Ptr):Void;
	static function objc_autoreleasePoolPush():Ptr;
	static function objc_autoreleasePoolPop(pool:Ptr):Void;
}
