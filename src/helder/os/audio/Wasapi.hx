package helder.os.audio;

import hxmc.unsafe.*;

// WASAPI (the Windows Audio Session API, Vista and later): COM's entry
// points (ole32), the events of kernel32, then the interfaces the output
// calls (helder.os.win32.Com: a method is its vtable slot in the official
// headers, the object its first argument). HRESULTs are Int (negative:
// failed), REFERENCE_TIME Int64 (100 ns units); objects and GUIDs are Ptr.
@:hxmc.c @:hxmc.lib("ole32") extern class Ole32 {
	static function CoInitializeEx(reserved:Ptr, flags:Int):Int;
	static function CoCreateInstance(clsid:Ptr, outer:Ptr, context:Int, iid:Ptr, out:Ptr<Ptr>):Int;
	static function CoTaskMemFree(p:Ptr):Void;
}

@:hxmc.c @:hxmc.fast @:hxmc.lib("kernel32") extern class Events {
	static function CreateEventW(attributes:Ptr, manualReset:Int, initialState:Int, name:Ptr):Ptr;
	static function SetEvent(event:Ptr):Int;
}

// (blocks: in a safe region; the runtime's WaitForSingleObject is @:hxmc.fast)
@:hxmc.c @:hxmc.lib("kernel32") extern class Waits {
	static function WaitForMultipleObjects(count:Int, handles:Ptr<Ptr>, all:Int, ms:Int):Int;
}

@:build(helder.os.win32.Com.build())
class IMMDeviceEnumerator {
	@:slot(4) static function GetDefaultAudioEndpoint(self:Ptr, flow:Int, role:Int, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class IMMDevice {
	@:slot(3) static function Activate(self:Ptr, iid:Ptr, context:Int, params:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class IAudioClient {
	@:slot(3) static function Initialize(self:Ptr, shareMode:Int, flags:Int, bufferDuration:Int64, periodicity:Int64, format:Ptr, session:Ptr):Int;
	@:slot(4) static function GetBufferSize(self:Ptr, frames:Ptr<Int32>):Int;
	@:slot(5) static function GetStreamLatency(self:Ptr, latency:Ptr<Int64>):Int;
	@:slot(6) static function GetCurrentPadding(self:Ptr, frames:Ptr<Int32>):Int;
	@:slot(8) static function GetMixFormat(self:Ptr, format:Ptr<Ptr>):Int;
	@:slot(10) static function Start(self:Ptr):Int;
	@:slot(11) static function Stop(self:Ptr):Int;
	@:slot(12) static function Reset(self:Ptr):Int;
	@:slot(13) static function SetEventHandle(self:Ptr, event:Ptr):Int;
	@:slot(14) static function GetService(self:Ptr, iid:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class IAudioRenderClient {
	@:slot(3) static function GetBuffer(self:Ptr, frames:Int, data:Ptr<Ptr>):Int;
	@:slot(4) static function ReleaseBuffer(self:Ptr, frames:Int, flags:Int):Int;
}

// WAVEFORMATEXTENSIBLE (its WAVEFORMATEX is 18 bytes, packed; the rest
// falls on natural alignment)
@:hxmc.struct @:publicFields class WAVEFORMATEXTENSIBLE {
	var wFormatTag:UInt16;
	var nChannels:UInt16;
	var nSamplesPerSec:UInt32;
	var nAvgBytesPerSec:UInt32;
	var nBlockAlign:UInt16;
	var wBitsPerSample:UInt16;
	var cbSize:UInt16;
	var wValidBitsPerSample:UInt16;
	var dwChannelMask:UInt32;
	var subFormat1:Int64;
	var subFormat2:Int64;
}

class WASAPI {
	public static inline var CLSCTX_ALL = 0x17;
	public static inline var COINIT_MULTITHREADED = 0;
	public static inline var eRender = 0;
	public static inline var eConsole = 0;
	public static inline var AUDCLNT_SHAREMODE_SHARED = 0;
	public static inline var AUDCLNT_STREAMFLAGS_EVENTCALLBACK = 0x00040000;
	public static inline var AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY = 0x08000000;
	public static inline var AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM = 0x80000000;
	public static inline var WAVE_FORMAT_EXTENSIBLE = 0xFFFE;
	public static inline var WAIT_TIMEOUT = 0x102;
	// HRESULTs
	public static inline var E_NOTFOUND = 0x80070490;
	public static inline var AUDCLNT_E_DEVICE_INVALIDATED = 0x88890004;

	public static final CLSID_MMDeviceEnumerator = helder.os.win32.Com.guid(0xBCDE0395, 0xE52F, 0x467C, [0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E]);
	public static final IID_IMMDeviceEnumerator = helder.os.win32.Com.guid(0xA95664D2, 0x9614, 0x4F35, [0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6]);
	public static final IID_IAudioClient = helder.os.win32.Com.guid(0x1CB9AD4C, 0xDBFA, 0x4C32, [0xB1, 0x78, 0xC2, 0xF5, 0x68, 0xA7, 0x03, 0xB2]);
	public static final IID_IAudioRenderClient = helder.os.win32.Com.guid(0xF294ACFC, 0x3146, 0x4483, [0xA7, 0xBF, 0xAD, 0xDC, 0xA7, 0xC2, 0x60, 0xE2]);
}
