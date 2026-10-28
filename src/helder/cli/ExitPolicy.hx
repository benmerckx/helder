package helder.cli;

// What `helder dev` does when the program it runs ends (DevCommand), as
// `tauri dev` and electron-forge do:
// - on this machine (the dev host, or a process per build), a program that
//   ends by itself with exit code 0 was closed (its window): the session
//   ends, the watcher and the servers stopped, exit code 0;
// - one that ends otherwise (an exit code not 0, a signal) crashed: the
//   session stays, the error shown, and the next change builds it and
//   starts it again;
// - one that helder dev ended itself (a reload's restart, a program that
//   did not answer it, ctrl-c) decides nothing;
// - web: no program here, a page in a browser; a tab closed is a client
//   gone, the server stays (as vite's);
// - android and ios (not wired yet: Options.NOT_YET): the app closed on the
//   phone should not end the session, which keeps serving and starts it
//   again with the next build; a crash the same.
// Pure: DevCommand gives it what happened.
class ExitPolicy {
	public static function decide(platform:Platform, code:Int, replaced:Bool, stopping:Bool):ExitAction {
		if (stopping || replaced) return Ignore;
		return switch platform {
			case Desktop: code == 0 ? EndSession : WaitForChange;
			case Web: Ignore;
			case Mobile: WaitForChange;
		}
	}
}

enum Platform {
	// this machine: linux-, windows-, macos-
	Desktop;
	// a page in a browser
	Web;
	// android, ios: a phone, an emulator or a simulator
	Mobile;
}

enum ExitAction {
	// the user closed it: helder dev ends, exit code 0
	EndSession;
	// it crashed (or, on a phone, was closed): shown, started again with the next build
	WaitForChange;
	// helder dev ended it itself
	Ignore;
}
