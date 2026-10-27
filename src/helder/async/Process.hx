package helder.async;

import haxe.io.Bytes;
import helder.async.Io;
import helder.async.Stream;

// A child process on the loop: its output read and its exit awaited without
// blocking. Natively on POSIX its pipes are non-blocking descriptors the
// backend polls, and its exit a waitpid at each poll; on Windows and Eval a
// thread reads each pipe and one waits for the exit (posting to the loop).
//
//   var p = new Process("haxe", ["build.hxml"]);
//   var out = new Reader(p.stdout);
//   var line; while ((line = out.readLine()) != null) Sys.println(line);
//   var code = p.wait();
class Process {
	public final pid:Int;
	public final stdout:Source;
	public final stderr:Source;
	public final stdin:Sink;
	var exit:Dynamic;
	var code:Null<Int>;
	final handles:Array<Handle>;

	// cmd found on the PATH; args each passed as they are (no shell)
	public function new(cmd:String, args:Array<String>) {
		#if !eval
		if (Sys.systemName() != "Windows") {
			var fds = [0, 0, 0];
			pid = hxmc.NativeSys.processRun(cmd, args, fds);
			for (fd in fds)
				hxmc.NativeNet.setBlocking(fd, false);
			handles = [for (fd in fds) Handle.ofFd(fd)];
			exit = pid;
			stdin = new Pipe(handles[0]);
			stdout = new Pipe(handles[1]);
			stderr = new Pipe(handles[2]);
			return;
		}
		#end
		var p = new sys.io.Process(cmd, args);
		pid = p.getPid();
		handles = [new Handle(null, -1, null, p.stdin), new Handle(null, -1, p.stdout), new Handle(null, -1, p.stderr)];
		exit = p;
		stdin = new Pipe(handles[0]);
		stdout = new Pipe(handles[1]);
		stderr = new Pipe(handles[2]);
	}

	// its exit code, once it exited
	@:coroutine public function wait():Int {
		if (code == null) code = new Op(Exit, null, null, 0, 0, "", 0, exit).run().result;
		return code;
	}

	// no more input (the child reads the end of its stdin)
	public function closeStdin()
		close1(handles[0]);

	public function kill() {
		if (exit is Int) {
			#if !eval hxmc.NativeSys.processKill(pid); #end
		} else (exit : sys.io.Process).kill();
	}

	// the pipes closed (after wait: they may still hold output)
	public function close()
		for (h in handles)
			close1(h);

	function close1(h:Handle) {
		if (h.closed) return;
		h.closed = true;
		if (h.fd >= 0) {
			#if !eval hxmc.NativeSys.fileClose(h.fd); #end
		} else if (h.output != null) h.output.close() else h.input.close();
	}

	// (the backend's poll: the exit code, -1 while it runs)
	@:allow(helder.async) static function exited(pid:Int):Int {
		#if eval
		return -1;
		#else
		return hxmc.NativeSys.processWait(pid, false);
		#end
	}
}

private class Pipe implements Source implements Sink {
	final handle:Handle;

	public function new(h)
		handle = h;

	@:coroutine public function read(b:Bytes, pos:Int, len:Int):Int {
		if (handle.closed) return 0;
		return new Op(Read, handle, b, pos, len).run().result;
	}

	@:coroutine public function write(b:Bytes, pos:Int, len:Int):Void {
		while (len > 0) {
			var n = new Op(Write, handle, b, pos, len).run().result;
			pos += n;
			len -= n;
		}
	}
}
