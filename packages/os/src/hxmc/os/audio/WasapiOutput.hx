package hxmc.os.audio;

import hxmc.os.audio.Wasapi;
import hxmc.os.win32.Com;
import hxmc.unsafe.*;
import sys.thread.Lock;
import sys.thread.Thread;

// hxmc.os.audio.Audio on Windows: WASAPI in shared mode on the default
// render endpoint, event driven. The stream is 32-bit floats at the rate
// asked for (AUTOCONVERTPCM: the audio engine converts to the mix format
// and resamples). WASAPI signals an event each period; the audio thread is
// ours, waiting on it (in a safe region), then filling what the endpoint's
// buffer has free (GetCurrentPadding): any count up to the buffer's frames
// (Audio.frames), about a period each time. COM runs multithreaded on the
// threads that call it.
@:allow(hxmc.os.audio)
class WasapiOutput {
	final owner:Audio;
	var enumerator = Ptr.nil();
	var device = Ptr.nil();
	var client = Ptr.nil();
	var render = Ptr.nil();
	final event:Ptr<Ptr>;
	final scratch:Ptr<Ptr>;
	// (the audio thread's: GetBuffer's pointer, the padding)
	final data:Ptr<Ptr>;
	final padding:Ptr<Int32>;
	var bufferFrames = 0;
	var quit = false;
	final done = new Lock();
	var error:Null<String>;

	function new(owner:Audio, name:Null<String>) {
		this.owner = owner;
		if (name != null) throw "hxmc.os.audio: WASAPI plays on the default output only (device " + name + ")";
		Ole32.CoInitializeEx(Ptr.nil(), WASAPI.COINIT_MULTITHREADED);
		scratch = LibC.malloc(16);
		event = LibC.malloc(8);
		data = LibC.malloc(8);
		padding = LibC.malloc(4);
		event.value = Events.CreateEventW(Ptr.nil(), 0, 0, Ptr.nil());
		check(Ole32.CoCreateInstance(WASAPI.CLSID_MMDeviceEnumerator, Ptr.nil(), WASAPI.CLSCTX_ALL, WASAPI.IID_IMMDeviceEnumerator, scratch),
			"CoCreateInstance(MMDeviceEnumerator)");
		enumerator = scratch.value;
		var hr = IMMDeviceEnumerator.GetDefaultAudioEndpoint(enumerator, WASAPI.eRender, WASAPI.eConsole, scratch);
		if (hr == WASAPI.E_NOTFOUND) fail("no output device (WASAPI: no default render endpoint)");
		check(hr, "GetDefaultAudioEndpoint");
		device = scratch.value;
		check(IMMDevice.Activate(device, WASAPI.IID_IAudioClient, WASAPI.CLSCTX_ALL, Ptr.nil(), scratch), "IMMDevice::Activate(IAudioClient)");
		client = scratch.value;
		Arena.scoped(a -> {
			var f = a.make(WAVEFORMATEXTENSIBLE);
			f.value.wFormatTag = WASAPI.WAVE_FORMAT_EXTENSIBLE;
			f.value.nChannels = owner.channels;
			f.value.nSamplesPerSec = owner.sampleRate;
			f.value.nBlockAlign = owner.channels * 4;
			f.value.nAvgBytesPerSec = owner.sampleRate * owner.channels * 4;
			f.value.wBitsPerSample = 32;
			f.value.cbSize = 22;
			f.value.wValidBitsPerSample = 32;
			// (the speakers in order: front left, front right, ...; KSDATAFORMAT_SUBTYPE_IEEE_FLOAT)
			f.value.dwChannelMask = owner.channels >= 31 ? -1 : (1 << owner.channels) - 1;
			var sub:Ptr<Int32> = f.raw().add(24);
			sub[0] = 0x00000003;
			sub[1] = 0x00100000;
			sub[2] = 0xAA000080;
			sub[3] = 0x719B3800;
			// (the buffer: the hint's four periods, in 100 ns units)
			var duration:Int64 = Math.round(owner.frames * 4 * 1e7 / owner.sampleRate);
			check(IAudioClient.Initialize(client, WASAPI.AUDCLNT_SHAREMODE_SHARED,
				WASAPI.AUDCLNT_STREAMFLAGS_EVENTCALLBACK | WASAPI.AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | WASAPI.AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
				duration, 0, f, Ptr.nil()),
				"IAudioClient::Initialize");
		});
		var n:Ptr<Int32> = scratch.raw();
		check(IAudioClient.GetBufferSize(client, n), "IAudioClient::GetBufferSize");
		bufferFrames = n.value;
		owner.frames = bufferFrames;
		var lat:Ptr<Int64> = scratch.raw();
		check(IAudioClient.GetStreamLatency(client, lat), "IAudioClient::GetStreamLatency");
		owner.latency = bufferFrames / owner.sampleRate + lat.value.toInt() / 1e7;
		check(IAudioClient.SetEventHandle(client, event.value), "IAudioClient::SetEventHandle");
		check(IAudioClient.GetService(client, WASAPI.IID_IAudioRenderClient, scratch), "IAudioClient::GetService(IAudioRenderClient)");
		render = scratch.value;
	}

	function check(hr:Int, what:String)
		if (hr < 0) fail(what + " failed (HRESULT 0x" + StringTools.hex(hr, 8) + ")");

	function fail(s:String) {
		release();
		throw "hxmc.os.audio: " + s;
	}

	function release() {
		Com.release(render);
		Com.release(client);
		Com.release(device);
		Com.release(enumerator);
		render = client = device = enumerator = Ptr.nil();
	}

	function start() {
		quit = false;
		Thread.create(run);
	}

	// the audio thread
	function run() {
		try {
			Ole32.CoInitializeEx(Ptr.nil(), WASAPI.COINIT_MULTITHREADED);
			// (the whole buffer before the stream starts, then what each period frees)
			write(bufferFrames);
			hr(IAudioClient.Start(client), "Start");
			while (!quit) {
				if (Waits.WaitForMultipleObjects(1, event, 0, 2000) == WASAPI.WAIT_TIMEOUT) throw "the endpoint stopped asking for samples";
				if (quit) break;
				hr(IAudioClient.GetCurrentPadding(client, padding), "GetCurrentPadding");
				var free = bufferFrames - padding.value;
				if (free > 0) write(free);
			}
		} catch (e:Dynamic) {
			error = Std.string(e);
		}
		done.release();
	}

	// fills n frames of the endpoint's buffer
	function write(n:Int) {
		var r = IAudioRenderClient.GetBuffer(render, n, data);
		if (r >= 0) {
			owner.pull(data.value, n);
			r = IAudioRenderClient.ReleaseBuffer(render, n, 0);
		}
		hr(r, "IAudioRenderClient::GetBuffer");
	}

	static function hr(r:Int, what:String)
		if (r < 0) throw what + " failed (HRESULT 0x" + StringTools.hex(r, 8) + ")";

	function stop() {
		quit = true;
		Events.SetEvent(event.value);
		done.wait();
		IAudioClient.Stop(client);
		IAudioClient.Reset(client);
		if (error != null) throw "hxmc.os.audio: " + error;
	}

	function close() {
		release();
		Win32.CloseHandle(event.value);
		LibC.free(event);
		LibC.free(scratch);
		LibC.free(data);
		LibC.free(padding);
	}
}
