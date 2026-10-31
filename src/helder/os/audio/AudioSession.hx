package helder.os.audio;

import helder.os.objc.*;
import hxmc.unsafe.*;

// iOS's AVAudioSession for helder.os.audio's RemoteIO output
// (CoreAudioOutput): its category set before the first output opens
// ("ambient" by default: mixed with other apps' audio, silenced by the
// ring/silent switch and the screen lock; "playback": heard with the switch
// on silent, other apps' audio stopped), a preferred I/O buffer of a
// period, the session made active. Interruptions (a call, an alarm, Siri:
// AVAudioSessionInterruptionNotification, observed by a class made at run
// time) stop the output units; when one ends the session is made active
// again and the outputs that were running start again (Audio.interrupted).
class AudioSession {
	static var ready = false;
	static var observer = Ptr.nil();

	public static function setup(category:Null<String>, sampleRate:Int, frames:Int) {
		if (ready) return;
		ready = true;
		// (AVFAudio's classes: the framework loaded by name, as UIKit's are)
		Posix.dlopen(Mem.cstr("/System/Library/Frameworks/AVFAudio.framework/AVFAudio"), 2);
		var session = Msg.id(ObjC.cls("AVAudioSession"), ObjC.sel("sharedInstance"));
		if (session.isNull()) return;
		// (the categories' NSString constants hold their own names)
		var name = ObjC.str(category == "playback" ? "AVAudioSessionCategoryPlayback" : "AVAudioSessionCategoryAmbient");
		SessionMsg.bPtrPtr(session, ObjC.sel("setCategory:error:"), name, Ptr.nil());
		ObjC.release(name);
		SessionMsg.bFloatPtr(session, ObjC.sel("setPreferredSampleRate:error:"), sampleRate, Ptr.nil());
		SessionMsg.bFloatPtr(session, ObjC.sel("setPreferredIOBufferDuration:error:"), frames / sampleRate, Ptr.nil());
		SessionMsg.bBoolPtr(session, ObjC.sel("setActive:error:"), true, Ptr.nil());
		var cls = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcAudioObserver"), 0);
		if (cls.isNull()) cls = ObjC.cls("HxmcAudioObserver");
		else {
			Runtime.class_addMethod(cls, ObjC.sel("interrupted:"), Callback.addr(interrupted), Mem.cstr("v@:@"));
			Runtime.objc_registerClassPair(cls);
		}
		observer = Msg.id(Msg.id(cls, ObjC.sel("alloc")), ObjC.sel("init"));
		var center = Msg.id(ObjC.cls("NSNotificationCenter"), ObjC.sel("defaultCenter"));
		var note = ObjC.str("AVAudioSessionInterruptionNotification");
		SessionMsg.vPtrPtrPtrPtr(center, ObjC.sel("addObserver:selector:name:object:"), observer, ObjC.sel("interrupted:"), note, session);
		ObjC.release(note);
	}

	// AVAudioSessionInterruptionNotification (the main thread): its
	// userInfo's AVAudioSessionInterruptionTypeKey, 1 began, 0 ended
	@:hxmc.callback static function interrupted(self:Ptr, cmd:Ptr, note:Ptr):Void {
		var info = Msg.id(note, ObjC.sel("userInfo"));
		if (info.isNull()) return;
		var key = ObjC.str("AVAudioSessionInterruptionTypeKey");
		var n = Msg.idPtr(info, ObjC.sel("objectForKey:"), key);
		ObjC.release(key);
		var began = !n.isNull() && Msg.i(n, ObjC.sel("unsignedIntegerValue")) == 1;
		if (!began) {
			var session = Msg.id(ObjC.cls("AVAudioSession"), ObjC.sel("sharedInstance"));
			SessionMsg.bBoolPtr(session, ObjC.sel("setActive:error:"), true, Ptr.nil());
		}
		Audio.interrupted(began);
	}
}

@:build(helder.os.objc.Sender.build())
class SessionMsg {
	static function bPtrPtr(self:Ptr, sel:Ptr, a:Ptr, b:Ptr):Bool;
	static function bFloatPtr(self:Ptr, sel:Ptr, a:Float, b:Ptr):Bool;
	static function bBoolPtr(self:Ptr, sel:Ptr, a:Bool, b:Ptr):Bool;
	static function vPtrPtrPtrPtr(self:Ptr, sel:Ptr, a:Ptr, b:Ptr, c:Ptr, d:Ptr):Void;
}
