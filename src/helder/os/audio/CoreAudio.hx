package helder.os.audio;

import hxmc.unsafe.*;

// CoreAudio's output units (AudioToolbox) and the default device's id
// (CoreAudio): the calls an output needs. AudioUnits and AudioComponents
// are Ptr, OSStatus Int (0: no error), four-character codes Int.
@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox") extern class AudioToolbox {
	static function AudioComponentFindNext(after:Ptr, desc:Ptr<AudioComponentDescription>):Ptr;
	static function AudioComponentInstanceNew(component:Ptr, out:Ptr<Ptr>):Int;
	static function AudioComponentInstanceDispose(unit:Ptr):Int;
	static function AudioUnitSetProperty(unit:Ptr, id:Int, scope:Int, element:Int, data:Ptr, size:Int):Int;
	static function AudioUnitGetProperty(unit:Ptr, id:Int, scope:Int, element:Int, data:Ptr, size:Ptr<Int32>):Int;
	static function AudioUnitInitialize(unit:Ptr):Int;
	static function AudioUnitUninitialize(unit:Ptr):Int;
	static function AudioOutputUnitStart(unit:Ptr):Int;
	static function AudioOutputUnitStop(unit:Ptr):Int;
	// (pulls `frames` frames through the unit: its render callback, on this thread)
	static function AudioUnitRender(unit:Ptr, flags:Ptr<Int32>, time:Ptr, bus:Int, frames:Int, list:Ptr):Int;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreAudio.framework/CoreAudio") extern class CoreAudioHw {
	static function AudioObjectGetPropertyData(object:Int, address:Ptr<AudioObjectPropertyAddress>, qualifierSize:Int, qualifier:Ptr, size:Ptr<Int32>,
		data:Ptr):Int;
}

// libdispatch's semaphores: the render callback (any thread, no GC) signals,
// the audio thread waits (in a safe region); libSystem, where the C library is
@:hxmc.c @:hxmc.fast extern class Dispatch {
	static function dispatch_semaphore_create(value:Int64):Ptr;
	static function dispatch_semaphore_signal(sem:Ptr):Int64;
	static function dispatch_time(when:Int64, delta:Int64):Int64;
	static function dispatch_release(o:Ptr):Void;
}

@:hxmc.c extern class DispatchWait {
	static function dispatch_semaphore_wait(sem:Ptr, timeout:Int64):Int64;
}

@:hxmc.struct @:publicFields class AudioComponentDescription {
	var componentType:UInt32;
	var componentSubType:UInt32;
	var componentManufacturer:UInt32;
	var componentFlags:UInt32;
	var componentFlagsMask:UInt32;
}

@:hxmc.struct @:publicFields class AudioStreamBasicDescription {
	var mSampleRate:Float;
	var mFormatID:UInt32;
	var mFormatFlags:UInt32;
	var mBytesPerPacket:UInt32;
	var mFramesPerPacket:UInt32;
	var mBytesPerFrame:UInt32;
	var mChannelsPerFrame:UInt32;
	var mBitsPerChannel:UInt32;
	var mReserved:UInt32;
}

@:hxmc.struct @:publicFields class AURenderCallbackStruct {
	var inputProc:Ptr;
	var inputProcRefCon:Ptr;
}

@:hxmc.struct @:publicFields class AudioObjectPropertyAddress {
	var mSelector:UInt32;
	var mScope:UInt32;
	var mElement:UInt32;
}

class CA {
	// four-character codes
	public static inline var kAudioUnitType_Output = 0x61756f75; // auou
	public static inline var kAudioUnitSubType_DefaultOutput = 0x64656620; // def
	public static inline var kAudioUnitSubType_GenericOutput = 0x67656e72; // genr
	public static inline var kAudioUnitManufacturer_Apple = 0x6170706c; // appl
	public static inline var kAudioFormatLinearPCM = 0x6c70636d; // lpcm
	public static inline var kAudioHardwarePropertyDefaultOutputDevice = 0x644f7574; // dOut
	public static inline var kAudioObjectPropertyScopeGlobal = 0x676c6f62; // glob
	public static inline var kAudioDevicePropertyBufferFrameSize = 0x6673697a; // fsiz
	public static inline var kAudioObjectSystemObject = 1;
	public static inline var kAudioFormatFlagIsFloat = 1;
	public static inline var kAudioFormatFlagIsPacked = 8;
	public static inline var kAudioUnitProperty_StreamFormat = 8;
	public static inline var kAudioUnitProperty_MaximumFramesPerSlice = 14;
	public static inline var kAudioUnitProperty_SetRenderCallback = 23;
	public static inline var kAudioUnitScope_Global = 0;
	public static inline var kAudioUnitScope_Input = 1;
	public static inline var kAudioUnitScope_Output = 2;
	public static inline var kAudioTimeStampSampleTimeValid = 1;
}
