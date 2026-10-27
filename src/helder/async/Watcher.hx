package helder.async;

// What changed in some directories, in batches: next() waits for the next
// batch (the paths added, changed or removed, after a quiet spell: the
// debounce). PollWatcher scans; inotify, FSEvents and
// ReadDirectoryChangesW are other implementations of this interface.
interface Watcher {
	@:coroutine function next():Array<String>;
	function close():Void;
}
