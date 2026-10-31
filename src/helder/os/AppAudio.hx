package helder.os;

// The app's lifecycle reaching its audio: helder.os.audio.Audio sets hold
// when an output opens on Android or iOS; Android's activity paused (true)
// and resumed (false), iOS's app gone to the background and back, call it
// (AndroidWindow, UIKitWindow), which stops the running outputs and starts
// them again. Here so that an app without audio does not take it in.
class AppAudio {
	public static var hold:Null<Bool->Void>;
}
